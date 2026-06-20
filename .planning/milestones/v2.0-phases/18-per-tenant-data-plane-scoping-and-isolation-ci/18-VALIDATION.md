---
phase: 18
slug: per-tenant-data-plane-scoping-and-isolation-ci
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-20
---

# Phase 18 — Validation Strategy

> Per-phase validation contract. Detailed checks derive from `18-RESEARCH.md` → `## Validation Architecture` (§5). The planner fills the Per-Task map below.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `python3 json.load` + jq/grep structural assertions on the workflow JSONs + Strapi `schema.json`; `node --check` is N/A (no Code-node edits this phase — scoping is SQL inside postgres nodes); psql DO-block isolation assertions against ephemeral Postgres via `.github/workflows/phase-18-assertions.yml`; idempotent-migration apply check on ephemeral PG |
| **Config file** | `.github/workflows/phase-18-assertions.yml` |
| **Quick run command (structural, <5s)** | `for f in W_ORDER_FINALIZER W51_VIP_WIN_BACK W53_DYNAMIC_KITCHEN_LOAD W_THE_USUAL W_ADMIN_PROACTIVE_AGENT W14_ADMIN_WA_SUPPORT_CONSOLE; do jq -r '.nodes[]\|select(.parameters.query)\|.parameters.query' workflows/$f.json \| grep -q tenant_id \|\| echo "MISS $f"; done; jq -e '.attributes.tenant_id' inventory-cms/src/api/order/content-types/order/schema.json` |
| **Full suite command** | `act pull_request -W .github/workflows/phase-18-assertions.yml` (or push to PR) |
| **Local SQL run (NO docker; root cannot initdb)** | ephemeral Postgres as the `postgres` system user — see below |
| **Estimated runtime** | ~90s (CI: PG service start + minimal DDL + seed + isolation SQL + jq structural); <5s per-task local jq/grep; ~10s local ephemeral-PG SQL suite |

### Local ephemeral Postgres (documented hard constraint)

Docker daemon is **DOWN** on this host and `initdb` refuses to run as `root`. Run the SQL fixtures /
assertions / the migrations-strapi idempotency check via the system `postgres` user +
`/usr/lib/postgresql/16/bin` (verified working 2026-06-20):

```bash
TMPPG=$(mktemp -d); chown postgres:postgres "$TMPPG"
su postgres -c "/usr/lib/postgresql/16/bin/initdb -D $TMPPG/data -A trust -U postgres"
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D $TMPPG/data -o '-p 55433 -k $TMPPG' -l $TMPPG/log start"
PSQL="su postgres -c \"/usr/lib/postgresql/16/bin/psql -h $TMPPG -p 55433 -U postgres -d postgres -v ON_ERROR_STOP=1\""
# Isolation suite (18-03): create tenants/restaurants + minimal orders table, then:
#   -f db/ci-fixtures/18-two-tenant-seed.sql ; -f db/ci-assertions/18-cross-tenant-isolation.sql
# Migration idempotency (18-02): create orders/customers stub tables, then apply the migration TWICE:
#   -f db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql  (run it a second time -> no-op)
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D $TMPPG/data stop"; rm -rf "$TMPPG"
```

Local runner is PG **16.13**; CI service is PG **15-alpine** (prod parity). `not_null_violation` /
`foreign_key_violation` / nested `BEGIN..EXCEPTION` semantics are identical across 15/16. **No
pgBouncer** in CI or local — DDL and `CREATE UNIQUE INDEX` run against plain Postgres directly; the
`CONCURRENTLY` form is the commented 🔴 VPS-only path (targets `postgres:5432`, not pgbouncer:6432).

---

## Sampling Rate

- **After every task commit:** touched-workflow `json.load` + jq `tenant_id` grep; for the Strapi
  schemas, `jq -e '.attributes.tenant_id'`; for SQL/migration changes, the local ephemeral-PG run.
- **After every plan wave:** full suite (`phase-18-assertions.yml`, both jobs).
- **Before `/gsd:verify-work`:** full suite green AND the `18-SCOPING-CHECKLIST.md` artifact complete
  (every order/customer path annotated, O-1 resolved).
