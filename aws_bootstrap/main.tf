
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
}

# The same suffix is used by aws_tf/ (passed in via var.name_suffix) so both
# modules share one naming namespace, mirroring bootstrap/'s az_tf pairing.
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_suffix = random_id.suffix.hex
}

# S3 bucket names are globally unique and allow only lowercase alphanumeric
# characters and hyphens, so this uses a short fixed prefix instead of
# var.resource_prefix (which may contain characters unsafe to double up on).
resource "aws_s3_bucket" "tfstate" {
  bucket = "aiprj-${local.name_suffix}-tfstate"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# terraform's s3 backend needs a lock table to serialize concurrent applies;
# Azure's Blob backend does this natively via lease, so there is no
# azurerm-side equivalent resource to this one.
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "aiprj-${local.name_suffix}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
