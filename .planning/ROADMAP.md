# Roadmap: RESTO BOT — SaaS Multi-Tenant Hardening

> v1.0 (Platform Hardening & Reliability, Phases 1–14) is **shipped and archived** to
> `.planning/milestones/v1.0-ROADMAP.md`. This file is scoped to the current milestone, **v2.0**.
> Phase numbering continues from v1.0 (next integer is 15).

## 🚧 v2.0 SaaS Multi-Tenant Hardening (In Progress)

**Milestone Goal:** Turn the shipped-but-scaffolding-only SaaS multi-tenant layer into a genuinely
production-safe one, so a *second* restaurant/tenant can be onboarded without cross-tenant data
leakage or entitlement bypass.

## Overview

The platform already carries a full relational tenant model and the inbound adapters already parse the
channel-native tenant signal — but the two are wired wrong: a **UUID data plane** (`orders.tenant_id`)
and a **VARCHAR entitlement plane** keyed on the literal `'default'` never reconcile, Meta channels
fall through to an unset `DEFAULT_TENANT_ID`, the admin UI fails *open* while the guard fails *closed*,
the SaaS DB constraints and `entitlement_audit_log` writers don't exist on the live system, and the
guard adds two uncached Strapi round-trips per inbound message. This is **hardening existing
scaffolding, not greenfield** — no new libraries (`ioredis`/`pg`/`zod` + Strapi-5-native
middleware/policies already present), no major version upgrades, no Postgres RLS (pgBouncer
transaction-pooling conflict), no schema-per-tenant.

The work follows a **strict dependency chain (keystone first)**. Phase 15 establishes the single
canonical tenant key before any code touches the two planes. Phase 16 makes the SaaS migration
live-safe and adds the `channel_identities` routing table the resolver will need. Phase 17 fixes
inbound tenant derivation to fail closed on unknown identities. Phase 18 scopes every order/customer
read and write by tenant and proves isolation in CI. Phase 19 lands the single lifecycle hook that
both audits entitlement changes and invalidates cache — which **must** exist before Phase 20 turns on
Redis caching in the guard (a cache without its invalidation hook is a security regression). Phase 20
also provisions `STRAPI_API_TOKEN_INTERNAL` so the fail-closed guard can't become a total outage.
Phase 21 tightens the UI to fail-closed parity and clears the type/lint debt **last**, once the
backend returns correct entitlements.

**Deploy posture (same as v1.0):** every requirement is implemented and **CI-verified locally**.
Steps that need the production VPS (applying a migration to live Postgres, provisioning a secret
value, importing a workflow) are designed here but their *execution* is 🔴 **deferred** to a
prod-connected session. Success criteria below are locally/CI-verifiable; the 🔴 VPS apply/import
step is called out as a deferred sub-step where it exists.

## Phases

**Phase Numbering:**
- Integer phases (15, 16, …): Planned milestone work
- Decimal phases (16.1, …): Urgent insertions (marked with INSERTED)

