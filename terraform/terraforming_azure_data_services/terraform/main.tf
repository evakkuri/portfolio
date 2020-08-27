# Terraform setup
terraform {}

# Providers
provider "azurerm" {
  version = "~> 2"
  features {}
}

provider "azuread" {
  version = "~> 0"
}

provider "random" {
  version = "~> 2"
}

#### Resource group
resource "azurerm_resource_group" "rg" {
  name     = "${var.environment}-rg"
  location = var.location

  tags = {
    Environment = var.environment
    Author      = "Elias Vakkuri"
  }
}

#### Data Lake Storage
resource "azurerm_storage_account" "data_lake_storage" {
  name                      = "${var.environment}adls"
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  account_kind              = "StorageV2"
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true
  is_hns_enabled            = true

  network_rules {
    /*
    - bypass defines which types of requests bypass the firewall settings 
    - Takes as parameter a list of strings
    - Valid values in list are "Logging", "Metrics", "AzureServices" and "None"
    - If you have "None" together with other values, None is disregarded and the other values are used instead
    - NOTE: different from e.g. Azure SQL Database, 'AzureServices' here covers only Azure resources in same subscription
      --> safer choice by comparison
      See https://docs.microsoft.com/en-gb/azure/storage/common/storage-network-security#exceptions for more information.
    */
    bypass = ["None", ]

    # default_action can be either "Deny" or "Allow"
    default_action = "Deny"

    # ip_rules takes either individual IP's or IP ranges in CIDR notation.
    # NOTE: /31 or /32 ranges are not supported, so write those out as individual IP's,
    # without the CIDR suffix. 
    ip_rules = [
      var.user_ip
    ]

    # List of VNET subnet resource ID's from which to allow traffic to Storage Account
    virtual_network_subnet_ids = [
      azurerm_subnet.subnet_databricks_public.id
    ]
  }

  # Set on diagnostic logging for Blobs with Azure CLI
  # This uses provisioner as Terraform AzureRm provider or ARM do not support this.
  # NOTE: This is only run on resource creation, not on subsequent updates.
  provisioner "local-exec" {
    command = "az storage logging update --log 'rwd' --retention 365 --services 'b' --account-name ${self.name}  --version '2.0'"
  }
}

# Create Data Lake Storage Filesystem
resource "azurerm_storage_data_lake_gen2_filesystem" "filesystem" {
  name               = "meetupfilesystem"
  storage_account_id = azurerm_storage_account.data_lake_storage.id
}

#### Databricks with VNET injection

# VNET
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.environment}-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = var.vnet_address_space_list
}

