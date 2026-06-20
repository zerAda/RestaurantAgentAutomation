-- =============================================================================
-- entitlement_audit_log.tenant_id VARCHAR(255) -> uuid + NULLABLE FK to tenants (AUD-01).
-- Strapi DB target.
--
-- 🔴 VPS DEFERRED — this migration alters the LIVE strapi-DB `entitlement_audit_log`
-- table; apply it in a prod-connected session via the migrations-strapi PGDATABASE=strapi
-- pass, direct to postgres:5432 (NOT pgbouncer:6432). On prod, the FK target must be the
-- LIVE tenant UUID plane — never hardcode the CI seed `…0001` (ADR 0001 runtime-discovery
-- rule; this migration does NOT write any tenant_id values, so no hardcoding occurs here).
--
-- BACKGROUND: ADR 0001:101 assigned this VARCHAR->uuid + nullable-FK migration to Phase 19
-- (the phase that wires the audit writers, which validate before insert). ADR 0003 records
-- the disposition (O-3 = migrate now). The column starts as
-- `tenant_id VARCHAR(255) NOT NULL` per db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql:114-126.
--
-- CORRECTION (ADR 0003): tenant_id becomes `uuid NULL` (NOT NOT-NULL) with a NULLABLE FK to
-- tenants(tenant_id) — parity with the admin_audit_log.tenant_id uuid NULL precedent
-- (db/bootstrap.sql:987-988). Global product-module audit rows legitimately carry
-- tenant_id = NULL (platform-scope); the all-zero sentinel is NOT used. We therefore also
-- DROP the legacy NOT NULL on tenant_id so those NULL-tenant rows are accepted.
--
-- SAFE TO RE-RUN: every step is idempotent (applies cleanly TWICE on an ephemeral Postgres
-- = no-op):
--   - The ALTER … TYPE uuid runs ONLY when the column is not already uuid (guarded).
--   - The DROP NOT NULL is a no-op once the column is already nullable.
--   - The FK is ADDed only if absent (pg_constraint guard) and only if tenants exists
--     (to_regclass guard); VALIDATE on an already-validated constraint is a no-op.
--   - CREATE INDEX uses IF NOT EXISTS.
--
-- PITFALL (Phase 18 §5): transaction-control rollback statements are illegal inside a
-- PL/pgSQL DO block. None are used below — the guards are plain IF/EXISTS checks.
-- =============================================================================

-- STEP 0: Session timeouts (bounded locks on the live table).
SET lock_timeout = '5s';
SET statement_timeout = '120s';

-- STEP 1: tenant_id VARCHAR(255) -> uuid, only if not already uuid (guarded -> re-run is a no-op).
-- The `USING tenant_id::uuid` cast converts existing canonical-UUID strings; a non-UUID legacy
-- value (e.g. the literal 'default') would error LOUDLY — which is correct, it must be cleaned
-- first (ADR 0001's backfill makes the value a UUID-as-string before this runs).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'entitlement_audit_log'
      AND column_name = 'tenant_id'
      AND data_type <> 'uuid'
  ) THEN
    EXECUTE 'ALTER TABLE entitlement_audit_log ALTER COLUMN tenant_id TYPE uuid USING tenant_id::uuid';
  END IF;
END $$;

-- STEP 2: Make tenant_id NULLABLE (parity with admin_audit_log; global product-module rows
-- carry tenant_id = NULL). DROP NOT NULL is a no-op once the column is already nullable.
ALTER TABLE entitlement_audit_log ALTER COLUMN tenant_id DROP NOT NULL;

-- STEP 3: NULLABLE FK to tenants(tenant_id), live-safe (NOT VALID then VALIDATE).
-- Guarded on (a) the constraint not already existing AND (b) the tenants table existing in
-- THIS database (to_regclass) — on a strapi DB without a local `tenants` table the FK step
-- no-ops and the type migration still applies (recorded in the prod-apply runbook).
DO $$
BEGIN
  IF to_regclass('tenants') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_constraint WHERE conname = 'fk_entitlement_audit_tenant'
     ) THEN
    EXECUTE 'ALTER TABLE entitlement_audit_log
             ADD CONSTRAINT fk_entitlement_audit_tenant
             FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) NOT VALID';
  END IF;
END $$;

-- Separate guarded VALIDATE (only when the constraint exists; VALIDATE on an already-validated
-- constraint is a no-op). A nullable FK lets NULL-tenant (global product-module) rows through.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_entitlement_audit_tenant'
  ) THEN
    EXECUTE 'ALTER TABLE entitlement_audit_log VALIDATE CONSTRAINT fk_entitlement_audit_tenant';
  END IF;
END $$;

-- STEP 4 (idempotent re-assert): keep the tenant index across the type change.
CREATE INDEX IF NOT EXISTS idx_entitlement_audit_tenant
  ON entitlement_audit_log (tenant_id, created_at DESC);

-- 🔴 VPS: on prod, the FK target tenants(tenant_id) must exist in the strapi DB. If tenants is
-- NOT present in the strapi DB on prod, the FK step is skipped (the to_regclass guard no-ops)
-- and the type migration still applies — record this in the prod-apply runbook. Discover the
-- LIVE tenant UUID per ADR 0001 (SELECT tenant_id FROM tenants LIMIT 1); never hardcode `…0001`.
