-- Migration: P1 - Ops/Sec/QA Scopes & Admin Audit
-- Guard migration: compatible with bootstrap.sql (source of truth)
-- Bootstrap schema is the source of truth for all table definitions.

-- admin_wa_audit_log indexes (table created by bootstrap.sql)
CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_created ON admin_wa_audit_log (created_at);
CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_actor ON admin_wa_audit_log (actor_phone);

-- admin_phone_allowlist (bootstrap uses: tenant_id, restaurant_id, phone_number,
--   display_name, role, permissions, is_active, created_by)
CREATE TABLE IF NOT EXISTS admin_phone_allowlist (
  id serial PRIMARY KEY,
  tenant_id      uuid,
  restaurant_id  uuid,
  phone_number   text NOT NULL UNIQUE,
  display_name   text,
  role           text NOT NULL DEFAULT 'admin' CHECK (role IN ('admin','owner','super_admin')),
  permissions    jsonb NOT NULL DEFAULT '["status","flags","dlq:list","help"]'::jsonb,
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text
);

CREATE INDEX IF NOT EXISTS idx_admin_phone_allowlist_phone
  ON admin_phone_allowlist(phone_number) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_admin_phone_allowlist_tenant
  ON admin_phone_allowlist(tenant_id, restaurant_id) WHERE is_active = true;

-- admin_audit_log (created by bootstrap.sql)
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id              bigserial PRIMARY KEY,
  tenant_id       uuid NULL REFERENCES tenants(tenant_id) ON DELETE SET NULL,
  restaurant_id   uuid NULL REFERENCES restaurants(restaurant_id) ON DELETE SET NULL,
  actor_client_id uuid NULL REFERENCES api_clients(client_id) ON DELETE SET NULL,
  actor_name      text NULL,
  action          text NOT NULL,
  object_type     text NULL,
  object_id       text NULL,
  request_id      text NULL,
  ip              text NULL,
  user_agent      text NULL,
  payload_json    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_tenant_time
  ON admin_audit_log (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_action_time
  ON admin_audit_log (action, created_at DESC);
