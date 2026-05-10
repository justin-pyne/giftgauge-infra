# =============================================================================
# Provider configuration.
#
# AWS provider as before.
#
# helm and kubernetes providers use EXEC-based auth rather than a static
# token from data.aws_eks_cluster_auth. With static tokens, the helm
# provider opens long-lived connections that get into corrupted TLS states
# during heavy CRD installs (kube-prometheus-stack has 8 CRDs and triggers
# this reliably). Exec auth runs `aws eks get-token` per request, which
# tolerates connection drops cleanly.
#
# The exec command requires the AWS CLI to be on PATH when terraform runs.
# That's true on developer laptops and on standard GitHub Actions runners.
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = var.project_name
      ManagedBy  = "terraform"
      Repository = "justin-pyne/giftgauge-infra"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name", aws_eks_cluster.main.name,
        "--region", var.aws_region,
      ]
    }
  }
}

provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name", aws_eks_cluster.main.name,
      "--region", var.aws_region,
    ]
  }
}
