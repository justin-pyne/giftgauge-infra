# Runbook: Database schema migrations (expand / migrate / contract)

**Audience:** anyone shipping a schema change to a running GiftGauge environment.
**Severity:** any schema change is a P1 if mishandled. Read this before merging.

---

## TL;DR

GiftGauge uses **expand → migrate → contract** for schema changes that must
land without downtime. Each new SQL file in `helm/giftgauge/files/migrations/`
becomes a Helm `pre-upgrade` hook the next time the chart is upgraded in any
namespace.

Workflow per change:

1. Write `Vn__<description>.sql` — must be backward-compatible (expand only).
2. PR review — verify backward compatibility with the previous app version.
3. Merge to `main` (infra repo). Next `helm upgrade` runs it.
4. Deploy app code that uses the new column (if applicable).
5. After old code is fully retired, write `Vn+1__contract_<thing>.sql` to
   tighten constraints (NOT NULL, etc.).

---

## The pattern

A "safe" schema change is one that **both** the current and previous versions
of the application can run against without errors. The constraint is that we
deploy code and schema independently, so for some period the database supports
two app versions reading and writing simultaneously.

### Phase 1 — Expand

Add the new column / table / index, but **don't require it**.

- New columns must be nullable.
- New columns must not have a NOT NULL constraint.
- New columns may have a DEFAULT, but watch out: in Postgres < 11 a DEFAULT
  triggered a full table rewrite. We're on Postgres 16 where it's metadata-only.
- Existing INSERT/UPDATE statements in old code must keep working.
- Existing SELECT statements in old code must keep working.

The expand migration is what V3 does in this project.

### Phase 2 — Migrate

The application code that uses the new column ships. Backfill any existing
rows with reasonable values if the column is meant to be populated. Backfill
should be done in batches (e.g., 1000 rows at a time) to avoid long table
locks; for small tables you can backfill in a single statement.

This phase may be implicit (no backfill needed) or may require a separate
runbook for the backfill batch job.

### Phase 3 — Contract

Once **all** instances of the old app code are retired (i.e., across blue/green
both colors run the new version), tighten the constraints:

- `ALTER COLUMN ... SET NOT NULL` once all rows have values
- `DROP COLUMN` once the new column has fully replaced an old one
- `DROP INDEX` once the old query pattern is gone

The contract phase requires confirmation that no instance of the previous
version is running. For us, that means: prod-blue and prod-green both run
the post-expand code.

### Anti-patterns to avoid

| Bad change | Why | Safe equivalent |
|---|---|---|
| `ALTER TABLE ... ADD COLUMN x NOT NULL` | Existing INSERTs from old code break instantly | Add nullable, then add NOT NULL in V_n+1 after backfill |
| `ALTER TABLE ... DROP COLUMN x` | Old code's SELECT/INSERT statements that reference x break | Stop writing in code first, ship that, *then* drop column |
| `ALTER TABLE ... RENAME COLUMN x TO y` | Old code referring to x breaks; new code referring to y breaks before migration | Add y, dual-write x and y in app code, backfill, deploy code that reads y, drop x |
| `ALTER TABLE ... TYPE` (e.g., INTEGER to BIGINT on a large table) | Pre-Postgres 12 was a full rewrite. On 12+ it's safer but check release notes. | Test on a copy first; if it's a rewrite, use a new column + dual-write + swap |

---

## Mechanics: how migrations actually run in this project

Migrations are SQL files in `helm/giftgauge/files/migrations/` named with the
pattern `Vn__<description>.sql`. The lexicographic order is the apply order
(so V1 → V2 → V3 → ...).

When `helm upgrade` runs on any namespace, a pre-upgrade hook:

1. Builds a ConfigMap from those SQL files (`migration-scripts` in the target namespace)
2. Spins up a Job pod (`postgres:16-alpine`) that:
   - Creates the namespace's database if it doesn't exist (e.g., `giftgauge_prod`)
   - Runs `migrate.sh`, which checks each `V*.sql` file against the
     `schema_migrations` bookkeeping table and applies any that haven't run yet
3. If the Job succeeds, the deployments roll out the new app version.
4. If the Job fails, the deployments don't roll, and the chart upgrade fails.

