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

// =============================================================================
// PATCH for terraform/versions.tf
//
// Add the `random` provider to the existing `required_providers` block.
// (The `random_password` resource in database.tf needs it.)
//
// Your file currently looks like:
//
//   terraform {
//     required_version = ">= 1.7"
//
//     required_providers {
//       aws = {
//         source  = "hashicorp/aws"
//         version = "~> 6.0"
//       }
//     }
//   }
//
// Add the `random` block so it ends up like this:
// =============================================================================

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
