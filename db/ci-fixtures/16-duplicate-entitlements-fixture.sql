-- =============================================================================
-- TEST/CI FIXTURE ONLY — NOT a production migration. Targets the strapi DB.
-- Seeds DUPLICATE rows so the live-safe migration's probe+dedupe path is exercised.
--
-- Purpose: Provide tenant_entitlements and product_modules tables with pre-seeded
-- duplicate (tenant_id, module_key) rows so the Phase 16 live-safe migration's
-- probe → dedupe → CONCURRENTLY path is fully exercised in CI.
--
-- DO NOT place under db/migrations/ — that directory targets the n8n DB.
-- This fixture targets the strapi DB (POSTGRES_DB: strapi).
-- =============================================================================

CREATE TABLE IF NOT EXISTS tenant_entitlements (
  id           serial PRIMARY KEY,
  tenant_id    varchar(255) NOT NULL,
  module_key   varchar(255) NOT NULL,
  enabled      boolean NOT NULL DEFAULT true,
  activated_at timestamptz DEFAULT now(),
  activated_by varchar(255),
  notes        text
);

CREATE TABLE IF NOT EXISTS product_modules (
  id         serial PRIMARY KEY,
  key        varchar(255) NOT NULL,
  name       varchar(255),
  created_at timestamptz DEFAULT now()
);

-- Seed DUPLICATE (tenant_id, module_key) rows with different activated_at so
-- the dedupe-keep-latest logic is exercised. The row with the latest activated_at
-- (the second 'order_bot_core' row) is the expected survivor.
INSERT INTO tenant_entitlements (tenant_id, module_key, enabled, activated_at) VALUES
  ('00000000-0000-0000-0000-000000000001', 'order_bot_core',   true, now() - interval '2 days'),
  ('00000000-0000-0000-0000-000000000001', 'order_bot_core',   true, now()),  -- the winner
  ('00000000-0000-0000-0000-000000000001', 'channel_whatsapp', true, now());

-- Seed DUPLICATE product_modules.key rows to exercise the product_modules dedupe path.
INSERT INTO product_modules (key) VALUES
  ('order_bot_core'),
  ('order_bot_core'),
  ('channel_whatsapp');
