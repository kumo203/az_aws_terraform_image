# Per-team onboarding, mirroring az_tf's api_management_teams.tf: each team
# gets its own API key (analogous to an APIM subscription key) and usage
# plan. Unlike APIM Consumption tier, API Gateway usage plans support a real
# quota natively (see var.gateway_teams in variables.tf), so no workaround is
# needed here.
resource "aws_api_gateway_api_key" "teams" {
  for_each = var.gateway_teams

  name = "${var.resource_prefix}-${local.name_suffix}-${each.key}"
}

resource "aws_api_gateway_usage_plan" "teams" {
  for_each = var.gateway_teams

  name = "${var.resource_prefix}-${local.name_suffix}-${each.key}-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.gateway.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    rate_limit  = each.value.rate_limit
    burst_limit = each.value.burst_limit
  }

  quota_settings {
    limit  = each.value.quota_limit
    period = each.value.quota_period
  }
}

resource "aws_api_gateway_usage_plan_key" "teams" {
  for_each = var.gateway_teams

  key_id        = aws_api_gateway_api_key.teams[each.key].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.teams[each.key].id
}
