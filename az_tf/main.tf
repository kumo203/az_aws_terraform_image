
terraform {
  required_version = ">= 1.5"

  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "azurerm" {
  features {
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}

# resource_group_name/name_suffix come from the bootstrap/ module's outputs
# (see terraform.tfvars) so this project's resources land in the same
# resource group as the tfstate storage account instead of creating their own.
locals {
  name_suffix = var.name_suffix
}
