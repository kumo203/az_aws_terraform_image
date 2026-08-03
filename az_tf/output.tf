output "foundry_account_id" {
  value = azurerm_cognitive_account.foundry.id
}

output "foundry_endpoint" {
  value = azurerm_cognitive_account.foundry.endpoint
}

output "foundry_project_id" {
  value = azurerm_cognitive_account_project.this.id
}

output "model_deployment_ids" {
  value = { for k, v in azurerm_cognitive_deployment.models : k => v.id }
}