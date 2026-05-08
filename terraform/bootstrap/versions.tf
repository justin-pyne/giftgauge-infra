# =============================================================================
# Required Terraform and provider versions for the bootstrap config.
#
# This config uses LOCAL state because it is the thing that creates the
# remote-state backend used by everything else. After `terraform apply`,
# a `terraform.tfstate` file will appear in this directory. It is gitignored.
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
  }
}
