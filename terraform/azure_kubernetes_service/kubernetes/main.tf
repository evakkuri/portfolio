/*
Example - Azure Kubernetes Service and supporting services - Kubernetes
resources

Based on Microsoft Azure Kubernetes Workshop materials:
https://docs.microsoft.com/en-us/learn/modules/aks-workshop/

Deploys:
- Sample app deployment with Helm and Kubernetes deployments from Azure
  Container Registry
- NGINX ingress controller
- cert-manager for TLS certificate automation

NOTE 1:
Deploy first the cloud infra in folder '../aks'. Then note the login server
of the Azure Container Registry, that is required as an input for Kubernetes
deployments below.

NOTE 2:
Currently the Kubernetes and Helm providers rely on Azure AD authentication to
work. This causes the deployment to fail at the point of Kubernetes deployments
as the authentication needs to be configured separately. This is quite safe,
just run the deployment up to failure, authenticate to AKS with Azure AD, then
run the deployment again.

To authenticate with Azure AD, first get a token from AKS with Azure CLI:

az aks get-credentials --resource-group <RG name> --name <AKS cluster name>

Then run e.g. 'kubectl get nodes' to start the Azure authentication flow.

This should fill the necessary information in Kubernetes configuration


NOTE 3:
For this to work, you need to separately push the relevant example app images
to Azure Container Registry. 

You can build and push the image by cloning these publicly available
repository:
https://github.com/MicrosoftDocs/mslearn-aks-workshop-ratings-api
https://github.com/MicrosoftDocs/mslearn-aks-workshop-ratings-web

and then in each repo folder, building the Docker image and pushing it into ACR
with one Azure CLI command:

az acr build \
  --resource-group <Resource Group name> \
  --registry <ACR name> \
  --image <ratings-api:v1 OR ratings-web:v1> .

Note the period at the end, that's to identify the current folder.

NOTE 4:
Let's Encrypt certificates seem to rate-limit quite aggressively for the
publicly available domain name services like nip.io. In many cases it seems
difficult to get a certificate.
*/

