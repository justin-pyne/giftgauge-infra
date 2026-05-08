# =============================================================================
# Outputs.
#
# `bucket_name` is what you'll paste into ../backend.tf in step 2B. Print it
# at any time with `terraform output bucket_name`.
# =============================================================================

output "bucket_name" {
  description = "Name of the S3 bucket holding Terraform state for the foundation Terraform config."
  value       = aws_s3_bucket.tfstate.bucket
}

output "bucket_arn" {
  description = "ARN of the state bucket. Useful for IAM policies (none used in this lab, but kept for completeness)."
  value       = aws_s3_bucket.tfstate.arn
}

output "bucket_region" {
  description = "Region the state bucket lives in. Must match the `region` value in any backend config that uses this bucket."
  value       = var.aws_region
}
