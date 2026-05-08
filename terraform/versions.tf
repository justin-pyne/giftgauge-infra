# =============================================================================
# Required Terraform and provider versions for the foundation config.
#
# This config uses the S3 backend created by ../bootstrap/. After bootstrap
# completes, you can `terraform init` here and Terraform will store state
# remotely.
# =============================================================================

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