This means the **schema change is applied once per environment**, atomically
with the chart upgrade. In prod blue/green, both colors share the
`giftgauge_prod` database, so the first color upgraded after a new migration
file is added applies it; the second color's migration Job sees it's already
recorded and skips.

Idempotency comes from:
- `schema_migrations` table tracks which `Vn` files have been applied
- The SQL files use `IF NOT EXISTS` for ADD COLUMN and CREATE INDEX where possible

---

## Practice run: V3 in prod

The objective of this practice run is to demonstrate that V3 can be applied
to the live shared `giftgauge_prod` database while:

- prod-blue (v0.1.0, the old app) is still serving warm-standby traffic
- prod-green (v0.1.2, the current app) is serving live traffic at app.justinpyne.xyz
- Both versions continue to respond 200 throughout the change

### Prerequisites

- Cluster is reachable: `kubectl get nodes` returns 3 Ready nodes
- Both prod releases are healthy:
  ```bash
  kubectl get pods -n prod-blue
  kubectl get pods -n prod-green
  ```
- Helm sees both releases:
  ```bash
  helm list -n prod-blue
  helm list -n prod-green
  ```

### Step 1 — verify the column does not yet exist

```bash
kubectl run psql-debug --rm -i --tty \
  --image=postgres:16-alpine --restart=Never --namespace=prod-green \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "psql-debug",
        "image": "postgres:16-alpine",
        "stdin": true,
        "tty": true,
        "command": ["sh"],
        "envFrom": [{"secretRef": {"name": "giftgauge-db"}}]
      }]
    }
  }'
```

Inside the pod:

```sh
export PGHOST=$DB_HOST PGPORT=$DB_PORT PGUSER=$DB_USER PGPASSWORD=$DB_PASSWORD PGSSLMODE=require
psql -d giftgauge_prod -c "\d profiles"
exit
```

You should see the 7 columns from V1: `id, display_name, occasion, budget_min,
budget_max, owner_token, created_at`. No `recipient_email`.

### Step 2 — drop the V3 file into the chart

```bash
cd ~/path/to/giftgauge-infra
# Place V3__add_recipient_email.sql in helm/giftgauge/files/migrations/

ls helm/giftgauge/files/migrations/
# Expected: V1__initial_schema.sql  V2__add_scoring_metadata.sql  V3__add_recipient_email.sql
```

### Step 3 — start a load test against app.justinpyne.xyz

In one terminal, start a continuous health probe so we can prove zero
downtime:

```bash
# Polls every second; logs only failures
while true; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" https://app.justinpyne.xyz/api/profile/health)
  if [ "$CODE" != "200" ]; then
    echo "$(date -u +%H:%M:%S) FAIL code=$CODE"
  fi
  sleep 1
done
```

Leave this running for the entire migration. The log should remain empty
(no FAIL lines).

### Step 4 — run the migration via helm upgrade on prod-green

In another terminal:

```bash
cd ~/path/to/giftgauge-infra
helm upgrade giftgauge ./helm/giftgauge \
  --namespace prod-green \
  -f envs/prod-green/values.yaml \
  -f envs/prod-active-color.yaml \
  --wait --timeout 5m
```

Watch the migration Job in another window:

```bash
kubectl get pods -n prod-green -l app.kubernetes.io/component=migrator -w
```

Expected sequence: `Pending → ContainerCreating → Running → Completed`, total
about 10 seconds. The Job pod disappears on success (hook-succeeded cleanup).

### Step 5 — verify the column now exists

Re-run the psql-debug pod and:

```sh
psql -d giftgauge_prod -c "\d profiles"
psql -d giftgauge_prod -c "SELECT version, applied_at FROM schema_migrations ORDER BY version"
```

Expected:
- `\d profiles` now shows 8 columns including `recipient_email`
- `schema_migrations` lists V1, V2, AND V3 with applied_at timestamps

### Step 6 — verify both app versions still work

