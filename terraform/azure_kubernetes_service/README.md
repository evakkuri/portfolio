# Azure Kubernetes Services with Terraform

## Overview
Terraform implementation following the rather good Microsoft Azure Kubernetes Service Workshop materials found here: https://docs.microsoft.com/en-us/learn/modules/aks-workshop/

Deploys:

__Azure infrastructure__
- VNET + subnet
- New user group for AKS admins
- Azure Kubernetes Service with default node pool in created subnet and Azure AD authentication
- Azure Container Registry
- Azure Key Vault
- Service Principal for Github Actions (not used yet, but plan to)

__Kubernetes resources__
- Sample app deployment with Helm and Kubernetes deployments from Azure Container Registry
- NGINX ingress controller
- cert-manager for TLS certificate automation

## Usage

### Prerequisites
You need access to an Azure Subscription or Resource Group where you have owner access. Also, you need to be able to create user groups and service principals.

In addition, clone the following sample app repos as they are deployed into the Kubernetes cluster:
https://github.com/MicrosoftDocs/mslearn-aks-workshop-ratings-api
https://github.com/MicrosoftDocs/mslearn-aks-workshop-ratings-web

### Implementation

The scripts are divided into two folders as follows:
* __infra__: Azure infrastructure, such as Azure Kubernetes Service, Azure Container Registry, etc.
* __kubernetes__: Everything that goes inside the Kubernetes cluster, such as the services, ingress controller, certificate management etc.

The reason for this split is that you after deploying the infra you need to push the container images into Azure Container Registry. This way also the two modules have separate states, which limits the blast radius of changes somewhat.

Once you have the scripts from this folder and the sample app repos handy, you should be good to go. The Terraform scripts contain further information.