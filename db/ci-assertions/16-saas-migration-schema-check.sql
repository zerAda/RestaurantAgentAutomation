-- =============================================================================
-- Phase 16 — CI assertion: verify all 6 SaaS objects exist after live-safe migration
--
-- Run AFTER the live-safe migration (db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql).
-- Each DO-block raises an exception (non-zero exit) on failure, or a NOTICE on pass.
-- Use: psql -v ON_ERROR_STOP=1 -d strapi -f db/ci-assertions/16-saas-migration-schema-check.sql
-- Target: strapi DB
-- =============================================================================

-- Assertion 1: uq_tenant_module constraint exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_tenant_module') THEN
    RAISE EXCEPTION 'FAIL: constraint uq_tenant_module does not exist — migration may not have run or ATTACH step failed';
  END IF;
  RAISE NOTICE 'PASS: uq_tenant_module constraint exists';
END $$;

-- Assertion 2: uq_product_module_key constraint exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_product_module_key') THEN
    RAISE EXCEPTION 'FAIL: constraint uq_product_module_key does not exist — migration may not have run or ATTACH step failed';
  END IF;
  RAISE NOTICE 'PASS: uq_product_module_key constraint exists';
END $$;

-- Assertion 3: idx_entitlements_tenant index exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i' AND c.relname = 'idx_entitlements_tenant'
  ) THEN
    RAISE EXCEPTION 'FAIL: index idx_entitlements_tenant does not exist';
  END IF;
  RAISE NOTICE 'PASS: idx_entitlements_tenant index exists';
END $$;

-- Assertion 4: idx_entitlements_module index exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i' AND c.relname = 'idx_entitlements_module'
  ) THEN
    RAISE EXCEPTION 'FAIL: index idx_entitlements_module does not exist';
  END IF;
  RAISE NOTICE 'PASS: idx_entitlements_module index exists';
END $$;

-- Assertion 5: idx_entitlements_active index exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i' AND c.relname = 'idx_entitlements_active'
  ) THEN
    RAISE EXCEPTION 'FAIL: index idx_entitlements_active does not exist';
  END IF;
  RAISE NOTICE 'PASS: idx_entitlements_active index exists';
END $$;

-- Assertion 6: entitlement_audit_log table exists
DO $$
BEGIN
  IF to_regclass('public.entitlement_audit_log') IS NULL THEN
    RAISE EXCEPTION 'FAIL: table entitlement_audit_log does not exist';
  END IF;
  RAISE NOTICE 'PASS: entitlement_audit_log table exists';
END $$;

-- Assertion 7: idx_entitlement_audit_tenant index exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i' AND c.relname = 'idx_entitlement_audit_tenant'
  ) THEN
    RAISE EXCEPTION 'FAIL: index idx_entitlement_audit_tenant does not exist';
  END IF;
  RAISE NOTICE 'PASS: idx_entitlement_audit_tenant index exists';
END $$;

-- Assertion 8: uq_tenant_module_idx is UNIQUE and READY (proves CONCURRENTLY built a real unique index)
DO $$
DECLARE
  v_is_unique  boolean;
  v_is_ready   boolean;
BEGIN
  SELECT i.indisunique, i.indisready
    INTO v_is_unique, v_is_ready
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
   WHERE c.relname = 'uq_tenant_module_idx';

  IF v_is_unique IS NULL THEN
    RAISE EXCEPTION 'FAIL: index uq_tenant_module_idx not found in pg_index — CONCURRENTLY step may not have run';
  END IF;
  IF NOT v_is_unique THEN
    RAISE EXCEPTION 'FAIL: uq_tenant_module_idx is not a unique index (indisunique = false)';
  END IF;
  IF NOT v_is_ready THEN
    RAISE EXCEPTION 'FAIL: uq_tenant_module_idx is not ready (indisready = false) — CONCURRENTLY may still be building';
  END IF;
  RAISE NOTICE 'PASS: uq_tenant_module_idx is unique and ready (CONCURRENTLY-built)';
END $$;

-- Assertion 9: uq_tenant_module REJECTS a duplicate insert (proves constraint is enforced)
DO $$
DECLARE
  v_raised boolean := false;
BEGIN
  BEGIN
    INSERT INTO tenant_entitlements (tenant_id, module_key)
      VALUES ('00000000-0000-0000-0000-000000000001', 'order_bot_core');
    INSERT INTO tenant_entitlements (tenant_id, module_key)
      VALUES ('00000000-0000-0000-0000-000000000001', 'order_bot_core');
    -- If we reach here without a violation, the constraint is NOT enforced
  EXCEPTION WHEN unique_violation THEN
    v_raised := true;
  END;

  IF NOT v_raised THEN
    RAISE EXCEPTION 'FAIL: uq_tenant_module did NOT reject a duplicate (tenant_id, module_key) insert — constraint is not enforced';
  END IF;
  RAISE NOTICE 'PASS: uq_tenant_module correctly rejected duplicate (tenant_id, module_key) insert';
END $$;