- **Max feedback latency:** ~90s (full CI suite); <5s per-task local jq/grep; ~10s local SQL suite.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 18-01-01 | 01 | 1 | TEN-04 | grep (O-1 evidence) | `grep -q "O-1" 18-SCOPING-CHECKLIST.md && grep -qiE "DATABASE_NAME\|POSTGRES_DB\|two (physically )?separate" 18-SCOPING-CHECKLIST.md` | ✅ | ⬜ pending |
| 18-01-02 | 01 | 1 | TEN-04 | grep (inventory completeness) | per-path `grep -q $WORKFLOW 18-SCOPING-CHECKLIST.md` for W12/W_ORDER_FINALIZER/W51/W53/W_THE_USUAL/W_ADMIN_PROACTIVE/W14/W61/W_KIOSK_ORDER + `grep -qi "Sweep Decisions"` + ≥80 lines | ✅ | ⬜ pending |
| 18-02-01 | 02 | 1 | TEN-04 | json/jq/grep | 7 workflows `json.load`; `W_ORDER_FINALIZER` INSERT has `tenant_id` + `qty`/`unit_price_cents`; W51/W53/W_THE_USUAL/W_ADMIN_PROACTIVE/W14 order queries `grep -q tenant_id`; no `\|\| 'default'`/`DEFAULT_TENANT_ID` | ✅ after 18-03 | ⬜ pending |
| 18-02-02 | 02 | 1 | TEN-04 | json/jq/grep (tdd) | order+customer `schema.json` valid; `jq -e '.attributes.tenant_id'` both; customer `phone.unique != true`; both `lifecycles.ts` throw on blank tenant_id, no fallback | ✅ | ⬜ pending |
| 18-02-03 | 02 | 1 | TEN-04 | sql (ephemeral PG, apply twice) | `migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql`: `ADD COLUMN IF NOT EXISTS tenant_id`, backfill `…0001`, `SET NOT NULL`, `uq_customers_tenant_phone`; apply twice on ephemeral PG = no-op | ✅ | ⬜ pending |
| 18-03-01 | 03 | 1 | TEN-05 | sql (fixture) | `18-two-tenant-seed.sql`: tenant B `…00b2`, orders `aaaaaaaa…`/`bbbbbbbb…`, `ON CONFLICT`, `customer_userId` | ❌ W0 | ⬜ pending |
| 18-03-02 | 03 | 1 | TEN-05 | psql (ephemeral PG, DO-blocks) | `18-cross-tenant-isolation.sql`: ≥5 DO-blocks (both-direction read, A→B write, `not_null_violation`, `foreign_key_violation`), NO SAVEPOINT | ❌ W0 | ⬜ pending |
| 18-03-03 | 03 | 1 | TEN-05 | yaml / CI gate | `python3 yaml.safe_load(phase-18-assertions.yml)`; references seed + assertions + `postgres:15-alpine` + pinned checkout SHA; structural job present; full gate via `act` | ❌ W0 | ⬜ pending |

*Wave-0 SQL + CI gate files (18-03) are themselves the validation infrastructure; they are created in this phase (Plan 18-03, also Wave 1) and gate 18-01/18-02 structurally — exactly as Plan 17-03 did for Phase 17. 18-02's structural assertions only pass once 18-02 lands; that is the gate proving 18-02.*

---

## Wave 0 Requirements

- [ ] `db/ci-fixtures/18-two-tenant-seed.sql` — two-tenant + per-tenant order seed (Plan 18-03 Task 1)
- [ ] `db/ci-assertions/18-cross-tenant-isolation.sql` — both-direction read/write + non-defaultable-write + FK DO-block assertions (Plan 18-03 Task 2)
- [ ] `.github/workflows/phase-18-assertions.yml` — CI gate (isolation SQL job + structural workflow/schema job), wired to fail the build (Plan 18-03 Task 3)
- [ ] `.planning/phases/18-…/18-SCOPING-CHECKLIST.md` — the success-criterion-1 enumeration artifact (Plan 18-01)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 🔴 Apply `db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql` to prod Postgres (column add + backfill + NOT NULL + `(tenant_id,phone)` unique via `CREATE UNIQUE INDEX CONCURRENTLY` direct to `postgres:5432`, not pgbouncer:6432) | TEN-04 | Requires prod Postgres + the migrations-strapi PGDATABASE=strapi pass | Deferred to prod-connected session |
| 🔴 Rebuild the CMS so the new `order`/`customer` `tenant_id` attributes + lifecycles take effect | TEN-04 | Requires prod CMS build/restart | Deferred to prod-connected session |
| 🔴 Import the updated scoped workflows (W_ORDER_FINALIZER, W51, W53, W_THE_USUAL, W_ADMIN_PROACTIVE, W14, W4_CORE) on prod n8n | TEN-04 | Requires prod n8n API/SSH | Deferred to prod-connected session |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (every task carries one)
- [x] Wave 0 covers all MISSING references (18-two-tenant-seed.sql + 18-cross-tenant-isolation.sql + phase-18-assertions.yml, all in Plan 18-03; 18-SCOPING-CHECKLIST.md in Plan 18-01)
- [x] No watch-mode flags
- [x] Feedback latency < 90s (full suite); <5s per-task local; ~10s local ephemeral-PG SQL suite
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planned (3 plans, all Wave 1, disjoint file ownership — 18-01 owns the checklist artifact; 18-02 owns the workflows + Strapi schemas/lifecycles + migrations-strapi SQL; 18-03 owns the CI fixtures/assertions/yml; no file is touched by two plans)
