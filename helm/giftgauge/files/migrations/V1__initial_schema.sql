-- =============================================================================
-- V1__initial_schema.sql
-- Initial schema for GiftGauge.
-- Tables: profiles, preferences, share_links, gift_submissions, gift_scores
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- for gen_random_uuid()

-- -----------------------------------------------------------------------------
-- profiles: a recipient's private taste profile.
--
-- NOTE on owner_token:
--   For simplicity in this class project the owner token is stored in plain
--   text. In production this column should be replaced with `owner_token_hash`
--   storing a SHA-256 (or argon2) hash with a per-row salt, and lookups should
--   compare hashes only. Documented in README.md.
-- -----------------------------------------------------------------------------
CREATE TABLE profiles (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name  TEXT NOT NULL,
  occasion      TEXT NOT NULL,
  budget_min    INTEGER NOT NULL CHECK (budget_min >= 0),
  budget_max    INTEGER NOT NULL CHECK (budget_max >= budget_min),
  owner_token   TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_profiles_owner_token ON profiles(owner_token);

-- -----------------------------------------------------------------------------
-- preferences: free-text items grouped by category.
-- Categories used by the app: owns, wants, likes, dislikes, hobbies, style, avoid.
-- We use a CHECK constraint instead of an ENUM so adding a new category later
-- is a one-line ALTER and does not require a type migration.
-- -----------------------------------------------------------------------------
CREATE TABLE preferences (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  category    TEXT NOT NULL CHECK (category IN (
                'owns', 'wants', 'likes', 'dislikes', 'hobbies', 'style', 'avoid'
              )),
  text        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_preferences_profile_id ON preferences(profile_id);

-- -----------------------------------------------------------------------------
-- share_links: opaque codes a recipient can hand to gift givers.
-- The share_code itself is what the gift giver types into the UI.
-- -----------------------------------------------------------------------------
CREATE TABLE share_links (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  share_code  TEXT NOT NULL UNIQUE,
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_share_links_profile_id ON share_links(profile_id);

-- -----------------------------------------------------------------------------
-- gift_submissions: a gift idea typed in by a giver.
-- We keep the share_code (not the profile_id) as the foreign key here because
-- the sharing-service should not need direct knowledge of profile internals.
-- -----------------------------------------------------------------------------
CREATE TABLE gift_submissions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  share_code        TEXT NOT NULL REFERENCES share_links(share_code) ON DELETE CASCADE,
  giver_name        TEXT NOT NULL,
  gift_name         TEXT NOT NULL,
  gift_description  TEXT,
  estimated_price   NUMERIC(10, 2),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_gift_submissions_share_code ON gift_submissions(share_code);

-- -----------------------------------------------------------------------------
-- gift_scores: AI-generated scores. Stored separately from gift_submissions
-- because (a) a gift can be re-scored, and (b) the scoring service owns these.
-- pros/cons are JSONB arrays of strings.
-- -----------------------------------------------------------------------------
CREATE TABLE gift_scores (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  share_code        TEXT NOT NULL REFERENCES share_links(share_code) ON DELETE CASCADE,
  gift_name         TEXT NOT NULL,
  gift_description  TEXT,
  estimated_price   NUMERIC(10, 2),
  score             INTEGER NOT NULL CHECK (score BETWEEN 1 AND 10),
  summary           TEXT NOT NULL,
  pros              JSONB NOT NULL DEFAULT '[]'::jsonb,
  cons              JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_gift_scores_share_code ON gift_scores(share_code);
