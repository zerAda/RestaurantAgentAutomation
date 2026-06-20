---
phase: 15
slug: tenant-identity-model-canonical-key
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-20
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Detailed checks are derived from `15-RESEARCH.md` → `## Validation Architecture`. The planner filled the Per-Task map below.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + psql (SQL assertions against ephemeral Postgres, via `.github/workflows/phase-15-assertions.yml`) + standalone Node ESM assertion (`node`, NOT vitest — `inventory-cms` has no test runner) + grep (fallback inventory) |
| **Config file** | none — CI ephemeral `postgres:15-alpine` service (db `strapi`) + `node:assert` script |
| **Quick run command** | `node inventory-cms/src/bootstrap-seeds/assert-canonical-tenant.mjs` |
| **Full suite command** | `psql -d strapi -f db/ci-fixtures/15-tenant-entitlements-fixture.sql && psql -v ON_ERROR_STOP=1 -d strapi -f db/ci-assertions/15-backfill-tenant-entitlements.sql && psql -v ON_ERROR_STOP=1 -d strapi -f db/ci-assertions/15-tenant-canonical-key.sql && node inventory-cms/src/bootstrap-seeds/assert-canonical-tenant.mjs` |
| **Estimated runtime** | ~30 seconds (incl. ephemeral Postgres spin-up in CI; <2s locally for the node + grep checks) |

> Correction vs draft: the draft referenced "vitest in inventory-cms". Confirmed during planning that
> `inventory-cms/package.json` has NO test runner and no `test` script — the seeder assertion is a
> standalone `node` ESM script per 15-RESEARCH.md's documented fallback.

---

## Sampling Rate

- **After every task commit:** Run the quick command (node seed-assertion) + the touched-criterion grep/SQL.
- **After every plan wave:** Run the full suite command above.
- **Before `/gsd:verify-work`:** Full suite must be green.
- **Max feedback latency:** 30 seconds.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | TEN-01 | doc/grep | `test -f docs/adr/0001-canonical-tenant-key.md && grep -q "00000000-0000-0000-0000-000000000001" docs/adr/0001-canonical-tenant-key.md && grep -q "tenants.tenant_id" docs/adr/0001-canonical-tenant-key.md && grep -qi "VARCHAR(255)" docs/adr/0001-canonical-tenant-key.md && grep -qi "SELECT tenant_id FROM tenants LIMIT 1" docs/adr/0001-canonical-tenant-key.md && grep -qi "Phase 19" docs/adr/0001-canonical-tenant-key.md && grep -q "schema.json" docs/adr/0001-canonical-tenant-key.md` | ❌ Task creates | ⬜ pending |
| 15-02-01 | 02 | 1 | TEN-01 | sql/file | `test -f db/ci-fixtures/15-tenant-entitlements-fixture.sql && grep -q "WHERE tenant_id = 'default'" db/ci-assertions/15-backfill-tenant-entitlements.sql && grep -q "RAISE EXCEPTION" db/ci-assertions/15-tenant-canonical-key.sql && test ! -f db/migrations/15-backfill-tenant-entitlements.sql` | ❌ W0 (this task) | ⬜ pending |
| 15-02-02 | 02 | 1 | TEN-01 | ci/yaml | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/phase-15-assertions.yml'))" && grep -q "ON_ERROR_STOP=1" .github/workflows/phase-15-assertions.yml && grep -q "15-backfill-tenant-entitlements.sql" .github/workflows/phase-15-assertions.yml` | ❌ W0 (this task) | ⬜ pending |
| 15-03-01 | 03 | 1 | TEN-01 | node/grep | `node inventory-cms/src/bootstrap-seeds/assert-canonical-tenant.mjs && grep -q "CANONICAL_FIRST_TENANT_UUID" inventory-cms/src/bootstrap-seeds/saas-entitlements.ts && ! grep -q "DEFAULT_TENANT_ID || 'default'" inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` | ❌ W0 (this task) | ⬜ pending |
| 15-03-02 | 03 | 1 | TEN-01 | doc/grep/json | `test -f docs/adr/0002-tenant-id-fallback-inventory.md && grep -q "INVENTORY-15" admin-dashboard/src/hooks/useEntitlements.ts && grep -rq "INVENTORY-15" workflows/W0_MODULE_GUARD.json workflows/W1_IN_WA.json workflows/W_DRIVER_ONBOARDING.json && python3 -c "import json; [json.load(open(f)) for f in ['workflows/W0_MODULE_GUARD.json','workflows/W1_IN_WA.json','workflows/W_DRIVER_ONBOARDING.json']]"` | ❌ Task creates | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky.*

> Coverage note: TEN-01-a/-b → 15-02 (SQL backfill + canonical assertion); TEN-01-c/-d → 15-03 Task 1
> (seeder fix + node assertion); TEN-01-e → 15-03 Task 2 (fallback inventory + annotations); the
> decision-record criterion (ROADMAP #1) → 15-01.

---

## Wave 0 Requirements

- [ ] `db/ci-fixtures/15-tenant-entitlements-fixture.sql` — Strapi-shaped `tenant_entitlements` + seeded `'default'` rows (Plan 15-02 Task 1)
- [ ] `db/ci-assertions/15-backfill-tenant-entitlements.sql` + `db/ci-assertions/15-tenant-canonical-key.sql` — backfill + DO-block assertions (Plan 15-02 Task 1)
- [ ] `.github/workflows/phase-15-assertions.yml` — wires fixture → backfill → assertion into the PR gate (Plan 15-02 Task 2)
- [ ] `inventory-cms/src/bootstrap-seeds/assert-canonical-tenant.mjs` — node seed-assertion, no test runner needed (Plan 15-03 Task 1)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 🔴 Live VPS entitlement-plane backfill to the real tenant UUID | TEN-01 | Requires prod SSH; discover live UUID via `SELECT tenant_id FROM tenants LIMIT 1` (never hardcode the CI/dev UUID) | Deferred to a prod-connected session per REMAINING-WORK posture. Documented in docs/adr/0001 §VPS-caveat and the 15-02 backfill header. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (fixture, assertions, CI workflow, node assertion)
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planned (ready for execution)
