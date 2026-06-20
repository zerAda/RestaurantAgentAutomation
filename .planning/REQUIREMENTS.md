# Requirements: RESTO BOT — v2.0 SaaS Multi-Tenant Hardening

**Defined:** 2026-06-20
**Core Value:** Orders placed on any channel reach the kitchen, get paid, and get delivered — reliably and without manual intervention.
**Milestone Goal:** Turn the shipped-but-scaffolding-only SaaS multi-tenant layer into a genuinely production-safe one, so a *second* restaurant/tenant can be onboarded without cross-tenant data leakage or entitlement bypass.

> Grounded in `.planning/research/SUMMARY.md` and `.planning/codebase/CONCERNS.md`. **Keystone:** the platform has two disjoint `tenant_id` planes — a UUID data plane (`orders.tenant_id uuid`, already scoped) and a VARCHAR entitlement plane keyed on the literal `'default'`. The canonical key is the UUID `tenants.tenant_id`; both planes must reconcile to it.
>
> **Deploy posture (same as v1.0):** every requirement is implemented and CI-verified **locally**; steps that require the production VPS (applying a migration to live Postgres, provisioning a secret on the VPS, importing a workflow) are designed here but their *execution* is 🔴 **deferred** to a prod-connected session.

## v2.0 Requirements

### Tenant Resolution & Data Isolation

- [ ] **TEN-01**: A single canonical tenant key is established — the UUID `tenants.tenant_id` is the system of record. The entitlement plane's VARCHAR `tenant_id` (`tenant_entitlements`, `saas-entitlements.ts`) is reconciled to the canonical UUID (or a documented, enforced 1:1 mapping). No runtime path silently substitutes the literal `'default'`.
- [ ] **TEN-02**: A `channel_identities` routing table (migration) maps channel-native identifiers — WhatsApp `phone_number_id`, Instagram/Messenger `recipient_id`/page id, kiosk device id — to `(tenant_id, restaurant_id)`. Seeded for the current single tenant.
- [ ] **TEN-03**: Inbound adapters resolve tenant from `channel_identities`: `B0 - Apply Auth Context` (in `W1_IN_WA.json`, `W2_IN_IG.json`, `W3_IN_MSG.json`) uses the already-parsed `phone_number_id`/`recipient_id` instead of falling through to `DEFAULT_TENANT_ID`. An **unknown** channel identity fails closed (message parked/rejected with a log event) — it does **not** default to `'default'`.
- [x] **TEN-04**: Order and customer **reads and writes** are scoped by `tenant_id`. `tenant_id` is non-defaultable on the write path (NOT NULL, no `|| 'default'` fallback). Existing scoped reads (e.g. `W12_ADMIN_ORDERS.json`) are confirmed; unscoped paths are closed. — DONE (Phase 18, code/CI): 7 n8n order workflows scoped + W_ORDER_FINALIZER write fixed; Strapi order/customer content types gain required `tenant_id`/`restaurant_id` + fail-loud `beforeCreate` + `db/migrations-strapi/` migration. 🔴 strapi-DB apply + CMS rebuild + prod n8n import deferred.
- [x] **TEN-05**: An automated CI test proves cross-tenant isolation — a request resolved to tenant A cannot read or write tenant B's orders/customers (seeds two tenants, asserts separation). — DONE (Phase 18): `.github/workflows/phase-18-assertions.yml` + `db/ci-fixtures/18-two-tenant-seed.sql` + `db/ci-assertions/18-cross-tenant-isolation.sql` (both-direction read/write + non-defaultable-write + FK; proven on ephemeral PG twice + negative control fires).

### Fail-Closed Entitlement Consistency

- [ ] **ENT-01**: `useEntitlements.hasModule` (`admin-dashboard/src/hooks/useEntitlements.ts`) defaults to **false** (or a known shared-core allowlist) while `loading` and on fetch error — parity with `W0_MODULE_GUARD`'s fail-closed posture. The UI surfaces an explicit error/locked state instead of silently rendering all modules.
- [ ] **ENT-02**: Admin navigation module-keys in `admin-dashboard/src/App.tsx` are reconciled with the seeder/manifest keys (`config/product_modules.json`, `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts`). Every gated nav item maps to a real entitlement key (no silent fail-closed from `addon_kitchen_display`-style ghost keys).
- [ ] **ENT-03**: `STRAPI_API_TOKEN_INTERNAL` is a first-class secret — declared in `docker-compose.hostinger.prod.yml`/`base`, `config/.env.example`, and the secrets inventory — so the fail-closed guard cannot convert a missing secret into a total inbound/operator lockout. A startup/preflight check fails fast (with a clear message) if it is unset. *(VPS provisioning of the secret value: 🔴 deferred.)*

### Guard Caching, Entitlement Audit & DB Constraints