terraform {

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "1.2.4"
    }
    kubernetes = {
      "source"  = "hashicorp/kubernetes"
      "version" = "1.12.0"
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

locals {
  LETSENCRYPT_EMAIL              = var.letsencrypt_email
  LETSENCRYPT_STAGING_ANNOTATION = "letsencrypt-staging"
  LETSENCRYPT_PROD_ANNOTATION    = "letsencrypt-prod"
  AKS_MONGODB_USERNAME           = "eliasvakkuri"
  AKS_MONGODB_PASSWORD           = data.kubernetes_secret.mongodb_password.data.mongodb-password
  AKS_MONGODB_CONN_STR           = "mongodb://${local.AKS_MONGODB_USERNAME}:${local.AKS_MONGODB_PASSWORD}@ratings-mongodb.ratingsapp:27017/ratingsdb"
  AKS_RATINGS_API_NAME           = "ratings-api"
  AKS_RATINGS_WEB_NAME           = "ratings-web"
}

# Configure Terraform Kubernetes provider, for managing the Kubernetes cluster.
# When configured like this, uses default Kubernetes configuration file (e.g.
# ~/.kube/config) for credentials. To get this working, authenticate to AKS
# beforehand with Azure CLI:
#
# az aks get-credentials --resource-group <RG name> --name <AKS cluster name>
#
# and then run e.g. 'kubectl get nodes' to start the Azure authentication flow. 
#
# This should fill the necessary information in Kubernetes configuration
provider "kubernetes" {}

# Configure Terraform Helm provider, for installing Helm charts.
# When configured like this, uses the same Kubernetes config file and auth
# as above
provider "helm" {}

# Define namespace for example app
resource "kubernetes_namespace" "ratings" {

  metadata {
    annotations = {
      "name" = "ratingsapp"
    }

    labels = {
      "app" = "ratingsapp"
    }

    name = "ratingsapp"
  }
}

# Deploy a MongoDB database container with Helm
# This also creates relevant Kubernetes secrets, which are used next
resource "helm_release" "ratings_mongodb" {
  name       = "ratings"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "mongodb"
  namespace  = kubernetes_namespace.ratings.metadata[0].name

  set {
    name  = "auth.username"
    value = "eliasvakkuri"
  }

  set {
    name  = "auth.database"
    value = "ratingsdb"
  }
}

# Get MongoDB password from Kubernetes secrets
data "kubernetes_secret" "mongodb_password" {
  depends_on = [helm_release.ratings_mongodb]
  metadata {
    name      = "ratings-mongodb"
    namespace = "ratingsapp"
  }
}

# Create a new secret with the
resource "kubernetes_secret" "mongodb_connection_string" {
  metadata {
    namespace = kubernetes_namespace.ratings.metadata[0].name
    name      = "mongosecret"
  }

  data = {
    "MONGOCONNECTION" = local.AKS_MONGODB_CONN_STR
  }
}

# Deploy the ratings app backend API containers using Kubernetes deployment.
#
# NOTE: The image needs to be pushed to the ACR repository beforehand for the
# deployment to work. You can safely deploy with Terraform and let the
# deployment fail, then build and push the image, then terraform apply again
# for the rest of the resources.
#
# You can build and push the image by cloning this publicly available
# repository:
#
# https://github.com/MicrosoftDocs/mslearn-aks-workshop-ratings-api
# 
# and then building the Docker image and pushing it into ACR. you can do this
# with one Azure CLI command when in the cloned repo folder:
# 
# az acr build \
#   --resource-group <Resource Group name> \
#   --registry <ACR name> \
#   --image ratings-api:v1 .
#
resource "kubernetes_deployment" "ratings_api" {

  timeouts {
    create = "5m"
  }

  metadata {
    name      = local.AKS_RATINGS_API_NAME
    namespace = kubernetes_namespace.ratings.metadata[0].name
    labels = {
      "app" = local.AKS_RATINGS_API_NAME
    }
  }

  spec {

    selector {
      match_labels = {
        app = local.AKS_RATINGS_API_NAME
      }
    }

    template {
      metadata {
        labels = {
          app = local.AKS_RATINGS_API_NAME # The label for the pods and the deployments
        }
      }

      spec {
        container {
          name              = local.AKS_RATINGS_API_NAME
          image             = "${var.acr_login_server}/${local.AKS_RATINGS_API_NAME}:v1"
          image_pull_policy = "Always"

          port {
            container_port = 3000
          }

          env {
            name = "MONGODB_URI" # the application expects to find the MongoDB connection details in this environment variable
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mongodb_connection_string.metadata[0].name # the name of the Kubernetes secret containing the data
                key  = "MONGOCONNECTION"                                            # the key inside the Kubernetes secret containing the data
              }
            }
          }

          resources {
            requests {
              cpu    = "250m"
              memory = "64Mi"
            }
            limits {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          readiness_probe {
            http_get {
              port = 3000
              path = "/healthz"
            }
          }

          liveness_probe {
            http_get {
              port = 3000
              path = "/healthz"
            }
          }
        }
      }
    }
  }
}

# Define Service to expose the deployment
resource "kubernetes_service" "ratings_api" {
  depends_on = [kubernetes_deployment.ratings_api]
  metadata {
    name      = local.AKS_RATINGS_API_NAME
    namespace = kubernetes_namespace.ratings.metadata[0].name
  }
  spec {
    type = "ClusterIP"

    selector = {
      app = local.AKS_RATINGS_API_NAME
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 3000
    }
  }
}

# Deploy the ratings app frontend containers using Kubernetes deployment.
#
# NOTE: Same notes for deploying image to ACR as for the previous deployment
# apply. See above for instructions. 
#
# The code for the front-end application can be found in the publicly available
# repo:
#
# https://github.com/MicrosoftDocs/mslearn-aks-workshop-ratings-web
#
# and the Azure CLI command to use is:
# az acr build \
#   --resource-group <Resource Group name> \
#   --registry <ACR name> \
#   --image ratings-web:v1 .
resource "kubernetes_deployment" "ratings_web" {
  depends_on = [kubernetes_service.ratings_api]

  timeouts {
    create = "5m"
  }

  metadata {
    name      = local.AKS_RATINGS_WEB_NAME
    namespace = kubernetes_namespace.ratings.metadata[0].name
    labels = {
      "app" = local.AKS_RATINGS_WEB_NAME
    }
  }

  spec {

    selector {
      match_labels = {
        app = local.AKS_RATINGS_WEB_NAME
      }
    }

    template {
      metadata {
        labels = {
          app = local.AKS_RATINGS_WEB_NAME # The label for the pods and the deployments
        }
      }

      spec {
        container {
          name              = local.AKS_RATINGS_WEB_NAME
          image             = "${var.acr_login_server}/${local.AKS_RATINGS_WEB_NAME}:v1"
          image_pull_policy = "Always"

          port {
            container_port = 8080
          }

          env {
            name  = "API" # the application expects to connect to the API at this endpoint
            value = "http://${local.AKS_RATINGS_API_NAME}.${kubernetes_namespace.ratings.metadata[0].name}.svc.cluster.local"
          }

          resources {
            requests {
              cpu    = "250m"
              memory = "64Mi"
            }
            limits {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
}

# Define Service to expose the deployment
resource "kubernetes_service" "ratings_web" {
  depends_on = [kubernetes_deployment.ratings_web]
  metadata {
    name      = local.AKS_RATINGS_WEB_NAME
    namespace = kubernetes_namespace.ratings.metadata[0].name
  }
  spec {
    type = "ClusterIP"

    selector = {
      app = local.AKS_RATINGS_WEB_NAME
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8080
    }
  }
}

### Ingress controller using NGINX

# Create new namespace for NGINX ingress controller
resource "kubernetes_namespace" "ingress" {

  metadata {
    annotations = {
      "name" = "ingress"
    }

    labels = {
      "app" = "ingress"
    }

    name = "ingress"
  }
}

# Deploy an NGINX ingress controller using a Helm chart
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes-charts.storage.googleapis.com/"
  chart      = "nginx-ingress"
  namespace  = kubernetes_namespace.ingress.metadata[0].name

  set {
    name  = "controller.replicaCount"
    value = 2
  }

  set {
    name  = join("", ["controller.nodeSelector.", "beta\\.kubernetes\\.io/os"])
    value = "linux"
    type  = "string"
  }

  set {
    name  = join("", ["defaultBackend.nodeSelector.", "beta\\.kubernetes\\.io/os"])
    value = "linux"
    type  = "string"
  }
}

# Services can identify the ingress controller with the ingress service's
# external IP with periods replaced by dashes -> Get the external IP of the
# NGINX ingress service and create a dashed version of that, and create a host
# string.

data "kubernetes_service" "nginx_ingress_controller" {
  depends_on = [helm_release.nginx_ingress]

  metadata {
    name      = "${helm_release.nginx_ingress.name}-controller"
    namespace = kubernetes_namespace.ingress.metadata[0].name
  }
}

locals {
  NGINX_INGRESS_HOST_IP = replace(
    data.kubernetes_service.nginx_ingress_controller.load_balancer_ingress.0.ip,
    ".",
    "-"
  )
  NGINX_INGRESS_HOST = "frontend.${local.NGINX_INGRESS_HOST_IP}.nip.io"
}

### SSL/TLS termination using cert-manager

# Create a new namespace for cert-manager
resource "kubernetes_namespace" "cert_manager" {

  metadata {
    annotations = {
      "name" = "cert-manager"
    }

    labels = {
      "app" = "cert-manager"
    }

    name = "cert-manager"
  }
}

# Deploy cert-manager using Helm
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  version    = "v0.16.1"

  set {
    name  = "installCRDs"
    value = true
  }

  set {
    name  = "nodeSelector.beta\\.kubernetes\\.io/os"
    value = "linux"
    type  = "string"
  }
}

# Deploy Let's Encrypt cert-manager Issuer. As this is a custom resource
# created by cert-manager, this must be done outside the Kubernetes provider
resource "null_resource" "cert_manager_issuers" {
  provisioner "local-exec" {
    #command = "kubectl create -f cluster-issuers.yaml --namespace ${kubernetes_namespace.ratings.metadata[0].name}"
    command = <<EOT
cat <<EOF | kubectl create --namespace ratingsapp -f -
apiVersion: cert-manager.io/v1alpha2
kind: Issuer
metadata:
  name: ${local.LETSENCRYPT_STAGING_ANNOTATION}
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${local.LETSENCRYPT_EMAIL}
    privateKeySecretRef:
      name: ${local.LETSENCRYPT_STAGING_ANNOTATION}
    solvers:
    - http01:
        ingress:
          class:  nginx
EOF
EOT
  }
}

# Create a Kubernetes ingress using the dashed external IP of the ingress
# controller created above. Also attempts to request a Let's Encrypt
# certificate, though might get hit with rate limiting, even for the 
# 
# When ready, you can access the ratings-web service through the host value
# defined below.
#
# NOTE: nip.io is an open-source service for creating domain names, this is
# used below to create the host name. See nip.io for more information.
resource "kubernetes_ingress" "nginx_ingress" {
  depends_on = [null_resource.cert_manager_issuers]
  metadata {
    name = "ratings-web-ingress"
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
      "cert-manager.io/issuer"      = local.LETSENCRYPT_STAGING_ANNOTATION
    }
    namespace = kubernetes_namespace.ratings.metadata[0].name
  }

  spec {

    rule {
      # Host identifies the ingress controller with the ingress controller
      # external IP with periods replaced with dashes 
      host = local.NGINX_INGRESS_HOST

      http {
        path {
          backend {
            service_name = "ratings-web"
            service_port = 80
          }

          path = "/"
        }
      }
    }

    tls {
      hosts       = [local.NGINX_INGRESS_HOST]
      secret_name = "ratings-web-cert"
    }
  }
}
