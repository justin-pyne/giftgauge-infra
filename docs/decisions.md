# GiftGauge — Architectural Decisions

This document records the architectural decisions made for the GiftGauge final
project. Each entry includes the choice, the rationale, the trade-offs we
accepted, and a short "presentation note" — the answer to give when an
instructor asks "why did you do it that way?"

The format is loosely modelled on Architectural Decision Records (ADRs) but
flattened into one file because the project is small enough that splitting
each decision into its own file would add ceremony without value.

> **Author:** Justin Pyne
> **Status:** Phase 1 — locked
> **Last updated:** 2026-05-07

---

## Constraints we are designing within

These are **not** decisions; they are facts about the environment we have to
respect.

- The deployment target is **AWS Academy Learner Lab**. This means:
  - We cannot create IAM roles or users. Everything that needs an AWS API
    permission has to use the pre-existing `LabRole` or `LabInstanceProfile`.
  - The EKS OIDC provider is disabled in this lab variant. **IAM Roles for
    Service Accounts (IRSA) does not work.** Add-ons that normally use IRSA
    (AWS Load Balancer Controller, EBS CSI driver, external-dns, cluster
    autoscaler) must be configured to use the node IAM role instead.
  - All work must happen in `us-east-1` or `us-west-2`.
  - Lab session credentials expire (typically every 4 hours), and lab
    instances are stopped at session end. This forces a discipline of
    `terraform destroy` between work sessions and idempotent provisioning.
  - The total platform credit is $100 for the duration of the class.
- **Route 53 is restricted** in this lab variant; DNS must be hosted outside
  AWS.
- **ACM is restricted** for the same reason; SSL certificates must come from
  somewhere else.

---

## A. Region: `us-east-1`

**Decision.** All infrastructure runs in `us-east-1`.

**Rationale.** The lab restricts us to `us-east-1` and `us-west-2`. We picked
`us-east-1` because it has the highest service density and the most copyable
documentation, AMI IDs, and example code. There is no latency-sensitive
workload here that would benefit from `us-west-2`.

**Trade-off accepted.** Slightly higher latency for users on the West Coast.
Negligible at this scale.

**Presentation note.** *"Region was constrained by the lab to us-east-1 or
us-west-2. I chose us-east-1 for ecosystem maturity. There's no
business-driven reason to prefer one over the other for this workload."*

---

## B. Terraform state backend: S3, no DynamoDB lock

**Decision.** Terraform state lives in a dedicated S3 bucket in the lab
account, with versioning and SSE-S3 enabled. **No DynamoDB locking table.**

**Rationale.** S3 backends are the AWS-native choice and let us inspect state
out-of-band when needed. DynamoDB-based state locking is the standard
companion, but DynamoDB access is unreliable in the lab environment and we
have a single developer, so the locking table would only ever be defending
against ourselves.

**Trade-off accepted.** No protection against concurrent `terraform apply`
runs. In a team setting this would be unsafe; for a single developer it is a
documented risk. The state bucket itself is versioned, so even an aborted
apply is recoverable by rolling back to a prior state version.

**Bootstrap caveat.** The S3 bucket cannot itself be managed by the Terraform
that uses it (chicken-and-egg). It is created by a one-time
`infra/bootstrap/` script (`aws s3api create-bucket` plus versioning and
encryption). That script is committed to the repo and is idempotent.

**Presentation note.** *"DynamoDB-based state locking is the standard
companion to an S3 backend. In our lab DynamoDB access is restricted, and as
a single developer the lock would only ever defend against me. I accepted
that trade-off and documented it. If this were a real team I'd either move
to Terraform Cloud's free tier — which gives you state, locking, and runs in
one product — or invest in unblocking DynamoDB."*

---

## C. Repository topology: two repos

**Decision.** Two GitHub repositories with a clean ownership boundary:

- `justin-pyne/giftgauge` — application source (frontend, three backend
  services, SQL migrations, local Compose), and the CI pipeline that builds
  and publishes images.
- `justin-pyne/giftgauge-infra` — Terraform, Helm chart, environment values
  files, cluster bootstrap, and all deploy workflows.

