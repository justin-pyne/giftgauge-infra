# =============================================================================
# Provider configuration.
#
# Credentials come from the standard AWS provider chain (env vars or
# ~/.aws/credentials). See ../bootstrap/providers.tf for the full
# explanation; the same applies here.
#
# `default_tags` are applied to every taggable resource we create — both
# directly here and inside any module (the AWS provider passes them
# through). This means we don't have to repeat tags inside the VPC module
# call.
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
