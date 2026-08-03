
variable "resource_prefix" {
  description = "Prefix applied to the name of every top-level resource"
  type        = string
  default     = "ai-prj-sample20260803"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus2"
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