- [x] **Phase 15: Tenant Identity Model (Canonical Key)** - Establish the UUID `tenants.tenant_id` as the single system of record and reconcile the VARCHAR entitlement plane to it [TEN-01] — COMPLETE (2026-06-20, code/CI; live VPS backfill deferred)
- [x] **Phase 16: Live-Safe SaaS Migration + Channel Routing Table** - Make the SaaS constraints migration safe to apply on a live table (dup-probe + `CREATE INDEX CONCURRENTLY`), add the `channel_identities` routing table, and wire both into `db-migrate` [TEN-02, DB-01] — COMPLETE (2026-06-20, code/CI; live VPS apply deferred)
- [x] **Phase 17: Inbound Tenant Derivation (Fail-Closed)** - Resolve tenant from `channel_identities` in `B0 - Apply Auth Context`; an unknown channel identity fails closed instead of defaulting to `'default'` [TEN-03] — COMPLETE (2026-06-20, code/CI; prod workflow import deferred)
- [x] **Phase 18: Per-Tenant Data-Plane Scoping + Isolation CI** - Scope every order/customer read and write by a non-defaultable `tenant_id`, and prove cross-tenant isolation with an automated CI test [TEN-04, TEN-05] — CODE COMPLETE (2026-06-20, 3/3 plans; awaiting verifier; live strapi-DB apply + CMS rebuild + prod n8n import deferred)
- [ ] **Phase 19: Entitlement Audit + Cache-Invalidation Lifecycle Hook** - Add the single Strapi `lifecycles.ts` that writes `entitlement_audit_log` rows AND invalidates the Redis entitlement cache on every change [AUD-01, AUD-02]
- [ ] **Phase 20: Redis-Cached Fail-Closed Guard + Internal Token Provisioning** - Cache guard lookups in Redis (still fail-closed on error) and make `STRAPI_API_TOKEN_INTERNAL` a first-class, preflight-checked secret so a missing secret can't become a total inbound lockout [GRD-01, ENT-03]
- [ ] **Phase 21: UI Fail-Closed Parity + Module-Key Alignment + Type Cleanup** - Default `useEntitlements.hasModule` to false on loading/error, align `App.tsx` nav keys to the seeder, and replace the `any` debt with typed entitlement DTOs so Frontend Lint goes green [ENT-01, ENT-02, TYP-01]

## Phase Details

### Phase 15: Tenant Identity Model (Canonical Key)
**Goal**: A single canonical tenant key — the UUID `tenants.tenant_id` — is the documented system of record, and the VARCHAR entitlement plane is reconciled to it so no runtime path silently substitutes the literal `'default'`
**Depends on**: Nothing (first phase — the keystone)
**Requirements**: TEN-01
**Success Criteria** (what must be TRUE):
  1. A decision record names `tenants.tenant_id` (UUID) as canonical and documents the 1:1 mapping (or backfill) from the entitlement plane's VARCHAR `tenant_id` to that UUID; the `entitlement_audit_log.tenant_id` type decision (keep `VARCHAR(255)` vs migrate to `uuid` mirroring `admin_audit_log`) is recorded with rationale
  2. A `tenants`/`restaurants` row exists for the real first restaurant, and `tenant_entitlements` rows that were seeded against `'default'` are backfilled to that canonical UUID (seed/backfill SQL runs green against an ephemeral CI Postgres)
  3. A repo-wide grep shows every `|| 'default'` / `DEFAULT_TENANT_ID` fallback on a tenant-key path is inventoried and annotated (justified, or marked for removal in a later phase) — no silent substitution remains undocumented
  4. `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` seeds entitlements against the canonical UUID, not the literal `'default'`, verified by a unit/seed assertion
  - 🔴 VPS: backfilling/aligning the live `tenant_entitlements` rows on production Postgres is deferred to a prod-connected session.
**Plans**: 3 plans (all Wave 1, parallel — disjoint file ownership)

Plans:
- [x] 15-01-PLAN.md — Canonical-key ADR (`docs/adr/0001`): names `tenants.tenant_id` (UUID) canonical, records 1:1 entitlement mapping + the keep-`VARCHAR(255)`/migrate-in-P19 audit-log decision, confirms schema.json, surfaces the 🔴 VPS runtime-UUID-discovery caveat
- [x] 15-02-PLAN.md — Idempotent entitlement-plane backfill + CI assertion harness (`db/ci-fixtures/`, `db/ci-assertions/`, `phase-15-assertions.yml`): seeds an ephemeral Postgres `'default'` row, runs the backfill, asserts zero `'default'` rows remain (NOT a `db/migrations/` file — strapi-DB target)
- [x] 15-03-PLAN.md — Seeder fix to canonical UUID + node seed-assertion + annotated 5-occurrence `|| 'default'` fallback inventory (`docs/adr/0002`), each site tagged with its owning phase (15/17/17/17/21)

