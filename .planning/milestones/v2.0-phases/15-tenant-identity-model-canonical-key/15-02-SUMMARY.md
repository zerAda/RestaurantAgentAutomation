---
phase: 15-tenant-identity-model-canonical-key
plan: 02
subsystem: tenant-identity
tags: [ci, backfill, sql, workflow, tenant]
key-decisions:
  - "Backfill is NOT under db/migrations/ — it targets the strapi DB, not the n8n DB"
  - "CI fixture simulates Strapi-auto-created tenant_entitlements with 3 'default' seed rows"
  - "VPS backfill caveat documented in backfill SQL header: use SELECT tenant_id FROM tenants LIMIT 1"
  - "CI workflow uses POSTGRES_DB: strapi service (not n8n) to correctly scope the ephemeral DB"
key-files:
  created:
    - db/ci-fixtures/15-tenant-entitlements-fixture.sql
    - db/ci-assertions/15-backfill-tenant-entitlements.sql
    - db/ci-assertions/15-tenant-canonical-key.sql
    - .github/workflows/phase-15-assertions.yml
  modified: []
metrics:
  duration: "~10 minutes"
  completed: "2026-06-20"
  tasks: 2
  files: 4
---

# Phase 15 Plan 02: CI Backfill Harness Summary

One-liner: Idempotent tenant_entitlements backfill SQL (UPDATE 'default' -> canonical UUID) with CI fixture and DO-block assertion wired into a postgres:15-alpine PR gate workflow targeting the strapi DB.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Wave 0 — CI fixture, backfill SQL, assertion SQL | 422427a | db/ci-fixtures/15-tenant-entitlements-fixture.sql, db/ci-assertions/15-backfill-tenant-entitlements.sql, db/ci-assertions/15-tenant-canonical-key.sql |
| 2 | CI workflow wiring fixture -> backfill -> assertion | 422427a | .github/workflows/phase-15-assertions.yml |

## Acceptance Criteria Status

- [x] All three SQL files exist at exact paths
- [x] Fixture contains `CREATE TABLE IF NOT EXISTS tenant_entitlements` and `('default',` seed rows
- [x] Backfill contains `UPDATE tenant_entitlements`, `WHERE tenant_id = 'default'`, and canonical UUID
- [x] Backfill header contains `SELECT tenant_id FROM tenants LIMIT 1` (VPS caveat)
- [x] Assertion file contains two `RAISE EXCEPTION` lines
- [x] No backfill file under `db/migrations/`
- [x] CI workflow is valid YAML (python3 yaml.safe_load passes)
- [x] Declares `postgres:15-alpine` service with `POSTGRES_DB: strapi`
- [x] References both assertion files
- [x] Uses `-v ON_ERROR_STOP=1` on all assertion steps
- [x] `paths:` trigger includes `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts`

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED
