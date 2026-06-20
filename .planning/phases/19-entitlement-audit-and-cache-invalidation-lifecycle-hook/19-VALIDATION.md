---
phase: 19
slug: entitlement-audit-and-cache-invalidation-lifecycle-hook
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-20
---

# Phase 19 — Validation Strategy

> Per-phase validation contract. Detailed checks derive from `19-RESEARCH.md` → `## 7. Validation Architecture`. The planner fills the Per-Task map below. The keystone of this phase is a **pure helper** (`audit-hook.ts`) with **zero `@strapi/strapi` imports**, so it is testable in plain Node against an ephemeral Postgres + ephemeral Redis — **without booting Strapi** (whose TS compile is already red on a pre-existing baseline).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `node --test` (Node 22.22.2, TAP) driving the pure `audit-hook.ts` against an ephemeral Postgres (`entitlement_audit_log` write assertion) + ephemeral Redis (SET→invalidate→GET-nil round-trip); `psql` DO-block assertions against ephemeral Postgres via `.github/workflows/phase-19-assertions.yml`; `jq`/`grep` structural assertions on the lifecycle/hook TS + the cache key; scoped `tsc --noEmit` error-count-vs-baseline gate (NO new CMS TS errors) |
| **Config file** | `.github/workflows/phase-19-assertions.yml` (new, Wave 0 — mirrors `phase-18-assertions.yml` + adds a `redis:7-alpine` service) |
| **Quick run command (structural, <5s)** | `grep -q "ralphe:entitlement:" inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/audit-hook.ts && test -f inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/lifecycles.ts && test -f inventory-cms/src/api/product-module/content-types/product-module/lifecycles.ts` |
| **Helper test (local, ~10s)** | `bash scripts/test-phase19.sh` (boots ephemeral PG via the system `postgres` user + ephemeral `redis-server` on a high port, then runs `node --test inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/__tests__/audit-hook.test.mjs`) |
| **Full suite command** | `act pull_request -W .github/workflows/phase-19-assertions.yml` (or push to PR) |
| **TS-baseline gate** | `cd inventory-cms && npx tsc --noEmit` — error count MUST be `<=` the pre-existing baseline (the `product-module`/`tenant-entitlement` ContentType TS2345 + `ioredis` TS2351 errors are a KNOWN baseline slated for Phase 21; Phase 19 must not REGRESS, need not FIX) |
| **Estimated runtime** | ~100s (CI: PG + Redis service start + DDL + seed + node-test + DO-block SQL + structural jq); <5s per-task local jq/grep; ~10s local `scripts/test-phase19.sh` |

### Local ephemeral services (NO docker — both verified on this host 2026-06-20)

Docker daemon is **DOWN** on this host and `initdb` refuses to run as `root`. Run the helper test, the
SQL fixtures/assertions, and the migration idempotency check via the system `postgres` user +
`/usr/lib/postgresql/16/bin`, and a local `redis-server` on a high port (both proven 2026-06-20):

**Ephemeral Postgres (docker DOWN; root cannot `initdb`)** — identical mechanism to Phase 18:

```bash
TMPPG=$(mktemp -d); chown postgres:postgres "$TMPPG"
su postgres -c "/usr/lib/postgresql/16/bin/initdb -D $TMPPG/data -A trust -U postgres"
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D $TMPPG/data -o '-p 55433 -k $TMPPG' -l $TMPPG/log start"
# Apply the entitlement_audit_log DDL (already-uuid shape) + the tenant_entitlements seed:
#   -f db/ci-fixtures/19-entitlement-audit-seed.sql
# Drive the pure helper (writeAuditRow) against it, then:
#   -f db/ci-assertions/19-entitlement-audit.sql
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D $TMPPG/data stop"; rm -rf "$TMPPG"
```

**Ephemeral Redis (binary present at `/usr/bin/redis-server` + `/usr/bin/redis-cli`; not running by
default)** — SET→DEL→GET-nil round-trip on the **exact canonical key** was proven locally 2026-06-20:

```bash
redis-server --port 7390 --daemonize yes --save "" --appendonly no --dir /tmp
redis-cli -p 7390 set "ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp" 1
redis-cli -p 7390 get "ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp"  # -> "1"
# run invalidateCache(redis, tenant_id, module_key) from audit-hook.ts here
redis-cli -p 7390 get "ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp"  # -> (nil) ✅ PROVEN
redis-cli -p 7390 shutdown nosave
```

