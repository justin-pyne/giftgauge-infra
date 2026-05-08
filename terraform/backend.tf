# =============================================================================
# Remote state backend.
#
# Bucket name comes from `terraform output bucket_name` in ../bootstrap/.
# If you ever re-bootstrap (e.g. starting a new AWS Academy session that
# can't reach the old bucket), update the `bucket` value here.
#
# - `key`     keeps state organized within the bucket. Future Terraform
#             configs (per-cluster, per-env) can use different keys in the
#             same bucket.
# - `encrypt` requests server-side encryption on the state object itself
#             (the bucket also has SSE-S3 default-encryption from bootstrap).
# - No DynamoDB lock — see docs/decisions.md § B for the trade-off.
# =============================================================================

terraform {
  backend "s3" {
    bucket  = "giftgauge-tfstate-b3fef895"
    key     = "foundation/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