```bash
# prod-blue (v0.1.0) — the old app
curl -s https://prod-blue.justinpyne.xyz/api/profile/health
# {"status":"ok"}

# Create a profile via the old app code
curl -s -X POST https://prod-blue.justinpyne.xyz/api/profile/api/profiles \
  -H 'content-type: application/json' \
  -d '{"displayName":"Old Code Test","occasion":"Birthday","budgetMin":25,"budgetMax":100}'
# Expected: {"profileId":"...","ownerToken":"..."}

# prod-green (v0.1.2) — the current app
curl -s -X POST https://app.justinpyne.xyz/api/profile/api/profiles \
  -H 'content-type: application/json' \
  -d '{"displayName":"New Code Test","occasion":"Anniversary","budgetMin":50,"budgetMax":200}'
# Expected: same shape
```

Both should return profile IDs. Both rows in the DB will have
`recipient_email IS NULL` because neither version writes the column yet —
exactly what we wanted from the expand phase.

### Step 7 — stop the health-probe loop

Ctrl-C the loop from Step 3. Verify the log is empty (or, at most, has
one or two FAILs from cert/connection blips unrelated to the migration).

### Step 8 — record the change

```bash
cd ~/path/to/giftgauge-infra
git add helm/giftgauge/files/migrations/V3__add_recipient_email.sql
git commit -m "feat(schema): V3 — add profiles.recipient_email (expand)

Backward-compatible expand. Column is nullable, no default, no rewrite.
Old app code continues to INSERT/SELECT without referencing the column.
Future v0.1.3 of the application will populate this column on new inserts.
The eventual contract (SET NOT NULL) will be V_n once all old code is retired."
git push
```

---

## Rollback

**For an expand-only change like V3:** there is nothing to roll back.
The new column is unused; leaving it nullable has no behavioral impact.

If V3 were paired with broken app code, you would:

1. Roll the app back via `release-prod.yml` (deploy the previous tag to inactive, flip).
2. Leave the schema change in place — Postgres doesn't care about extra nullable columns.

**For a contract-style migration that broke prod:**

1. Immediately re-apply the inverse migration if possible (`ALTER COLUMN ... DROP NOT NULL`).
2. Roll the app back.
3. Investigate before re-attempting.

**To physically drop a migrated column:**

This is rare and dangerous. You'd need to:

1. Confirm no code references the column (`grep -r column_name app/ services/`)
2. Confirm all environments are running that code
3. Take a backup of the table
4. Write a new migration `Vn__drop_<column>.sql` with `ALTER TABLE ... DROP COLUMN`
5. Apply via the standard helm upgrade flow

---

## Common failure modes

| Symptom | Root cause | Fix |
|---|---|---|
| Migration Job stays `Pending` | Node pod-cap reached or insufficient resources | `kubectl describe pod`; if "Too many pods", clear capacity (see runbooks/node-rotation.md) |
| Migration Job `Error` with `psql: invalid percent-encoded token` | Password URL-encoding issue (we've already fixed this) | Verify migration-job.yaml uses PG* env vars, not DATABASE_URL |
| Migration Job `Error` with `psql: connection refused` | RDS unreachable from the node | Check SG: cluster SG must be allowed in RDS SG (Phase 4 setup) |
| Migration Job `Completed` but column doesn't exist | SQL syntax error silently caught (rare) | Look at Job logs — `kubectl logs job/migrate-N -n <ns>` |
| Helm upgrade hangs at "pre-upgrade hooks failed" | Job took > 10m | Increase `--timeout`, or check Job logs |
| App pods start crashing after migration | Migration introduced a NOT NULL on existing data | Roll back via re-migration (`ALTER COLUMN ... DROP NOT NULL`), then roll app back |

---

## Why this works for blue/green specifically

In our prod blue/green setup:

- prod-blue and prod-green share `giftgauge_prod`
- Each color has its own migration Job that points at the same DB
- Whichever color's `helm upgrade` runs first applies the new migration
- The other color's Job sees the entry in `schema_migrations` and skips

Since expand-only migrations are backward compatible, the lagging color
continues to work against the expanded schema. This is exactly the property
we needed: **schema deploys independently of any single color's app version**.

The contract phase has to wait until BOTH colors are running the post-expand
code. That coordination is the price of zero-downtime deploys.
