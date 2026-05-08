# =============================================================================
# Input variables for the bootstrap config.
#
# Both have defaults so `terraform apply` works with no flags. Override via
# `-var` or a terraform.tfvars file if you ever need a different region or
# project name (you almost certainly won't for this project).
# =============================================================================

variable "aws_region" {
  description = "AWS region in which to create the state bucket."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.aws_region)
    error_message = "AWS Academy permits only us-east-1 and us-west-2."
  }
}

variable "project_name" {
  description = "Project identifier, used as a prefix on the bucket name and in resource tags."
  type        = string
  default     = "giftgauge"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name must be 3–31 chars, lowercase alphanumeric and dashes, starting with a letter."
  }
}
