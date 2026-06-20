-- =============================================================================
-- Phase 17 — CI assertion: verify channel_identities resolver behavior.
--
-- Run AFTER the channel_identities migration (db/migrations/2026-06-20_channel_identities.sql)
-- and FK-parent seed (tenants + restaurants). Each DO-block raises EXCEPTION on failure
-- (non-zero psql exit under ON_ERROR_STOP=1) or NOTICE on pass.
--
-- Use: psql -h localhost -p 5432 -U n8n -d n8n -v ON_ERROR_STOP=1 -f db/ci-assertions/17-tenant-resolution.sql
-- Target: n8n DB
--
-- This file proves the resolver SQL used by B0 - Resolve Channel Identity (DB):
--   SELECT tenant_id::text, restaurant_id::text
--   FROM channel_identities
--   WHERE channel = $1 AND identity = $2 AND is_active = true
--   LIMIT 1
-- behaves correctly for known and unknown identities.
-- =============================================================================

-- Assertion 1: KNOWN WA identity resolves to the correct tenant
DO $$
DECLARE v_tenant_id uuid; v_restaurant_id uuid;
BEGIN
  SELECT tenant_id, restaurant_id INTO v_tenant_id, v_restaurant_id
  FROM channel_identities
  WHERE channel = 'whatsapp' AND identity = 'CI_WA_PHONE_NUMBER_ID' AND is_active = true
  LIMIT 1;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: known identity CI_WA_PHONE_NUMBER_ID did not resolve';
  END IF;
  IF v_tenant_id <> '00000000-0000-0000-0000-000000000001'::uuid THEN
    RAISE EXCEPTION 'FAIL: resolved to wrong tenant: %', v_tenant_id;
  END IF;
  RAISE NOTICE 'PASS: known WA identity CI_WA_PHONE_NUMBER_ID resolves to correct tenant %', v_tenant_id;
END $$;

-- Assertion 2: KNOWN IG identity on a different channel resolves to the same canonical tenant
DO $$
DECLARE v_tenant_id uuid; v_restaurant_id uuid;
BEGIN
  SELECT tenant_id, restaurant_id INTO v_tenant_id, v_restaurant_id
  FROM channel_identities
  WHERE channel = 'instagram' AND identity = 'CI_IG_PAGE_ID' AND is_active = true
  LIMIT 1;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: known identity CI_IG_PAGE_ID did not resolve';
  END IF;
  IF v_tenant_id <> '00000000-0000-0000-0000-000000000001'::uuid THEN
    RAISE EXCEPTION 'FAIL: IG identity resolved to wrong tenant: %', v_tenant_id;
  END IF;
  RAISE NOTICE 'PASS: known IG identity CI_IG_PAGE_ID resolves to correct tenant %', v_tenant_id;
END $$;

-- Assertion 3: UNKNOWN identity returns 0 rows (fail-closed lookup behavior)
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM channel_identities
  WHERE channel = 'whatsapp' AND identity = 'UNKNOWN_RANDOM_ID_XYZ' AND is_active = true;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: unknown identity resolved — expected 0 rows, got %', v_count;
  END IF;
  RAISE NOTICE 'PASS: unknown identity UNKNOWN_RANDOM_ID_XYZ returns 0 rows (fail-closed verified)';
END $$;

-- Assertion 4: is_active = false row does NOT resolve (inactive identity is fail-closed)
-- NOTE: SAVEPOINT / ROLLBACK TO SAVEPOINT are transaction-control statements and are
-- NOT permitted inside a PL/pgSQL DO block. We instead deactivate the seeded row,
-- measure, then restore it (mutate-then-restore) so the assertion is idempotent.
DO $$
DECLARE v_count integer;
BEGIN
  UPDATE channel_identities SET is_active = false
  WHERE channel = 'whatsapp' AND identity = 'CI_WA_PHONE_NUMBER_ID';

  SELECT COUNT(*) INTO v_count
  FROM channel_identities
  WHERE channel = 'whatsapp' AND identity = 'CI_WA_PHONE_NUMBER_ID' AND is_active = true;

  -- Restore the seeded row before any further work so the file is re-runnable.
  UPDATE channel_identities SET is_active = true
  WHERE channel = 'whatsapp' AND identity = 'CI_WA_PHONE_NUMBER_ID';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: inactive identity still resolves — expected 0 rows, got %', v_count;
  END IF;

  RAISE NOTICE 'PASS: inactive identity (is_active=false) returns 0 rows (fail-closed on deactivated identity)';
END $$;
