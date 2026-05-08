# terraform/

All AWS and in-cluster infrastructure for GiftGauge as Terraform.

> **Status:** scaffolded. Phases 2–5 will fill in the modules.

## Layout

```
terraform/
├── README.md                 (this file)
├── bootstrap/                Run ONCE — creates the S3 bucket holding our state
├── modules/                  Reusable modules
│   ├── vpc/                  Phase 2
│   ├── ecr/                  Phase 2
│   ├── rds/                  Phase 3
│   ├── eks/                  Phase 4
│   └── platform/             Phase 5 (helm_release for cluster bootstrap)
│
├── backend.tf                S3 backend config (added in Phase 2)
├── versions.tf               Required versions and provider sources
├── providers.tf              AWS / Helm / Kubernetes provider config
├── main.tf                   Module composition: this is the wiring file
├── variables.tf
├── outputs.tf
└── terraform.tfvars.example  Template for local var overrides
```

## The chicken-and-egg

Terraform needs a state backend to run, but our state backend is itself an
S3 bucket that ought to be managed in Terraform. The standard resolution:

1. `terraform/bootstrap/` is a tiny Terraform configuration that uses
   **local state** to create the S3 bucket (with versioning + encryption).
   Run once.
2. Everything in `terraform/` (top level) uses an **S3 backend** that
   points at the bucket created in step 1.

If we ever need to re-create the bucket (e.g. starting in a new AWS Academy
session), the `bootstrap/` apply is idempotent and leaves the existing
state intact in the bucket.

See `bootstrap/README.md` for the exact one-time commands.

## Day-to-day usage

After bootstrap, the normal operator loop is:

```bash
cd terraform/
terraform init       # idempotent; safe to run anytime
terraform plan       # see what will change
terraform apply      # ship it
terraform output     # grab values needed by Helm or kubectl
```

Common outputs we expect to expose:

- `eks_cluster_name`, `eks_cluster_endpoint`
- `rds_endpoint`, `rds_secret_arn`
- `ecr_repository_urls` (one per service)
- `vpc_id`, `private_subnet_ids`

## Module conventions

Each module under `modules/`:

- Has its own `variables.tf`, `main.tf`, `outputs.tf`, and `README.md`.
- Takes inputs only — no provider config, no backends.
- Uses **kebab-case** for resource names, **snake_case** for variables.
- Tags every taggable resource with `project = "giftgauge"` and
  `environment = var.environment` at minimum.
- Avoids creating IAM roles (lab restriction). When a role is required, the
  module accepts a role ARN as an input.
