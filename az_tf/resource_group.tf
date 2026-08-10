
# Created by the bootstrap/ module, which also owns the tfstate storage
# account within it. Referenced here (not (re)created) so az_tf's resources
# and the state backend live in one shared resource group.
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}
