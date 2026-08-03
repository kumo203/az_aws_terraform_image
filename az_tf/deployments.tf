
resource "azurerm_cognitive_deployment" "models" {
  for_each = var.model_deployments

  name                 = each.key
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  model {
    format  = "OpenAI"
    name    = each.key
    version = each.value.version
  }

  sku {
    name     = var.deployment_sku_name
    capacity = var.deployment_capacity
  }
}