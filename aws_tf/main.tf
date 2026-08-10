
terraform {
  required_version = ">= 1.5"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region
}

# name_suffix comes from the aws_bootstrap/ module's output (see
# terraform.tfvars) so this project's resources share the same naming
# namespace as the tfstate bucket/lock table.
locals {
  name_suffix = var.name_suffix
}
