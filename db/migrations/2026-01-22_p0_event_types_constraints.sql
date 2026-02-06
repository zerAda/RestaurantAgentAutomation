/*
P1-DB-003 — EVENT TYPES CONSTRAINTS (security_events)

Goal:
- Standardize public.security_events.event_type via reference table + ENUM enforcement.
- Ensure fresh installs remain compatible with existing workflows.

Approach:
- Create ops.security_event_types (reference / documentation)
- Seed known event types (from workflows) + reserved RETENTION_RUN
- Create enum security_event_type_enum containing seeded values
- Alter security_events.event_type from text -> enum (idempotent)

Important:
- We deliberately do NOT attempt to constrain workflow_errors types because the current schema does not
  define an error_type column. If a future migration adds one, extend similarly.
*/

CREATE SCHEMA IF NOT EXISTS ops;

-- Reference table
CREATE TABLE IF NOT EXISTS ops.security_event_types (
  code        TEXT PRIMARY KEY,
  description TEXT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed known event types used by workflows (keep this list in sync with docs/EVENT_TYPES.md)
INSERT INTO ops.security_event_types(code, description) VALUES
  ('AUTH_DENY', 'Auth token invalid / access denied'),
  ('AUDIO_URL_BLOCKED', 'Voice URL rejected by security gate'),
  ('RETENTION_RUN', 'Retention purge job execution log')
ON CONFLICT (code) DO NOTHING;

-- Create enum once (idempotent)
DO $$
DECLARE
  v_vals TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'security_event_type_enum') THEN
    SELECT string_agg(quote_literal(code), ', ' ORDER BY code)
      INTO v_vals
    FROM ops.security_event_types;

    IF v_vals IS NULL THEN
      v_vals := quote_literal('RETENTION_RUN');
    END IF;

    EXECUTE format('CREATE TYPE security_event_type_enum AS ENUM (%s)', v_vals);
  END IF;
END $$;

-- Ensure enum contains seeded values (safe for replays)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT code FROM ops.security_event_types ORDER BY code LOOP
    BEGIN
      EXECUTE format('ALTER TYPE security_event_type_enum ADD VALUE %L', r.code);
    EXCEPTION WHEN duplicate_object THEN
      NULL;
    END;
  END LOOP;
END $$;

-- Convert column type (only if security_events exists and column is not already enum)
DO $$
DECLARE
  v_udt_name TEXT;
BEGIN
  IF to_regclass('public.security_events') IS NULL THEN
    RETURN;
  END IF;

  SELECT udt_name INTO v_udt_name
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='security_events' AND column_name='event_type';

  IF v_udt_name IS NULL THEN
    RETURN;
  END IF;

  IF v_udt_name <> 'security_event_type_enum' THEN
    -- Defensive trim to avoid unexpected whitespace values
    UPDATE public.security_events
       SET event_type = btrim(event_type)
     WHERE event_type IS NOT NULL;

    ALTER TABLE public.security_events
      ALTER COLUMN event_type TYPE security_event_type_enum
      USING event_type::text::security_event_type_enum;
  END IF;
END $$;
