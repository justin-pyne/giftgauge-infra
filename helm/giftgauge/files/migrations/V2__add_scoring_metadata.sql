-- =============================================================================
-- V2__add_scoring_metadata.sql
--
-- Adds richer scoring metadata to gift_scores:
--   - confidence_score: 0-100 integer indicating model confidence
--   - budget_fit:       'low' | 'good' | 'high' | 'unknown'
--
-- This migration is intentionally separate from V1 to support the Day 2
-- schema-change demo: deploy with V1 only, then later run a one-shot
-- migration job that applies V2 against the live database with no downtime.
-- The application code treats both columns as nullable / optional, so a
-- service running before V2 is applied will keep working, and a service
-- running after V2 is applied will start populating the new columns.
-- =============================================================================

ALTER TABLE gift_scores
  ADD COLUMN IF NOT EXISTS confidence_score INTEGER
  CHECK (confidence_score IS NULL OR (confidence_score BETWEEN 0 AND 100));

ALTER TABLE gift_scores
  ADD COLUMN IF NOT EXISTS budget_fit TEXT
  CHECK (budget_fit IS NULL OR budget_fit IN ('low', 'good', 'high', 'unknown'));
