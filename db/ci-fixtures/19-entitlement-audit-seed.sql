-- =============================================================================
-- Phase 19 — CI fixture: entitlement-audit seed (AUD-01/AUD-02). Strapi-shaped DB target.
--
-- Creates the post-19-01 (uuid) shape of entitlement_audit_log + a minimal `tenants`
-- (the FK parent) + a `tenant_entitlements` seed row under the canonical UUID, so the
-- node-test helper (writeAuditRow) and the DO-block assertions both exercise the target
-- shape — and the nullable FK behavior — WITHOUT needing to run the live migration first.
--
-- Use: psql -h localhost -p 5432 -U n8n -d n8n -v ON_ERROR_STOP=1 -f db/ci-fixtures/19-entitlement-audit-seed.sql
--
-- Idempotent: every CREATE uses IF NOT EXISTS; every INSERT uses ON CONFLICT DO NOTHING.
--
-- CORRECTION (ADR 0003 / Blocker B): entitlement_audit_log.tenant_id is `uuid` NULL
-- (nullable) with a NULLABLE FK to tenants(tenant_id) — global product-module audit rows
-- legitimately carry tenant_id = NULL (platform-scope; parity with admin_audit_log). The
-- all-zero sentinel is NOT used. The FK is included so the test exercises real FK behavior
-- (a non-null bogus uuid is rejected; a NULL tenant_id is accepted).
--
-- Canonical CI identifiers (parity with Phase 18 + ADR 0001):
--   tenant_id (canonical UUID)  00000000-0000-0000-0000-000000000001
--   module_key                  channel_whatsapp
--   canonical cache key         ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp
-- =============================================================================

-- FK parent: minimal tenants table + the canonical CI tenant.
CREATE TABLE IF NOT EXISTS tenants (
  tenant_id uuid PRIMARY KEY,
  name text
);

INSERT INTO tenants (tenant_id, name)
VALUES ('00000000-0000-0000-0000-000000000001', 'Default Chain')
ON CONFLICT (tenant_id) DO NOTHING;

-- entitlement_audit_log in the post-19-01 uuid shape (tenant_id uuid NULL + nullable FK).
CREATE TABLE IF NOT EXISTS entitlement_audit_log (
  id         SERIAL PRIMARY KEY,
  tenant_id  uuid,                       -- NULLABLE: global product-module rows carry NULL
  module_key VARCHAR(255) NOT NULL,
  action     VARCHAR(50)  NOT NULL,      -- 'created'|'config_changed'|'enabled'|'disabled'|'expired'|'deleted'
  changed_by VARCHAR(255),
  old_value  JSONB,
  new_value  JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Nullable FK to tenants(tenant_id) — exercises real FK behavior (NULL allowed; bogus uuid rejected).
-- Guarded so re-running the seed is a no-op.
DO $$
BEGIN
  IF to_regclass('tenants') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_constraint WHERE conname = 'fk_entitlement_audit_tenant'
     ) THEN
    EXECUTE 'ALTER TABLE entitlement_audit_log
             ADD CONSTRAINT fk_entitlement_audit_tenant
             FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id)';
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_entitlement_audit_tenant
  ON entitlement_audit_log (tenant_id, created_at DESC);

-- tenant_entitlements: the row the helper's create/update/delete audit operates on.
CREATE TABLE IF NOT EXISTS tenant_entitlements (
  id          SERIAL PRIMARY KEY,
  tenant_id   uuid NOT NULL,
  module_key  VARCHAR(255) NOT NULL,
  enabled     boolean DEFAULT true,
  expires_at  timestamptz
);

INSERT INTO tenant_entitlements (tenant_id, module_key, enabled)
VALUES ('00000000-0000-0000-0000-000000000001', 'channel_whatsapp', true)
ON CONFLICT DO NOTHING;
