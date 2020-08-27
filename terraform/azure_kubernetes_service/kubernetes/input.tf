/*
Example - Azure Kubernetes Service and supporting services - inputs for
Kubernetes resources
*/

variable "acr_login_server" {
    type = string
    description = <<-EOF
    Login server of Azure Container Registry from which to fetch container
    images.
    EOF
}