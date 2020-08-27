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

variable "letsencrypt_email" {
    type = string
    description = <<-EOT
    Email address to provide to Let's Encrypt for e.g. certificate expiry
    notifications.
    EOT
}