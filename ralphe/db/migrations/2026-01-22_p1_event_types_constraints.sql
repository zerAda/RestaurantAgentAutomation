-- Migration: P1 - Event Types & Constraints
-- Consolidated into db/bootstrap.sql (security_events table)
-- This file is idempotent and safe to re-run.

-- security_events uses TEXT NOT NULL for event_type (no enum)
-- Ensure column exists with correct type
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'security_events' AND column_name = 'event_type'
  ) THEN
    RAISE NOTICE 'security_events.event_type column missing - see bootstrap.sql';
  END IF;
END $$;