### Phase 16: Live-Safe SaaS Migration + Channel Routing Table
**Goal**: The SaaS constraints/indexes/audit-log migration is safe to apply on a live, possibly-duplicated table, the new `channel_identities` routing table exists (seeded for the current single tenant), and both are wired into the existing `db-migrate` mechanism
**Depends on**: Phase 15
**Requirements**: TEN-02, DB-01
**Success Criteria** (what must be TRUE):
  1. The SaaS migration runs a read-only duplicate probe before adding `uq_tenant_module`, dedupes (keep latest `activated_at`), and creates the unique constraint via `CREATE UNIQUE INDEX CONCURRENTLY` then attaches it (`USING INDEX`) — taking no `ACCESS EXCLUSIVE` lock and **not failing on pre-existing duplicate rows** (same pattern for `uq_product_module_key`)
  2. The migration sets a `lock_timeout`/`statement_timeout` and is idempotent (re-running is a no-op); a CI run that seeds duplicate entitlement rows proves the migration succeeds rather than erroring
  3. A new `channel_identities(channel, identity, tenant_id, restaurant_id, is_active)` migration exists in the n8n DB with `(channel, identity)` as PK and FKs to `tenants`/`restaurants`, seeded with CI sentinels (real WhatsApp `phone_number_id`, IG/Messenger page ids, kiosk device id discovered at 🔴 VPS apply)
  4. Both migrations are registered with the existing `db-migrate` service (strapi migration via a new `db/migrations-strapi/` PGDATABASE=strapi pass; CONCURRENTLY direct to `postgres:5432`) and tracked in `schema_migrations`; a two-DB CI check asserts the `channel_identities` table, `uq_tenant_module`, the four entitlement indexes, `uq_product_module_key`, and `entitlement_audit_log` all exist after apply
  - 🔴 VPS: executing both migrations against production Postgres (and seeding real channel ids) is deferred to a prod-connected session.
**Plans**: 3 plans (Wave 1: 16-01, 16-02 parallel — disjoint files; Wave 2: 16-03 wires both)

Plans:
- [x] 16-01-PLAN.md [DB-01] — Live-safe rewrite of the SaaS migration: read-only dup-probe → dedupe (keep latest `activated_at`) → `CREATE UNIQUE INDEX CONCURRENTLY` + `ALTER TABLE ... USING INDEX` for `uq_tenant_module` AND `uq_product_module_key` → `lock_timeout`/`statement_timeout` → fully idempotent. Relocated to `db/migrations-strapi/` (strapi DB target); old `db/migrations/2026-04-06_*` deleted. Includes Wave 0 fixture (`16-duplicate-entitlements-fixture.sql`) + schema-check assertion.
- [x] 16-02-PLAN.md [TEN-02] — `channel_identities` migration in the n8n DB: PK `(channel, identity)`, FKs to `tenants`/`restaurants`, `is_active boolean DEFAULT true`, seeded with 4 CI sentinels under canonical CI UUID; idempotent. 🔴 VPS seed discovers real values from `platform_settings`. Includes Wave 0 channel-identities assertion.
- [x] 16-03-PLAN.md [DB-01, TEN-02] — Wire both into `db-migrate`: new `db/migrations-strapi/` PGDATABASE=strapi pass direct to `postgres:5432` (CONCURRENTLY-safe) + separate strapi-DB `schema_migrations`; two-DB `phase-16-assertions.yml` (strapi + n8n) proving dup-survival, idempotent re-run, all unique constraints/indexes, and channel_identities existence.

