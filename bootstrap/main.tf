
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

# The same suffix is used by az_tf/ (passed in via var.name_suffix) so both
# modules address the one shared resource group.
resource "random_uuid" "suffix" {}

locals {
  name_suffix = substr(replace(random_uuid.suffix.result, "-", ""), 0, 8)
}

resource "azurerm_resource_group" "this" {
  name     = "${var.resource_prefix}-${local.name_suffix}-rg"
  location = var.location
}

# Storage account names allow only lowercase alphanumeric characters (no
# hyphens) within 3-24 chars, so this uses a short fixed prefix instead of
# var.resource_prefix.
resource "azurerm_storage_account" "tfstate" {
  name                            = "aiprj${local.name_suffix}tfstate"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# terraform's azurerm backend uses use_azuread_auth, so whoever runs `terraform
# init -migrate-state` / `terraform apply` against this backend needs data-plane
# access on the storage account, not just management-plane (ARM) access.
resource "azurerm_role_assignment" "state_access" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
