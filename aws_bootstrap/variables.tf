
variable "resource_prefix" {
  description = "Prefix for aws_tf resource names. Must match az_tf's resource_prefix convention (not the actual bucket/table names, which use a fixed short prefix due to S3 naming rules)."
  type        = string
  default     = "ai-prj-sample"
}

variable "region" {
  description = "AWS region for the tfstate bucket/lock table. Must be a region where the bedrock-mantle endpoint is available (us-east-1, us-east-2, or us-west-2) since aws_tf is deployed into the same region."
  type        = string
  default     = "us-east-1"
}