### Phase 17: Inbound Tenant Derivation (Fail-Closed)
**Goal**: Inbound adapters resolve a real `(tenant_id, restaurant_id)` from `channel_identities` using the already-parsed channel-native id, and an unknown identity fails closed (parked/rejected with a log event) instead of defaulting to `'default'`
**Depends on**: Phase 16
**Requirements**: TEN-03
**Success Criteria** (what must be TRUE):
  1. `B0 - Apply Auth Context` in `W1_IN_WA.json`, `W2_IN_IG.json`, and `W3_IN_MSG.json` adds a resolution rung that looks up the parsed `phone_number_id`/`recipient_id` in `channel_identities` *before* any default, and seals the resolved real tenant downstream via the existing `tenant_context_seal`
  2. A message arriving on a **mapped** identity is stamped with that identity's real `tenant_id` (not the env `DEFAULT_TENANT_ID`), verified by a workflow-level test/fixture
  3. A message arriving on an **unmapped/unknown** identity is failed closed — parked or rejected with a `UNKNOWN_CHANNEL_IDENTITY`/`TENANT_UNRESOLVED` `security_events` row — and is **never** silently routed to tenant `'default'`
  4. Any legacy single-tenant fallback is gated behind one explicit, documented flag (e.g. `SINGLE_TENANT_MODE`); no bare `|| 'default'` remains on the resolution path
  - 🔴 VPS: importing/activating the updated inbound workflows on the production n8n is deferred to a prod-connected session.
**Plans**: 3 plans (all Wave 1, parallel — disjoint file ownership: 17-01 owns W1/W2/W3; 17-02 owns W0_MODULE_GUARD + W_DRIVER_ONBOARDING + ADR 0002; 17-03 owns the CI gate files)

Plans:
- [x] 17-01-PLAN.md [TEN-03] — `channel_identities` resolver rung in W1/W2/W3: insert `B0 - Resolve Channel Identity (DB)` (postgres typeVersion 2, credential `postgres-main`, exact SQL) + `B0 - Map Channel Identity Result` shim between `B0 - Resolve Client (DB)` and `B0 - Apply Auth Context`; rewrite `B0 - Apply Auth Context` to consume `ci_tenant_id`/`ci_restaurant_id`, fail closed with `denyReason='UNKNOWN_CHANNEL_IDENTITY'`, remove env/hardcoded fallbacks, and fix the duplicate `const metaSigValid` bug in W2/W3
- [x] 17-02-PLAN.md [TEN-03] — Remove the remaining fail-open fallbacks outside the adapters: `W0_MODULE_GUARD.json` (`|| DEFAULT_TENANT_ID || 'default'` → fail-closed `allowed:false`) + `W_DRIVER_ONBOARDING.json` (UUID/env fallback → no-fallback NOT NULL); strip `__inventory_15` markers; update `docs/adr/0002` occurrences #2/#3/#4 → `REMOVED (Phase 17)`
- [x] 17-03-PLAN.md [TEN-03] — CI gate: `db/ci-assertions/17-tenant-resolution.sql` (known WA/IG identity resolves to right tenant; unknown returns 0 rows) + `.github/workflows/phase-17-assertions.yml` (ephemeral-PG SQL job + structural jq/grep job: resolver present in W1/W2/W3, no `'default'`/`DEFAULT_TENANT_ID` on tenant path, `UNKNOWN_CHANNEL_IDENTITY` present, no `INVENTORY-17` markers, W2/W3 single-`const metaSigValid`)

### Phase 18: Per-Tenant Data-Plane Scoping + Isolation CI
**Goal**: Every order and customer read and write is scoped by a non-defaultable `tenant_id`, and an automated CI test proves a request resolved to tenant A cannot read or write tenant B's data
**Depends on**: Phase 17
**Requirements**: TEN-04, TEN-05
**Success Criteria** (what must be TRUE):
  1. A checklist artifact enumerates every order/customer read AND write path (the ~11 workflows incl. `W4_CORE`/`W4.1_ROUTER`/`W_KIOSK_ORDER`/`W_ORDER_FINALIZER` plus `order/lifecycles.ts` and Strapi controllers); each is annotated scoped/unscoped before any change
  2. `tenant_id` is **non-defaultable on the write path** — NOT NULL with no `|| 'default'` fallback — so an omitted tenant errors loudly rather than inheriting a default; existing scoped reads (e.g. `W12_ADMIN_ORDERS`) are confirmed and every previously-unscoped path now carries `WHERE tenant_id = $ctx`
  3. An automated CI test seeds two tenants and asserts that a request resolved to tenant A cannot read or write tenant B's orders/customers (separation proven in both directions)
  4. The CI isolation test is wired into the pipeline and fails the build if a cross-tenant read or write succeeds
  - 🔴 VPS: applying any new `tenant_id` column/backfill migration to production Postgres, and importing the updated workflows, is deferred to a prod-connected session.
