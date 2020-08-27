/*
Example - Azure Kubernetes Service and supporting services - cloud infra

Based on Microsoft Azure Kubernetes Service Workshop materials:
https://docs.microsoft.com/en-us/learn/modules/aks-workshop/

Deploys:
- VNET + subnet
- New user group for AKS admins
- Azure Kubernetes Service with default node pool in created subnet and Azure
  AD authentication
- Azure Container Registry

- Service Principal with password authentication for GitHub Actions, with
  credentials written to a GitHub repo
*/

# Backend settings
terraform {

  required_providers {
    azuread = {
      "source"  = "hashicorp/azuread"
      "version" = "~> 0"
    }
    azurerm = {
      "source"  = "hashicorp/azurerm"
      "version" = "~> 2"
    }
    github = {
      "source"  = "hashicorp/github"
      "version" = "~> 2"
    }
    null = {
      "source"  = "hashicorp/null"
      "version" = "2.1.2"
    }
    random = {
      "source"  = "hashicorp/random"
      "version" = "~> 2"
    }
  }

  required_version = "~> 0.13"
}

data "azuread_users" "aks_owners_user_principal_names" {
  user_principal_names = var.aks_owners_user_principal_names
}

resource "random_integer" "random_suffix" {
  min = 1000
  max = 9999
}

locals {
  RANDOM_SUFFIX             = random_integer.random_suffix.result
  AKS_ADMINS_MEMBER_ID_LIST = data.azuread_users.aks_owners_user_principal_names.object_ids
  DEVELOPER_IP_FULL         = var.developer_ip_full
}

provider "azuread" {}

provider "azurerm" {
  features {}
}

data "azurerm_subscription" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "rg" {
  name     = join("", ["example-aks-rg", local.RANDOM_SUFFIX])
  location = "westeurope"
}

# Create VNET and subnet
resource "azurerm_virtual_network" "vnet" {
  name                = join("", ["example-aks-vnet", local.RANDOM_SUFFIX])
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/8"]
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.240.0.0/16"]
}

# Create user group for Azure Kubernetes Service admins
resource "azuread_group" "aks_admins" {
  name    = "aks-admins"
  members = local.AKS_ADMINS_MEMBER_ID_LIST
}

# Create Key Vault
resource "azurerm_key_vault" "key_vault" {
  name                = join("", ["example-aks-kv", local.RANDOM_SUFFIX])
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tenant_id           = data.azurerm_subscription.current.tenant_id
  sku_name            = "standard"
  soft_delete_enabled = true

  network_acls {
    bypass         = "None" # Possible values are "AzureServices" and "None"
    default_action = "Deny" # Possible values are "Allow" and "Deny"
    ip_rules = [
      local.DEVELOPER_IP_FULL
    ]
  }
}

# Create Key Vault Access Control List entry for new AKS Admins group
resource "azurerm_key_vault_access_policy" "owners_acl" {
  key_vault_id       = azurerm_key_vault.key_vault.id
  tenant_id          = data.azurerm_subscription.current.tenant_id
  object_id          = azuread_group.aks_admins.id
  secret_permissions = ["get", "set", "list", "delete"]
}

