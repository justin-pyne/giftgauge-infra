# =============================================================================
# Terraform state bucket.
#
# This single S3 bucket holds the state file for every other Terraform config
# in this repo. We harden it as if it held production credentials, because
# Terraform state can contain sensitive output values (DB passwords, ARNs,
# etc.) and accidental disclosure is bad.
#
# Configuration applied here:
#   - Random 8-char suffix, since S3 bucket names are global.
#   - Versioning ENABLED — so we can recover from a corrupted apply.
#   - SSE-S3 (AES-256) server-side encryption — sufficient for our threat
#     model; KMS would add cost and key-management overhead with no benefit
#     in the lab.
#   - Public access fully blocked at the bucket level.
#   - Bucket policy denies all non-TLS access (CIS benchmark recommendation).
#   - force_destroy = false — we never want a `terraform destroy` to delete
#     state by accident. To intentionally destroy the bucket, set this to
#     true and apply BEFORE destroying.
# =============================================================================

# 8 hex chars of randomness on the bucket name. S3 names are global; this
# avoids a collision if anyone else ever spins up a "giftgauge-tfstate-..."
# bucket in any AWS account, ever.
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name = "${var.project_name}-tfstate-${random_id.suffix.hex}"
}

# -----------------------------------------------------------------------------
# The bucket itself.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  force_destroy = false

  tags = {
    Name = local.bucket_name
  }
}

# -----------------------------------------------------------------------------
# Versioning — keep every prior state version. Cheap insurance.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# Server-side encryption with AES-256 (SSE-S3).
# `bucket_key_enabled` is a small cost optimization that's safe to leave on.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# -----------------------------------------------------------------------------
# Block all forms of public access. Defense in depth — even if a misconfigured
# bucket policy is applied later, these settings prevent accidental exposure.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# Bucket policy: deny any request that did not come over TLS. AWS S3 does
# accept HTTP, and we want to make absolutely sure state never travels in the
# clear.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "tfstate_tls_only" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  # Apply this AFTER the public-access block, otherwise S3 may reject the
  # policy as "potentially public."
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}
