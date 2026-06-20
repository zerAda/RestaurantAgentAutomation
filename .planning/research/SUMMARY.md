# Project Research Summary

**Project:** RESTO BOT — SaaS Multi-Tenant Hardening (v2.0)
**Domain:** Multi-tenant SaaS hardening of a live, single-operator/multi-restaurant conversational-commerce platform (Strapi 5 CMS + n8n 2.9.4 queue-mode + Postgres 15 / Redis 7 on one Hostinger VPS)
**Researched:** 2026-06-20
**Confidence:** HIGH

## Executive Summary

This milestone is **hardening existing scaffolding, not greenfield**. The platform already carries a full relational tenant model (`tenants`, `restaurants`, `api_clients`, `restaurant_users`, `conversation_state` — all `tenant_id uuid NOT NULL REFERENCES tenants(...)` in `db/bootstrap.sql`), the inbound adapters already parse the channel-native tenant signal (`meta.phone_number_id` for WhatsApp, `meta.recipient_id` for IG/Messenger), `workflows/W12_ADMIN_ORDERS.json` already runs `FROM orders o WHERE o.tenant_id = $1`, and the Redis/Postgres/zod clients are already installed. The work is **integration and correctness on a live system**, not building a new subsystem. All four research streams converged on this: **no new libraries are required** — the tenant primitives exist but are wired wrong, applied inconsistently, or not applied to the VPS.

