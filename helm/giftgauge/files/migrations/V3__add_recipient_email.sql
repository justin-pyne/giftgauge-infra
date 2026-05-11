-- =============================================================================
-- V3__add_recipient_email.sql
--
-- Day-2 schema change demonstrating the expand/migrate/contract pattern.
-- =============================================================================

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS recipient_email TEXT;

CREATE INDEX IF NOT EXISTS idx_profiles_recipient_email
  ON profiles(recipient_email)
  WHERE recipient_email IS NOT NULL;
