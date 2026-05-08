# docs/runbooks/

Operator runbooks for routine and demo scenarios.

> **Status:** filled in during Phase 8. Listed here so the structure is
> visible from day one.

## Planned runbooks

| File | Scenario | Rubric tie-in |
|---|---|---|
| `01-schema-migration.md` | Apply a backwards-compatible schema change to RDS using the expand → migrate → contract pattern. | Day 2 — Schema Changes (10%) |
| `02-node-rotation.md` | Roll EKS worker nodes onto a new AMI with zero downtime. PodDisruptionBudgets, drain, replace. | Day 2 — OS/Security Patching (10%) |
| `03-blue-green-flip.md` | Production promotion: how `release.yml` runs the cutover, what to watch for, how to abort. | Application & Networking (15%) |
| `04-rollback.md` | What to do when a deploy is bad. Time-budgeted by severity (sev1, sev2). | Presentation — Confidence in the Unknown (15%) |
| `05-chaos-playbook.md` | The diagnostic flowchart for "instructor broke something, where do I look?" Maps observed symptom → which Grafana panel → which Loki query → which `kubectl` command. | Presentation — Live Chaos Defense (15%) |
| `06-credentials-refresh.md` | When the AWS Academy session credentials expire, exactly which secrets need updating and where. | Operational hygiene |

## Runbook conventions

Each runbook follows this skeleton:

1. **When to use this runbook** — one-line trigger.
2. **Pre-flight check** — what to verify before starting (e.g. cluster
   reachable, no active incident, off-hours if applicable).
3. **Procedure** — numbered steps. Every command shown in a code fence
   exactly as it should be run. No prose-only steps.
4. **Verification** — how to confirm the procedure worked. Concrete
   metric / log / kubectl assertion.
5. **Rollback** — undo procedure if step 3 went wrong.
6. **Notes for the presentation** — one-paragraph "what the grader cares
   about." This is what becomes my live narration.