- [ ] **GRD-01**: `W0_MODULE_GUARD.json` caches module/entitlement lookups in Redis (≈5-min TTL, keyed by `tenant_id:module_key`), so a cache hit skips both synchronous Strapi round-trips per inbound message. Cache miss falls back to Strapi and still fails closed on error.
- [x] **AUD-01**: The `tenant-entitlement` (and `product-module`) Strapi content types gain `lifecycles.ts` that write an `entitlement_audit_log` row on create/update/delete (who/what/when/old→new). The currently-dead `entitlement_audit_log` table gets real writers (or is explicitly dropped if descoped — decision recorded).
- [x] **AUD-02**: The same lifecycle hook **invalidates** the Redis entitlement cache (`GRD-01`) on any entitlement change, so a revoked or expired entitlement cannot survive in cache.
- [ ] **DB-01**: The `db/migrations/2026-04-06_saas_modules_entitlements.sql` constraints (`uq_tenant_module`, the four entitlement indexes, `uq_product_module_key`, `entitlement_audit_log`) are made **safe to apply on a live table**: a pre-apply duplicate probe + `CREATE UNIQUE INDEX CONCURRENTLY` (no exclusive lock, no failure on existing duplicates). The migration is wired into the existing `db-migrate` mechanism. *(VPS apply: 🔴 deferred.)*

### Type & Lint Debt Cleanup

- [ ] **TYP-01**: Typed interfaces for the Strapi `ProductModule` and `TenantEntitlement` responses (tolerant of v4/v5 shapes) replace the `any` usages in `admin-dashboard/src/hooks/useEntitlements.ts` and the five other flagged components (`NotificationCenter.tsx`, `ToastProvider.tsx`, `AnalyticsView.tsx`, `AutomationView.tsx`, `AIChatBubble.tsx`). `npm run lint` passes for `admin-dashboard` (the standing Frontend Lint CI failure goes green).

## Out of Scope (v2.0)

| Item | Reason |
|------|--------|
| Postgres Row-Level Security (RLS) | Conflicts with pgBouncer transaction-mode pooling; app-layer scoping + non-defaultable `tenant_id` + CI test chosen instead (research SUMMARY). May revisit as defense-in-depth later. |
| Schema-per-tenant / DB-per-tenant isolation | Over-engineered for a single-operator-multi-restaurant model; pooled `tenant_id` column is sufficient. |
| Self-serve tenant signup / billing / per-tenant RBAC | Operator-provisioned tenants only this milestone. |
| External feature-flag SaaS (LaunchDarkly, etc.) | Strapi entitlements + Redis cache cover the need. |
| n8n 2.x → 3.x / Strapi / Postgres major upgrades | Hard constraint — no major version changes. |
| Multi-tenant Strapi community plugins | Built-in Document-Service middleware + policies suffice. |

## Constraints

- **No major version upgrades** (n8n 2.9.4, Strapi 5.37.1, Postgres 15, Redis 7).
- **No new runtime libraries** — `ioredis`, `pg`, `zod` already installed; use Strapi-5-native middleware/policies.
- **Zero downtime / live-data safe** — migrations must not lock or fail on the production table; entitlement fail-closed flips must not lock operators out before the secret exists.
- **Public API contract** `https://api.../v1/*` stays stable.

## Traceability (requirement → scope group)

| Req | Group | Local-implementable | VPS-deferred part |
|-----|-------|---------------------|-------------------|
| TEN-01 | Resolution & Isolation | Yes | — |
| TEN-02 | Resolution & Isolation | Yes (migration + seed) | apply on VPS |
| TEN-03 | Resolution & Isolation | Yes (workflow JSON) | import on VPS |
| TEN-04 | Resolution & Isolation | Yes (workflows + Strapi schemas/lifecycles + migration) | apply strapi-DB migration + rebuild CMS + import workflows on VPS |
| TEN-05 | Resolution & Isolation | Yes (CI test) | — |
| ENT-01 | Fail-Closed Entitlements | Yes | — |
| ENT-02 | Fail-Closed Entitlements | Yes | — |
| ENT-03 | Fail-Closed Entitlements | Yes (compose/env/preflight) | set secret value on VPS |
| GRD-01 | Caching/Audit/DB | Yes (workflow JSON) | import on VPS |
| AUD-01 | Caching/Audit/DB | Yes (lifecycles.ts) | rebuild CMS on VPS |
| AUD-02 | Caching/Audit/DB | Yes | rebuild CMS on VPS |
| DB-01 | Caching/Audit/DB | Yes (safe migration) | apply on VPS |
| TYP-01 | Type/Lint Debt | Yes | — |

**Coverage:** 13 requirements across 4 scoped groups. All have a local-implementable, CI-verifiable core; 6 carry a 🔴 VPS execution step deferred to a prod-connected session.

---
*Requirements defined: 2026-06-20 — v2.0 SaaS Multi-Tenant Hardening; seeded by 4-agent domain research + the 2026-06-20 codebase audit.*
