
variable "resource_prefix" {
  description = "Prefix for the shared resource group name. Must match az_tf's resource_prefix so both modules target the same resource group."
  type        = string
  default     = "ai-prj-sample"
}

variable "location" {
  description = "Azure region for the shared resource group and state storage account"
  type        = string
  default     = "eastus2"
}
