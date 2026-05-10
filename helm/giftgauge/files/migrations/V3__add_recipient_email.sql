-- =============================================================================
-- V3__add_recipient_email.sql
--
-- Day-2 schema change demonstrating the expand/migrate/contract pattern.
--
-- This is the EXPAND phase: add the column without breaking anything.
--
-- Safety properties for zero-downtime deploys:
--
--   1. ADD COLUMN in Postgres 11+ is a metadata-only operation when there's
--      no DEFAULT clause. The migration completes in milliseconds; no table
--      rewrite, no long-held locks.
--
--   2. IF NOT EXISTS makes the migration idempotent — re-running V3 is safe.
--
--   3. The column is nullable. The application's INSERT statements that don't
--      mention recipient_email continue to work (the column gets NULL).
--
--   4. There's no DEFAULT. Postgres does not backfill existing rows, so the
--      migration is O(1) regardless of profiles table size.
--
-- Subsequent migrations (V4, V5, ...) would tighten the constraint to NOT NULL
-- once all old code that doesn't write the column has been retired. That's
-- the CONTRACT phase. We're not doing it here because v0.1.2 of the app
-- doesn't write recipient_email yet — a future v0.1.3+ would.
-- =============================================================================

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS recipient_email TEXT;

-- Optional helpful index for future "look up by email" queries.
-- B-tree on a sparse nullable column; small index, fast to build.
CREATE INDEX IF NOT EXISTS idx_profiles_recipient_email
  ON profiles(recipient_email)
  WHERE recipient_email IS NOT NULL;
