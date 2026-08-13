
variable "resource_prefix" {
  description = "Prefix applied to the name of every top-level resource"
  type        = string
  default     = "ai-prj-sample"
}

variable "region" {
  description = "AWS region for all resources. Must be a region where the bedrock-mantle endpoint is available."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-2"], var.region)
    error_message = "bedrock-mantle is only available in us-east-1, us-east-2, or us-west-2 as of 2026-08 (see aws_tf/README.md)."
  }
}

# Produced by `terraform output` in aws_bootstrap/ after `terraform apply`
# there; copy it into terraform.tfvars before applying this module. It has no
# default because a fresh value is generated on every bootstrap apply.
variable "name_suffix" {
  description = "Shared naming suffix used across this module's resources (bootstrap output: name_suffix)"
  type        = string
}

# xai.grok-4.3 is the only model reachable from this account (see
# aws_tf/README.md) — unlike az_tf's model_deployments map, there is nothing
# to deploy/provision per-model on the Bedrock side, so this is a single value
# threaded through the Lambda proxy and client-facing outputs.
variable "model_id" {
  description = "Bedrock Mantle model id forwarded to the OpenAI-compatible endpoint"
  type        = string
  default     = "xai.grok-4.3"
}

variable "bedrock_credential_expiration_days" {
  description = "Expiration (in days) for the IAM service-specific credential used as the Bedrock Mantle bearer token"
  type        = number
  default     = 365
}

variable "enable_gateway_logging" {
  description = "Whether to provision CloudWatch Log Groups and wire API Gateway/Lambda logging to them"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for API Gateway access logs and the Lambda proxy's logs"
  type        = number
  default     = 30
}

variable "default_throttle_rate_limit" {
  description = "Stage-wide default requests/second throttle (per-team limits are set separately via each team's usage plan)"
  type        = number
  default     = 100
}

variable "default_throttle_burst_limit" {
  description = "Stage-wide default burst capacity"
  type        = number
  default     = 50
}

# Per-team onboarding for the gateway in front of Bedrock Mantle. Each entry
# gets its own API Gateway API key and usage plan (throttle + quota) so no
# single team can exhaust the shared Grok 4.3 capacity. Unlike az_tf's
# copilot_teams (APIM Consumption tier rejects quota/quota-by-key outright),
# API Gateway usage plans support a real quota natively, so it is set here
# rather than worked around.
variable "gateway_teams" {
  description = "Map of teams to their API Gateway usage plan/API key settings"
  type = map(object({
    display_name = string
    rate_limit   = number
    burst_limit  = number
    quota_limit  = number
    quota_period = string # DAY, WEEK, or MONTH
  }))
  default = {
    "team-alpha" = {
      display_name = "Team Alpha"
      rate_limit   = 10
      burst_limit  = 5
      quota_limit  = 10000
      quota_period = "DAY"
    }
  }
}