# Databricks Network Security Group
# Databricks will manage the security rules once you deploy the Databricks Workspace
resource "azurerm_network_security_group" "nsg_databricks" {
  name                = "${var.environment}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Databricks public subnet
# This needs to be delegated to Databricks
# This is also the subnet that connects to external data services, so add service
# endpoints here
resource "azurerm_subnet" "subnet_databricks_public" {
  name                 = "databricks-public"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefix       = var.databricks_public_subnet_address_prefix

  service_endpoints = [
    "Microsoft.Storage"
  ]

  delegation {
    name = "databricks-del-public"

    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

# NSG association for public subnet
resource "azurerm_subnet_network_security_group_association" "databricks_public_subnet_association" {
  subnet_id                 = azurerm_subnet.subnet_databricks_public.id
  network_security_group_id = azurerm_network_security_group.nsg_databricks.id
}

# Databricks private subnet
# This is for cluster-internal communications, so does not require service endpoints
resource "azurerm_subnet" "subnet_databricks_private" {
  name                 = "databricks-private"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefix       = var.databricks_private_subnet_address_prefix

  delegation {
    name = "databricks-del-private"

    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

# NSG-subnet association for public
resource "azurerm_subnet_network_security_group_association" "databricks_private_subnet_association" {
  subnet_id                 = azurerm_subnet.subnet_databricks_private.id
  network_security_group_id = azurerm_network_security_group.nsg_databricks.id
}

# Databricks Workspace
resource "azurerm_databricks_workspace" "databricks" {
  name                = "${var.environment}-bricks"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "standard"

  custom_parameters {
    no_public_ip        = false
    virtual_network_id  = azurerm_virtual_network.vnet.id
    public_subnet_name  = azurerm_subnet.subnet_databricks_public.name
    private_subnet_name = azurerm_subnet.subnet_databricks_private.name
  }
}

#### Secrets to Key Vault

# Key Vault
resource "azurerm_key_vault" "keyvault" {
  name                = "${var.environment}-kv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tenant_id           = var.keyvault_aad_tenant_id
  sku_name            = "standard"

  network_acls {
    bypass         = "None" # Possible values are "AzureServices" and "None"
    default_action = "Deny" # Possible values are "Allow" and "Deny"
    ip_rules = [
      "23.100.0.135/32",  # Databricks control plane IP, West & North Europe
      "${var.user_ip}/32" # Your current IP
      # NOTE: use full CIDR format as Key Vault forces the missing suffix, e.g. /32
      # If you do not have the suffix here, then you will see changes on each subsequent plan
    ]
    virtual_network_subnet_ids = []
  }
}

# Key Vault Access Control List entry
resource "azurerm_key_vault_access_policy" "keyvault_acl" {
  key_vault_id = azurerm_key_vault.keyvault.id
  tenant_id    = azurerm_key_vault.keyvault.tenant_id
  object_id    = var.keyvault_acl_user_id

  secret_permissions = [
    "backup", "delete", "get", "list", "purge", "recover", "restore", "set"
  ]
}

# Add Data Lake Storage primary key to Key Vault
resource "azurerm_key_vault_secret" "keyvault_secret_adls_primary_key" {
  depends_on   = [azurerm_key_vault_access_policy.keyvault_acl]
  key_vault_id = azurerm_key_vault.keyvault.id
  name         = "adls-primary-access-key"
  value        = azurerm_storage_account.data_lake_storage.primary_access_key
}

#### Accessing with Service Principal

# Application registration for Databricks
resource "azuread_application" "databricks_application" {
  name                       = "${var.environment}-databricks-sp"
  homepage                   = "https://${var.environment}-databricks-sp"
  available_to_other_tenants = false
}

/*
Create random string for Databricks Service Principal password
 
NOTE: in order to rotate the Service Principal password, taint and recreate THIS resource,
not the azuread_application_password resource.

If you only recreate the azuread_application_password resource, you will create a new
application password, but it will use the previously created password value.
*/
resource "random_password" "databricks_random_password" {
  length  = 64
  special = true
}

# Create Application password for Landing Zone Databricks
resource "azuread_application_password" "databricks_application_password" {
  application_object_id = azuread_application.databricks_application.id
  value                 = random_password.databricks_random_password.result
  end_date_relative     = "24h"
}

# Create Service Principal for Landing Zone Databricks
resource "azuread_service_principal" "databricks_sp" {
  application_id = azuread_application.databricks_application.application_id
}

# Add Service Principal client ID to Key Vault
resource "azurerm_key_vault_secret" "keyvault_secret_databricks_sp_client_id" {
  key_vault_id = azurerm_key_vault.keyvault.id
  name         = "databricks-sp-client-id"
  value        = azuread_service_principal.databricks_sp.application_id

  # Set explicit dependency to ACL entry, as otherwise Terraform will often delete the
  # ACL before the secrets, which will cause an error
  depends_on = [azurerm_key_vault_access_policy.keyvault_acl]
}

# Add Service Principal secret to Key Vault
resource "azurerm_key_vault_secret" "keyvault_secret_databricks_sp_secret" {
  key_vault_id = azurerm_key_vault.keyvault.id
  name         = "databricks-sp-secret"
  value        = azuread_application_password.databricks_application_password.value

  # Explicit dependency
  depends_on = [azurerm_key_vault_access_policy.keyvault_acl]
}

# Add access rights for Service Principal to ADLS
# To access data, you need data plane rights -> e.g. Storage Blob Data Contributor
resource "azurerm_role_assignment" "adls_databricks" {
  scope                = azurerm_storage_account.data_lake_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.databricks_sp.id
}