**Rationale.** Separation of concerns. The app repo answers "what is the
app?"; the infra repo answers "where does it run, and how does it get
there?" Two teams could own these independently in a real org. It also makes
the "git-driven promotion" requirement easier to satisfy cleanly: prod state
lives in the infra repo, so the infra repo's git history *is* the production
audit log.

**Trade-off accepted.** Two repos to keep in sync. We mitigate this by:
- Never retagging images across environments. The image SHA from the app
  repo build is the same artifact that flows through dev → qa → uat → prod;
  promotion is purely a one-line edit to a values file in the infra repo.
- Cross-repo communication uses GitHub `repository_dispatch` events rather
  than shared state, so the coupling is asynchronous and observable in
  Actions logs.

**Presentation note.** *"I separated the repos along the boundary a real
platform team would. The app repo is owned by 'application engineers' — code
and image artifacts. The infra repo is owned by 'platform engineers' —
clusters, Helm charts, deploy logic. Same person plays both roles here, but
the boundary keeps the responsibilities clear, and it makes the production
git history an audit log of what's in prod, which is what auditors actually
want."*

---

## D. Container registry: Amazon ECR

**Decision.** Each of the four services has its own private ECR repository,
managed by Terraform.

**Rationale.** Keeps "everything is in Terraform" honest. Pulls from EKS are
authenticated automatically via the node IAM role. Lifecycle policies on
each repo automatically delete untagged images after 7 days, which protects
the budget.

**Trade-off accepted.** GitHub Actions has to authenticate with AWS to push,
which means we have to keep the lab's session credentials in GitHub Actions
secrets and refresh them when they expire. We do not use OIDC federation
because IAM federation requires creating IAM identity providers, which the
lab forbids.

**Presentation note.** *"ECR was chosen for two reasons: every resource the
rubric grades is then in Terraform, and EKS pull authentication is automatic
via the node role. The cost of using ECR over GHCR is that GitHub Actions
needs AWS credentials to push, and because the lab disables OIDC providers
we can't use the modern OIDC-federated approach — we ship session
credentials. I documented that risk."*

---

## E. OAuth provider for Grafana: GitHub

**Decision.** Grafana authenticates via GitHub OAuth. Username/password is
disabled. The OAuth app is registered under `justin-pyne`'s GitHub account
with callback URL `https://grafana.justinpyne.xyz/login/github`.

**Rationale.** GitHub is the simplest provider to set up — five-minute form
in GitHub Settings → Developer settings → OAuth Apps. The instructor and
graders all have GitHub accounts. Google OAuth requires a Google Cloud
project with OAuth consent screen approval; Okta is overkill for a class
project.

**Trade-off accepted.** Anyone with a GitHub account can attempt to
authenticate. Authorisation will be restricted to a specific GitHub
organisation or named user list via Grafana's `auth.github.allowed_organizations`
or `allowed_emails` settings.

**Presentation note.** *"GitHub OAuth was a five-minute setup — register an
OAuth app in my GitHub developer settings, paste the client ID and secret
into Grafana's Helm values. I locked authorisation down with
`allowed_emails` so only invited accounts can actually log in."*

---

## F. Deployment strategy: namespace-level blue/green

**Decision.** Production runs in two namespaces, `prod-blue` and
`prod-green`. The production Ingress points its backend to one of them at a
time. Promotion to prod is the act of patching the Ingress to point at the
inactive colour after smoke tests pass against it. The previous colour stays
running for 10 minutes as instant-rollback insurance.

Non-prod environments (`dev`, `qa`, `uat`) use native Kubernetes rolling
updates because they don't need atomic cutover.

**Rationale.** GiftGauge has user-visible state. A canary or rolling update
in prod could mean Alex gets a score from v1.0 while Bob gets one from v1.1
ten seconds later. Blue/green at the namespace level gives an atomic
switchover and an instant rollback path.

We chose namespace-level blue/green over Argo Rollouts because it requires
**no extra cluster components**. Every Kubernetes engineer can read the
manifests and understand exactly what's happening, which matters when
debugging at 2am.

**Trade-off accepted.** Production resource consumption is roughly doubled
during the cutover window. The cutover window is short (10 minutes), and
the blue/green deployment is cheaper than maintaining a cluster large enough
to absorb canary spikes safely.

