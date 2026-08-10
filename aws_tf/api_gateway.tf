resource "aws_api_gateway_rest_api" "gateway" {
  name = "${var.resource_prefix}-${local.name_suffix}-gw"
}

# Path tree: /openai/v1/{chat/completions, responses, models} — exactly the
# surface Bedrock Mantle exposes for xai.grok-4.3 (see aws_tf/README.md;
# bedrock-runtime/Invoke/Converse are not supported for this model, so no
# other route shapes are needed).
resource "aws_api_gateway_resource" "openai" {
  rest_api_id = aws_api_gateway_rest_api.gateway.id
  parent_id   = aws_api_gateway_rest_api.gateway.root_resource_id
  path_part   = "openai"
}

resource "aws_api_gateway_resource" "v1" {
  rest_api_id = aws_api_gateway_rest_api.gateway.id
  parent_id   = aws_api_gateway_resource.openai.id
  path_part   = "v1"
}

resource "aws_api_gateway_resource" "chat" {
  rest_api_id = aws_api_gateway_rest_api.gateway.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "chat"
}

resource "aws_api_gateway_resource" "chat_completions" {
  rest_api_id = aws_api_gateway_rest_api.gateway.id
  parent_id   = aws_api_gateway_resource.chat.id
  path_part   = "completions"
}

resource "aws_api_gateway_resource" "responses" {
  rest_api_id = aws_api_gateway_rest_api.gateway.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "responses"
}

resource "aws_api_gateway_resource" "models" {
  rest_api_id = aws_api_gateway_rest_api.gateway.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "models"
}

resource "aws_api_gateway_method" "chat_completions_post" {
  rest_api_id      = aws_api_gateway_rest_api.gateway.id
  resource_id      = aws_api_gateway_resource.chat_completions.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "responses_post" {
  rest_api_id      = aws_api_gateway_rest_api.gateway.id
  resource_id      = aws_api_gateway_resource.responses.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "models_get" {
  rest_api_id      = aws_api_gateway_rest_api.gateway.id
  resource_id      = aws_api_gateway_resource.models.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

# AWS_PROXY (Lambda proxy) integrations always use POST as the
# integration_http_method regardless of the method's own http_method — this
# is what routes every call through mantle_proxy so it can inject the real
# Authorization header, log bodies, and emit token-usage metrics (the
# aoai-api-policy.xml equivalent).
resource "aws_api_gateway_integration" "chat_completions" {
  rest_api_id             = aws_api_gateway_rest_api.gateway.id
  resource_id             = aws_api_gateway_resource.chat_completions.id
  http_method             = aws_api_gateway_method.chat_completions_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.mantle_proxy.invoke_arn
}

resource "aws_api_gateway_integration" "responses" {
  rest_api_id             = aws_api_gateway_rest_api.gateway.id
  resource_id             = aws_api_gateway_resource.responses.id
  http_method             = aws_api_gateway_method.responses_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.mantle_proxy.invoke_arn
}

resource "aws_api_gateway_integration" "models" {
  rest_api_id             = aws_api_gateway_rest_api.gateway.id
  resource_id             = aws_api_gateway_resource.models.id
  http_method             = aws_api_gateway_method.models_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.mantle_proxy.invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mantle_proxy.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.gateway.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "gateway" {
  rest_api_id = aws_api_gateway_rest_api.gateway.id

  # Forces a new deployment whenever any route/integration changes, since
  # aws_api_gateway_deployment has no other way to detect drift.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.chat_completions.id,
      aws_api_gateway_resource.responses.id,
      aws_api_gateway_resource.models.id,
      aws_api_gateway_integration.chat_completions.id,
      aws_api_gateway_integration.responses.id,
      aws_api_gateway_integration.models.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.gateway.id
  deployment_id = aws_api_gateway_deployment.gateway.id
  stage_name    = "prod"

  # No attribute of aws_api_gateway_account.this is referenced above, so
  # Terraform has no implicit ordering between them; without this, the stage
  # can try to enable access logging before the account-level CloudWatch
  # Logs role exists ("CloudWatch Logs role ARN must be set in account
  # settings to enable logging") — the AWS analog of az_tf's time_sleep for
  # AAD role-assignment propagation.
  depends_on = [aws_api_gateway_account.this]

  dynamic "access_log_settings" {
    for_each = var.enable_gateway_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.apigw_access[0].arn
      # Metadata only — request/response bodies are logged by mantle_proxy
      # instead, same reasoning as az_tf's observability.tf: duplicating the
      # body into both the gateway's access log and the Lambda's log would
      # only push entries closer to being dropped for size with no benefit.
      format = jsonencode({
        requestId          = "$context.requestId"
        ip                 = "$context.identity.sourceIp"
        apiKeyId           = "$context.identity.apiKeyId"
        requestTime        = "$context.requestTime"
        httpMethod         = "$context.httpMethod"
        resourcePath       = "$context.resourcePath"
        status             = "$context.status"
        responseLength     = "$context.responseLength"
        integrationLatency = "$context.integrationLatency"
        latency            = "$context.responseLatency"
      })
    }
  }
}

resource "aws_api_gateway_method_settings" "prod" {
  rest_api_id = aws_api_gateway_rest_api.gateway.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = var.default_throttle_rate_limit
    throttling_burst_limit = var.default_throttle_burst_limit
    metrics_enabled        = var.enable_gateway_logging
    logging_level          = var.enable_gateway_logging ? "INFO" : "OFF"
  }
}
