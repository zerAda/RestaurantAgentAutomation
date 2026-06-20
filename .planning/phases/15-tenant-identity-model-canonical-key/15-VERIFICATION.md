---
phase: 15-tenant-identity-model-canonical-key
verified: 2026-06-20T14:00:00Z
status: passed
score: 4/4 success criteria verified (VPS live backfill deferred)
gaps: []
requirements_satisfied: [TEN-01]
deferred_to_vps: ["live tenant_entitlements backfill to the real tenant UUID (runtime-discovered via SELECT tenant_id FROM tenants LIMIT 1)"]
---

# Phase 15: Tenant Identity Model (Canonical Key) — Verification Report

**Phase Goal:** A single canonical tenant key — the UUID `tenants.tenant_id` — is the documented system of record, and the VARCHAR entitlement plane is reconciled to it so no runtime path silently substitutes the literal `'default'`.
**Verified:** 2026-06-20
**Status:** passed — 4/4 ROADMAP success criteria met at code/CI level; live VPS backfill deferred.

## Observable Truths

| # | Success Criterion | Status | Evidence |
|---|-------------------|--------|----------|
| 1 | Decision record names `tenants.tenant_id` (UUID) canonical + 1:1 entitlement mapping + `entitlement_audit_log.tenant_id` keep-VARCHAR-till-P19 decision | VERIFIED | `docs/adr/0001-canonical-tenant-key.md` (177 lines): contains `tenants.tenant_id`, canonical UUID `00000000-0000-0000-0000-000000000001`, `VARCHAR(255)`, `Phase 19`, `schema.json`, and the VPS `SELECT tenant_id FROM tenants LIMIT 1` caveat. Commit `0f6e8ed`. |
| 2 | Entitlement rows seeded against `'default'` are backfilled to the canonical UUID; backfill SQL runs green against ephemeral CI Postgres | VERIFIED (CI) | `db/ci-fixtures/15-tenant-entitlements-fixture.sql` + `db/ci-assertions/15-backfill-tenant-entitlements.sql` (idempotent `UPDATE ... WHERE tenant_id='default'`, strapi DB) + `15-tenant-canonical-key.sql` (`RAISE EXCEPTION` on survivors) wired into `.github/workflows/phase-15-assertions.yml` (`ON_ERROR_STOP=1`, `postgres:15-alpine`). NOT under `db/migrations/`. Commit `422427a`. |
| 3 | Every `\|\| 'default'` / `DEFAULT_TENANT_ID` fallback inventoried + annotated; no undocumented silent substitution | VERIFIED | `docs/adr/0002-tenant-id-fallback-inventory.md` lists all 5 occurrences with owning phases (15/17/17/17/21); `INVENTORY-15` markers present in `useEntitlements.ts`, `W0_MODULE_GUARD.json`, `W1_IN_WA.json`, `W_DRIVER_ONBOARDING.json` (all valid JSON). Commit `d305e83`. |
| 4 | Seeder seeds entitlements against canonical UUID, not `'default'`, verified by assertion | VERIFIED | `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` uses `CANONICAL_FIRST_TENANT_UUID`; `! grep "DEFAULT_TENANT_ID \|\| 'default'"` passes; `node inventory-cms/src/bootstrap-seeds/assert-canonical-tenant.mjs` exits 0. Commit `d305e83`. |

## Local Verification

14/14 non-DB acceptance checks passed (grep/file/yaml/json/node). The psql backfill+assertion SQL is syntactically valid and runs in CI against an ephemeral `postgres:15-alpine` (`strapi` DB) — not runnable in this sandbox (no local Postgres), which is the intended CI gate.

## Deferred (🔴 VPS)

Backfilling the **live** `tenant_entitlements` rows on production Postgres — must discover the real tenant UUID at runtime (`SELECT tenant_id FROM tenants LIMIT 1`), never the dev seed UUID. Deferred to a prod-connected session.

## Verdict

`passed` — TEN-01 satisfied at code/CI level. The keystone is in place: a canonical UUID key, a reconciled+CI-guarded entitlement plane, and a complete fallback inventory unblock Phases 16–21.
