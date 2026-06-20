-- =============================================================================
-- Phase 16 — CI assertion: verify channel_identities table exists with correct
-- schema, constraints, and CI-sentinel seed rows.
--
-- Run AFTER the channel_identities migration (db/migrations/2026-06-20_channel_identities.sql).
-- Each DO-block raises an exception (non-zero exit) on failure, or a NOTICE on pass.
-- Use: psql -v ON_ERROR_STOP=1 -d n8n -f db/ci-assertions/16-channel-identities-check.sql
-- Target: n8n DB
-- =============================================================================

-- Assertion 1: table exists
DO $$
BEGIN
  IF to_regclass('public.channel_identities') IS NULL THEN
    RAISE EXCEPTION 'FAIL: table channel_identities does not exist in the n8n DB';
  END IF;
  RAISE NOTICE 'PASS: channel_identities table exists';
END $$;

-- Assertion 2: is_active column exists with default true
DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM information_schema.columns
   WHERE table_name = 'channel_identities'
     AND column_name = 'is_active'
     AND column_default LIKE '%true%';

  IF v_count = 0 THEN
    RAISE EXCEPTION 'FAIL: is_active column with DEFAULT true not found in channel_identities';
  END IF;
  RAISE NOTICE 'PASS: is_active column exists with DEFAULT true';
END $$;

-- Assertion 3: PK is (channel, identity) — 2-column primary key
DO $$
DECLARE
  v_pk_cols text;
BEGIN
  SELECT string_agg(a.attname, ',' ORDER BY array_position(i.indkey, a.attnum))
    INTO v_pk_cols
    FROM pg_constraint c
    JOIN pg_index i ON i.indexrelid = c.conindid
    JOIN pg_attribute a ON a.attrelid = c.conrelid
     AND a.attnum = ANY(i.indkey)
   WHERE c.contype = 'p'
     AND c.conrelid = 'channel_identities'::regclass;

  IF v_pk_cols IS NULL OR v_pk_cols NOT IN ('channel,identity', 'identity,channel') THEN
    RAISE EXCEPTION 'FAIL: PK on channel_identities is not (channel, identity) — got: %', coalesce(v_pk_cols, 'NULL');
  END IF;
  RAISE NOTICE 'PASS: channel_identities PK is (channel, identity)';
END $$;

-- Assertion 4a: FK to tenants(tenant_id) exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE contype = 'f'
       AND conrelid = 'channel_identities'::regclass
       AND confrelid = 'tenants'::regclass
  ) THEN
    RAISE EXCEPTION 'FAIL: FK from channel_identities to tenants not found';
  END IF;
  RAISE NOTICE 'PASS: FK channel_identities -> tenants(tenant_id) exists';
END $$;

-- Assertion 4b: FK to restaurants(restaurant_id) exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE contype = 'f'
       AND conrelid = 'channel_identities'::regclass
       AND confrelid = 'restaurants'::regclass
  ) THEN
    RAISE EXCEPTION 'FAIL: FK from channel_identities to restaurants not found';
  END IF;
  RAISE NOTICE 'PASS: FK channel_identities -> restaurants(restaurant_id) exists';
END $$;

-- Assertion 5: exactly 4 seed rows under the canonical CI tenant UUID,
-- one per channel (whatsapp/instagram/messenger/kiosk)
DO $$
DECLARE
  v_total    integer;
  v_channels integer;
BEGIN
  SELECT COUNT(*) INTO v_total
    FROM channel_identities
   WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

  IF v_total <> 4 THEN
    RAISE EXCEPTION 'FAIL: expected 4 seed rows for canonical CI tenant, found %', v_total;
  END IF;

  SELECT COUNT(DISTINCT channel) INTO v_channels
    FROM channel_identities
   WHERE tenant_id = '00000000-0000-0000-0000-000000000001'
     AND channel IN ('whatsapp', 'instagram', 'messenger', 'kiosk');

  IF v_channels <> 4 THEN
    RAISE EXCEPTION 'FAIL: expected 4 distinct channels (whatsapp/instagram/messenger/kiosk), found %', v_channels;
  END IF;

  RAISE NOTICE 'PASS: 4 CI-sentinel seed rows exist, one per channel';
END $$;

-- Assertion 6: FK is ENFORCED — negative test: bogus tenant_id must raise foreign_key_violation
DO $$
DECLARE
  v_violated boolean := false;
BEGIN
  BEGIN
    INSERT INTO channel_identities (channel, identity, tenant_id, restaurant_id)
      VALUES ('whatsapp', 'BOGUS_FK_TEST', '11111111-1111-1111-1111-111111111111',
              '00000000-0000-0000-0000-000000000000');
  EXCEPTION WHEN foreign_key_violation THEN
    v_violated := true;
  END;

  IF NOT v_violated THEN
    RAISE EXCEPTION 'FAIL: FK constraint did NOT reject a bogus tenant_id — referential integrity is not enforced';
  END IF;
  RAISE NOTICE 'PASS: FK enforced — bogus tenant_id was correctly rejected';
END $$;

-- Assertion 7: PK is ENFORCED — negative test: duplicate (channel, identity) must raise unique_violation
DO $$
DECLARE
  v_violated boolean := false;
BEGIN
  BEGIN
    INSERT INTO channel_identities (channel, identity, tenant_id, restaurant_id)
      VALUES ('whatsapp', 'CI_WA_PHONE_NUMBER_ID',
              '00000000-0000-0000-0000-000000000001',
              '00000000-0000-0000-0000-000000000000');
    INSERT INTO channel_identities (channel, identity, tenant_id, restaurant_id)
      VALUES ('whatsapp', 'CI_WA_PHONE_NUMBER_ID',
              '00000000-0000-0000-0000-000000000001',
              '00000000-0000-0000-0000-000000000000');
  EXCEPTION WHEN unique_violation THEN
    v_violated := true;
  END;

  IF NOT v_violated THEN
    RAISE EXCEPTION 'FAIL: PK did NOT reject a duplicate (channel, identity) insert — PK constraint is not enforced';
  END IF;
  RAISE NOTICE 'PASS: PK enforced — duplicate (channel, identity) was correctly rejected';
END $$;
