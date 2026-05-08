# giftgauge-infra

Infrastructure-as-code and deployment automation for **GiftGauge**, a graduate
DevOps capstone project.

This repository is the *"where it runs"* half of the project. The application
source — frontend, three backend microservices, SQL migrations — lives in a
separate repository at
[`justin-pyne/giftgauge`](https://github.com/justin-pyne/giftgauge).

> **Status:** Phase 1 complete. Architectural decisions are recorded in
> [`docs/decisions.md`](docs/decisions.md). Phases 2–8 in progress; see the
> [Roadmap](#roadmap) at the bottom of this README.

---

## What lives in this repository

| Path | Contents |
|---|---|
| `terraform/` | All AWS and in-cluster infrastructure as Terraform. VPC, EKS, RDS, ECR, plus `helm_release` resources for cluster bootstrap (cert-manager, ingress, Prometheus, Grafana, Loki). |
| `terraform/bootstrap/` | A one-time setup that creates the S3 bucket holding Terraform state for the rest of the project. Uses local state. Run exactly once. |
| `terraform/modules/` | Reusable modules — one per concern (`vpc`, `ecr`, `rds`, `eks`, `platform`). |
| `helm/giftgauge/` | Helm chart packaging the four GiftGauge services along with their Ingress, ConfigMaps, ServiceMonitors, and a pre-upgrade migration job. |
| `envs/` | Per-environment values overrides (`dev/`, `qa/`, `uat/`, `prod/`). The image SHA recorded in each environment's `values.yaml` is what is currently deployed there. |
| `docs/decisions.md` | Architectural decision record. Every Phase-1 choice with rationale, trade-off, and a "what to say if asked" note for the presentation. |
| `docs/runbooks/` | Operator runbooks for the rubric's Day-2 demos: schema migration, AMI/node rotation, blue/green flip, rollback. |
| `.github/workflows/` | CI/CD: `terraform plan` on PRs, `terraform apply` on merge, deployment workflows triggered by `repository_dispatch` from the app repo, and the production blue/green flip triggered by tag push. |

---

## Prerequisites

| Tool | Minimum version | Purpose |
|---|---|---|
| Terraform | `1.7` | Everything in `terraform/` |
| kubectl | `1.29` | Cluster operations after EKS exists |
| helm | `3.14` | Chart installs and deploys |
| aws-cli | `2.15` | Auth + ad-hoc operations |
| Docker | recent | Local app builds (mostly used in the app repo) |
| git | recent | — |

You also need:

- An **AWS Academy Learner Lab** session with valid credentials. Constraints
  this implies are documented in [`docs/decisions.md`](docs/decisions.md);
  the most important is that **IRSA does not work** in this lab variant, so
  every cluster add-on uses the node IAM role for AWS access.
- A domain on **Cloudflare DNS** (`justinpyne.xyz` for this project).
- A **GitHub OAuth App** for Grafana login. Created in your GitHub Developer
  Settings; client ID and secret go into the cluster as a Helm value.

Phase-2 will add an `infra/bootstrap/README.md` with exact commands to
initialise the state bucket. Until then, no `terraform apply` is expected.

---

## How this repo and the app repo work together

The two repos exchange **two things**, and only two things:

1. **Container images.** The app repo builds Docker images on every push to
   `main` and publishes them to ECR tagged with the Git commit SHA. Images
   are **never retagged** — the same `:abc1234` artifact flows through every
   environment.
2. **`repository_dispatch` events.** After a successful build, the app repo
   fires a custom event to this repo carrying a payload like
   `{ "environment": "dev", "image_sha": "abc1234" }`. A workflow here
   handles the deploy.

There is no shared Terraform state, no shared submodule, no pinned chart
version — just images and events. This keeps coupling asynchronous and
auditable. The full promotion mechanic, including the production blue/green
flip, is documented in `docs/decisions.md` § J.

```
              ┌────────────────────┐                 ┌────────────────────┐
              │    giftgauge       │                 │  giftgauge-infra   │
              │    (app repo)      │                 │    (this repo)     │
              ├────────────────────┤                 ├────────────────────┤
   commit ──▶ │  build & push to   │ ── dispatch ──▶ │  helm upgrade env  │
              │  ECR :<sha>        │   {env, sha}    │  with new image    │
              │                    │                 │                    │
              │  Conventional      │                 │  v*.*.* tag here   │
              │  Commits → UAT     │                 │  → blue/green prod │
              └────────────────────┘                 └────────────────────┘
```

---

## Local quickstart

A full operator quickstart lives in `terraform/README.md` once Phase 2 is
complete. The short version that will eventually work:

```bash
# 1. One-time: stand up the state bucket
cd terraform/bootstrap
terraform init && terraform apply

# 2. Day-to-day: stand up the platform
cd ../
terraform init && terraform apply

# 3. After the platform is up, deploy the app to dev
helm upgrade --install giftgauge ./helm/giftgauge \
    -f envs/dev/values.yaml \
    --namespace dev --create-namespace
```

---

## Roadmap

- [x] **Phase 1** — Architectural decisions and repo bootstrap
- [ ] **Phase 2** — Terraform: VPC + ECR
- [ ] **Phase 3** — Terraform: RDS Postgres
- [ ] **Phase 4** — Terraform: EKS cluster
- [ ] **Phase 5** — Cluster bootstrap: ingress, cert-manager, observability
- [ ] **Phase 6** — Application Helm chart and per-environment values
- [ ] **Phase 7** — CI/CD workflows (build, promote, blue/green)
- [ ] **Phase 8** — Day 2 runbooks, chaos drill prep, presentation

---

## License

[MIT](LICENSE).
