
resource "azurerm_resource_group" "this" {
  name     = "${var.resource_prefix}-rg"
  location = var.location
}
