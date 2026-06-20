-- =============================================================================
-- Phase 15 — CI assertion: verify tenant_entitlements canonical key state
--
-- Run after the backfill SQL (15-backfill-tenant-entitlements.sql).
-- Each DO-block raises an exception (non-zero exit) on failure, or a NOTICE on pass.
-- Use: psql -v ON_ERROR_STOP=1 ... -f db/ci-assertions/15-tenant-canonical-key.sql
-- =============================================================================

-- Assertion 1: zero rows where tenant_id = 'default' (backfill eliminated them all)
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM tenant_entitlements WHERE tenant_id = 'default';
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FAIL: % entitlement rows still use tenant_id = ''default'' — backfill did not run or seeder re-wrote default rows', v_count;
  END IF;
  RAISE NOTICE 'PASS: no default-tenant entitlement rows (0 rows with tenant_id = ''default'')';
END $$;

-- Assertion 2: at least one row with the canonical UUID exists
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM tenant_entitlements
    WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  IF v_count = 0 THEN
    RAISE EXCEPTION 'FAIL: no entitlement rows found for canonical tenant UUID ''00000000-0000-0000-0000-000000000001'' — backfill may not have run';
  END IF;
  RAISE NOTICE 'PASS: % entitlement rows under canonical UUID ''00000000-0000-0000-0000-000000000001''', v_count;
END $$;
