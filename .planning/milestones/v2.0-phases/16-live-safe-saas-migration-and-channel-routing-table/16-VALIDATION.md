---
phase: 16
slug: live-safe-saas-migration-and-channel-routing-table
status: ready
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-20
---

# Phase 16 — Validation Strategy

> Per-phase validation contract. Detailed checks derive from `16-RESEARCH.md` → `## Validation Architecture`.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + psql against ephemeral Postgres (two instances: strapi DB + n8n DB) via `.github/workflows/phase-16-assertions.yml`; python `yaml.safe_load` structural checks for the compose/workflow edits |
| **Config file** | none — CI ephemeral `postgres:15-alpine` services (no pgbouncer in CI, so CONCURRENTLY works against the plain service) |
| **Quick run command** | `psql -h localhost -U n8n -d strapi -v ON_ERROR_STOP=1 -f db/ci-fixtures/16-duplicate-entitlements-fixture.sql && psql -h localhost -U n8n -d strapi -v ON_ERROR_STOP=1 -f db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql && psql -h localhost -U n8n -d strapi -v ON_ERROR_STOP=1 -f db/ci-assertions/16-saas-migration-schema-check.sql` |
| **Full suite command** | full `.github/workflows/phase-16-assertions.yml` (strapi track: fixture → live-safe migration → idempotent re-run → schema-check; n8n track: FK-parent seed → channel_identities → idempotent re-run → channel-identities check) |
| **Estimated runtime** | ~60s |

---

## Sampling Rate

- **After every task commit:** touched-criterion psql/yaml check (the task's `<verify><automated>`)
- **After every plan wave:** full suite (`phase-16-assertions.yml`)
- **Before `/gsd:verify-work`:** full suite green
- **Max feedback latency:** ~60s

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-00 | 01 | 1 | DB-01 | sql | `psql -d strapi -f db/ci-fixtures/16-duplicate-entitlements-fixture.sql && psql -d strapi -c "SELECT count(*) FROM tenant_entitlements"` | ❌ W0 → created in 16-01 T0 | ⬜ pending |
| 16-01-01 | 01 | 1 | DB-01 | sql | `psql -d strapi -f db/ci-fixtures/16-duplicate-entitlements-fixture.sql && psql -d strapi -f db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql && psql -d strapi -f db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql && psql -d strapi -f db/ci-assertions/16-saas-migration-schema-check.sql` | ❌ W0 → 16-01 T0 | ⬜ pending |
| 16-02-00 | 02 | 1 | TEN-02 | sql | `test -f db/ci-assertions/16-channel-identities-check.sql` | ❌ W0 → created in 16-02 T0 | ⬜ pending |
| 16-02-01 | 02 | 1 | TEN-02 | sql | `psql -d n8n -f db/migrations/2026-06-20_channel_identities.sql && psql -d n8n -f db/migrations/2026-06-20_channel_identities.sql && psql -d n8n -f db/ci-assertions/16-channel-identities-check.sql` | ❌ W0 → 16-02 T0 | ⬜ pending |
| 16-03-01 | 03 | 2 | DB-01 | yaml | `python3 -c "import yaml; ... assert 'migrations-strapi' and '-d strapi' and '-h postgres' in db-migrate command"` | ✅ (edits docker-compose.base.yml) | ⬜ pending |
| 16-03-02 | 03 | 2 | DB-01, TEN-02 | yaml | `python3 -c "import yaml; ... two postgres services, both 16 assertions + fixture referenced"` | ❌ → created in 16-03 T2 | ⬜ pending |

*All Wave 0 fixture/assertion files are created inside the Task 0 of plans 16-01 and 16-02 (so each plan owns its own test scaffold). 16-03 only consumes them.*

---

## Wave 0 Requirements

- [ ] `db/ci-fixtures/16-duplicate-entitlements-fixture.sql` — seeds duplicate `(tenant_id, module_key)` + duplicate `product_modules.key` rows to prove the migration survives dupes *(created by 16-01 Task 0)*
- [ ] `db/ci-assertions/16-saas-migration-schema-check.sql` — uq_tenant_module/uq_product_module_key + 4 entitlement indexes + entitlement_audit_log exist; CONCURRENTLY index unique+ready; dup-insert rejected *(created by 16-01 Task 0)*
- [ ] `db/ci-assertions/16-channel-identities-check.sql` — table exists with PK `(channel, identity)` + FKs + is_active + 4 seed rows; FK/PK enforced *(created by 16-02 Task 0)*
- [ ] `.github/workflows/phase-16-assertions.yml` — two-DB CI gate (strapi + n8n) *(created by 16-03 Task 2)*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 🔴 Apply live-safe migration on production strapi DB (CONCURRENTLY direct to postgres:5432) | DB-01 | Requires prod SSH + live data | Deferred to prod-connected session |
| 🔴 Apply + seed channel_identities on production n8n DB (real WA/IG/MSG ids from `platform_settings`, runtime-discovered tenant/restaurant UUIDs) | TEN-02 | Requires prod SSH + live data; values are operator-supplied secrets | Deferred to prod-connected session — NEVER hardcode prod values |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready
