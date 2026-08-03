
resource "azurerm_cognitive_account" "foundry" {
  name                       = "${var.resource_prefix}-foundry"
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  kind                       = "AIServices"
  sku_name                   = "S0"
  custom_subdomain_name      = "${var.resource_prefix}-foundry"
  project_management_enabled = true
  purge_on_destroy           = true

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_cognitive_account_project" "this" {
  name                 = "${var.resource_prefix}-project"
  cognitive_account_id = azurerm_cognitive_account.foundry.id
  location             = azurerm_resource_group.this.location
  display_name         = "${var.resource_prefix}-project"

  identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_cognitive_deployment.models]
}