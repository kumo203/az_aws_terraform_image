output "foundry_account_id" {
  value = azurerm_cognitive_account.foundry.id
}

output "foundry_endpoint" {
  description = "Internal-only. Do not distribute to Copilot consumers post-APIM cutover — use apim_gateway_url instead."
  value       = azurerm_cognitive_account.foundry.endpoint
}

output "foundry_project_id" {
  value = azurerm_cognitive_account_project.this.id
}

output "model_deployment_ids" {
  value = { for k, v in azurerm_cognitive_deployment.models : k => v.id }
}

output "apim_gateway_url" {
  description = "Stable Copilot-facing endpoint; configure this as the AOAI base URL in Copilot's BYOM policy"
  value       = azurerm_api_management.this.gateway_url
}

output "apim_subscription_keys" {
  description = "Per-team APIM subscription (api-key) values; distribute one per team, never the raw Foundry key"
  value       = { for k, v in azurerm_api_management_subscription.teams : k => v.primary_key }
  sensitive   = true
}