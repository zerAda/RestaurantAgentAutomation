-- =============================================================================
-- Phase 15 — Idempotent backfill: tenant_entitlements 'default' -> canonical UUID
--
-- Target DB in production: strapi (NOT n8n).
-- Idempotent: re-running affects 0 rows once the seeder is fixed (Plan 15-03).
--
-- 🔴 VPS: the production run MUST discover the live UUID via
-- `SELECT tenant_id FROM tenants LIMIT 1` on the n8n DB and use THAT value —
-- never hardcode the CI/dev UUID below. The UUID
-- '00000000-0000-0000-0000-000000000001' is ONLY correct for CI/dev environments
-- where db/bootstrap.sql has been applied. See docs/adr/0001-canonical-tenant-key.md
-- for the full VPS caveat.
--
-- CI/dev canonical UUID (seeded by db/bootstrap.sql:2510-2517):
--   '00000000-0000-0000-0000-000000000001'
-- =============================================================================

-- Pre-flight: count rows to update
SELECT COUNT(*) AS rows_to_update FROM tenant_entitlements WHERE tenant_id = 'default';

-- Backfill: replace all 'default' tenant_id values with the canonical UUID
UPDATE tenant_entitlements
  SET tenant_id = '00000000-0000-0000-0000-000000000001'
WHERE tenant_id = 'default';

-- Post-flight: verify — must be 0 after backfill
SELECT COUNT(*) AS remaining_default_rows FROM tenant_entitlements WHERE tenant_id = 'default';
