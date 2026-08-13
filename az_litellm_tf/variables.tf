
# Distinct default from az_tf/'s "ai-prj-sample" so this environment's
# resources never collide by name with az_tf's inside the same shared
# resource group (both modules read the same bootstrap resource_group_name).
variable "resource_prefix" {
  description = "Prefix applied to the name of every top-level resource"
  type        = string
  default     = "ai-prj-litellm"
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
  description = "Azure OpenAI REST API version (the `api-version` field) to enter when registering the Azure model in LiteLLM's Admin UI/API"
  type        = string
  default     = "2024-06-01"
}

variable "key_vault_sku_name" {
  description = "SKU for the Key Vault holding Postgres/LiteLLM/Foundry secrets"
  type        = string
  default     = "standard"
}

# false keeps `terraform destroy` clean for this sample/dev environment
# (mirrors the existing Cognitive Services soft-delete purge tradeoff already
# documented for az_tf/). Set true for a longer-lived deployment and purge
# manually on teardown instead.
variable "key_vault_purge_protection_enabled" {
  description = "Whether to enable Key Vault purge protection (true = safer but requires manual purge on teardown)"
  type        = bool
  default     = false
}

variable "postgres_sku_name" {
  description = "Postgres Flexible Server SKU (Burstable tier for lowest cost)"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "Postgres Flexible Server storage size in MB (32768 is the Flexible Server minimum)"
  type        = number
  default     = 32768
}

variable "postgres_version" {
  description = "Postgres major version"
  type        = string
  default     = "16"
}

variable "postgres_admin_username" {
  description = "Postgres Flexible Server administrator login"
  type        = string
  default     = "litellmadmin"
}

variable "postgres_database_name" {
  description = "Name of the database LiteLLM uses for its Prisma-managed schema"
  type        = string
  default     = "litellm"
}

variable "postgres_admin_source_ip_ranges" {
  description = "Extra firewall rule source IPs (e.g. an operator workstation) for ad hoc psql access; empty by default"
  type        = list(string)
  default     = []
}

variable "postgres_backup_retention_days" {
  description = "Postgres backup retention in days (7 is the minimum)"
  type        = number
  default     = 7
}

variable "postgres_geo_redundant_backup_enabled" {
  description = "Whether to enable geo-redundant backups (cost-first default: disabled)"
  type        = bool
  default     = false
}

# Must be the "-database" variant: STORE_MODEL_IN_DB=True requires the
# bundled Prisma client/binaries and startup migration step. The plain
# `litellm` image errors without them.
variable "litellm_image_repository" {
  description = "Container image repository for the LiteLLM proxy (must be the Prisma-enabled database variant)"
  type        = string
  default     = "ghcr.io/berriai/litellm-database"
}

# No default on purpose: verify the current stable release tag on GHCR
# before applying. Never pin to `latest`/`main-latest` — every scale-from-zero
# cold start re-pulls the image, and a moving tag can silently change the
# LiteLLM version (and its Prisma schema) out from under this deployment.
variable "litellm_image_tag" {
  description = "Pinned LiteLLM container image tag (verify against ghcr.io/berriai/litellm-database tags; never `latest`)"
  type        = string
}

variable "litellm_min_replicas" {
  description = "Minimum Container App replicas (0 = scale-to-zero when idle)"
  type        = number
  default     = 0
}

variable "litellm_max_replicas" {
  description = "Maximum Container App replicas"
  type        = number
  default     = 2
}

variable "litellm_container_cpu" {
  description = "vCPU allocated to the LiteLLM container"
  type        = number
  default     = 0.5
}

variable "litellm_container_memory" {
  description = "Memory allocated to the LiteLLM container"
  type        = string
  default     = "1Gi"
}

variable "litellm_target_port" {
  description = "Port the LiteLLM proxy listens on inside the container"
  type        = number
  default     = 4000
}
