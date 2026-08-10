"""Proxies API Gateway requests to the Bedrock Mantle OpenAI-compatible
endpoint, injecting the real bearer token so callers only ever need their
API Gateway API key. This is the AWS-side stand-in for az_tf's
aoai-api-policy.xml: backend auth injection, response-token metric
emission, and size-capped request/response body logging all happen here
instead of in a gateway policy, because API Gateway itself cannot inspect
or transform bodies without a Lambda in the path.
"""

import json
import logging
import os
import urllib.error
import urllib.request

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

MANTLE_HOST = os.environ["MANTLE_HOST"]
SECRET_ARN = os.environ["SECRET_ARN"]
METRIC_NAMESPACE = os.environ.get("METRIC_NAMESPACE", "GenAIGateway")
LOG_BODY_MAX_BYTES = int(os.environ.get("LOG_BODY_MAX_BYTES", "8192"))

_secrets_client = boto3.client("secretsmanager")
_cloudwatch_client = boto3.client("cloudwatch")

# Cached across warm invocations, same rationale as az_tf's policy caching an
# acquired AAD token for the lifetime of a gateway instance.
_bearer_token_cache = None


def _get_bearer_token():
    global _bearer_token_cache
    if _bearer_token_cache is None:
        response = _secrets_client.get_secret_value(SecretId=SECRET_ARN)
        _bearer_token_cache = response["SecretString"]
    return _bearer_token_cache


def _truncate_for_log(body_str):
    encoded = body_str.encode("utf-8")
    if len(encoded) <= LOG_BODY_MAX_BYTES:
        return body_str
    return encoded[:LOG_BODY_MAX_BYTES].decode("utf-8", errors="ignore") + "...[truncated]"


def _emit_token_metrics(usage, model_id, api_key_id):
    if not usage:
        return
    metric_data = []
    for usage_field, metric_name in (
        ("prompt_tokens", "PromptTokens"),
        ("completion_tokens", "CompletionTokens"),
        ("total_tokens", "TotalTokens"),
    ):
        value = usage.get(usage_field)
        if value is None:
            continue
        metric_data.append(
            {
                "MetricName": metric_name,
                "Dimensions": [
                    {"Name": "ApiKeyId", "Value": api_key_id},
                    {"Name": "Model", "Value": model_id},
                ],
                "Value": float(value),
                "Unit": "Count",
            }
        )
    if metric_data:
        _cloudwatch_client.put_metric_data(Namespace=METRIC_NAMESPACE, MetricData=metric_data)


def handler(event, context):
    path = event["path"]
    http_method = event["httpMethod"]
    request_body = event.get("body") or ""
    api_key_id = event.get("requestContext", {}).get("identity", {}).get("apiKeyId", "unknown")

    logger.info("request path=%s method=%s body=%s", path, http_method, _truncate_for_log(request_body))

    model_id = "unknown"
    if request_body:
        try:
            model_id = json.loads(request_body).get("model", "unknown")
        except json.JSONDecodeError:
            pass

    url = f"https://{MANTLE_HOST}{path}"
    req = urllib.request.Request(
        url,
        data=request_body.encode("utf-8") if request_body else None,
        method=http_method,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {_get_bearer_token()}",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            status_code = resp.status
            response_body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        status_code = e.code
        response_body = e.read().decode("utf-8")

    logger.info("response status=%s body=%s", status_code, _truncate_for_log(response_body))

    try:
        usage = json.loads(response_body).get("usage")
    except json.JSONDecodeError:
        usage = None
    _emit_token_metrics(usage, model_id, api_key_id)

    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": response_body,
        "isBase64Encoded": False,
    }