**Presentation note.** *"I chose blue/green over canary for two reasons.
First, GiftGauge has user-visible scoring state where mid-rollout
inconsistency would be confusing. Second, blue/green gives me an atomic
rollback in seconds, where canary rollback means waiting for the canary
percentage to drain. I implemented it at the namespace level — entire app
stack into prod-blue and prod-green, an Ingress controls which one is live —
because that requires no extra cluster components, and any engineer can read
the YAML and understand exactly what's happening."*

---

## G. Cluster topology: single cluster, multiple namespaces

**Decision.** One EKS cluster hosts all environments. Namespaces:

- `dev`
- `qa`
- `uat`
- `prod-blue`, `prod-green` (only one is live at a time)
- `monitoring` (kube-prometheus-stack, Loki, Promtail)
- `cert-manager`
- `ingress-nginx` (or `aws-load-balancer-controller`, depending on Phase 5)

NetworkPolicies prevent pods in one environment from talking to pods in
another. Each namespace has its own RBAC bindings. Each environment has its
own Postgres database (separate RDS schemas, not separate instances —
documented in [Decision K] in Phase 3).

**Rationale.** EKS control planes cost $0.10/hr ($72/month each). Four
clusters would burn the entire $100 budget on control planes in two weeks.
Namespace isolation is a defensible production pattern when budget or
operational simplicity demands it.

**Trade-off accepted.** Blast radius — a control-plane incident affects all
environments. In a real production setting prod would live in its own
cluster for blast-radius reasons.

**Presentation note.** *"Four clusters would have cost more than the
project's entire budget. I made a budget-driven decision to use namespace
isolation with NetworkPolicies and RBAC. The blast radius is documented in
my decisions doc — in production I'd put prod in its own cluster, but for
this project the budget made the call."*

---

## H. Domain and DNS: justinpyne.xyz on Cloudflare

**Decision.** The project is reachable at `app.justinpyne.xyz` and Grafana
at `grafana.justinpyne.xyz`. The domain is registered at Namecheap; DNS is
delegated to Cloudflare's nameservers. CNAME records for both subdomains
point at the AWS Application Load Balancer hostname created by the
ingress-nginx Helm chart.

**Rationale.** Route 53 is restricted in the lab. Cloudflare DNS is free,
fast, and has a clean web UI plus an API that we can fall back to for
cert-manager DNS-01 challenges if HTTP-01 ever fails to resolve.

**Trade-off accepted.** DNS records are managed manually rather than by
external-dns. We could install external-dns later with the Cloudflare
provider — it doesn't need IRSA — but for two records the manual approach is
simpler and easier to demonstrate.

**Presentation note.** *"DNS is on Cloudflare because Route 53 is locked in
the lab environment. I left it manual rather than installing external-dns
because for two records the operational complexity isn't worth it. If I were
adding more services I'd add external-dns with the Cloudflare provider — it
doesn't need IRSA, so it works in our lab."*

---

## I. SSL: cert-manager + Let's Encrypt

**Decision.** TLS certificates for `app.justinpyne.xyz` and
`grafana.justinpyne.xyz` come from Let's Encrypt, issued by cert-manager
running in the cluster, using the HTTP-01 challenge through the public
ingress.

**Rationale.** ACM is restricted in the lab. cert-manager is the de facto
Kubernetes standard for certificate lifecycle. HTTP-01 is the simplest
challenge type and works because our ingress is internet-reachable.

**Trade-off accepted.** Wildcard certificates are not possible with HTTP-01;
we'd need DNS-01 (Cloudflare API) for that. Two named hosts is fine for
this project's scope.

**Presentation note.** *"ACM was unavailable so I used cert-manager with
Let's Encrypt — that's the Kubernetes-native pattern most production
clusters use anyway. HTTP-01 challenge resolves through the public ingress;
no extra infrastructure required."*

---

## J. Promotion mechanics

**Decision.** Promotion is **always git-driven**, never manual.

