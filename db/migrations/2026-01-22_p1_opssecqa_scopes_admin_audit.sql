-- Migration: P1 - Ops/Sec/QA Scopes & Admin Audit
-- Consolidated into db/bootstrap.sql (admin_wa_audit_log, admin_phone_allowlist)
-- This file is idempotent and safe to re-run.

CREATE TABLE IF NOT EXISTS admin_wa_audit_log (
  id             bigserial PRIMARY KEY,
  tenant_id      uuid NULL,
  restaurant_id  uuid NULL,
  actor_phone    text NOT NULL,
  actor_role     text NOT NULL DEFAULT 'admin',
  action         text NOT NULL,
  target_type    text,
  target_id      text,
  command_raw    text,
  metadata_json  jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip_address     text,
  success        boolean NOT NULL DEFAULT true,
  error_message  text,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_created ON admin_wa_audit_log (created_at);
CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_actor ON admin_wa_audit_log (actor_phone);

CREATE TABLE IF NOT EXISTS admin_phone_allowlist (
  id             serial PRIMARY KEY,
  tenant_id      uuid,
  restaurant_id  uuid,
  phone_number   text NOT NULL UNIQUE,
  display_name   text,
  role           text NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'owner', 'super_admin')),
  permissions    jsonb NOT NULL DEFAULT '["status","flags","dlq:list","help"]'::jsonb,
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text
);
