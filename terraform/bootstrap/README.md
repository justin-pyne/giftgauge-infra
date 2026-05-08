# terraform/bootstrap/

**Run this exactly once per AWS account.** It creates the S3 bucket that
holds Terraform state for the rest of the project.

This module uses **local state** because it has to — it's the thing that
creates the remote-state backend. After it runs, commit the resulting
`terraform.tfstate` to a safe place outside of git (e.g. a password manager
or 1Password vault), or just accept that the bucket can be re-created by
running this again. The bucket itself is configured for versioning, so
state history survives even a re-bootstrap.

## What it creates

- One S3 bucket named `giftgauge-tfstate-<random_suffix>`
  - Versioning: enabled
  - Server-side encryption: SSE-S3 (AES-256)
  - Public access: blocked at the bucket level
  - Bucket policy: deny all non-TLS access

## What it deliberately does NOT create

- A DynamoDB lock table. We accept the no-locking trade-off; see
  [`docs/decisions.md` § B](../../docs/decisions.md#b-terraform-state-backend-s3-no-dynamodb-lock).

## How to run (Phase 2 will populate this directory with the actual code)

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output bucket_name   # save this — it's referenced by ../backend.tf
```

After this, set the `bucket` value in the top-level `terraform/backend.tf`
to the output value, then go up one directory and run `terraform init`
to migrate the rest of the project onto the remote backend.

## Tearing it down

Don't, unless you mean it. Destroying this bucket destroys all Terraform
state for the project. If you're starting a brand-new AWS Academy lab
session and the old state is no longer reachable, you can simply leave the
old bucket orphaned (it's tiny) and run `apply` again — a new bucket will
be created with a fresh suffix.
