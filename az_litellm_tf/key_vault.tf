
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  # Key Vault names allow only 3-24 chars, too short for the
  # "${var.resource_prefix}-${local.name_suffix}-kv" pattern used elsewhere in
  # this module ("ai-prj-litellm-<suffix>-kv" is 26 chars), so this uses a
  # short fixed prefix instead of var.resource_prefix (same reasoning as
  # bootstrap/main.tf's storage account name).
  name                       = "kv-litellm-${local.name_suffix}"
  location                   = data.azurerm_resource_group.this.location
  resource_group_name        = data.azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku_name
  rbac_authorization_enabled = true
  purge_protection_enabled   = var.key_vault_purge_protection_enabled
  soft_delete_retention_days = 7
}

# Connection-string-safe charset: avoids `@ : / ? # %`, which have delimiter
# meaning inside a postgresql:// URI and would otherwise need URL-encoding
# wherever the password is interpolated (see postgres.tf).
resource "random_password" "postgres_admin" {
  length           = 24
  special          = true
  override_special = "-_."
}

resource "random_password" "litellm_master_key" {
  length           = 32
  special          = true
  override_special = "-_."
}

# LiteLLM's own convention for master keys is an `sk-` prefix.
locals {
  litellm_master_key = "sk-${random_password.litellm_master_key.result}"
}

# Terraform's own identity needs write access to the RBAC-authorized vault
# before it can create secrets — same "grant role, wait for AAD propagation,
# then proceed" pattern az_tf/api_management.tf used for its MSI role
# assignment.
resource "azurerm_role_assignment" "tf_deployer_kv_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "kv_rbac_propagation" {
  depends_on      = [azurerm_role_assignment.tf_deployer_kv_secrets_officer]
  create_duration = "90s"
}

resource "azurerm_key_vault_secret" "litellm_master_key" {
  name         = "litellm-master-key"
  value        = local.litellm_master_key
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.kv_rbac_propagation]
}

resource "azurerm_key_vault_secret" "postgres_admin_password" {
  name         = "postgres-admin-password"
  value        = random_password.postgres_admin.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.kv_rbac_propagation]
}

resource "azurerm_key_vault_secret" "foundry_api_key" {
  name         = "foundry-api-key"
  value        = azurerm_cognitive_account.foundry.primary_access_key
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.kv_rbac_propagation]
}

# Read-only data-plane role for the Container App's runtime identity —
# deliberately separate from the write-capable role above.
resource "azurerm_role_assignment" "container_app_kv_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.litellm.principal_id
}

resource "time_sleep" "container_app_kv_rbac_propagation" {
  depends_on      = [azurerm_role_assignment.container_app_kv_secrets_user]
  create_duration = "90s"
}
