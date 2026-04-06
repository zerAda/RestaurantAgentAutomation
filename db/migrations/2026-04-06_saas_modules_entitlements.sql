-- =============================================================================
-- SaaS Modules & Multi-Tenant Entitlements Migration
-- 2026-04-06 — Platform Hardening
-- =============================================================================

-- Strapi auto-creates these tables from content-type schemas on boot.
-- This migration ensures DB-level constraints that Strapi doesn't enforce.

-- 1. Unique constraint: one entitlement per tenant+module pair
-- (Strapi created the table, we add the constraint)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_tenant_module'
  ) THEN
    ALTER TABLE tenant_entitlements
      ADD CONSTRAINT uq_tenant_module UNIQUE (tenant_id, module_key);
  END IF;
END $$;

-- 2. Index for fast tenant lookup
CREATE INDEX IF NOT EXISTS idx_entitlements_tenant
  ON tenant_entitlements (tenant_id);

-- 3. Index for fast module lookup  
CREATE INDEX IF NOT EXISTS idx_entitlements_module
  ON tenant_entitlements (module_key);

-- 4. Index for active entitlements
CREATE INDEX IF NOT EXISTS idx_entitlements_active
  ON tenant_entitlements (tenant_id, enabled) WHERE enabled = true;

-- 5. Product modules unique key constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_product_module_key'
  ) THEN
    ALTER TABLE product_modules
      ADD CONSTRAINT uq_product_module_key UNIQUE (key);
  END IF;
END $$;

-- 6. Audit trail: track entitlement changes
CREATE TABLE IF NOT EXISTS entitlement_audit_log (
  id SERIAL PRIMARY KEY,
  tenant_id VARCHAR(255) NOT NULL,
  module_key VARCHAR(255) NOT NULL,
  action VARCHAR(50) NOT NULL, -- 'enabled', 'disabled', 'expired', 'config_changed'
  changed_by VARCHAR(255),
  old_value JSONB,
  new_value JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_entitlement_audit_tenant
  ON entitlement_audit_log (tenant_id, created_at DESC);
