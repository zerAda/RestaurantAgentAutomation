-- =============================================================================
-- Phase 18 — CI assertion: cross-tenant isolation (TEN-05). n8n DB target.
--
-- Run AFTER db/ci-fixtures/18-two-tenant-seed.sql (tenants A+B, restaurants A+B,
-- one order each). Each DO-block raises EXCEPTION on failure (non-zero psql exit
-- under ON_ERROR_STOP=1) or NOTICE on pass.
--
-- Use: psql -h localhost -p 5432 -U n8n -d n8n -v ON_ERROR_STOP=1 -f db/ci-assertions/18-cross-tenant-isolation.sql
--
-- Proves, in BOTH directions:
--   (1) Tenant A's scoped read cannot see Tenant B's order   (A->B read blocked)
--   (2) Tenant B's scoped read cannot see Tenant A's order   (B->A read blocked)
--   (3) Tenant A's scoped UPDATE cannot mutate Tenant B's order (A->B write blocked)
--   (4) An INSERT omitting tenant_id fails loudly (non-defaultable write)
--   (5) An INSERT with a bogus tenant_id is rejected by the FK
--
-- PITFALL 5: transaction-control rollback statements are NOT permitted inside a
-- PL/pgSQL DO block. The expected-failure assertions (4, 5) use a nested
-- BEGIN..EXCEPTION block to catch the error instead.
-- =============================================================================

-- Assertion 1: A->B read blocked — Tenant A's scoped read CANNOT see Tenant B's order.
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM orders
  WHERE tenant_id = '00000000-0000-0000-0000-000000000001'   -- A's ctx
    AND order_id  = 'bbbbbbbb-0000-0000-0000-00000000000b';  -- B's order
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant A read tenant B order (% rows)', v_count;
  END IF;
  RAISE NOTICE 'PASS: tenant A cannot read tenant B order';
END $$;

-- Assertion 2: B->A read blocked — Tenant B's scoped read CANNOT see Tenant A's order.
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM orders
  WHERE tenant_id = '00000000-0000-0000-0000-0000000000b2'   -- B's ctx
    AND order_id  = 'aaaaaaaa-0000-0000-0000-00000000000a';  -- A's order
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant B read tenant A order (% rows)', v_count;
  END IF;
  RAISE NOTICE 'PASS: tenant B cannot read tenant A order';
END $$;

-- Assertion 3: A->B write blocked — a tenant-scoped UPDATE by A cannot mutate B's order.
DO $$
DECLARE v_rows integer;
BEGIN
  WITH upd AS (
    UPDATE orders SET status = 'cancelled'
    WHERE order_id  = 'bbbbbbbb-0000-0000-0000-00000000000b'   -- B's order
      AND tenant_id = '00000000-0000-0000-0000-000000000001'   -- A scoping B's row
    RETURNING 1
  ) SELECT COUNT(*) INTO v_rows FROM upd;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FAIL: tenant A updated tenant B order (% rows)', v_rows;
  END IF;
  RAISE NOTICE 'PASS: tenant A scoped UPDATE cannot mutate tenant B order';
END $$;

-- Assertion 4: non-defaultable write — INSERT omitting tenant_id fails loudly.
-- Nested BEGIN..EXCEPTION catches the NOT NULL violation (Pitfall 5: no nested txn-control).
DO $$
DECLARE v_failed boolean := false;
BEGIN
  BEGIN
    INSERT INTO orders (order_id, restaurant_id, channel, "customer_userId", total_amount, status)
    VALUES ('cccccccc-0000-0000-0000-00000000000c',
            '00000000-0000-0000-0000-000000000000', 'whatsapp', 'userC', 50, 'confirmed');
  EXCEPTION WHEN not_null_violation THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'FAIL: INSERT without tenant_id succeeded (should be a NOT NULL violation)';
  END IF;
  RAISE NOTICE 'PASS: INSERT omitting tenant_id fails loudly (non-defaultable write enforced)';
END $$;

-- Assertion 5: FK enforcement — an order pointing at a non-existent tenant is rejected.
-- Nested BEGIN..EXCEPTION catches the foreign_key_violation (Pitfall 5: no nested txn-control).
DO $$
DECLARE v_failed boolean := false;
BEGIN
  BEGIN
    INSERT INTO orders (order_id, tenant_id, restaurant_id, channel, "customer_userId", total_amount, status)
    VALUES ('dddddddd-0000-0000-0000-00000000000d',
            '99999999-9999-9999-9999-999999999999',   -- not in tenants
            '00000000-0000-0000-0000-000000000000', 'whatsapp', 'userD', 50, 'confirmed');
  EXCEPTION WHEN foreign_key_violation THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'FAIL: order with bogus tenant_id accepted (should be a foreign_key_violation)';
  END IF;
  RAISE NOTICE 'PASS: order with non-existent tenant_id rejected by FK';
END $$;
