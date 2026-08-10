output "mantle_endpoint_internal" {
  description = "Internal-only. Do not distribute to clients directly — use apigw_invoke_url instead."
  value       = "https://bedrock-mantle.${var.region}.api.aws/openai/v1"
}

output "apigw_invoke_url" {
  description = "Stable client-facing endpoint; base_url for OpenAI-compatible clients is this + /openai/v1"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/openai/v1"
}

output "apigw_api_keys" {
  description = "Per-team API Gateway key values (sent as the x-api-key header); distribute one per team, never the real Bedrock bearer token"
  value       = { for k, v in aws_api_gateway_api_key.teams : k => v.value }
  sensitive   = true
}

# Everything a client needs, in one place, except the key itself (kept
# separate/sensitive in apigw_api_keys). Note the client-facing key header
# (x-api-key, checked by API Gateway) is separate from the backend
# Authorization: Bearer header the Lambda proxy injects — clients never see
# or need the latter.
output "openai_client_setup" {
  description = "Values for configuring an OpenAI-compatible client against this gateway; get the matching key from apigw_api_keys"
  value = {
    base_url       = "${aws_api_gateway_stage.prod.invoke_url}/openai/v1"
    api_key_header = "x-api-key"
    model_ids      = [var.model_id]
  }
}

# Ready-to-paste shell export commands per team. Unlike the OpenAI SDK's
# default OPENAI_API_KEY (sent as "Authorization: Bearer ..."), API
# Gateway's usage-plan keys are always read from the fixed "x-api-key"
# header, so SDK-based clients need to set that as a default header
# explicitly rather than relying on OPENAI_API_KEY alone.
output "env_snippets" {
  description = "team => shell export commands (BASE_URL/API_KEY) for calling this gateway"
  sensitive   = true
  value = {
    for team_key, key in aws_api_gateway_api_key.teams : team_key => join("\n", [
      "export GATEWAY_BASE_URL=\"${aws_api_gateway_stage.prod.invoke_url}/openai/v1\"",
      "export GATEWAY_API_KEY=\"${key.value}\"",
      "# curl -H \"x-api-key: $GATEWAY_API_KEY\" -H \"Content-Type: application/json\" \\",
      "#   -d '{\"model\":\"${var.model_id}\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}' \\",
      "#   \"$GATEWAY_BASE_URL/chat/completions\"",
    ])
  }
}
