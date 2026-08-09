
resource "azurerm_api_management" "this" {
  name                = "${var.resource_prefix}-${local.name_suffix}-apim"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = var.apim_sku_name

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_api_management_backend" "foundry" {
  name                = "foundry-openai"
  resource_group_name = data.azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = trimsuffix(azurerm_cognitive_account.foundry.endpoint, "/")
}

resource "azurerm_role_assignment" "apim_openai_user" {
  scope                = azurerm_cognitive_account.foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}

# APIM's managed-identity policy acquires an AAD token for the Foundry backend at
# request time; AAD role-assignment propagation is not modeled in Terraform's
# dependency graph, so this front-loads the typical delay into apply instead of
# surprising callers with 401/403s right after a successful apply.
resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.apim_openai_user]
  create_duration = "90s"
}
