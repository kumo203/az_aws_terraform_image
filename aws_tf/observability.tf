# count-gated on var.enable_gateway_logging, same pattern as az_tf's
# observability.tf gating Log Analytics/App Insights on
# var.enable_apim_diagnostics.

resource "aws_cloudwatch_log_group" "apigw_access" {
  count = var.enable_gateway_logging ? 1 : 0

  name              = "/aws/apigateway/${var.resource_prefix}-${local.name_suffix}-gw"
  retention_in_days = var.log_retention_days
}

# Named to match Lambda's implicit log group so mantle_proxy's own logging
# (request/response bodies, truncated to 8KB — see lambda_src/handler.py)
# lands here instead of an auto-created, unmanaged group.
resource "aws_cloudwatch_log_group" "lambda" {
  count = var.enable_gateway_logging ? 1 : 0

  name              = "/aws/lambda/${aws_lambda_function.mantle_proxy.function_name}"
  retention_in_days = var.log_retention_days
}

# API Gateway account-level setting: unlike APIM (where diagnostics wiring is
# purely a resource on the APIM instance itself), CloudWatch Logs access for
# *any* API Gateway REST API in this account requires a role configured here
# once. No Azure equivalent exists for this step.
resource "aws_iam_role" "apigw_cloudwatch" {
  count = var.enable_gateway_logging ? 1 : 0

  name = "${var.resource_prefix}-${local.name_suffix}-apigw-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "apigateway.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  count = var.enable_gateway_logging ? 1 : 0

  role       = aws_iam_role.apigw_cloudwatch[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  count = var.enable_gateway_logging ? 1 : 0

  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch[0].arn
}
