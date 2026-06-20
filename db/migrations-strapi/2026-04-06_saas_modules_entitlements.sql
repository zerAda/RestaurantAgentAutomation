-- =============================================================================
-- Live-safe SaaS modules & entitlements migration. Strapi DB target.
--
-- 🔴 VPS apply deferred to a prod-connected session.
--
-- DELIVERY: applied by the strapi-DB pass in db-migrate (PGDATABASE=strapi).
-- The CONCURRENTLY step is executed direct-to-postgres:5432 (bypassing
-- pgBouncer POOL_MODE=transaction) by the 16-03 apply wrapper —
-- CREATE INDEX CONCURRENTLY cannot run inside a transaction block.
--
-- SAFE TO RE-RUN: all steps are idempotent.
--   - CONCURRENTLY uses IF NOT EXISTS
--   - ATTACH is guarded by pg_constraint check
--   - Indexes use CREATE INDEX IF NOT EXISTS
--   - Tables use CREATE TABLE IF NOT EXISTS
--
-- STRUCTURE: each logical step is a top-level statement or DO block.
-- The CONCURRENTLY statements (Step 4) are BARE top-level statements —
-- NOT wrapped in a DO block or BEGIN/COMMIT — so psql auto-commits them,
-- allowing CONCURRENTLY to run outside any transaction.
-- =============================================================================

-- STEP 0: Set session timeouts
SET lock_timeout = '5s';
SET statement_timeout = '120s';

-- STEP 1: Read-only duplicate PROBE (no failure — probe never fails the migration)
DO $$
DECLARE
  v_ent_dups   integer;
  v_prod_dups  integer;
BEGIN
  SELECT COUNT(*) INTO v_ent_dups
    FROM (
      SELECT tenant_id, module_key, COUNT(*)
        FROM tenant_entitlements
       GROUP BY tenant_id, module_key
      HAVING COUNT(*) > 1
    ) dups;

  SELECT COUNT(*) INTO v_prod_dups
    FROM (
      SELECT key, COUNT(*)
        FROM product_modules
       GROUP BY key
      HAVING COUNT(*) > 1
    ) dups;

  RAISE NOTICE 'PROBE: % entitlement dup-groups, % product_module dup-groups', v_ent_dups, v_prod_dups;
END $$;

-- STEP 2: DEDUPE tenant_entitlements — keep latest activated_at (ties broken by highest id)
DELETE FROM tenant_entitlements WHERE id NOT IN (
  SELECT DISTINCT ON (tenant_id, module_key) id
    FROM tenant_entitlements
   ORDER BY tenant_id, module_key, activated_at DESC NULLS LAST, id DESC
);

-- STEP 3: DEDUPE product_modules — keep highest id as survivor
DELETE FROM product_modules WHERE id NOT IN (
  SELECT DISTINCT ON (key) id
    FROM product_modules
   ORDER BY key, id DESC
);

-- STEP 4: CONCURRENTLY index builds
-- CONCURRENTLY: run OUTSIDE any txn, direct to postgres:5432
-- (see 16-03 wrapper). IF NOT EXISTS makes re-run idempotent.
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_tenant_module_idx
  ON tenant_entitlements (tenant_id, module_key);

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_product_module_key_idx
  ON product_modules (key);

-- STEP 5: ATTACH indexes as constraints (idempotent — guarded by pg_constraint check)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_tenant_module') THEN
    ALTER TABLE tenant_entitlements
      ADD CONSTRAINT uq_tenant_module UNIQUE USING INDEX uq_tenant_module_idx;
    RAISE NOTICE 'APPLIED: uq_tenant_module constraint attached from index';
  ELSE
    RAISE NOTICE 'SKIP: uq_tenant_module constraint already exists';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_product_module_key') THEN
    ALTER TABLE product_modules
      ADD CONSTRAINT uq_product_module_key UNIQUE USING INDEX uq_product_module_key_idx;
    RAISE NOTICE 'APPLIED: uq_product_module_key constraint attached from index';
  ELSE
    RAISE NOTICE 'SKIP: uq_product_module_key constraint already exists';
  END IF;
END $$;

-- STEP 6: Safe-as-is objects (already idempotent; copy verbatim from original migration)
-- Note: tenant_id kept as VARCHAR(255) per ADR 0001; uuid migration deferred to Phase 19.

-- 2. Index for fast tenant lookup
CREATE INDEX IF NOT EXISTS idx_entitlements_tenant
  ON tenant_entitlements (tenant_id);

-- 3. Index for fast module lookup
CREATE INDEX IF NOT EXISTS idx_entitlements_module
  ON tenant_entitlements (module_key);

-- 4. Index for active entitlements
CREATE INDEX IF NOT EXISTS idx_entitlements_active
  ON tenant_entitlements (tenant_id, enabled) WHERE enabled = true;

-- 5. Audit trail: track entitlement changes
CREATE TABLE IF NOT EXISTS entitlement_audit_log (
  id         SERIAL PRIMARY KEY,
  tenant_id  VARCHAR(255) NOT NULL,
  module_key VARCHAR(255) NOT NULL,
  action     VARCHAR(50)  NOT NULL, -- 'enabled', 'disabled', 'expired', 'config_changed'
  changed_by VARCHAR(255),
  old_value  JSONB,
  new_value  JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_entitlement_audit_tenant
  ON entitlement_audit_log (tenant_id, created_at DESC);
