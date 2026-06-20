---
phase: 19-entitlement-audit-and-cache-invalidation-lifecycle-hook
verified: 2026-06-20T17:20:00Z
status: passed
score: 4/4 success criteria verified (both former blockers A+B independently confirmed resolved; prod migration apply + CMS rebuild + prod-Redis identity + live-actor capture deferred)
gaps: []
requirements_satisfied: [AUD-01, AUD-02]
deferred_to_vps:
  - "apply db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql to the LIVE strapi DB (VARCHAR->uuid + DROP NOT NULL + nullable FK NOT VALID->VALIDATE), via the migrations-strapi PGDATABASE=strapi pass direct to postgres:5432 (NOT pgbouncer:6432), using the LIVE tenant UUID discovered on prod (ADR 0001 — never hardcode …0001)"
  - "rebuild the CMS so the new tenant-entitlement/product-module lifecycles.ts + audit-hook.ts take effect (the lifecycle hooks only fire in a running CMS)"
  - "confirm the prod REDIS_URL/REDIS_HOST the hook's DEL targets is the SAME Redis the Phase-20 GRD-01 guard reads (else revocation won't invalidate the live cache)"
  - "🔴 manual-only: admin-panel entitlement edit -> assert the audit row's changed_by is the real admin email (strapi.requestContext AsyncLocalStorage actor path) — the node-test runs the pure helper with NO Strapi boot, so it can only exercise the explicit changed_by, not the live actor capture"
---

# Phase 19: Entitlement Audit + Cache-Invalidation Lifecycle Hook — Verification

**Goal:** A single Strapi lifecycle hook on the SaaS content types writes an `entitlement_audit_log` row on every entitlement change AND invalidates the Redis entitlement cache — fail-loud, with the cross-DB placement resolved — so audit coverage exists and a revoked/expired entitlement cannot survive in cache.
**Status:** passed — 4/4 ROADMAP success criteria met at the code/CI level; both former blockers (A: Node-22 pin; B: nullable tenant_id / product-module NULL) independently confirmed resolved; the full helper suite + SQL assertions + migration idempotency were independently reproduced on ephemeral PG + Redis (exit 0); prod apply + CMS rebuild + prod-Redis identity + live-actor capture deferred to a prod-connected session.

## Observable Truths

