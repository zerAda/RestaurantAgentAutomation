-- =============================================================================
-- TEST/CI FIXTURE ONLY — NOT a production migration.
-- Simulates the Strapi-auto-created tenant_entitlements table in the strapi DB.
--
-- Purpose: Provide a tenant_entitlements table in ephemeral CI Postgres so that
-- the Phase 15 backfill SQL and assertions can run without requiring a live
-- Strapi instance.
--
-- This fixture mirrors the Strapi-created shape derived from:
-- inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/schema.json
--
-- DO NOT place under db/migrations/ — that directory targets the n8n DB.
-- This fixture targets the strapi DB (POSTGRES_DB: strapi in phase-15-assertions.yml).
-- =============================================================================

CREATE TABLE IF NOT EXISTS tenant_entitlements (
  id serial PRIMARY KEY,
  tenant_id varchar(255) NOT NULL,
  module_key varchar(255) NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  activated_at timestamptz DEFAULT now(),
  activated_by varchar(255),
  notes text
);

-- Seed three 'default' rows simulating the seeder's pre-fix output
-- (one row per non-shared_core, non-experimental module that the seeder creates)
INSERT INTO tenant_entitlements (tenant_id, module_key, enabled) VALUES
  ('default', 'order_bot_core', true),
  ('default', 'channel_whatsapp', true),
  ('default', 'channel_instagram', true);
