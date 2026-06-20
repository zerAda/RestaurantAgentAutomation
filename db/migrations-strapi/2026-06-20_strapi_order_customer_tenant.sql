-- =============================================================================
-- Per-tenant scoping for the Strapi-DB order/customer plane (TEN-04). Strapi DB target.
--
-- 🔴 VPS DEFERRED — this migration alters the LIVE strapi-DB orders/customers tables;
-- apply it in a prod-connected session via the migrations-strapi PGDATABASE=strapi pass
-- direct to postgres:5432 (NOT pgbouncer:6432). Backfill (Step 2) MUST complete BEFORE
-- the NOT NULL flip (Step 3).
--
-- BACKGROUND (18-01 O-1): the Strapi CMS connects to a SEPARATE `strapi` database
-- (inventory-cms/config/database.ts -> DATABASE_NAME default 'strapi'); the kiosk path
-- (kiosk-app POST /api/orders) writes the strapi-DB `orders` table, which carried NO
-- tenant field. This migration brings the strapi plane to parity with the n8n plane's
-- non-defaultable tenant_id scoping.
--
-- SAFE TO RE-RUN: every step is idempotent.
--   - ADD COLUMN uses IF NOT EXISTS
--   - Backfill targets only NULL rows
--   - SET NOT NULL is a no-op once the column is already NOT NULL
--   - DROP CONSTRAINT / DROP INDEX use IF EXISTS
--   - CREATE UNIQUE INDEX uses IF NOT EXISTS
--
-- Canonical CI tenant/restaurant (backfill default; parity with the n8n canonical key):
--   tenant     00000000-0000-0000-0000-000000000001
--   restaurant 00000000-0000-0000-0000-000000000000
-- =============================================================================

-- STEP 0: Session timeouts (bounded locks on the live tables).
SET lock_timeout = '5s';
SET statement_timeout = '120s';

-- STEP 1: Add the tenant columns idempotently (nullable first, so the backfill can run).
ALTER TABLE orders    ADD COLUMN IF NOT EXISTS tenant_id     uuid;
ALTER TABLE orders    ADD COLUMN IF NOT EXISTS restaurant_id uuid;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS tenant_id     uuid;

-- STEP 2: Backfill existing rows to the canonical tenant/restaurant BEFORE flipping NOT NULL.
UPDATE orders
   SET tenant_id     = '00000000-0000-0000-0000-000000000001',
       restaurant_id = '00000000-0000-0000-0000-000000000000'
 WHERE tenant_id IS NULL;

UPDATE customers
   SET tenant_id = '00000000-0000-0000-0000-000000000001'
 WHERE tenant_id IS NULL;

-- STEP 3: Flip NOT NULL (re-running SET NOT NULL on an already-NOT NULL column is a no-op).
ALTER TABLE orders    ALTER COLUMN tenant_id     SET NOT NULL;
ALTER TABLE orders    ALTER COLUMN restaurant_id SET NOT NULL;
ALTER TABLE customers ALTER COLUMN tenant_id     SET NOT NULL;

-- STEP 4: Replace the global phone unique with a per-tenant composite (tenant_id, phone).
--   The schema-level `phone unique:true` is dropped in customer/schema.json; the DB-level
--   uniqueness becomes per-tenant so two tenants can share a customer phone.
ALTER TABLE customers DROP CONSTRAINT IF EXISTS customers_phone_unique;
ALTER TABLE customers DROP CONSTRAINT IF EXISTS customers_phone_key;
DROP INDEX IF EXISTS customers_phone_unique;

-- CI/local form (plain Postgres, no pgBouncer): index builds inside the transaction.
CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_tenant_phone ON customers (tenant_id, phone);

-- 🔴 VPS form for the LIVE table (run direct to postgres:5432, NOT pgbouncer:6432 — Pitfall 6):
-- CREATE UNIQUE INDEX CONCURRENTLY uq_customers_tenant_phone ON customers (tenant_id, phone);
-- NOTE: CREATE UNIQUE INDEX CONCURRENTLY cannot run inside a transaction block and must
-- target postgres:5432 directly (pgBouncer POOL_MODE=transaction aborts CONCURRENTLY).
