
variable "resource_group_name" {
  description = "Name of the resource group holding the Terraform state storage account. Fixed (no random suffix) so it survives unrelated environment recreation in az_tf/."
  type        = string
  default     = "ai-prj-sample-tfstate-rg"
}

variable "location" {
  description = "Azure region for the state storage account"
  type        = string
  default     = "eastus2"
}

variable "storage_account_name" {
  description = "Globally-unique storage account name (lowercase alphanumeric only, 3-24 chars). Override if the default is already taken in your tenant."
  type        = string
  default     = "aiprjsampletfstate"
}