The dominant failure mode the whole milestone must reconcile is that the platform has **two disjoint `tenant_id` systems in the same database that never reconcile**: a **UUID data plane** (`orders.tenant_id uuid`, already scoped to a real UUID resolved from the caller's API-client token) and a **VARCHAR entitlement plane** keyed on the literal string `'default'` (`db/migrations/2026-04-06_saas_modules_entitlements.sql` -> `entitlement_audit_log.tenant_id VARCHAR(255)`; `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts:127` seeds `tenant_entitlements.tenant_id = 'default'`). The inbound path stamps every message with the env UUID (or the all-zeros fallback) regardless of which WhatsApp number it arrived on, while the guard checks entitlements against the string `'default'`. **Fixing one plane while forgetting the other is the single biggest risk.** The keystone decision — made before any code — is one canonical tenant key: the `tenants.tenant_id` UUID is canonical, and the entitlement plane must store that same UUID string.

The second structural finding is that tenant resolution is a **terminated ladder**. `B0 - Apply Auth Context` resolves a real `(tenant_id, restaurant_id)` for token-authenticated API clients, but Meta channels are token-exempt, so they always fall through to `DEFAULT_TENANT_ID` (itself unset in compose, collapsing to `''`/`'default'`). The fix is **one new resolution rung** — a `channel_identities(channel, identity, tenant_id, restaurant_id)` routing table looked up *before* the meta-signature default, failing **closed** on unmapped identities. Combined with: a single `lifecycles.ts` on both SaaS content types (the only insertion point for `entitlement_audit_log` writers AND Redis cache invalidation — neither content type currently has one), module-key drift repair (`admin-dashboard/src/App.tsx` references keys absent from the seeder/manifest), and a strict dependency-sequenced build order, this is a tractable, low-new-code, high-correctness milestone. The deliberate anti-features (schema-per-tenant, Postgres RLS, self-serve billing/RBAC, fail-open posture) keep scope contained to what a single-operator/multi-restaurant model actually needs.

## Key Findings

### Recommended Stack

**No new dependencies.** `ioredis@^5.10`, `pg@^8.18`, and `zod@^4.3` are already in `inventory-cms/package.json` and already satisfy the latest releases. The only "additions" are framework features already shipped with `@strapi/strapi` 5.37.1: **Document Service middleware** (`strapi.documents.use`, registered in `register()`) for cross-cutting tenant-filter injection, and **route policies** (`./src/policies/`) for fail-closed inbound rejection. DB constraints are *authored but not applied* — the gap is a CD step that runs the existing migration against the VPS, not new migration tooling. See `.planning/research/STACK.md`.

**Core technologies (all already installed):**
- `ioredis ^5.10` — Redis read-through entitlement cache + Pub/Sub invalidation — already the Strapi Redis client (powers SSE on `order_updates`); no install, no bump.
- `pg ^8.18` — DB-level uniqueness + tenant-FK enforcement — Strapi's Postgres driver; the gap is *applying* `db/migrations/2026-04-06_saas_modules_entitlements.sql`, not the client.
- `zod ^4.3` — validate `tenant_id` resolution + entitlement DTO shapes — replaces the `any` debt in `useEntitlements.ts`.
- Strapi 5 **Document Service middleware** — sanctioned single hook to inject `tenant_id` filters on `findMany/create/update` for `order`/`customer` types — Strapi-5-native, no plugin, no upgrade.
- Strapi 5 **route policies** — reject inbound requests lacking a resolved tenant, set `ctx.state.tenant_id` — fail-closed-friendly.

**Explicitly rejected stack additions:** any n8n/Strapi/Postgres/Redis major upgrade (milestone constraint); a multi-tenant Strapi plugin (Strapi-v4 era, unmaintained, supply-chain risk on a 2-CPU/4GB VPS); `pgcrypto`/`uuid-ossp` (`gen_random_uuid()` is core in PG 15); a second cache library; a new ORM/migration framework.

### Expected Features

The data plane is already multi-tenant-shaped (pooled `tenant_id` model — the industry-standard starting point). The gap is **resolution**, **scoping enforcement**, and **semantic consistency (UI vs guard)**. This is "close the last mile," not "build the model." See `.planning/research/FEATURES.md`.

**Must have (table stakes — onboarding a 2nd restaurant is unsafe without these):**
- **Tenant resolution from channel identity** — map `meta.phone_number_id`/`recipient_id` -> real `(tenant_id, restaurant_id)`; today everything collapses to `'default'`. P1.
- **Tenant-scoped order/customer queries** — close every missing `WHERE tenant_id` across reads AND writes (~11 workflows + Strapi controllers/lifecycles). P1.
- **UI fail-closed parity** — `useEntitlements.hasModule()` must default `false` on loading/error to match the guard's `GUARD_ERROR_FAILCLOSED`. P1.
- **Module-key alignment + CI check** — `App.tsx` references `addon_kitchen_display`/`addon_analytics`/`experimental_growth_agent`, none of which exist in the seeder or `config/product_modules.json`. P1.
- **Apply SaaS DB constraints to VPS** (`uq_tenant_module`, `entitlement_audit_log`) + CD migration-apply step. P1.
- **Provision `STRAPI_API_TOKEN_INTERNAL`** + `GUARD_ERROR_FAILCLOSED` alert — a missing token fail-closes all 8 entrypoints (total inbound outage). P1.
- **Wire `entitlement_audit_log` writers** — the table has zero writers (dead schema). P2.

**Should have (competitive / leverage existing strengths):**
- Redis-cached entitlement lookups (kills the 2 uncached Strapi round-trips per inbound message that erode Meta's <5s webhook budget). P2.
- Cache invalidation on entitlement change (couples to the audit hook — same event writes the audit row and `DEL`s the key). P2.
- `GUARD_ERROR_FAILCLOSED` vs `NO_ENTITLEMENT` alerting split.
- `config_overrides` consumption downstream; channel-registry as a full Strapi content type.

**Defer / DO NOT build (anti-features — wrong for a single-operator/multi-restaurant model):**
- **Schema-per-tenant / per-tenant DB** — massive op cost on a 2-CPU/4GB VPS; operator is a single trusted party.
- **Postgres Row-Level Security** — conflicts with pgBouncer transaction-mode pooling (`SET app.tenant_id` session GUCs don't survive transaction-pooled connections); high blast radius; not needed for the uniqueness/FK goals. **(Note: PITFALLS.md raises RLS as a defense-in-depth option for write-path leak prevention; STACK/FEATURES/ARCHITECTURE recommend deferring it. Reconciliation below.)**
- **Self-serve signup/billing/subscription tiers** — no external customers; operator provisions manually.
- **Per-end-user RBAC inside a tenant** — end users are WhatsApp/IG customers with no accounts; keep the two-tier customer/`isFullAdmin` split.
- **Tenant resolution from untrusted body hints** — spoofable; adapters already tag these `source: 'untrusted_payload'`.
- **Fail-OPEN entitlement checks** — these gate paid channel access and data boundaries, not cosmetic flags.

### Architecture Approach

Almost everything is "modify an existing chokepoint," not "build a new subsystem." The crux is that `B0 - Apply Auth Context` already parses the channel-native tenant signal and discards it for Meta channels, falling to `DEFAULT_TENANT_ID`. The fix is one new resolution rung against a `channel_identities` routing table (lives in the **n8n DB** next to `tenants`/`api_clients`, reusing the existing `postgres-main` credential and FK graph — no cross-DB hop, no new credential). See `.planning/research/ARCHITECTURE.md`.

**Major components (after v2.0):**
1. **Inbound adapter auth node** (`B0 - Apply Auth Context` in `W1_IN_WA`/`W2_IN_IG`/`W3_IN_MSG`/`W1_IN_TIKTOK`) — derive real tenant from channel identity; fail-closed on unmapped (`security_events: UNKNOWN_CHANNEL_IDENTITY`). The existing HMAC seal (`tenant_context_seal`, `TENANT_CONTEXT_SECRET`) then carries the *real* tenant downstream — unchanged.
2. **`channel_identities` routing table** (new, n8n DB) — `(channel, identity)` PK -> `(tenant_id uuid, restaurant_id uuid)` FK to `tenants`/`restaurants`.
3. **Module guard** (`W0_MODULE_GUARD.json`) — fail-closed entitlement decision, now Redis cache-aside (`ralphe:entitlement:<tenant>:<module>`, 300s positive / 60s negative TTL); Redis error falls through to Strapi, Strapi error denies, transient guard errors are never cached.
4. **Entitlement lifecycle hook** (new `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/lifecycles.ts`) — the **single insertion point** that, on `afterCreate/afterUpdate/afterDelete`, both writes `entitlement_audit_log` AND `DEL`s the Redis cache key. Neither SaaS content type currently has a `lifecycles.ts` (only `schema.json`). Strapi already holds a Redis connection for SSE, so no new dependency.
5. **Data scoping** — `WHERE tenant_id = $ctx` on order/customer reads & writes across `W4_CORE`/`W4.1_ROUTER`/`W_KIOSK_ORDER`/`W_ORDER_FINALIZER` + `order/lifecycles.ts`.
6. **UI gate** (`useEntitlements.ts`, `App.tsx`) — fail-closed, typed, module-keys aligned to `SAAS_MODULES`.

### Critical Pitfalls

1. **Reconciling only one of the two `tenant_id` planes** (UUID data plane vs VARCHAR `'default'` entitlement plane) — fixing derivation in one plane leaves the other comparing UUID-vs-string: queries silently return 0 rows or throw `invalid input syntax for type uuid: "default"`; a tenant gets right data but wrong modules. **Avoid:** decide one canonical key (`tenants.tenant_id` UUID) before any code; entitlement plane stores the same UUID string; one shared resolver; backfill before flipping derivation. *(Keystone — Phase 1.)*
2. **Leaving the `|| 'default'` / `DEFAULT_TENANT_ID` fallback in the resolver ("fail-open tenant")** — an unknown number silently routes to the default tenant = cross-tenant leakage with no error. **Avoid:** fail-**closed** with `TENANT_UNRESOLVED` + alert; gate legacy behavior behind one explicit `SINGLE_TENANT_MODE` flag; grep-and-justify every `|| 'default'`.
3. **Scoping queries without auditing every read AND write path** — order/customer access is spread across ~11 workflows + Strapi controllers; a forgotten `INSERT` inherits the wrong default silently (data plane is `NOT NULL`, so it doesn't error). **Avoid:** enumerate every query as a checklist artifact before changing any; make `tenant_id` non-defaultable on writes so omissions error loudly.
4. **Flipping UI/guard to fail-closed and locking out the live operator** — a Strapi 500, 3-8 min cold start, or missing `STRAPI_API_TOKEN_INTERNAL` makes the admin render nothing / denies all 8 entrypoints. **Avoid:** separate "not entitled" from "cannot determine"; on determination failure apply a narrow `shared_core`/`platform_runtime` allowlist + page an alert; provision + startup-assert the token *before* tightening; distinct `GUARD_ERROR_FAILCLOSED` alert.
5. **Applying `uq_tenant_module` to a live table that already contains duplicates** — bare `ADD CONSTRAINT` fails on dupes and takes an `ACCESS EXCLUSIVE` lock that stalls inbound; the migration's idempotency guard only checks constraint existence, not duplicate rows. **Avoid:** read-only duplicate probe on the VPS first; dedupe (keep latest `activated_at`); `CREATE UNIQUE INDEX CONCURRENTLY` then attach; `lock_timeout`/`statement_timeout`.
6. **Caching entitlements with no/wrong invalidation** — stale `allowed:true` survives a disable; negative cache keeps a newly-enabled module off; a tenant-less key bleeds across tenants; cached `expires_at` boolean ignores mid-TTL expiry. **Avoid:** key on `tenant_id:module_key`; explicit `DEL` on every change (shared with the audit hook); cache the raw row and re-evaluate expiry on read; tolerate `allkeys-lru` eviction (miss -> live query, never deny).
7. **Audit log as fire-and-forget that silently loses entries / mismatches schema** — `continueOnFail: true` swallows write failures (reproducing AUDIT-02/03/04); `VARCHAR(255)` accepts garbage `tenant_id`; writers `INSERT` into a non-existent table if the migration hasn't run. **Avoid:** apply migration first + post-deploy smoke; write audit in the same hook that mutates the entitlement; route any failure branch to a counter/alert; validate `tenant_id` to the canonical UUID; mirror `admin_audit_log`'s typed+FK shape.

## Implications for Roadmap

Based on combined research, the suggested phase structure follows a strict dependency chain. All four researchers converged on essentially the same ordering; this synthesis reconciles ARCHITECTURE's 7-step build order with PITFALLS' 7-phase mapping (they align 1:1, modulo a foundational identity-model phase that PITFALLS surfaces as the keystone). **Critical sequencing rules: never enable the cache before its invalidation hook exists; never flip the UI/guard to fail-closed before resolution+scoping are correct AND the secret is provisioned; never `ADD CONSTRAINT` without a live duplicate probe.**

### Phase 1: Tenant Identity Model (canonical key)
**Rationale:** The keystone. The two-plane split (UUID data plane vs VARCHAR `'default'` entitlement plane) is the dominant failure mode; sequencing this anywhere but first guarantees rework.
**Delivers:** A documented single canonical tenant key (`tenants.tenant_id` UUID); a `tenants`/`restaurants` row for the real first restaurant; backfill of its UUID into `tenant_entitlements` (replacing `'default'`); a decision on whether `entitlement_audit_log.tenant_id` migrates from `VARCHAR(255)` to `uuid` (mirror `admin_audit_log`).
**Addresses:** Foundational to every table-stakes feature.
**Avoids:** Pitfall 1 (two-plane reconciliation).

### Phase 2: Apply SaaS DB Constraints + Provision Secrets (pre-flight dedupe)
**Rationale:** Everything downstream assumes the constraint, audit table, and guard token exist. The repo<->VPS schema-drift gap (CONCERNS P0) blocks all SaaS work. Independently shippable.
**Delivers:** `db/migrations/2026-04-06_saas_modules_entitlements.sql` applied to the VPS via a guarded CD step (with read-only duplicate probe -> dedupe -> `CREATE UNIQUE INDEX CONCURRENTLY` -> attach); `STRAPI_API_TOKEN_INTERNAL` + `DEFAULT_TENANT_ID` provisioned in compose with a startup assertion; post-deploy schema check.
**Uses:** Existing `db-migrate` service + `pg`; `partial unique index` (PG 15 core).
**Avoids:** Pitfall 5 (constraint-on-duplicates), Pitfall 4's secret half (token absence).

### Phase 3: Channel Routing Table + Inbound Tenant Derivation
**Rationale:** Tenant resolution needs the lookup target to exist (additive, zero runtime impact), then the resolution rung must precede data scoping (scoping needs a correct `tenant_id`). Backward-compatible: the existing single tenant maps its own ids.
**Delivers:** New `channel_identities` migration + seed for the live tenant's `phone_number_id`/page ids; new resolution rung in `B0 - Apply Auth Context` (`W1_IN_WA`/`W2_IN_IG`/`W3_IN_MSG`/`W1_IN_TIKTOK`); trusted device->tenant for `W_KIOSK_ORDER`; fail-closed `TENANT_UNRESOLVED`/`UNKNOWN_CHANNEL_IDENTITY` on unmapped identity.
**Implements:** Architecture components 1-2; Pattern 1 (channel-identity resolution).
**Avoids:** Pitfall 2 (default-tenant fallback), Anti-Pattern 3.

### Phase 4: Per-Tenant Data-Plane Scoping
**Rationale:** Depends on real tenant (Phase 3). Highest-blast-radius change on live data — schedule a read-only audit/enumeration step first.
**Delivers:** `tenant_id` cols/indexes on orders/customers (migration + backfill to default tenant before NOT NULL); `WHERE tenant_id` on every read AND write across `W4_CORE`/`W4.1_ROUTER`/`W_KIOSK_ORDER`/`W_ORDER_FINALIZER` + `order/lifecycles.ts`; optionally the Strapi Document Service middleware for cross-cutting filter injection.
**Avoids:** Pitfall 3 (missed read/write paths).

### Phase 5: Entitlement Audit + Cache-Invalidation Lifecycle Hook
**Rationale:** Must exist **before** caching (Phase 6) so the cache is never stale-forever. Audit alone is independently valuable. One hook, two side effects.
**Delivers:** New `tenant-entitlement/lifecycles.ts` (+ optional `product-module/lifecycles.ts`) that on `afterCreate/afterUpdate/afterDelete` writes `entitlement_audit_log` AND `DEL`s the Redis key; failure branch routed to a counter/alert (no silent `continueOnFail`); `tenant_id` validated to canonical UUID.
**Implements:** Architecture component 4; Pattern 3.
**Avoids:** Pitfall 7 (audit silent loss / type mismatch).

### Phase 6: Redis-Cached Fail-Closed Guard
**Rationale:** Depends on Phase 5 (invalidation) to be safe and Phase 1 (canonical key) for the cache key. Delivers the P1 latency win (removes 2 Strapi round-trips/message).
**Delivers:** Cache-aside in `W0_MODULE_GUARD.json` keyed `ralphe:entitlement:<tenant>:<module>` (300s positive / 60s negative); Redis error -> fall through to Strapi; Strapi error -> deny; never cache transient guard errors; cache raw row + re-evaluate expiry on read; tolerate `allkeys-lru` eviction.
**Implements:** Pattern 2; Performance trap fix (+2 Strapi round-trips).
**Avoids:** Pitfall 6 (stale/cross-tenant cache bleed).

### Phase 7: UI Fail-Closed + Module-Key Alignment (last)
**Rationale:** Do **after** the backend returns correct entitlements — flipping fail-closed earlier would hide modules the tenant legitimately has while the backend is still wrong. Lowest blast radius, last.
**Delivers:** `useEntitlements.hasModule()` default `false` on loading/error + explicit error state + `shared_core` allowlist; typed interfaces (remove 6x `any`); `App.tsx` nav keys aligned to `SAAS_MODULES`; CI check that every `module_key` in `workflows/` and `App.tsx` exists in the seeder.
**Avoids:** Pitfall 4 (operator lockout), Anti-Pattern 4 (module-key drift).

### Phase Ordering Rationale

- **Identity before everything:** the canonical-key decision (Phase 1) gates correctness of every other plane; PITFALLS calls it the keystone and the dominant failure mode.
- **DB/secrets before logic:** the unapplied migration is CONCERNS P0; the guard token absence is a latent total-outage; both are prerequisites, not features.
- **Resolution before scoping:** scoping is meaningless while every request resolves to `'default'`.
- **Invalidation before caching:** a cache without its invalidation hook is a security regression (stale grants survive revocation).
- **Backend correct before UI tightening:** fail-closed UI on a still-wrong backend = self-inflicted operator lockout.
- **Module-key alignment gates fail-closed UI:** flipping fail-closed with drifted keys makes real modules vanish from nav.

### Research Flags

Phases likely needing deeper research (`/gsd:research-phase`) during planning:
- **Phase 4 (data scoping):** ARCHITECTURE explicitly flags the exact order/customer SQL nodes inside `W4_CORE.json`/`W4.1_ROUTER.json` as not enumerated (both files are large) — needs a phase-level inventory pass. Also the kiosk security model (signed device token vs `channel_identities` device row) for the unauthenticated kiosk `POST /v1/strapi/api/orders` is an open question.
- **Phase 5 (audit hook):** the **cross-DB write question** — `entitlement_audit_log` is created in the n8n DB by the SaaS migration, but the writer is a Strapi lifecycle bound to the strapi DB. Needs resolution: move the table to the strapi DB, or give the writer an explicit n8n-DB connection (the guard already crosses n8n->Strapi over HTTP).

Phases with standard patterns (can skip deeper research):
- **Phase 2 (apply migration + provision secrets):** mechanism exists (`db-migrate` service); the work is wiring + a dedupe probe.
- **Phase 3 (resolution rung):** the resolver pattern already exists in `W1_IN_WA` for token clients; the rung mirrors it.
- **Phase 6 (cache-aside):** well-documented pattern; `ioredis` Pub/Sub already used for SSE.
- **Phase 7 (UI fail-closed):** localized change to `useEntitlements.ts`/`App.tsx`; Vitest already present.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All deps verified present in `inventory-cms/package.json` and satisfying latest npm; Strapi 5 middleware/policy APIs verified in official docs. |
| Features | HIGH (codebase) / MEDIUM (industry patterns) | Every recommendation anchored to a real file/line; industry pattern sources are MEDIUM (WorkOS, Redis, Security Boulevard blogs). |
| Architecture | HIGH | All integration points read directly (parsers, auth ladder, missing lifecycle hooks confirmed by directory listing); build order MEDIUM-HIGH (exact scoping-query node wiring deferred to phase research). |
| Pitfalls | HIGH | Grounded in direct repo reads (`db/schema.sql`, the SaaS migration, `W0_MODULE_GUARD`, `W1_IN_WA`, `useEntitlements.ts`) cross-checked against CONCERNS.md. |

**Overall confidence:** HIGH

### Gaps to Address

- **RLS recommendation conflict (must reconcile in roadmap):** STACK, FEATURES, and ARCHITECTURE all recommend **against** Postgres RLS (pgBouncer transaction-pooling incompatibility, blast radius, not needed for uniqueness/FK goals). PITFALLS raises RLS as the "single highest-leverage control" for brownfield write-path leak prevention (Pitfall 3). **Resolution for Phase 4:** default to the majority position — app-layer scoping + non-defaultable `tenant_id` on writes + an exhaustive query inventory + a CI/test asserting tenant-scoped queries — because RLS via session GUCs is fragile under n8n's transaction-mode pooled connections. Treat RLS as a deferred, dedicated-milestone option only if a true adversarial-tenant model emerges. Flag this explicitly for the roadmapper to confirm.
- **`entitlement_audit_log` placement (cross-DB write):** unresolved whether the table moves to the strapi DB or the Strapi writer gets an explicit n8n-DB connection. Resolve in Phase 5 planning.
- **`entitlement_audit_log.tenant_id` type:** currently `VARCHAR(255)`; Phase 1 should decide whether to migrate it to `uuid` with an FK (mirroring `admin_audit_log`) before writers are wired.
- **Exact scoping-query inventory:** the ~11 order/customer workflows + Strapi controllers/lifecycles need enumeration as a Phase 4 checklist artifact before any change.
- **Kiosk tenant trust model:** signed device token vs `channel_identities` device row for unauthenticated kiosk POST — decide in Phase 3/4.
- **Canonical module-key set:** `App.tsx` keys (`addon_kitchen_display`, `addon_analytics`, `experimental_growth_agent`) vs seeder/`config/product_modules.json` (`kiosk_instore`, `growth_marketing`) — pick one set in Phase 7.

## Sources

### Primary (HIGH confidence)
- Codebase (direct reads): `db/bootstrap.sql`, `db/schema.sql`, `db/migrations/2026-04-06_saas_modules_entitlements.sql`, `db/migrations/2026-04-06_master_schema_unification.sql`, `db/migrations/2026-01-22_p1_opssecqa_scopes_admin_audit.sql`, `workflows/W0_MODULE_GUARD.json`, `workflows/W1_IN_WA.json`, `workflows/W4_CORE.json`, `workflows/W12_ADMIN_ORDERS.json`, `inventory-cms/package.json`, `inventory-cms/src/api/order/content-types/order/schema.json`, `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts`, `admin-dashboard/src/hooks/useEntitlements.ts`, `admin-dashboard/src/App.tsx`, `config/product_modules.json`
- `.planning/codebase/CONCERNS.md`, `INTEGRATIONS.md`, `STACK.md`, `.planning/PROJECT.md` — milestone constraints + audit findings
- `docs.strapi.io/cms/api/document-service/middlewares` — Document Service middleware registration + filter injection (verified)
- `docs.strapi.io/cms/backend-customization/policies` — route policy registration + `return false` rejection (verified)
- `registry.npmjs.org/ioredis/latest` (5.11.1), `registry.npmjs.org/pg/latest` (8.22.0) — installed ranges satisfy latest

### Secondary (MEDIUM confidence)
- WorkOS — developer's guide to SaaS multi-tenant architecture; multi-tenant RBAC SaaS
- Security Boulevard — Tenant Isolation in Multi-Tenant Systems
- Redis — Data isolation in multi-tenant SaaS
- OneUptime — Multi-tenant data isolation with RLS on Azure SQL
- Unleash / LaunchDarkly — feature-flag best practices (used to justify the no-external-flag-SaaS anti-feature)

### Tertiary (LOW confidence)
- DraftKings Engineering — Mastering Feature Flags: Performance and Resilience (general guidance, not load-bearing)

---
*Research completed: 2026-06-20*
*Ready for roadmap: yes*
