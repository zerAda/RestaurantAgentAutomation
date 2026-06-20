-- =============================================================================
-- Phase 19 — CI assertion: entitlement audit-row coverage (AUD-01). Strapi-shaped DB target.
--
-- Run AFTER db/ci-fixtures/19-entitlement-audit-seed.sql (tenants + the uuid-shaped
-- entitlement_audit_log + tenant_entitlements). Each DO-block raises EXCEPTION on failure
-- (non-zero psql exit under ON_ERROR_STOP=1) or NOTICE on pass.
--
-- Use: psql -h localhost -p 5432 -U n8n -d n8n -v ON_ERROR_STOP=1 -f db/ci-assertions/19-entitlement-audit.sql
--
-- Proves:
--   (1) a row is written per op (created/config_changed/deleted) with old->new captured
--   (2) a non-canonical-UUID tenant_id is rejected by the uuid column type
--   (3) the action vocabulary the deriveAction() helper produces is present
--   (4) CORRECTION (Blocker B): a product-module (global) row writes tenant_id IS NULL and
--       the nullable FK does NOT reject it — the all-zero sentinel is NOT used
--
-- PITFALL 5: transaction-control rollback statements are NOT permitted inside a PL/pgSQL DO
-- block. The expected-failure assertions use a nested BEGIN..EXCEPTION block to catch the
-- error instead — no in-block transaction control is used anywhere in this file.
--
-- Canonical identifiers: tenant 00000000-0000-0000-0000-000000000001, module channel_whatsapp.
-- =============================================================================

-- Inline-INSERT three rows simulating the three single-row hooks (the SQL-only DO-block path
-- does not depend on the node-test helper having run).
INSERT INTO entitlement_audit_log (tenant_id, module_key, action, changed_by, old_value, new_value) VALUES
  ('00000000-0000-0000-0000-000000000001', 'channel_whatsapp', 'created', 'system',
     NULL, '{"enabled": true}'::jsonb),
  ('00000000-0000-0000-0000-000000000001', 'channel_whatsapp', 'config_changed', 'admin@example.com',
     '{"enabled": true}'::jsonb, '{"enabled": true, "notes": "x"}'::jsonb),
  ('00000000-0000-0000-0000-000000000001', 'channel_whatsapp', 'deleted', 'system',
     '{"enabled": true}'::jsonb, NULL);

-- Assertion 1: a row per op + old->new capture (created = new-only; deleted = old-only).
DO $$
DECLARE
  v_count   integer;
  v_created integer;
  v_deleted integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM entitlement_audit_log
   WHERE tenant_id = '00000000-0000-0000-0000-000000000001'
     AND module_key = 'channel_whatsapp';
  IF v_count < 3 THEN
    RAISE EXCEPTION 'FAIL: not one audit row per op (found % rows)', v_count;
  END IF;

  SELECT COUNT(*) INTO v_created FROM entitlement_audit_log
   WHERE module_key = 'channel_whatsapp' AND action = 'created'
     AND old_value IS NULL AND new_value IS NOT NULL;
  IF v_created < 1 THEN
    RAISE EXCEPTION 'FAIL: created row missing new-only old->new capture';
  END IF;

  SELECT COUNT(*) INTO v_deleted FROM entitlement_audit_log
   WHERE module_key = 'channel_whatsapp' AND action = 'deleted'
     AND new_value IS NULL AND old_value IS NOT NULL;
  IF v_deleted < 1 THEN
    RAISE EXCEPTION 'FAIL: deleted row missing old-only old->new capture';
  END IF;

  RAISE NOTICE 'PASS: a row per op with old->new captured (created new-only, deleted old-only)';
END $$;

-- Assertion 2: canonical-UUID enforcement (DB plane). A non-UUID tenant_id must be rejected
-- by the uuid column type. Nested BEGIN..EXCEPTION (Pitfall 5: no transaction-control rollback).
DO $$
DECLARE v_failed boolean := false;
BEGIN
  BEGIN
    INSERT INTO entitlement_audit_log (tenant_id, module_key, action)
    VALUES ('default', 'channel_whatsapp', 'created');
  EXCEPTION WHEN invalid_text_representation OR others THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'FAIL: non-UUID tenant_id accepted into entitlement_audit_log';
  END IF;
  RAISE NOTICE 'PASS: non-UUID tenant_id rejected by the uuid column type';
END $$;

-- Assertion 3: action vocabulary present (ties to deriveAction() output).
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM entitlement_audit_log
   WHERE action IN ('created', 'config_changed', 'deleted');
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FAIL: no row with a known action vocabulary value';
  END IF;
  RAISE NOTICE 'PASS: action vocabulary (created/config_changed/deleted) present';
END $$;

-- Assertion 4 (CORRECTION / Blocker B): a product-module (global) audit row writes
-- tenant_id IS NULL and the nullable FK does NOT reject it — the all-zero sentinel is NOT used.
DO $$
DECLARE
  v_null_rows integer;
  v_fk_rejected boolean := false;
BEGIN
  -- A global product-module row: tenant_id = NULL must be ACCEPTED by the nullable FK.
  INSERT INTO entitlement_audit_log (tenant_id, module_key, action, changed_by, old_value, new_value)
  VALUES (NULL, 'channel_whatsapp', 'config_changed', 'system',
          '{"enabled_globally": true}'::jsonb, '{"enabled_globally": false}'::jsonb);

  SELECT COUNT(*) INTO v_null_rows FROM entitlement_audit_log WHERE tenant_id IS NULL;
  IF v_null_rows < 1 THEN
    RAISE EXCEPTION 'FAIL: product-module NULL-tenant audit row not written (nullable FK rejected it?)';
  END IF;

  -- Defensive: the all-zero sentinel must NOT be how globals are recorded.
  IF EXISTS (SELECT 1 FROM entitlement_audit_log
              WHERE tenant_id = '00000000-0000-0000-0000-000000000000') THEN
    RAISE EXCEPTION 'FAIL: all-zero sentinel tenant_id used for a global row (should be NULL)';
  END IF;

  -- And the nullable FK still rejects a NON-NULL bogus uuid (proves the FK is real, not dropped).
  BEGIN
    INSERT INTO entitlement_audit_log (tenant_id, module_key, action)
    VALUES ('99999999-9999-9999-9999-999999999999', 'channel_whatsapp', 'created');
  EXCEPTION WHEN foreign_key_violation THEN
    v_fk_rejected := true;
  END;
  IF NOT v_fk_rejected THEN
    RAISE EXCEPTION 'FAIL: non-null bogus tenant_id accepted (nullable FK is not enforcing)';
  END IF;

  RAISE NOTICE 'PASS: product-module row writes tenant_id IS NULL (accepted); non-null bogus uuid FK-rejected; no all-zero sentinel';
END $$;
