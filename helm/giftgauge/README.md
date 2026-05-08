# helm/giftgauge/

Helm chart that packages the four GiftGauge services (frontend + 3 backends)
along with their Ingress, ConfigMaps, ServiceMonitors, and a pre-upgrade
migration job.

> **Status:** placeholder. Built out in Phase 6.

## Planned chart structure

```
helm/giftgauge/
├── Chart.yaml
├── values.yaml                  Baseline defaults (used as -f base)
└── templates/
    ├── _helpers.tpl
    ├── frontend-deployment.yaml
    ├── frontend-service.yaml
    ├── profile-deployment.yaml
    ├── profile-service.yaml
    ├── sharing-deployment.yaml
    ├── sharing-service.yaml
    ├── scoring-deployment.yaml
    ├── scoring-service.yaml
    ├── ingress.yaml             One Ingress, routes by host + path
    ├── migrate-job.yaml         Helm hook: pre-install + pre-upgrade
    ├── servicemonitor.yaml      One per backend service
    ├── configmap.yaml
    └── secret-external.yaml     ExternalSecret reading from Secrets Manager
```

Per-environment overrides live in `../envs/<env>/values.yaml`. Deploy is:

```bash
helm upgrade --install giftgauge ./helm/giftgauge \
    -f helm/giftgauge/values.yaml \
    -f envs/dev/values.yaml \
    --namespace dev --create-namespace
```

## Conventions

- Image SHA is **always** passed in via values, never hardcoded.
  `image.tag` defaults to `"latest"` only as a guard rail; CI always sets
  it explicitly.
- Resource requests are conservative (100m CPU, 128Mi memory). Limits
  follow the established 2× request convention.
- `livenessProbe` uses `/health`, `readinessProbe` uses `/ready` — endpoints
  the application already implements.
- Migration job runs as a `pre-upgrade` Helm hook with
  `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded` so it
  reruns cleanly on each deploy.
