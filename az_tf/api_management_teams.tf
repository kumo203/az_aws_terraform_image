
resource "azurerm_api_management_product" "teams" {
  for_each              = var.copilot_teams
  product_id            = each.key
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = data.azurerm_resource_group.this.name
  display_name          = each.value.display_name
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "teams" {
  for_each            = var.copilot_teams
  api_name            = azurerm_api_management_api.aoai.name
  product_id          = azurerm_api_management_product.teams[each.key].product_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_api_management_product_policy" "teams" {
  for_each            = var.copilot_teams
  product_id          = azurerm_api_management_product.teams[each.key].product_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name

  xml_content = templatefile("${path.module}/policies/team-product-policy.xml.tftpl", {
    rate_limit_calls  = each.value.rate_limit_calls
    rate_limit_period = each.value.rate_limit_period_seconds
  })
}

resource "azurerm_api_management_subscription" "teams" {
  for_each            = var.copilot_teams
  api_management_name = azurerm_api_management.this.name
  resource_group_name = data.azurerm_resource_group.this.name
  product_id          = azurerm_api_management_product.teams[each.key].id
  display_name        = each.value.display_name
  state               = "active"
}
