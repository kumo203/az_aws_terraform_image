
# This environment has no APIM in front of it (LiteLLM is the gateway), so the
# only observability need is a destination for the Container Apps
# Environment's console/system logs. Token usage/spend is tracked by LiteLLM
# itself in Postgres instead of Application Insights.
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.resource_prefix}-${local.name_suffix}-law"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  sku                 = "PerGB2018"
}
