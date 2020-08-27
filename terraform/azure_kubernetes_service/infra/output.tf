/*
Example - Azure Kubernetes Service and supporting services - outputs from
Kubernetes resources
*/

output "acr_login_server" {
    value = azurerm_container_registry.acr.login_server
    description = <<-EOF
    Login server of the Container Registry. Used e.g. by Kubernetes deployments
    to identify container images.
    EOF
}