**Plans**: 3 plans (all Wave 1, parallel — disjoint file ownership: 18-01 owns the checklist artifact; 18-02 owns the scoped workflows + Strapi schemas/lifecycles + migrations-strapi SQL; 18-03 owns the CI fixtures/assertions/yml)

Plans (3/3 executed — code/CI complete, awaiting verifier):
- [x] 18-01-PLAN.md [TEN-04] — Order/customer read+write inventory checklist (`18-SCOPING-CHECKLIST.md`): every order/customer path annotated scoped/unscoped before any change; resolved O-1 (Strapi `order`/`customer` are PARALLEL tables in the separate strapi DB — confirmed: Strapi `DATABASE_NAME=strapi` vs n8n `POSTGRES_DB=n8n`; kiosk writes via `strapi.post('/api/orders')`), which gates the 18-02 Strapi migration; records the O-2 scheduled-sweep decisions + the carts transitive-scoping decision
- [x] 18-02-PLAN.md [TEN-04] — Applied scoping + non-defaultable writes: fixed `W_ORDER_FINALIZER`'s tenant_id-omitting + column-drifted INSERT, added `WHERE tenant_id` to W51/W53/W_THE_USUAL/W_ADMIN_PROACTIVE/W14 (+ W4_CORE defense-in-depth), added required `tenant_id`/`restaurant_id` to the Strapi order/customer content types + fail-loud `beforeCreate` injection + relaxed `phone` to `(tenant_id,phone)` unique, and the `db/migrations-strapi/` column-add/backfill/NOT NULL migration (idempotent, proven apply-twice on ephemeral PG; 🔴 VPS apply deferred)
- [x] 18-03-PLAN.md [TEN-05] — Cross-tenant isolation CI: `db/ci-fixtures/18-two-tenant-seed.sql`, `db/ci-assertions/18-cross-tenant-isolation.sql` (both-direction read + write isolation + non-defaultable-write via nested `BEGIN..EXCEPTION` + FK, NO SAVEPOINT), `.github/workflows/phase-18-assertions.yml` (ephemeral-PG SQL job + structural jq/grep job, mirroring `phase-17-assertions.yml`), wired so a cross-tenant read/write success FAILS the build (5/5 assertions PASS twice on ephemeral PG + negative control fires non-zero)

### Phase 19: Entitlement Audit + Cache-Invalidation Lifecycle Hook
**Goal**: A single Strapi lifecycle hook on the SaaS content types writes an `entitlement_audit_log` row on every entitlement change AND invalidates the Redis entitlement cache — so audit coverage exists and a revoked/expired entitlement cannot survive in cache
**Depends on**: Phase 16 (audit table + constraints exist), Phase 15 (canonical key for validation)
**Requirements**: AUD-01, AUD-02
**Success Criteria** (what must be TRUE):
  1. `tenant-entitlement` (and, where applicable, `product-module`) gains a `lifecycles.ts` that on `afterCreate`/`afterUpdate`/`afterDelete` writes an `entitlement_audit_log` row capturing who/what/when/old→new; a test asserts a row is written on each operation
  2. The cross-DB write question is resolved and documented (move the table to the strapi DB, or give the writer an explicit n8n-DB connection) and the chosen path is implemented so the writer targets a table that actually exists
  3. The same hook issues an explicit Redis `DEL` of the entitlement cache key on every change, and a test proves a key present before an entitlement mutation is gone after it (no stale grant survives revocation)
  4. The audit write is **not** silent fire-and-forget — any write failure routes to a counter/alert (no bare `continueOnFail` swallowing), and `tenant_id` is validated to the canonical UUID before insert