# Create Azure Kubernetes Service cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = join("", ["example-aks-cluster", local.RANDOM_SUFFIX])
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "exampleaks1"

  network_profile {

    # network_plugin: We're specifying the creation of the AKS cluster by using the CNI plug-in.
    network_plugin = "azure"

    load_balancer_sku = "standard"

    # service_cidr: This address range is the set of virtual IPs that
    # Kubernetes assigns to internal services in your cluster. The range must
    # not be within the virtual network IP address range of your cluster.
    # It should be different from the subnet created for the pods.
    service_cidr = "10.2.0.0/24"

    # dns_service_ip: The IP address is for the cluster's DNS service. This
    # address must be within the Kubernetes service address range. Don't use
    # the first IP address in the address range, such as 0.1. The first address
    # in the subnet range is used for the kubernetes.default.svc.cluster.local
    # address.
    dns_service_ip = "10.2.0.10"

    # docker-bridge-address: The Docker bridge network address represents the
    # default docker0 bridge network address present in all Docker
    # installations. AKS clusters or the pods themselves don't use docker0
    # bridge. However, you have to set this address to continue supporting
    # scenarios such as docker build within the AKS cluster. It's required to
    # select a classless inter-domain routing (CIDR) for the Docker bridge
    # network address. If you don't set a CIDR, Docker chooses a subnet
    # automatically. This subnet could conflict with other CIDRs. Choose an
    # address space that doesn't collide with the rest of the CIDRs on your
    # networks, which includes the cluster's service CIDR and pod CIDR.
    docker_bridge_cidr = "172.17.0.1/16"
  }

  default_node_pool {
    name           = "default"
    node_count     = 2
    vm_size        = "Standard_D2_v2"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  role_based_access_control {
    enabled = true

    azure_active_directory {
      managed = true
      admin_group_object_ids = [
        azuread_group.aks_admins.id
      ]
    }
  }

  addon_profile {
    kube_dashboard {
      enabled = true
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

# Create Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = join("", ["exampleaksacr", local.RANDOM_SUFFIX])
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
}

# Assign permissions for AKS to access ACR.
# Curiously, it's not the AKS clusters surfaced Managed Identity, instead
# it's another Managed Identity called '<AKS cluster name>-agentpool' to which
# you need to give the AcrPull right.

data "azuread_service_principal" "aks_agentpool" {
  display_name = "${azurerm_kubernetes_cluster.aks.name}-agentpool"
}

resource "azurerm_role_assignment" "aks_agentpool_acrpull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = data.azuread_service_principal.aks_agentpool.id
}

# Create Resource Group role assignment for Github Service Principal
resource "azurerm_role_assignment" "github_rg_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.id
}

# Create ACR role assignment for Github Service Principal
resource "azurerm_role_assignment" "github_acrpush" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github_actions.id
}

### CI / CD

# Create Azure AD Application and Service Principal for GitHub actions

# Create Application registration
resource "azuread_application" "github_actions" {
  name                       = "github-actions-app"
  homepage                   = "https://github-actions-app"
  available_to_other_tenants = false
}

# Create random passwords for Application and Service Principal
# NOTE: If you want to roll passwords, taint one of these, not the Application
# passwords
resource "random_password" "github_actions_1" {
  length  = 64
  special = false
}

resource "random_password" "github_actions_2" {
  length  = 64
  special = false
}

/*
Create Application passwords

Metadata for these is visible with "az ad sp credential list --id ..."

Login works with both passwords

You can provide either a concrete end date, done here with a local variable,
or you can provide end_date_relative, which updates the expiry based on
current timestamp.
*/
resource "azuread_application_password" "github_actions_1" {
  application_object_id = azuread_application.github_actions.id
  value                 = random_password.github_actions_1.result
  end_date_relative     = "8760h"
}

resource "azuread_application_password" "github_actions_2" {
  application_object_id = azuread_application.github_actions.id
  value                 = random_password.github_actions_2.result
  end_date_relative     = "8760h"
}

# Create Service Principal
resource "azuread_service_principal" "github_actions" {
  application_id = azuread_application.github_actions.application_id
}

locals {
  AZURE_CREDENTIALS = <<-EOF
  {
    "clientId": ${azuread_service_principal.github_actions.application_id},
    "clientSecret": ${azuread_application_password.github_actions_1.value},
    "subscriptionId": ${data.azurerm_subscription.current.id},
    "tenantId": ${data.azurerm_subscription.current.tenant_id},
    "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
    "resourceManagerEndpointUrl": "https://management.azure.com/",
    "activeDirectoryGraphResourceId": "https://graph.windows.net/",
    "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
    "galleryEndpointUrl": "https://gallery.azure.com/",
    "managementEndpointUrl": "https://management.core.windows.net/"
  }
  EOF
}

# Admin username
resource "azurerm_key_vault_secret" "github_credentials_json" {
  depends_on   = [azurerm_key_vault_access_policy.owners_acl]
  key_vault_id = azurerm_key_vault.key_vault.id
  name         = "github-credentials-json"
  value        = local.AZURE_CREDENTIALS
}
