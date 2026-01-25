/*
P1-ARCH-002 / P1-ARCH-003 — Add security event types for contracts + SLO monitoring

Adds:
- CONTRACT_VALIDATION_FAILED
- SLO_BREACH

This migration is safe to replay.
*/

CREATE SCHEMA IF NOT EXISTS ops;

INSERT INTO ops.security_event_types(code, description) VALUES
  ('CONTRACT_VALIDATION_FAILED', 'Inbound payload rejected by JSON Schema validation'),
  ('SLO_BREACH', 'SLO threshold breached (queue/outbox)')
ON CONFLICT (code) DO NOTHING;

DO $$
DECLARE
  r RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'security_event_type_enum') THEN
    -- enum created by previous migration; if not present, nothing to alter here
    RETURN;
  END IF;

  FOR r IN SELECT code FROM ops.security_event_types WHERE code IN ('CONTRACT_VALIDATION_FAILED','SLO_BREACH') ORDER BY code LOOP
    BEGIN
      EXECUTE format('ALTER TYPE security_event_type_enum ADD VALUE %L', r.code);
    EXCEPTION WHEN duplicate_object THEN
      NULL;
    END;
  END LOOP;
END $$;
