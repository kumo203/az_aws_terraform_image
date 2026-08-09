
resource "azurerm_log_analytics_workspace" "this" {
  count               = var.enable_apim_diagnostics ? 1 : 0
  name                = "${var.resource_prefix}-${local.name_suffix}-law"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
}

resource "azurerm_application_insights" "this" {
  count               = var.enable_apim_diagnostics ? 1 : 0
  name                = "${var.resource_prefix}-${local.name_suffix}-appi"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this[0].id
  application_type    = "web"
}

resource "azurerm_api_management_logger" "appinsights" {
  count               = var.enable_apim_diagnostics ? 1 : 0
  name                = "appinsights-logger"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  resource_id         = azurerm_application_insights.this[0].id

  application_insights {
    instrumentation_key = azurerm_application_insights.this[0].instrumentation_key
  }
}

resource "azurerm_api_management_diagnostic" "appinsights" {
  count                    = var.enable_apim_diagnostics ? 1 : 0
  identifier               = "applicationinsights"
  api_management_name      = azurerm_api_management.this.name
  resource_group_name      = azurerm_resource_group.this.name
  api_management_logger_id = azurerm_api_management_logger.appinsights[0].id
  sampling_percentage      = 100
  verbosity                = "information"
}
