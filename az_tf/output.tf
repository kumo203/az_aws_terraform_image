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

# Everything GitHub Copilot's BYOM policy needs, in one place, except the
# subscription key itself (kept separate/sensitive in apim_subscription_keys).
output "copilot_setup" {
  description = "Values to enter into GitHub Copilot's bring-your-own-model config; get the matching api-key from apim_subscription_keys"
  value = {
    base_url       = azurerm_api_management.this.gateway_url
    api_version    = var.api_version
    api_key_header = "api-key"
    deployment_ids = keys(var.model_deployments)
  }
}

# Ready-to-paste PowerShell env var commands for `copilot` CLI's Azure BYOK
# mode (https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models),
# one 3-line block per team/deployment combination. COPILOT_PROVIDER_TYPE is
# fixed to "azure" and isn't included here — set it once yourself alongside
# these three.
output "copilot_cli_powershell" {
  description = "team => deployment => PowerShell $env: commands (BASE_URL/API_KEY/MODEL) for GitHub Copilot CLI BYOK"
  sensitive   = true
  value = {
    for team_key, sub in azurerm_api_management_subscription.teams : team_key => {
      for deployment_key in keys(var.model_deployments) : deployment_key => join("\n", [
        "$env:COPILOT_PROVIDER_BASE_URL = \"${azurerm_api_management.this.gateway_url}/openai/deployments/${deployment_key}\"",
        "$env:COPILOT_PROVIDER_API_KEY = \"${sub.primary_key}\"",
        "$env:COPILOT_MODEL = \"${deployment_key}\"",
      ])
    }
  }
}