`scripts/test-phase19.sh` (Plan 19-03) orchestrates both: it boots PG + redis, runs the `node --test`
helper test, and tears them down — so the whole helper suite is locally runnable with docker DOWN.

Local runner is PG **16.13** + Redis from `/usr/bin`; CI services are PG **15-alpine** + **redis:7-alpine**
(prod parity: Postgres 15, Redis 7). `not_null_violation` / nested `BEGIN..EXCEPTION` semantics and the
`DEL`/`GET` round-trip are identical across the local/CI versions. **No pgBouncer** in CI or local — the
`ALTER … TYPE uuid` + FK migration runs against plain Postgres directly; the `… NOT VALID` / `VALIDATE
CONSTRAINT` two-step is the live-safe form for the 🔴 VPS apply.

---

## Sampling Rate

- **After every task commit:** for the helper/lifecycle TS, the structural `grep` for the canonical
  `ralphe:entitlement:` key + lifecycle-file presence + `node --check`/`node --test` on the helper; for
  the migration/SQL changes, the local ephemeral-PG apply; `npx tsc --noEmit` error-count MUST NOT exceed
  the baseline.
- **After every plan wave:** full suite (`phase-19-assertions.yml`: PG job + Redis job + structural job).
- **Before `/gsd:verify-work`:** full suite green AND ADR `docs/adr/0003-entitlement-audit-placement.md`
  recorded (cross-DB decision + cache-key contract + the TTL-bounded product-module gap).
- **Max feedback latency:** ~100s (full CI suite); <5s per-task local jq/grep; ~10s local
  `scripts/test-phase19.sh`.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 19-01-01 | 01 | 1 | AUD-01 | grep (ADR decision) | `grep -qi "raw Knex\|strapi.db.connection" docs/adr/0003-entitlement-audit-placement.md && grep -q "ralphe:entitlement:" docs/adr/0003-entitlement-audit-placement.md` | ✅ | ⬜ pending |
| 19-01-02 | 01 | 1 | AUD-01 | sql (ephemeral PG, apply twice) | `2026-06-20_entitlement_audit_uuid.sql`: guarded `ALTER … TYPE uuid USING tenant_id::uuid`, nullable FK `NOT VALID`→`VALIDATE`, `IF`-guarded; applies twice on ephemeral PG = no-op | ✅ | ⬜ pending |
| 19-02-01 | 02 | 2 | AUD-01 | node --test (pure helper) | `deriveAction`/`validateTenantId` unit cases pass; `validateTenantId('default')` throws; `node --test … audit-hook.test.mjs` green | ✅ after 19-03 W0 | ⬜ pending |
| 19-02-02 | 02 | 2 | AUD-01 | node/grep (lifecycles wired) | both `lifecycles.ts` exist + import the helper; `beforeUpdate`/`beforeDelete` stash `event.state.oldValue`; `after*` call the helper; product-module maps `key`→`module_key`; `node --check` | ✅ after 19-03 W0 | ⬜ pending |
| 19-02-03 | 02 | 2 | AUD-01 | grep + tsc-baseline (fail-loud) | helper: validate-then-THROW before insert; post-commit insert is `strapi.log.error`+counter (NOT throw); NO bare `continueOnFail`/`.catch(()=>{})`; `tsc --noEmit` ≤ baseline | ✅ after 19-03 W0 | ⬜ pending |
| 19-03-01 | 03 | 1 | AUD-02 | sql (fixture) | `19-entitlement-audit-seed.sql`: `entitlement_audit_log` DDL (already-uuid) + `tenant_entitlements` seed under canonical UUID; idempotent | ❌ W0 | ⬜ pending |
| 19-03-02 | 03 | 1 | AUD-01 | psql (ephemeral PG, DO-blocks) | `19-entitlement-audit.sql`: a row written per op (created/config_changed/deleted); invalid-uuid negative via nested `BEGIN..EXCEPTION`, NO SAVEPOINT in a DO block | ❌ W0 | ⬜ pending |
| 19-03-03 | 03 | 1 | AUD-02 | node --test (redis round-trip) | `audit-hook.test.mjs`: SET canonical key → `invalidateCache()` → `GET` nil; + the audit-row write; via `scripts/test-phase19.sh` (ephemeral PG + redis) | ❌ W0 | ⬜ pending |
| 19-03-04 | 03 | 1 | AUD-02 | yaml / CI gate | `python3 yaml.safe_load(phase-19-assertions.yml)`; `postgres:15-alpine` + `redis:7-alpine` services + pinned checkout SHA; references seed + assertions; structural job greps `ralphe:entitlement:` | ❌ W0 | ⬜ pending |

