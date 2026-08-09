output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

# Feed this into az_tf/terraform.tfvars (var.name_suffix) so az_tf's
# resources land in this same resource group with matching names.
output "name_suffix" {
  value = local.name_suffix
}

output "storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}

output "container_name" {
  value = azurerm_storage_container.tfstate.name
}