| Transition | Trigger | Mechanism |
|---|---|---|
| feature branch → `dev` | merge to `main` in **app repo** | App repo CI builds image `:<sha>` and fires `repository_dispatch` to infra repo with `{environment: dev, image_sha: <sha>}`. Infra repo deploys to `dev` namespace via `helm upgrade`. |
| `dev` → `qa` | nightly schedule + manual `workflow_dispatch` button | Infra repo workflow takes the most recent successful dev image SHA, runs `helm upgrade` against the `qa` namespace. |
| `qa` → `uat` | PR merge in **app repo** carrying the label `release-candidate` (or commit footer `Release-Candidate: rcN`) | App repo workflow fires `repository_dispatch` to infra repo with `{environment: uat, image_sha: <sha>}`. |
| `uat` → `prod` | git tag matching `v*.*.*` pushed on **infra repo** | Infra repo `release.yml` workflow runs the blue/green flip: deploys to inactive colour, smoke-tests, patches Ingress, leaves old colour running for 10 minutes. |

**Critical rule:** images are **never retagged** across environments. The
SHA from the original build is the same artifact that lands in production.
Each environment's `values-<env>.yaml` records which SHA it currently runs.
Promotion is a one-line YAML edit, committed and pushed.

**Rationale.** Immutable artifacts eliminate a whole class of "it worked in
QA but not prod" bugs. Git-based promotion makes the audit trail trivial:
`git log infra-repo/helm/values-prod.yaml` is the production change log.

**Presentation note.** *"Promotion is git-driven and the image is immutable.
The same SHA built once flows through every environment — no retagging, no
'rebuild for prod' — so what we test in UAT is bit-for-bit what runs in
production. The git history of values-prod.yaml is literally my audit log."*

---

## K. Observability stack

**Decision.** All self-hosted, all in the `monitoring` namespace.

- **Metrics:** kube-prometheus-stack Helm chart. Includes Prometheus,
  Alertmanager, Grafana, node-exporter, kube-state-metrics. Prometheus
  scrapes the application's `/metrics` endpoints via per-service
  `ServiceMonitor` CRDs.
- **Logs:** Grafana Loki via the `loki-stack` Helm chart, with Promtail as
  a DaemonSet shipping container logs.
- **Alerting:** Alertmanager → Gmail SMTP (app password). Alert rules:
  node CPU > 80% / memory > 85% / disk > 80% for 5 minutes; any pod in
  `CrashLoopBackOff`; `/ready` endpoint returning 503 for 2 minutes.
- **Access control:** Grafana Ingress at `grafana.justinpyne.xyz`, GitHub
  OAuth only (anonymous access disabled, basic auth disabled).

**Rationale.** Rubric requirement: "Self-hosted only. No AWS Managed
services." kube-prometheus-stack is the canonical bundle and gets us node
CPU/memory/disk dashboards out of the box. Loki is the lightest centralised
logging option that satisfies "queryable across all microservices."

**Presentation note.** *"Everything self-hosted in one namespace. The single
Loki query `{namespace=~'prod-.*'}` gives me every log line from every
service in production, joined by timestamp. The single Grafana view I built
shows traffic, error rate, and DB pool utilisation across all three services
side by side."*

---

## L. Email contacts

| Purpose | Address |
|---|---|
| Let's Encrypt registration | jpyne.justin@gmail.com |
| Alertmanager critical alerts | jpyne.justin@gmail.com |

A separate inbox (e.g. a Gmail filter) is recommended so alert noise is
isolated from primary email. For this project a single address is acceptable.

---

## Decisions deferred to later phases

These will be made when we get to the relevant phase, with their own entries
appended to this document:

- **Phase 3:** RDS instance class, single vs. multi-AZ, schema-per-environment
  vs. database-per-environment, secrets distribution mechanism (Helm values
  from CI vs. External Secrets Operator).
- **Phase 4:** EKS Kubernetes version, node group instance types, capacity
  type (on-demand vs. mixed with spot), single vs. multiple node groups.
- **Phase 5:** ingress-nginx vs. AWS Load Balancer Controller, manual DNS
  vs. external-dns, exact alert thresholds and routing tree.
- **Phase 8:** specific chaos scenarios to drill, presentation storyboard
  timing.