**Plans**: 3 plans (2 waves — disjoint file ownership: 19-01 owns the ADR + uuid migration; 19-03 owns the CI fixtures/assertions/yml + node-test + harness (the validation infra); 19-02 owns the two `lifecycles.ts` + the pure `audit-hook.ts`. 19-01 + 19-03 are Wave 1 (parallel); 19-02 is Wave 2 — its node-test consumes the 19-03 harness and its helper is the seam 19-03 tests. No file is touched by two plans.)

Plans:
- [ ] 19-01-PLAN.md [AUD-01] — ADR `docs/adr/0003-entitlement-audit-placement.md` (cross-DB: table stays in the strapi DB, raw-Knex `strapi.db.connection` writer since it is NOT a content type; locks the `ralphe:entitlement:{tenant_id}:{module_key}` cache-key contract + records O-1/O-2/O-3) + idempotent live-safe `db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql` (`tenant_id` VARCHAR→uuid + nullable FK; 🔴 VPS apply deferred)
- [ ] 19-02-PLAN.md [AUD-01, AUD-02] — Pure `audit-hook.ts` helper (deriveAction + zod canonical-UUID validate + raw-Knex audit insert + exact-key Redis DEL) wired through `tenant-entitlement/lifecycles.ts` (audit + invalidate; old→new captured in before* hooks, actor via `requestContext`) and `product-module/lifecycles.ts` (audit-only — O-1, maps `key`→`module_key`); fail-loud (validate-throw-pre-write, log-error+count-post-commit, no bare swallow); no NEW CMS TS errors
- [ ] 19-03-PLAN.md [AUD-02] — Validation infra: `db/ci-fixtures/19-entitlement-audit-seed.sql` + `db/ci-assertions/19-entitlement-audit.sql` (row-per-op + invalid-uuid negative, nested `BEGIN..EXCEPTION`, no SAVEPOINT) + `__tests__/audit-hook.test.mjs` (`node --test`: SET→`invalidateCache`→GET-nil on the canonical key + the audit-row write) + `scripts/test-phase19.sh` (ephemeral PG + `redis-server`, docker DOWN) + `.github/workflows/phase-19-assertions.yml` (mirrors phase-18 + adds a `redis:7-alpine` service)

### Phase 20: Redis-Cached Fail-Closed Guard + Internal Token Provisioning
**Goal**: `W0_MODULE_GUARD` caches module/entitlement lookups in Redis so a cache hit skips both Strapi round-trips per inbound message (still fail-closed on error), and `STRAPI_API_TOKEN_INTERNAL` is a first-class, preflight-checked secret so a missing secret can no longer become a total inbound/operator lockout
**Depends on**: Phase 19 (invalidation hook must exist before caching is turned on), Phase 15 (canonical cache key)
**Requirements**: GRD-01, ENT-03
**Success Criteria** (what must be TRUE):
  1. `W0_MODULE_GUARD.json` is cache-aside keyed `ralphe:entitlement:<tenant_id>:<module_key>` (~5-min positive / shorter negative TTL); a cache **hit** skips both synchronous Strapi `fetch()` calls, verified by a guard test asserting zero Strapi round-trips on hit
  2. On Redis error the guard falls through to Strapi; on Strapi error it **denies** (fail-closed); transient guard errors are never cached; the cached raw row's expiry is re-evaluated on read; an `allkeys-lru` eviction (cache miss) produces a live query and never a spurious deny
  3. `STRAPI_API_TOKEN_INTERNAL` is declared in `docker-compose.hostinger.prod.yml`/`base`, `config/.env.example`, and the secrets inventory; a startup/preflight check fails fast with a clear message if it is unset (the fail-closed flip is not made before the secret exists)
  4. A `GUARD_ERROR_FAILCLOSED` condition (cannot-determine) is distinguishable from a legitimate `NO_ENTITLEMENT` denial in logs/alerting, so a missing/expired token is pageable rather than a silent total outage
  - 🔴 VPS: importing the updated `W0_MODULE_GUARD` and provisioning the real `STRAPI_API_TOKEN_INTERNAL` value on the VPS is deferred to a prod-connected session.
