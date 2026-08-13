output "foundry_account_id" {
  value = azurerm_cognitive_account.foundry.id
}

output "foundry_endpoint" {
  description = "Internal-only. Paste into LiteLLM's Admin UI/API as `api_base` when registering the Azure model — never distribute directly to Copilot consumers."
  value       = azurerm_cognitive_account.foundry.endpoint
}

output "foundry_project_id" {
  value = azurerm_cognitive_account_project.this.id
}

output "model_deployment_ids" {
  value = { for k, v in azurerm_cognitive_deployment.models : k => v.id }
}

output "foundry_api_key" {
  description = "Internal-only. Paste into LiteLLM's Admin UI/API as `api_key` when registering the Azure model."
  value       = azurerm_cognitive_account.foundry.primary_access_key
  sensitive   = true
}

output "foundry_api_version" {
  description = "Value to enter as `api_version` when registering the Azure model in LiteLLM"
  value       = var.api_version
}

output "litellm_gateway_url" {
  description = "Copilot/client-facing base URL for this environment's LiteLLM Proxy"
  value       = "https://${azurerm_container_app.litellm.ingress[0].fqdn}"
}

output "litellm_master_key" {
  description = "Superuser key for LiteLLM's Admin API/UI — use only to bootstrap models/teams/keys, never distribute to end consumers"
  value       = local.litellm_master_key
  sensitive   = true
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "postgres_connection_string" {
  description = "Direct psql-style connection string for debugging LiteLLM's Prisma-managed schema"
  value       = local.postgres_connection_string
  sensitive   = true
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

# Everything needed to bootstrap this environment after the first `apply`,
# since model/team/key configuration now lives in LiteLLM's Postgres-backed
# runtime state rather than in Terraform. Re-verify the COPILOT_PROVIDER_TYPE
# value against LiteLLM's actual routes with `copilot --log-level debug`
# before relying on it — see az_litellm_tf/README.md.
output "bootstrap_instructions" {
  description = "One-time manual setup steps: health-check, register models, create a team + virtual key, then configure Copilot CLI with the virtual key (never the master key)"
  value       = <<-EOT
    1) Health check:
       curl https://${azurerm_container_app.litellm.ingress[0].fqdn}/health/liveliness

    2) Register each Azure model deployment (repeat per deployment in model_deployment_ids):
       curl -X POST https://${azurerm_container_app.litellm.ingress[0].fqdn}/model/new \
         -H "Authorization: Bearer <litellm_master_key>" \
         -H "Content-Type: application/json" \
         -d '{
               "model_name": "<deployment-name>",
               "litellm_params": {
                 "model": "azure/<deployment-name>",
                 "api_base": "${azurerm_cognitive_account.foundry.endpoint}",
                 "api_key": "<foundry_api_key>",
                 "api_version": "${var.api_version}"
               }
             }'

    3) Create a team and generate a virtual key:
       curl -X POST https://${azurerm_container_app.litellm.ingress[0].fqdn}/team/new \
         -H "Authorization: Bearer <litellm_master_key>" -H "Content-Type: application/json" \
         -d '{"team_alias": "team-alpha"}'
       curl -X POST https://${azurerm_container_app.litellm.ingress[0].fqdn}/key/generate \
         -H "Authorization: Bearer <litellm_master_key>" -H "Content-Type: application/json" \
         -d '{"team_id": "<team_id from previous step>"}'

    4) Configure Copilot CLI with the VIRTUAL KEY (not the master key):
       $env:COPILOT_PROVIDER_BASE_URL = "https://${azurerm_container_app.litellm.ingress[0].fqdn}"
       $env:COPILOT_PROVIDER_API_KEY  = "<virtual key from step 3>"
       $env:COPILOT_PROVIDER_TYPE     = "azure"  # unverified against LiteLLM — re-check with `copilot --log-level debug`
       $env:COPILOT_MODEL             = "<deployment-name>"
  EOT
}
