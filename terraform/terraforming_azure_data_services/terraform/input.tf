variable "environment" {
  type        = string
  description = "Environment identifier"
  default     = "eliasmeetup"
}

variable "location" {
  type        = string
  description = "Azure Region to which to deploy the resources."
  default     = "westeurope"
}

variable "vnet_address_space_list" {
  type        = list(string)
  description = "List of address spaces to include in AI Hub main VNET"
  default     = ["10.0.0.0/16"]
}

variable "databricks_public_subnet_address_prefix" {
  type        = string
  description = "Address prefix to use for Landing Zone Databricks' external communications subnet"
  default     = "10.0.0.0/24"
}

variable "databricks_private_subnet_address_prefix" {
  type        = string
  description = "Address prefix to use for Landing Zone Databricks' cluster-internal communications subnet"
  default     = "10.0.1.0/24"
}

variable "keyvault_aad_tenant_id" {
  type        = string
  description = "Azure AD Tenant ID for the target subscription."
}

variable "keyvault_acl_user_id" {
  type        = string
  description = "Azure AD User ID for user to add to Secret Management role in Key Vault"
}

variable "user_ip" {
  type        = string
  description = "Your current IP address. This will be added to firewalls for Data Lake Storage and Key Vault."
}