*Wave-0 SQL + CI gate + node-test + harness files (19-03) are themselves the validation infrastructure;
they are created in Plan 19-03 (Wave 1) and gate 19-02 (Wave 2) — exactly as Plan 18-03 did for Phase 18.
19-02's helper/lifecycle assertions only pass once 19-02 lands; that is the gate proving 19-02. 19-01
(ADR + migration) and 19-03 (validation infra) are independent (Wave 1, parallel); 19-02 (the hook) is
Wave 2 because its node-test consumes the 19-03 harness + fixtures and its helper extends the seam 19-03
tests.*

---

## Wave 0 Requirements

- [ ] `db/ci-fixtures/19-entitlement-audit-seed.sql` — `entitlement_audit_log` DDL (already-uuid shape) + `tenant_entitlements` seed under the canonical UUID (Plan 19-03 Task 1)
- [ ] `db/ci-assertions/19-entitlement-audit.sql` — DO-block: a row exists per op + invalid-uuid negative via nested `BEGIN..EXCEPTION` (NO SAVEPOINT) (Plan 19-03 Task 2)
- [ ] `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/__tests__/audit-hook.test.mjs` — `node --test` driving the pure helper (write + invalidate) against ephemeral PG + redis (Plan 19-03 Task 3)
- [ ] `scripts/test-phase19.sh` — local harness booting ephemeral PG (system `postgres` user) + ephemeral `redis-server` then running the node-test (Plan 19-03 Task 3)
- [ ] `.github/workflows/phase-19-assertions.yml` — CI gate (PG isolation/audit SQL job + Redis invalidation job + structural hook/key job), wired to fail the build (Plan 19-03 Task 4)
- [ ] `docs/adr/0003-entitlement-audit-placement.md` — cross-DB placement + raw-Knex-writer + cache-key contract decision (Plan 19-01)

*(No framework install — `node --test`, `psql`, `redis-cli`, `jq` all present on the host.)*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 🔴 Apply `db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql` to the prod **strapi** DB (`ALTER … TYPE uuid` + nullable FK `NOT VALID`→`VALIDATE`) using the LIVE tenant UUID discovered on prod (ADR 0001 — never hardcode `…0001`) | AUD-01 | Requires prod Postgres + the migrations-strapi PGDATABASE=strapi pass + live-UUID discovery | Deferred to prod-connected session |
| 🔴 Rebuild the CMS so the new `tenant-entitlement`/`product-module` `lifecycles.ts` + `audit-hook.ts` take effect | AUD-01, AUD-02 | Requires prod CMS build/restart | Deferred to prod-connected session |
| 🔴 Confirm the prod `REDIS_URL`/`REDIS_HOST` the hook's `DEL` targets is the SAME Redis the Phase-20 guard reads (else revocation won't invalidate the live cache) | AUD-02 | Requires prod Redis + Phase-20 guard wiring | Deferred to prod-connected session |
| 🔴 `changed_by` real-actor path: edit an entitlement in the admin panel as a logged-in admin, then confirm the new `entitlement_audit_log` row's `changed_by` is the **real admin email** (via `strapi.requestContext.get()?.state?.user?.email`), not `'system'` | AUD-01 | The node-test runs the pure helper with NO Strapi boot, so it cannot exercise the AsyncLocalStorage `strapi.requestContext` actor path — only a booted CMS with a real authenticated request populates `ctx.state.user`. The harness passes `changed_by` explicitly; the live actor capture is Strapi-runtime-only. | Deferred to a CMS-running session: log in to the admin panel, toggle an entitlement's `enabled`, then `SELECT changed_by FROM entitlement_audit_log ORDER BY created_at DESC LIMIT 1;` and confirm it equals the admin's email (seed/migration writes correctly fall back to `'system'`). |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (every task carries one)
- [x] Wave 0 covers all MISSING references (the seed + assertions + node-test + harness + phase-19-assertions.yml, all in Plan 19-03; the ADR + uuid migration in Plan 19-01)
- [x] No watch-mode flags
- [x] Feedback latency < 100s (full suite); <5s per-task local jq/grep; ~10s local `scripts/test-phase19.sh`
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planned (3 plans — disjoint file ownership. 19-01 owns the ADR + the uuid migration (Wave 1); 19-03 owns the CI fixtures/assertions/yml + node-test + harness (Wave 1, the validation infra); 19-02 owns the two `lifecycles.ts` + the pure `audit-hook.ts` (Wave 2, consumes the 19-03 harness). No file is touched by two plans.)
