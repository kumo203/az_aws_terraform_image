
resource "azurerm_resource_group" "this" {
  name     = "${var.resource_prefix}-${local.name_suffix}-rg"
  location = var.location
}