**Plans**: TBD

Plans:
- [ ] 20-01: Redis cache-aside in `W0_MODULE_GUARD` (keying, TTLs, fail-closed-on-error)
- [ ] 20-02: `STRAPI_API_TOKEN_INTERNAL` declared in compose/env/secrets-inventory + startup preflight
- [ ] 20-03: `GUARD_ERROR_FAILCLOSED` vs `NO_ENTITLEMENT` alert split

### Phase 21: UI Fail-Closed Parity + Module-Key Alignment + Type Cleanup
**Goal**: The admin UI fails closed in parity with the guard, every gated nav item maps to a real entitlement key, and the entitlement `any` debt is replaced with typed DTOs so the standing Frontend Lint CI failure goes green — done last, after the backend returns correct entitlements
**Depends on**: Phase 20 (backend returns correct, cached, fail-closed entitlements)
**Requirements**: ENT-01, ENT-02, TYP-01
**Success Criteria** (what must be TRUE):
  1. `useEntitlements.hasModule` defaults to **false** (or a known `shared_core` allowlist) while `loading` and on fetch error, and the UI surfaces an explicit error/locked state instead of silently rendering all modules — parity with `W0_MODULE_GUARD`'s fail-closed posture, asserted by a Vitest test
  2. Every gated nav module-key in `admin-dashboard/src/App.tsx` maps to a real key in `config/product_modules.json` / `saas-entitlements.ts` (no ghost `addon_kitchen_display`-style keys); a CI check asserts every `module_key` referenced in `workflows/` and `App.tsx` exists in the seeder
  3. Typed `ProductModule` and `TenantEntitlement` interfaces (tolerant of v4/v5 response shapes) replace the `any` usages in `useEntitlements.ts` and the five flagged components (`NotificationCenter.tsx`, `ToastProvider.tsx`, `AnalyticsView.tsx`, `AutomationView.tsx`, `AIChatBubble.tsx`)
  4. `npm run lint` passes for `admin-dashboard` — the standing Frontend Lint CI job goes green
**Plans**: TBD

Plans:
- [ ] 21-01: `useEntitlements.hasModule` fail-closed default + explicit error/locked UI state
- [ ] 21-02: `App.tsx` module-key alignment + CI module-key consistency check
- [ ] 21-03: Typed `ProductModule`/`TenantEntitlement` DTOs replacing `any` (lint green)

## Progress

**Execution Order:**
Phases execute in numeric order: 15 → 16 → 17 → 18 → 19 → 20 → 21

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 15. Tenant Identity Model (Canonical Key) | 0/3 | Planned | - |
| 16. Live-Safe SaaS Migration + Channel Routing Table | 0/3 | Planned | - |
| 17. Inbound Tenant Derivation (Fail-Closed) | 0/3 | Planned | - |
| 18. Per-Tenant Data-Plane Scoping + Isolation CI | 0/3 | Planned | - |
| 19. Entitlement Audit + Cache-Invalidation Lifecycle Hook | 0/3 | Not started | - |
| 20. Redis-Cached Fail-Closed Guard + Internal Token Provisioning | 0/3 | Not started | - |
| 21. UI Fail-Closed Parity + Module-Key Alignment + Type Cleanup | 0/3 | Not started | - |

**Coverage:** All 13 v2.0 requirements mapped to exactly one phase — TEN-01 → P15; TEN-02, DB-01 → P16;
TEN-03 → P17; TEN-04, TEN-05 → P18; AUD-01, AUD-02 → P19; GRD-01, ENT-03 → P20; ENT-01, ENT-02,
TYP-01 → P21. No orphans, no duplicates.

**Deploy posture:** Phases 15, 16, 17, 18, and 20 each carry a 🔴 VPS execution sub-step (live
migration apply / workflow import / secret provisioning) deferred to a prod-connected session; every
phase's success criteria are locally/CI-verifiable without VPS access.
