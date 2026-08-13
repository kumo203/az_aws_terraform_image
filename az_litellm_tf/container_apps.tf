
# Consumption-only environment (no workload_profile block => Consumption,
# the cost-first default): no VNet integration, no NAT/idle infra cost.
resource "azurerm_container_app_environment" "this" {
  name                       = "${var.resource_prefix}-${local.name_suffix}-cae"
  location                   = data.azurerm_resource_group.this.location
  resource_group_name        = data.azurerm_resource_group.this.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
}

# Dedicated UAI (rather than SystemAssigned) so the Key Vault "Secrets User"
# role assignment in key_vault.tf can exist and start propagating before the
# Container App itself is created, avoiding a chicken/egg dependency cycle.
resource "azurerm_user_assigned_identity" "litellm" {
  name                = "${var.resource_prefix}-${local.name_suffix}-litellm-id"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_container_app" "litellm" {
  name                         = "${var.resource_prefix}-${local.name_suffix}-litellm"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = data.azurerm_resource_group.this.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.litellm.id]
  }

  secret {
    name                = "postgres-connection-string"
    key_vault_secret_id = azurerm_key_vault_secret.postgres_connection_string.id
    identity            = azurerm_user_assigned_identity.litellm.id
  }

  secret {
    name                = "litellm-master-key"
    key_vault_secret_id = azurerm_key_vault_secret.litellm_master_key.id
    identity            = azurerm_user_assigned_identity.litellm.id
  }

  template {
    min_replicas = var.litellm_min_replicas
    max_replicas = var.litellm_max_replicas

    container {
      name   = "litellm"
      image  = "${var.litellm_image_repository}:${var.litellm_image_tag}"
      cpu    = var.litellm_container_cpu
      memory = var.litellm_container_memory

      env {
        name        = "DATABASE_URL"
        secret_name = "postgres-connection-string"
      }

      env {
        name        = "LITELLM_MASTER_KEY"
        secret_name = "litellm-master-key"
      }

      env {
        name  = "STORE_MODEL_IN_DB"
        value = "True"
      }

      env {
        name  = "PORT"
        value = tostring(var.litellm_target_port)
      }

      # Cold start (scale-from-zero) + Prisma init/migration-check + first DB
      # round trip can stack on the very first request. These thresholds are
      # a starting point only — tune after observing real cold-start timing;
      # an overly strict probe can leave a revision permanently unroutable on
      # the Consumption plan.
      liveness_probe {
        transport               = "HTTP"
        port                    = var.litellm_target_port
        path                    = "/health/liveliness"
        initial_delay           = 30
        interval_seconds        = 30
        timeout                 = 10
        failure_count_threshold = 5
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = var.litellm_target_port
        path                    = "/health/readiness"
        interval_seconds        = 10
        timeout                 = 10
        failure_count_threshold = 5
        success_count_threshold = 1
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = var.litellm_target_port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [
    time_sleep.container_app_kv_rbac_propagation,
    azurerm_postgresql_flexible_server_firewall_rule.allow_azure_services,
    azurerm_key_vault_secret.postgres_connection_string,
    azurerm_key_vault_secret.litellm_master_key,
  ]
}
