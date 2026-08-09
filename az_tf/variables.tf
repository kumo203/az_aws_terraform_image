
variable "resource_prefix" {
  description = "Prefix applied to the name of every top-level resource"
  type        = string
  default     = "ai-prj-sample"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus2"
}

# The following two variables are produced by `terraform output` in bootstrap/
# after `terraform apply` there; copy them into terraform.tfvars before
# applying this module. They have no default because a fresh value is
# generated on every bootstrap apply.
variable "resource_group_name" {
  description = "Name of the shared resource group (bootstrap output: resource_group_name)"
  type        = string
}

variable "name_suffix" {
  description = "Shared naming suffix used across this module's resources (bootstrap output: name_suffix)"
  type        = string
}

variable "deployment_sku_name" {
  description = "SKU name applied to every model deployment"
  type        = string
  default     = "GlobalStandard"
}

variable "deployment_capacity" {
  description = "Capacity (in units of 1,000 TPM) applied to every model deployment"
  type        = number
  default     = 400
}

# Model name/version pairs confirmed via `az cognitiveservices account deployment list`
# against an existing East US 2 AIServices account. Re-verify with
# `az cognitiveservices account list-models` before apply in case the catalog has moved on.
variable "model_deployments" {
  description = "Map of gpt-5.6 model deployments to create, keyed by model name"
  type = map(object({
    version = string
  }))
  default = {
    "gpt-5.6-luna"  = { version = "2026-07-09" }
    "gpt-5.6-terra" = { version = "2026-07-09" }
    "gpt-5.6-sol"   = { version = "2026-07-09" }
  }
}

variable "api_version" {
  description = "Azure OpenAI REST API version (the `api-version` query parameter) Copilot's BYOM client must send on every request"
  type        = string
  default     = "2024-06-01"
}

variable "apim_sku_name" {
  description = "SKU (name_capacity) for the API Management gateway in front of the Foundry endpoint"
  type        = string
  default     = "Consumption_0"
}

variable "apim_publisher_name" {
  description = "Publisher name shown in the APIM developer portal / used for service notifications"
  type        = string
  default     = "AI Platform Team"
}

variable "apim_publisher_email" {
  description = "Publisher email for APIM service notifications; override with a real distribution list before applying"
  type        = string
  default     = "aiops@example.com"
}

variable "enable_apim_diagnostics" {
  description = "Whether to provision Log Analytics + Application Insights and wire APIM diagnostics to them"
  type        = bool
  default     = true
}

# Per-team/consumer onboarding for the Copilot APIM gateway. Each entry gets its
# own APIM product, subscription key, and rate-limit policy so no single team
# can exhaust the shared model deployment capacity. Note: the Consumption SKU
# rejects rate-limit-by-key/quota/quota-by-key outright, so only a plain
# per-subscription rate-limit is enforced; revisit with a hard monthly quota
# if/when apim_sku_name moves off Consumption.
variable "copilot_teams" {
  description = "Map of Copilot-consuming teams to their APIM product/subscription settings"
  type = map(object({
    display_name              = string
    rate_limit_calls          = number
    rate_limit_period_seconds = number
  }))
  default = {
    "team-alpha" = {
      display_name              = "Team Alpha"
      rate_limit_calls          = 60
      rate_limit_period_seconds = 60
    }
  }
}