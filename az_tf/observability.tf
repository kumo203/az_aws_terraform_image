
resource "azurerm_log_analytics_workspace" "this" {
  count               = var.enable_apim_diagnostics ? 1 : 0
  name                = "${var.resource_prefix}-${local.name_suffix}-law"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  sku                 = "PerGB2018"
}

resource "azurerm_application_insights" "this" {
  count               = var.enable_apim_diagnostics ? 1 : 0
  name                = "${var.resource_prefix}-${local.name_suffix}-appi"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this[0].id
  application_type    = "web"
}

resource "azurerm_api_management_logger" "appinsights" {
  count               = var.enable_apim_diagnostics ? 1 : 0
  name                = "appinsights-logger"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  resource_id         = azurerm_application_insights.this[0].id

  application_insights {
    instrumentation_key = azurerm_application_insights.this[0].instrumentation_key
  }
}

resource "azurerm_api_management_diagnostic" "appinsights" {
  count                    = var.enable_apim_diagnostics ? 1 : 0
  identifier               = "applicationinsights"
  api_management_name      = azurerm_api_management.this.name
  resource_group_name      = data.azurerm_resource_group.this.name
  api_management_logger_id = azurerm_api_management_logger.appinsights[0].id
  sampling_percentage      = 100
  verbosity                = "information"

  # Logs the client-facing prompt/response bodies (per-subscription/team
  # attribution comes for free — APIM gateway logs always include the
  # subscription ID). 8192 bytes is the hard Azure maximum per field. Only
  # frontend_* is set: backend_request/response would duplicate this same
  # content (the policy forwards the body unchanged) while pushing the
  # combined log entry closer to the 32KB total cap, past which APIM drops
  # the body/trace entirely instead of truncating it.
  frontend_request {
    body_bytes = 8192

    # Preserves APIM's own default (implicit when this block is omitted
    # entirely): the API accepts api-key as a query param too
    # (subscription_key_parameter_names.query in api_management_api.tf), so
    # query params must stay masked or the key would appear in plaintext logs.
    data_masking {
      query_params {
        mode  = "Hide"
        value = "*"
      }
    }
  }

  frontend_response {
    body_bytes = 8192
  }
}
