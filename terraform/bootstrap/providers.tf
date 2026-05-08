# =============================================================================
# Provider configuration.
#
# We deliberately do NOT set `profile` or hardcode credentials here. The AWS
# provider picks credentials up from the standard chain in this order:
#
#   1. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
#      AWS_SESSION_TOKEN, AWS_REGION)
#   2. Shared credentials file (~/.aws/credentials)
#   3. EC2 / ECS instance metadata (irrelevant on a laptop)
#
# The Academy lab gives you a session-token-based credential set; either
# pasting them into ~/.aws/credentials or exporting them as env vars works.
#
# `default_tags` saves us from repeating the same tags on every taggable
# resource in this module. The AWS provider automatically attaches these
# tags to every resource that supports tagging.
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Component   = "tfstate-bootstrap"
      ManagedBy   = "terraform"
      Repository  = "justin-pyne/giftgauge-infra"
    }
  }
}