| # | Success Criterion | Status | Evidence |
|---|-------------------|--------|----------|
| 1 | `tenant-entitlement` + `product-module` `lifecycles.ts` write an `entitlement_audit_log` row on create/update/delete (who/what/when/old→new); a test asserts a row per op; Strapi-5 old-value captured in before-hooks via `event.state` | VERIFIED | Both `lifecycles.ts` export `before/afterCreate/Update/Delete`. `beforeUpdate`/`beforeDelete` stash `event.state.oldValue = await strapi.db.query(UID).findOne({where: event.params.where})` (the Strapi-5 quirk — `after*` carry no old value); `afterUpdate` derives the action via `deriveAction(oldValue, result)`; each `after*` calls `runAudit` → `writeAuditRow(strapi.db.connection, {tenant_id, module_key, action, changed_by, old_value, new_value})`. `changed_by` = `strapi.requestContext.get()?.state?.user?.email ?? 'system'` (who); `created_at` DB-defaults (when). **Independent run** of `bash scripts/test-phase19.sh`: `writeAuditRow` row-per-op test (#6) PASS (exactly one row added, created = old null/new set); SQL assertion 1 PASS ("a row per op with old→new captured, created new-only, deleted old-only"); assertion 3 PASS (action vocabulary created/config_changed/deleted present). |
| 2 | Cross-DB resolved + implemented: writer = raw Knex `strapi.db.connection('entitlement_audit_log')` (strapi DB; table is NOT a content type); ADR 0003 records it | VERIFIED | `audit-hook.ts:writeAuditRow` does `(knex)('entitlement_audit_log').insert({...})`; both `lifecycles.ts` inject `strapi.db.connection` (raw Knex) — lines `lifecycles.ts:60` (tenant-entitlement) + `:40` (product-module). `docs/adr/0003-entitlement-audit-placement.md` Decision 1 (Option A, with the A/B/C table): table stays in the strapi DB, raw-Knex writer because `entitlement_audit_log` is NOT a Strapi content type (no `schema.json`/UID → `strapi.db.query('api::…')` impossible), precedent `agent-chat.ts:107`/`control-plane.ts:76`. No cross-DB / second connection / table move. |
| 3 | The same hook issues Redis `DEL` of EXACTLY `ralphe:entitlement:{tenant_id}:{module_key}` on every entitlement change; a test proves key-present-before → gone-after; product-module is audit-only (no DEL / no SCAN) | VERIFIED | `audit-hook.ts:invalidateCache` builds `key = ` ``ralphe:entitlement:${tenant_id}:${module_key}`` and `await redis.del(key)` — a single exact-key DEL, no SCAN/KEYS. `tenant-entitlement/lifecycles.ts:79` calls `invalidateCache(getRedis(), tenant_id, module_key)` (USE_REDIS-guarded, static memoized `import Redis from 'ioredis'`). **Independent run:** node-test #5 (AUD-02) SET canonical key → `invalidateCache` → GET nil PASS — the round-trip used `ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp` (test #1 asserts the constructed key === this literal byte-for-byte). `product-module/lifecycles.ts` is audit-only: grep confirms NO `invalidateCache`, NO `.scan(`, NO `KEYS ` token (O-1, TTL-bounded; structural CI job "product-module is audit-only" PASS). |
| 4 | Fail-loud: `validateTenantId` THROWS before the write; post-commit insert + Redis DEL are log-error+counter (NOT silent swallow); tenant_id validated to canonical UUID | VERIFIED | `validateTenantId` (`z.string().guid()`) THROWS pre-insert on a non-null non-canonical value (returns null only for null/undefined global); `writeAuditRow` calls it FIRST so a bad row never reaches the DB. `tenant-entitlement/lifecycles.ts`: the post-commit `writeAuditRow` is `try/catch → auditFailureCount++ + strapi.log.error`; the DEL is `try/catch → auditFailureCount++ + strapi.log.warn` — NOT re-thrown (after-hooks fire post-commit; a throw can't roll back the grant), NO bare swallow. **Independent run:** node-test #4 (`validateTenantId('default')`/`''` throw, `null`→`null`) PASS; #8 (non-canonical tenant_id throws BEFORE insert, no row written) PASS; #9 (rejecting knex surfaces, no swallow) PASS; #10 (rejecting redis surfaces) PASS. SQL assertion 2 (non-UUID rejected by the uuid column type) PASS. Structural CI job "no continueOnFail / .catch(()=>{}) / SCAN / KEYS" PASS. |

**Score: 4/4 success criteria verified.**

## Former Blocker Resolution (critical)

### Blocker A — Node 22 pin: RESOLVED
`.github/workflows/phase-19-assertions.yml` parsed and step-ordered programmatically:
- `cache-invalidation-redis` (runs `node --test --experimental-strip-types`): `actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af # v4.1.0` (40-char SHA pin) with `node-version: '22'` at step idx 1, BEFORE the first node step (idx 4). BEFORE=True.
- `hook-structural` (runs `node --check`): same pinned `setup-node@…` `node-version: '22'` at step idx 1, BEFORE the node step (idx 8). BEFORE=True.
- `audit-row-sql` (SQL-only, no node step): correctly has no `setup-node` (none required).

`audit-hook.ts` is type-strippable: grep finds NO `enum` / `namespace` / parameter-properties; `node v22.22.2 --experimental-strip-types --check audit-hook.ts` is clean; the harness imported it via native type-stripping (10/10 tests ran, 0 skipped → the helper loaded).

### Blocker B — Nullable tenant_id, product-module = NULL: RESOLVED (mutually consistent)
The four artifacts are consistent around a nullable tenant_id, no all-zero sentinel:
- **Migration** (`2026-06-20_entitlement_audit_uuid.sql`): guarded `ALTER … TYPE uuid USING tenant_id::uuid` + `ALTER … DROP NOT NULL` + nullable FK `ADD … NOT VALID` → `VALIDATE CONSTRAINT` (both `pg_constraint`/`to_regclass`-guarded). **Independently applied twice** on ephemeral PG over the legacy `VARCHAR(255) NOT NULL` shape: APPLY #1 rc=0, APPLY #2 rc=0 (idempotent). Final shape `data_type=uuid, is_nullable=YES`, FK `fk_entitlement_audit_tenant` present. A `tenant_id=NULL` insert → `INSERT 0 1` (accepted); a bogus `99999999-…` non-null insert → FK violation ("not present in table tenants") rejected.
- **CI seed** (`19-entitlement-audit-seed.sql`): `tenant_id uuid` (nullable) + nullable FK to `tenants`; global rows carry NULL.
- **Writer** (`product-module/lifecycles.ts:36`): `const tenant_id = null` for global module rows (comment cites Blocker B; no all-zero sentinel).
- **Validation** (`audit-hook.ts:validateTenantId`): `if (tenant_id == null) return null` (skipped on null), throws on a bad non-null value.
- **Test** of the product-module NULL path against the nullable FK: node-test #7 PASS (global row writes `tenant_id IS NULL`, accepted; all-zero sentinel count === 0); SQL assertion 4 PASS (NULL accepted by the nullable FK + non-null bogus uuid still FK-rejected + no all-zero sentinel).
- **No all-zero sentinel:** the string `00000000-0000-0000-0000-000000000000` appears ONLY in the node-test as a NEGATIVE assertion (count must be 0); no production/migration/seed path writes it.

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `inventory-cms/.../tenant-entitlement/.../audit-hook.ts` | pure helper: deriveAction + validateTenantId(guid) + writeAuditRow(raw Knex) + invalidateCache(exact DEL) | VERIFIED | 125 lines, all 4 exports, zero `@strapi/strapi` import, type-strippable, `z.string().guid()`, exact-key DEL, no SCAN/KEYS |
| `inventory-cms/.../tenant-entitlement/.../lifecycles.ts` | audit + cache DEL; before* stash old; requestContext actor; fail-loud | VERIFIED | imports helper; before* stash `event.state.oldValue`; after* → runAudit; `strapi.db.connection` + memoized static ioredis; try/catch log-error/warn + counter |
| `inventory-cms/.../product-module/.../lifecycles.ts` | audit-only (O-1); key→module_key; tenant_id NULL | VERIFIED | imports shared helper; maps `result?.key`→module_key; `tenant_id = null`; NO invalidateCache/SCAN; fail-loud counter |
| `db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql` | VARCHAR→uuid + DROP NOT NULL + nullable FK, idempotent | VERIFIED | applies twice rc=0; final uuid/nullable; FK present; NULL accepted, bogus FK-rejected |
| `db/ci-fixtures/19-entitlement-audit-seed.sql` | uuid-NULL shape + tenants + tenant_entitlements; nullable FK | VERIFIED | `tenant_id uuid` nullable + FK; canonical tenant `…0001`; idempotent |
| `db/ci-assertions/19-entitlement-audit.sql` | 4 DO-blocks: row-per-op + non-UUID reject + action vocab + product-module NULL path | VERIFIED | all 4 PASS independently; no SAVEPOINT/ROLLBACK-TO in any block (nested BEGIN..EXCEPTION) |
| `inventory-cms/.../__tests__/audit-hook.test.mjs` | node --test: canonical-key contract + SET→invalidate→GET-nil + row-per-op + NULL path + fail-loud | VERIFIED | 10 tests, all PASS independently |
| `scripts/test-phase19.sh` | ephemeral PG (system postgres) + redis harness | VERIFIED | boots PG :55433 + redis :63799, runs node-test + SQL assertions, exit 0 |
| `.github/workflows/phase-19-assertions.yml` | PG + redis:7-alpine + structural; Node-22 pinned | VERIFIED | YAML valid; 3 jobs; pinned checkout + setup-node@SHA node 22 before every node step; redis:7-alpine service |
| `docs/adr/0003-entitlement-audit-placement.md` | strapi-DB placement + raw-Knex writer + cache-key contract + O-1/O-2/O-3 + Blocker-B correction | VERIFIED | Accepted; Decision 1 (Option A table + raw-Knex), Decision 2 (locked key), O-1/O-2/O-3, nullable-tenant correction |

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| AUD-01 | 19-01, 19-02 | `tenant-entitlement`/`product-module` `lifecycles.ts` write an `entitlement_audit_log` row on create/update/delete (who/what/when/old→new); the dead table gets real writers | SATISFIED | Truths 1+2; raw-Knex writer against the strapi-DB table; row-per-op proven (node #6, SQL #1/#3); product-module audit row (node #7, SQL #4) |
| AUD-02 | 19-02, 19-03 | The same hook invalidates the Redis entitlement cache on any change, so a revoked/expired entitlement cannot survive in cache | SATISFIED | Truth 3; exact-key DEL on the locked canonical key; SET→invalidate→GET-nil proven (node #5) on `ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp` |

No orphaned requirements: REQUIREMENTS.md maps Phase 19 to exactly AUD-01 + AUD-02, both claimed across the plans.

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | none | — | No TODO/FIXME/placeholder, no bare `.catch(()=>{})`, no `continueOnFail`, no SCAN/KEYS, no all-zero sentinel in any production/migration/seed path; the only `000…000` is a negative test assertion |

## Local Verification

**Independent `bash scripts/test-phase19.sh` (ephemeral PG 16 :55433 as system `postgres` user + redis-server :63799; docker DOWN):**

```
node --test:  # tests 10  # pass 10  # fail 0  # skipped 0
  ok 5 - invalidateCache: SET canonical key -> invalidateCache -> GET nil (AUD-02, no stale grant)
  ok 6 - writeAuditRow: writes one created row (old null, new set) (AUD-01)
  ok 7 - writeAuditRow: product-module global row writes tenant_id IS NULL (Blocker B)
  ok 8 - writeAuditRow: a non-canonical tenant_id throws BEFORE insert (fail-loud, no row)
SQL DO-block assertions (4/4 PASS):
  NOTICE: PASS: a row per op with old->new captured (created new-only, deleted old-only)
  NOTICE: PASS: non-UUID tenant_id rejected by the uuid column type
  NOTICE: PASS: action vocabulary (created/config_changed/deleted) present
  NOTICE: PASS: product-module row writes tenant_id IS NULL (accepted); non-null bogus uuid FK-rejected; no all-zero sentinel
PHASE 19 HELPER SUITE: PASS (node --test rc=0, assertions rc=0)
```

- **node-test: 10 pass / 0 fail / 0 skipped.**
- **SQL DO-block assertions: 4/4 PASS** (incl. product-module `tenant_id IS NULL` accepted + bogus non-null uuid FK-rejected).
- **Cache key used in the SET→invalidate→GET-nil round-trip:** `ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp` (asserted byte-for-byte equal to the canonical literal in test #1).

**Independent migration idempotency (ephemeral PG, legacy `VARCHAR(255) NOT NULL` start shape):** APPLY #1 rc=0, APPLY #2 rc=0 (idempotent no-op); final `tenant_id` = `uuid`/`is_nullable=YES`, FK `fk_entitlement_audit_tenant` present; `tenant_id=NULL` insert → `INSERT 0 1` (accepted); bogus non-null uuid → FK violation (rejected).

**Structural checks (re-run on the current tree): ALL-PASS** — canonical key in `audit-hook.ts`; both `lifecycles.ts` exist; no `@strapi/strapi` import; `z.string().guid()` present; no bare-swallow/SCAN/KEYS; product-module audit-only (no `invalidateCache`). Blocker-A step ordering verified programmatically (setup-node@SHA node-22 before every node step in both node-running jobs).

**tsc baseline (`cd inventory-cms && npx tsc --noEmit`): UNCHANGED — 5 errors before == 5 after**, the documented pre-existing baseline (4× TS2345 product-module/tenant-entitlement ContentType + 1× TS2351 `auth-ratelimit.ts` ioredis dynamic-import). ZERO new errors from `audit-hook.ts` or either `lifecycles.ts` (none of the Phase-19 TS files appear in the error set). Phase-21 scope; not a Phase-19 regression.

## Deferred (🔴 VPS — NOT gaps)

These require a prod-connected/CMS-running session and are out of code/CI scope:
1. Apply `db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql` to the LIVE strapi DB (migrations-strapi PGDATABASE=strapi pass direct to `postgres:5432`, NOT pgbouncer:6432), using the LIVE tenant UUID discovered on prod (ADR 0001 — never hardcode `…0001`).
2. Rebuild the CMS so the new `tenant-entitlement`/`product-module` `lifecycles.ts` + `audit-hook.ts` take effect (the hooks only fire in a running CMS).
3. Confirm the prod `REDIS_URL`/`REDIS_HOST` the hook's `DEL` targets is the SAME Redis the Phase-20 GRD-01 guard reads (else revocation won't invalidate the live cache).
4. 🔴 manual-only: admin-panel entitlement edit → assert the audit row's `changed_by` is the real admin email (the `strapi.requestContext` AsyncLocalStorage actor path) — the node-test runs the pure helper with NO Strapi boot, so it can only exercise the explicit `changed_by`, not the live actor capture.

## Verdict

`passed` — AUD-01 and AUD-02 satisfied at the code/CI level with no gaps. A single pair of Strapi-5 lifecycle adapters over one pure `audit-hook.ts` helper write an `entitlement_audit_log` row (who/what/when/old→new, old captured in before-hooks via `event.state`) via the raw-Knex `strapi.db.connection` writer against the strapi-DB table (cross-DB resolved + recorded in ADR 0003), and `tenant-entitlement` additionally issues an exact-key Redis `DEL` of the locked `ralphe:entitlement:{tenant_id}:{module_key}` canonical key (product-module is audit-only per O-1, no DEL/SCAN), fail-loud (validate-throw-pre-write; post-commit insert + DEL → log-error/warn + counter, no bare swallow). Both former blockers are independently confirmed resolved: **A** — the CI gate pins `actions/setup-node@<SHA>` `node-version: '22'` before every node step in both node-running jobs and the helper is type-strippable; **B** — the migration / seed / writer / validation are mutually consistent around `tenant_id uuid NULL` + nullable FK with product-module rows carrying NULL and no all-zero sentinel. Independently reproduced here: 10/10 node-tests pass, 4/4 SQL DO-block assertions pass, the SET→invalidate→GET-nil proof used `ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp`, the migration applies twice cleanly, and tsc is unchanged at the 5-error baseline. The four VPS items (live strapi-DB apply, CMS rebuild, prod-Redis identity, live-actor capture) are deferred to a prod-connected session.

---

_Verified: 2026-06-20T17:20:00Z_
_Verifier: Claude (gsd-verifier)_
