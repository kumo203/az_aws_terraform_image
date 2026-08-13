
resource "azurerm_postgresql_flexible_server" "this" {
  name                = "${var.resource_prefix}-${local.name_suffix}-pg"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name

  administrator_login    = var.postgres_admin_username
  administrator_password = random_password.postgres_admin.result

  sku_name   = var.postgres_sku_name
  version    = var.postgres_version
  storage_mb = var.postgres_storage_mb

  backup_retention_days        = var.postgres_backup_retention_days
  geo_redundant_backup_enabled = var.postgres_geo_redundant_backup_enabled

  # No VNet/private endpoint (cost-first decision); reachability is via the
  # "allow Azure services" firewall rule below plus enforced SSL.
  public_network_access_enabled = true

  # Left unpinned so Azure can place the server in whichever zone has
  # capacity for the Burstable SKU, avoiding zone-specific capacity failures.
}

resource "azurerm_postgresql_flexible_server_database" "litellm" {
  name      = var.postgres_database_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Azure's documented "allow any Azure-hosted resource" rule. Needed because
# Container Apps Consumption plan has no static/predictable outbound IP
# without VNet integration, which this design deliberately avoids for cost.
# Accepted tradeoff: any Azure tenant's resource can attempt a TCP connection
# here, though it still needs valid credentials to get past authentication.
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "admin_workstation" {
  for_each = { for idx, cidr in var.postgres_admin_source_ip_ranges : idx => cidr }

  name             = "admin-workstation-${each.key}"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = each.value
  end_ip_address   = each.value
}

# sslmode=require matches Postgres Flexible Server's default
# require_secure_transport=ON — do not disable it.
locals {
  postgres_connection_string = "postgresql://${var.postgres_admin_username}:${random_password.postgres_admin.result}@${azurerm_postgresql_flexible_server.this.fqdn}:5432/${var.postgres_database_name}?sslmode=require"
}

resource "azurerm_key_vault_secret" "postgres_connection_string" {
  name         = "postgres-connection-string"
  value        = local.postgres_connection_string
  key_vault_id = azurerm_key_vault.this.id
  depends_on = [
    time_sleep.kv_rbac_propagation,
    azurerm_postgresql_flexible_server_database.litellm,
  ]
}
