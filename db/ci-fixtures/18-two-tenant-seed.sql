-- =============================================================================
-- Phase 18 — CI fixture: two-tenant + per-tenant order seed (TEN-05). n8n DB target.
--
-- Run AFTER the FK-parents step (tenants + restaurants) and the minimal `orders`
-- DDL exist (see .github/workflows/phase-18-assertions.yml). Seeds a SECOND isolated
-- tenant (Tenant B) so db/ci-assertions/18-cross-tenant-isolation.sql can prove
-- both-direction read/write separation between Tenant A and Tenant B.
--
-- Use: psql -h localhost -p 5432 -U n8n -d n8n -v ON_ERROR_STOP=1 -f db/ci-fixtures/18-two-tenant-seed.sql
--
-- Idempotent: every INSERT uses ON CONFLICT DO NOTHING (re-running is a no-op).
-- Tenant A is also re-inserted here so the fixture is self-contained if run standalone.
--
-- Canonical UUIDs:
--   Tenant A   00000000-0000-0000-0000-000000000001  (restaurant 00000000-0000-0000-0000-000000000000)
--   Tenant B   00000000-0000-0000-0000-0000000000b2  (restaurant 00000000-0000-0000-0000-0000000000bb)
--   A's order  aaaaaaaa-0000-0000-0000-00000000000a
--   B's order  bbbbbbbb-0000-0000-0000-00000000000b
-- =============================================================================

-- Tenants A + B (A may already exist from the FK-parents step).
INSERT INTO tenants (tenant_id, name) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Tenant A'),
  ('00000000-0000-0000-0000-0000000000b2', 'Tenant B')
ON CONFLICT (tenant_id) DO NOTHING;

-- Restaurants A + B.
INSERT INTO restaurants (restaurant_id, tenant_id, name) VALUES
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001', 'Rest A'),
  ('00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-0000000000b2', 'Rest B')
ON CONFLICT (restaurant_id) DO NOTHING;

-- One order per tenant. The mixed-case "customer_userId" column is double-quoted.
-- NOT NULL columns supplied: tenant_id, restaurant_id, channel, "customer_userId", total_amount.
INSERT INTO orders (order_id, tenant_id, restaurant_id, channel, "customer_userId", total_amount, status) VALUES
  ('aaaaaaaa-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'whatsapp', 'userA', 100, 'confirmed'),
  ('bbbbbbbb-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000bb', 'whatsapp', 'userB', 200, 'confirmed')
ON CONFLICT (order_id) DO NOTHING;
