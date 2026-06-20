-- =============================================================================
-- channel_identities routing table — maps channel-native ids to (tenant_id, restaurant_id).
--
-- Target: n8n DB (db-migrate default PGDATABASE=n8n). FKs valid here because
-- tenants/restaurants live here (db/bootstrap.sql:2510-2533).
--
-- is_active INCLUDED now; Phase 17 resolver adds `AND is_active = true`.
--
-- 🔴 VPS SEED DEFERRED: the four CI_* rows below are CI/dev sentinels only.
-- On production, discover real values at apply time:
--   WA identity:  SELECT value FROM platform_settings WHERE key = 'WA_PHONE_NUMBER_ID';
--   IG identity:  SELECT value FROM platform_settings WHERE key = 'IG_PAGE_ID';
--   MSG identity: SELECT value FROM platform_settings WHERE key = 'MESSENGER_PAGE_ID';
--   tenant_id:    SELECT tenant_id FROM tenants LIMIT 1;
--   restaurant_id: SELECT restaurant_id FROM restaurants WHERE tenant_id = $real LIMIT 1;
-- NEVER hardcode production identity values in this file.
-- =============================================================================

SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE TABLE IF NOT EXISTS channel_identities (
  channel        text        NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok','kiosk')),
  identity       text        NOT NULL,
  tenant_id      uuid        NOT NULL REFERENCES tenants(tenant_id)         ON DELETE CASCADE,
  restaurant_id  uuid        NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  is_active      boolean     NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (channel, identity)
);

CREATE INDEX IF NOT EXISTS idx_channel_identities_tenant
  ON channel_identities (tenant_id);

-- CI/dev sentinel seed (placeholder identities; real values discovered at VPS apply time)
INSERT INTO channel_identities (channel, identity, tenant_id, restaurant_id) VALUES
  ('whatsapp',  'CI_WA_PHONE_NUMBER_ID', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000'),
  ('instagram', 'CI_IG_PAGE_ID',         '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000'),
  ('messenger', 'CI_MSG_PAGE_ID',        '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000'),
  ('kiosk',     'CI_KIOSK_DEVICE_ID',    '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000')
ON CONFLICT (channel, identity) DO NOTHING;
