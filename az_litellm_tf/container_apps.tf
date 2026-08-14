
# /model/new + STORE_MODEL_IN_DB=True DB persistence was confirmed broken
# against the (now old) main-v1.26.13 image, but re-verified working against
# main-v1.83.14-stable — it was a version gap, not a real LiteLLM bug. We
# still bake model_list into a static config.yaml here deliberately, so a bare
# `terraform apply` fully provisions the model list without ever depending on
# DB-registration behavior or requiring a manual /model/new call afterward.
# Passed in base64 via LITELLM_CONFIG_B64 and loaded with `litellm --config`
# on every container start (see the container block's command/args below).
# api_key is an os.environ reference, not a literal secret, so this is safe to
# keep in a plain (non-secret) env var.
locals {
  litellm_config = {
    model_list = [
      for name, _ in var.model_deployments : {
        model_name = name
        litellm_params = {
          model       = "azure/${name}"
          api_base    = azurerm_cognitive_account.foundry.endpoint
          api_key     = "os.environ/FOUNDRY_API_KEY"
          api_version = var.api_version
        }
      }
    ]
    general_settings = {
      master_key        = "os.environ/LITELLM_MASTER_KEY"
      database_url      = "os.environ/DATABASE_URL"
      store_model_in_db = true
    }
  }
  litellm_config_b64 = base64encode(yamlencode(local.litellm_config))

  # sh -c requires the script as a single argument (see container block args).
  litellm_startup_script = "echo \"$LITELLM_CONFIG_B64\" | base64 -d > /tmp/config.yaml && exec litellm --port $PORT --run_gunicorn --config /tmp/config.yaml"
}

# Consumption-only environment (no workload_profile block => Consumption,
# the cost-first default): no VNet integration, no NAT/idle infra cost.
resource "azurerm_container_app_environment" "this" {
  name                       = "${var.resource_prefix}-${local.name_suffix}-cae"
  location                   = data.azurerm_resource_group.this.location
  resource_group_name        = data.azurerm_resource_group.this.name
  logs_destination           = "log-analytics"
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

  secret {
    name                = "foundry-api-key"
    key_vault_secret_id = azurerm_key_vault_secret.foundry_api_key.id
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

      env {
        name        = "FOUNDRY_API_KEY"
        secret_name = "foundry-api-key"
      }

      env {
        name  = "LITELLM_CONFIG_B64"
        value = local.litellm_config_b64
      }

      # Overrides the image's default entrypoint so the baked-in model_list
      # config.yaml (LITELLM_CONFIG_B64 above) is loaded on every start,
      # instead of relying on the broken /model/new DB persistence.
      command = ["sh", "-c"]
      args    = [local.litellm_startup_script]

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
    azurerm_key_vault_secret.foundry_api_key,
  ]
}
