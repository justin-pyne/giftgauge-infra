# envs/

Per-environment Helm values overrides. **The image SHA recorded here is
literally what's deployed in each environment.** This makes the git history
of these files the audit log for what shipped where.

## Layout

```
envs/
├── README.md   (this file)
├── dev/
│   └── values.yaml
├── qa/
│   └── values.yaml
├── uat/
│   └── values.yaml
└── prod/
    └── values.yaml
```

> **Status:** scaffold. The values files are added in Phase 6.

## Promotion = a one-line edit + commit

The mechanic is intentionally boring:

1. **dev** is updated automatically on every merge to `main` in the app
   repo. The `deploy.yml` workflow listens for `repository_dispatch` from
   the app repo, edits `envs/dev/values.yaml` to set `image.tag` to the new
   commit SHA, runs `helm upgrade`, and commits the change back.
2. **qa** is updated by the nightly `nightly-qa.yml` workflow, which copies
   the current `image.tag` from `envs/dev/values.yaml` into
   `envs/qa/values.yaml` and runs `helm upgrade`.
3. **uat** is updated when an app-repo PR carrying the `release-candidate`
   label is merged. App-repo CI fires a `repository_dispatch` to this repo,
   which updates `envs/uat/values.yaml` and deploys.
4. **prod** is updated by editing `envs/prod/values.yaml` directly and
   tagging the commit `v*.*.*`. The tag triggers `release.yml`, which
   performs the blue/green flip described in
   [`docs/decisions.md` § F](../docs/decisions.md#f-deployment-strategy-namespace-level-bluegreen).

## What does NOT vary across environments

The image **artifact** is identical across all environments. We never
rebuild for prod. The same `:abc1234` image is what's tested in QA and
exactly what runs in prod. Environment differences live in the values file:

- `image.tag` (the SHA being deployed)
- `replicaCount` (smaller in dev, larger in prod)
- `resources.requests` / `resources.limits` (relaxed in dev, tighter in prod)
- `ingress.host` (host-per-environment)
- `database.url` (per-environment Postgres database)

## Why this pattern

It is the simplest pattern that satisfies the rubric's "fully automated"
and "no ClickOps" requirements while remaining auditable to a human reader.
There is no GitOps controller (Argo CD / Flux); we accept that the
controller is "GitHub Actions" instead. The gain is one fewer cluster
component to maintain.
