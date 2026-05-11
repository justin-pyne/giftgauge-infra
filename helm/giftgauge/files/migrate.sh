#!/bin/sh
# -----------------------------------------------------------------------------
# Simple Flyway-compatible-ish migration runner.
# Applies any *.sql files in /migrations that have not yet been recorded in
# the schema_migrations table, in lexicographic order.
# -----------------------------------------------------------------------------
set -eu

if [ -z "${DATABASE_URL:-}" ]; then
  echo "[migrator] FATAL: DATABASE_URL is not set" >&2
  exit 1
fi

echo "[migrator] waiting for database to accept connections..."
i=0
until psql "$DATABASE_URL" -c 'select 1' >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 30 ]; then
    echo "[migrator] FATAL: database did not become reachable in time" >&2
    exit 1
  fi
  sleep 1
done
echo "[migrator] database is reachable."

# Bootstrap the bookkeeping table.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  version     TEXT PRIMARY KEY,
  applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

# Apply each migration file in sorted order if it's not already recorded.
applied_count=0
for file in $(ls /migrations/*.sql 2>/dev/null | sort); do
  version="$(basename "$file" .sql)"

  already="$(psql "$DATABASE_URL" -tAc "SELECT 1 FROM schema_migrations WHERE version = '$version'")"
  if [ "$already" = "1" ]; then
    echo "[migrator] $version already applied, skipping."
    continue
  fi

  echo "[migrator] applying $version..."
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
    -c "INSERT INTO schema_migrations (version) VALUES ('$version')"
  applied_count=$((applied_count + 1))
done

echo "[migrator] done. Applied $applied_count new migration(s)."
