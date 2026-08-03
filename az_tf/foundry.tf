
resource "azurerm_cognitive_account" "foundry" {
  name                       = "${var.resource_prefix}-${local.name_suffix}-foundry"
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  kind                       = "AIServices"
  sku_name                   = "S0"
  custom_subdomain_name      = "${var.resource_prefix}-${local.name_suffix}-foundry"
  project_management_enabled = true

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_cognitive_account_project" "this" {
  name                 = "${var.resource_prefix}-${local.name_suffix}-project"
  cognitive_account_id = azurerm_cognitive_account.foundry.id
  location             = azurerm_resource_group.this.location
  display_name         = "${var.resource_prefix}-${local.name_suffix}-project"

  identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_cognitive_deployment.models]
}