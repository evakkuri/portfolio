/*
Example - Azure Kubernetes Service and supporting services - inputs for
Azure infrastructure
*/

variable "developer_ip_full" {
    type = string
    description = <<-EOT
    Outbound IP to set in the Azure services for limiting admin network access.
    EOT
}

variable "aks_owners_user_principal_names" {
    type = list(string)
    description = <<-EOT
    List of user ID's for creating the AKS Owners user group, which is then set
    as the admin for the AKS cluster
    EOT
}