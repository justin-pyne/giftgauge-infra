# =============================================================================
# Required Terraform and provider versions for the foundation config.
#
# Helm and kubernetes providers added in Phase 5A so Terraform can install
# Helm releases (ingress-nginx, cert-manager, kube-prometheus-stack, loki)
# directly into the EKS cluster.
# =============================================================================

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.34"
    }
  }
}
