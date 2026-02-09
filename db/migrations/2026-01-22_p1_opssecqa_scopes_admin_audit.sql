-- Migration: P1 - Ops/Sec/QA Scopes & Admin Audit
-- Consolidated into db/bootstrap.sql (admin_wa_audit_log, admin_phone_allowlist)
-- This file is idempotent and safe to re-run.

CREATE TABLE IF NOT EXISTS admin_wa_audit_log (
  id             bigserial PRIMARY KEY,
  ts             timestamptz NOT NULL DEFAULT now(),
  actor_phone    text NOT NULL,
  actor_type     text NOT NULL DEFAULT 'admin',
  command        text NOT NULL,
  target         text,
  result         text NOT NULL DEFAULT 'ok',
  detail         jsonb DEFAULT '{}'::jsonb,
  ip_address     inet,
  correlation_id text
);

CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_ts ON admin_wa_audit_log (ts);
CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_actor ON admin_wa_audit_log (actor_phone);

CREATE TABLE IF NOT EXISTS admin_phone_allowlist (
  id             serial PRIMARY KEY,
  phone_number   text NOT NULL UNIQUE,
  role           text NOT NULL DEFAULT 'admin',
  label          text,
  active         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz DEFAULT now()
);
