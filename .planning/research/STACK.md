# Stack Research — SaaS Multi-Tenant Hardening (v2.0)

**Domain:** Multi-tenant SaaS hardening of a shipped restaurant-automation platform (RESTO BOT)
**Researched:** 2026-06-20
**Confidence:** HIGH

> **Headline finding (reframes the question):** This milestone needs almost **no new dependencies**.
> The hard constraint ("no n8n/Strapi/Postgres major upgrades") is easy to honor because the
> tenant primitives are *already in the stack* — they are wired wrong, applied inconsistently, or
> not applied to the VPS, not missing. The DB already carries a full relational tenant model
> (`tenants`, `restaurants`, `api_clients`, `restaurant_users`, `conversation_state` — all
> `tenant_id uuid NOT NULL REFERENCES tenants(...) ON DELETE CASCADE` in `db/bootstrap.sql`),
> `W1_IN_WA.json` already derives a real tenant from `api_clients.token_hash` and HMAC-seals a
> `tenant_context`, and the Redis (`ioredis ^5.10`), Postgres (`pg ^8.18`), and validation
> (`zod ^4.3`) clients are already present in `inventory-cms/package.json`. The work is
> **integration and correctness**, achievable with the libraries already installed plus Strapi 5's
> built-in Document Service middleware. Treat new-library additions as a last resort.

---

## Recommended Stack

### Core Technologies (all ALREADY INSTALLED — verified present, no version bump needed)

| Technology | Installed Version | Latest (Context7/npm) | Purpose for this milestone | Why it's the right tool |
|------------|-------------------|------------------------|----------------------------|--------------------------|
| `ioredis` | `^5.10.0` (`inventory-cms/package.json:21`) | 5.11.1 (npm registry, 2026-06) | Redis read-through cache for module/entitlement lookups + Pub/Sub invalidation channel | Already the Strapi Redis client (powers SSE on `order_updates`). `^5.10` already satisfies 5.11.x — **no install, no bump**. Supports `SUBSCRIBE`/`PUBLISH` needed for cross-process cache invalidation. |
| `pg` | `^8.18.0` (`inventory-cms/package.json:22`) | 8.22.0 (npm registry, 2026-06) | DB-level uniqueness + tenant-FK enforcement (constraints already authored in `db/migrations/2026-04-06_saas_modules_entitlements.sql`) | Strapi's Postgres driver; n8n's 165 `postgres` nodes use the server-side `postgres-main` credential. No driver work needed — the gap is *applying* migrations, not the client. |
| `zod` | `^4.3.6` (`inventory-cms/package.json:27`) | 4.x | Validate the shape of `tenant_id` resolution + entitlement responses (replaces `any` in the guard/seeder paths) | Already used in CMS extensions/services. Use it to type the entitlement DTOs that currently force `any` in `useEntitlements.ts`. |
| Strapi 5 **Document Service middleware** (`strapi.documents.use`) | built into `@strapi/strapi` 5.37.1 | n/a (framework feature) | The single sanctioned hook to inject a `tenant_id` filter on every `findMany/create/update` for `order`, `customer`, and related content types | **Verified via official docs** (`docs.strapi.io/cms/api/document-service/middlewares`): register in `inventory-cms/src/index.ts` `register()`, must `return next()`. This is the Strapi-5-native answer to "scope data per tenant" — no plugin, no upgrade. |
| Strapi 5 **route policies** (`./src/policies/`) | built into `@strapi/strapi` 5.37.1 | n/a (framework feature) | Reject/annotate inbound REST requests (`/api/orders`, kiosk) that lack a resolved tenant; set `ctx.state.tenant_id` for the middleware to read | **Verified via official docs** (`docs.strapi.io/cms/backend-customization/policies`): policies run before controllers, can return `false` to reject and read/write `policyContext.state`. Native, fail-closed-friendly. |
| Postgres 15 **partial unique index + `REFERENCES`** | `postgres:15-alpine` (existing) | n/a | DB-level entitlement uniqueness (`uq_tenant_module`) and tenant FK integrity | Plain SQL DDL already authored; needs *application to the VPS*, not a new extension. **No `pgcrypto`/RLS extension dependency required for the unique-constraint goal.** |

### Supporting Patterns / Helpers (build in-repo — NOT new npm packages)

| Helper | Where it lives | Purpose | When to use |
|--------|----------------|---------|-------------|
| Redis read-through cache module | new `inventory-cms/src/services/entitlement-cache.ts` (uses existing `ioredis`) | `GET tenant:{id}:module:{key}` → on miss, query Strapi/DB, `SET` with `EX 300` (5-min TTL) | Behind both the Strapi entitlement service and the n8n guard's HTTP target |
| Cache-invalidation publisher | Strapi `tenant-entitlement` lifecycle (`inventory-cms/src/api/tenant-entitlement/content-types/.../lifecycles.ts`) | On `afterCreate/afterUpdate/afterDelete`, `DEL` the key(s) and `PUBLISH entitlement_invalidate {tenant_id, module_key}` | Whenever an entitlement changes (admin edit, seeder, expiry sweep) — fixes the "cache with invalidation" requirement |
| n8n Redis-first guard path | edit `workflows/W0_MODULE_GUARD.json` to add a leading `n8n-nodes-base.redis` `GET` node before the two `fetch()` calls | Serve hot entitlement decisions from Redis; only fall through to the 2 Strapi round-trips on cache miss | Cuts the documented "2 uncached Strapi round-trips per inbound message" (CONCERNS.md P1 perf) — uses the **existing** `REDIS_CREDENTIAL_ID` pattern (60 redis nodes already in the fleet) |
| `entitlement_audit_log` writer | Strapi entitlement lifecycle (above) + n8n `W_AUDIT_WRITE` reuse | INSERT into the already-authored `entitlement_audit_log` table (`db/migrations/2026-04-06_saas_modules_entitlements.sql:45`) | Closes the "table has zero writers" gap (CONCERNS.md P1) |
| Channel-identity → tenant resolver | DB lookup (extend `api_clients`/add a `channel_accounts` mapping if WABA `phone_number_id` is the key) | Map inbound Meta `value.metadata.phone_number_id` (token-exempt path) to `tenant_id`/`restaurant_id` | Only needed where the `api_clients.token_hash` path doesn't apply — i.e. raw Meta webhooks. **This is the one place a tiny new DB table may be justified (see "What NOT to Use" caveat).** |

### Development / Verification Tools (already present)

| Tool | Purpose | Notes |
|------|---------|-------|
| `db-migrate` compose service + `db/init/01_apply_migrations.sh` | Apply the SaaS constraint migration to the VPS | Mechanism exists; the gap is a **CD step that runs it against prod** (repo↔VPS drift is the P0 root cause in CONCERNS.md). No new tool — wire existing one into CD. |
| n8n `executeWorkflow` guard pattern | Already how 8 entrypoints call `W0_MODULE_GUARD` | Keep; only add the Redis cache node inside the guard. |
| Vitest ^4 (`admin-dashboard`, `kiosk-app`) | Assert UI gate fails **closed**, mirror server semantics | Use to test `useEntitlements.hasModule` default-deny (see PITFALLS). |

## Installation

```bash
# Core multi-tenant hardening: NOTHING to install.
# ioredis ^5.10, pg ^8.18, zod ^4.3 are already in inventory-cms/package.json
# and satisfy the latest releases (ioredis 5.11.1, pg 8.22.0).

# The only "installs" are framework features already shipped with @strapi/strapi 5.37.1:
#   - Document Service middleware  → register in inventory-cms/src/index.ts (register())
#   - Route policies               → add files under inventory-cms/src/policies/

# DB constraints: APPLY (do not author) the existing migration on the VPS:
docker exec <postgres-container> psql -U n8n -d n8n \
  < db/migrations/2026-04-06_saas_modules_entitlements.sql
# (tenant_entitlements / product_modules / entitlement_audit_log live in the n8n DB
#  per INTEGRATIONS.md; verify the target DB before running.)
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| Strapi Document Service middleware (`strapi.documents.use`) for tenant data scoping | Per-content-type `lifecycles.ts` `beforeFind/beforeCreate` hooks | Use lifecycles only for a *single* content type or for the audit-log writes; for cross-cutting `tenant_id` injection across many types, one global Document Service middleware is DRY-er and is the Strapi-5 sanctioned location. |
| Postgres **partial unique index** (`uq_tenant_module`, already authored) for entitlement uniqueness | Postgres **Row-Level Security (RLS)** policies | RLS is heavier and interacts awkwardly with pgBouncer **transaction-mode pooling** (`SET app.tenant_id` per-session does not survive transaction-pooled connections without `SET LOCAL` inside every txn). For the v2.0 *uniqueness* and *FK* goals, plain constraints + app-layer scoping are sufficient and pooling-safe. Revisit RLS only if a future milestone requires DB-enforced read isolation independent of the app layer. |
| `ioredis` read-through cache keyed `tenant:{id}:module:{key}` | n8n `staticData` / in-memory workflow cache | In-memory caches don't survive across the `n8n-main`/`n8n-worker` split (queue mode) and can't be invalidated by Strapi. Redis is shared by both processes and already authenticated. |
| Reuse `api_clients.token_hash` → tenant (already in `W1_IN_WA.json`) for tenant derivation | A brand-new tenant-resolution service/library | The resolver already exists and is HMAC-sealed (`tenant_context_seal`, `TENANT_CONTEXT_SECRET`). Extend it; don't replace it. |

## What NOT to Use / Add (hard guidance)

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **Any n8n / Strapi / Postgres / Redis major upgrade** | Explicit milestone constraint; CONCERNS.md flags n8n 2→3 as "high blast radius, separate milestone." | Stay on n8n 2.9.4 / Strapi 5.37.1 / PG 15 / Redis 7. |
| A multi-tenant **Strapi plugin** (e.g. community `strapi-plugin-multi-tenant`-style packages) | Most target Strapi v4, are unmaintained, and would fight Strapi 5's Document Service + the existing custom `tenant-entitlement` content type. Adds supply-chain + version-pin risk on a 2-CPU/4GB VPS with a 3–8 min CMS cold start. | Native `strapi.documents.use` middleware + route policies (both verified in Strapi 5 docs). |
| **`pgcrypto` / `uuid-ossp` extension just for IDs** | `tenants.tenant_id` already uses `gen_random_uuid()` (built into PG 13+ core, no extension). | Nothing — it already works. |
| **Postgres Row-Level Security** *for this milestone* | Interacts poorly with pgBouncer `POOL_MODE=transaction` (session GUCs like `app.current_tenant` don't persist across pooled transactions); large blast radius; not needed for the uniqueness/FK goals. | Application-layer scoping (Document Service middleware) + the already-authored unique/FK constraints. Defer RLS to a dedicated milestone if ever needed. |
| A new **cache library** (`node-cache`, `keyv`, `cache-manager`, Redis OM, etc.) | `ioredis` is already the Strapi Redis client and already does Pub/Sub for SSE. A second cache layer = two eviction policies, two failure modes, more RAM on a 256MB Redis. | The existing `ioredis` client with explicit `SET ... EX 300` + `DEL` + `PUBLISH`. |
| A new **secrets/config library** for `STRAPI_API_TOKEN_INTERNAL` / `DEFAULT_TENANT_ID` | The gap is *unset env vars in compose*, not missing tooling. `DEFAULT_TENANT_ID` is unset; `STRAPI_API_TOKEN_INTERNAL` is referenced by exactly one workflow and unconfirmed in compose. | Add the vars to `docker-compose.hostinger.prod.yml` n8n-main/-worker env blocks + `.env.example`; provision the token. (See PITFALLS — fail-closed guard turns a missing token into a total inbound outage.) |
| A new **ORM / query builder** in n8n for tenant scoping | n8n already runs 165 parameterized `postgres` nodes; orders/customers are reachable via Strapi REST or direct SQL. | Add `tenant_id`/`restaurant_id` columns + `WHERE tenant_id = $n` to the existing parameterized queries; add the column to the Strapi `order`/`customer` schemas (currently **absent** — `inventory-cms/src/api/order/content-types/order/schema.json` has no `tenant_id`, though `db/migrations/2026-04-06_master_schema_unification.sql` and the bootstrap join on `o.tenant_id`). This split-brain is the real data-scoping bug. |
| A heavyweight **schema-validation/migration framework** (Prisma migrate, Flyway, Liquibase) | The repo already has an idempotent `db/migrations/*.sql` + `schema_migrations` tracking + `db-migrate` service. The problem is **CD never applies migrations to the VPS**, not the migration tooling. | Add a guarded VPS migration-apply step to CD (`.github/workflows/cd-deploy.yml`) — or a documented runbook step + post-deploy schema check. |

## Stack Patterns by Variant

**If onboarding tenants whose inbound is token-authenticated (`api_clients`):**
- Use the existing `W1_IN_WA.json` B0 path: `api_clients.token_hash → tenant_id/restaurant_id`, sealed via `TENANT_CONTEXT_SECRET`.
- No new resolver needed; just ensure `DEFAULT_TENANT_ID`/`DEFAULT_RESTAURANT_ID` + `PROD_ENFORCE_DEFAULTS=true` are set so unmatched requests fail-closed rather than silently bucket into `'default'`.

**If onboarding tenants via raw Meta webhooks (token-exempt, HMAC-only):**
- The channel identity is `entry[].changes[].value.metadata.phone_number_id` (WABA) / `IG_PAGE_ID` / `MSG_PAGE_ID`.
- Add a `channel_accounts(provider, external_id, tenant_id, restaurant_id)` lookup table (mirrors `api_clients` shape; FK to `tenants`/`restaurants`) and resolve tenant from `phone_number_id` **before** `W0_MODULE_GUARD`. This is the *only* genuinely new schema this milestone may need — keep it minimal and FK-constrained.

**If the SaaS migration is not yet on the VPS (likely, per CONCERNS.md):**
- Apply `db/migrations/2026-04-06_saas_modules_entitlements.sql` first; without `uq_tenant_module`, concurrent writes/admin edits create duplicate entitlement rows that the guard's `data[0]` read silently masks.

## Version Compatibility

| Package / Component | Compatible With | Notes |
|---------------------|-----------------|-------|
| `ioredis@^5.10` (installed) | Redis 7, Node 20.20.0 | npm latest 5.11.1; `^5.10` already resolves it. `engines.node >=12.22.0` — well within Node 20. No bump. |
| `pg@^8.18` (installed) | PostgreSQL 15, pgBouncer transaction mode | npm latest 8.22.0; `^8.18` resolves it. **Caveat:** pgBouncer transaction-mode pooling means *no* prepared-statement reliance / session GUCs across calls — reinforces "no RLS via session vars." |
| `strapi.documents.use` middleware | `@strapi/strapi` 5.37.1 | Strapi-5-only API (does not exist in v4); register in `register()`, must `return next()`. Verified in current Strapi 5 docs. |
| Strapi route policies | `@strapi/strapi` 5.37.1 | `global::`, `api::`, `plugin::` scoping; can reject (`return false`) and read/write `policyContext.state`. |
| Postgres partial unique index `WHERE enabled = true` | PostgreSQL 15 | Already authored (`idx_entitlements_active`); 15 fully supports partial indexes. `gen_random_uuid()` is core in 15 (no extension). |

## Sources

- `docs.strapi.io/cms/api/document-service/middlewares` — **HIGH**: confirmed `strapi.documents.use(context, next)` registration in `src/index.ts` `register()`, filter-injection on `findMany/create/update`, mandatory `return next()`.
- `docs.strapi.io/cms/backend-customization/policies` — **HIGH**: confirmed route policy registration (`./src/policies/`), `return false` rejection, `policyContext.state` access.
- `registry.npmjs.org/ioredis/latest` — **HIGH**: latest 5.11.1, `engines.node >=12.22.0`; installed `^5.10` satisfies it.
- `registry.npmjs.org/pg/latest` — **HIGH**: latest 8.22.0; installed `^8.18` satisfies it.
- Codebase (HIGH, primary): `inventory-cms/package.json` (deps), `db/bootstrap.sql` (relational tenant model — `tenants`/`restaurants`/`api_clients`/`restaurant_users`/`conversation_state`), `db/migrations/2026-04-06_saas_modules_entitlements.sql` (authored constraints + `entitlement_audit_log`), `db/migrations/2026-04-06_master_schema_unification.sql` (orders `tenant_id` at DB level), `workflows/W1_IN_WA.json` (real tenant derivation via `api_clients` + HMAC `tenant_context_seal`), `workflows/W0_MODULE_GUARD.json` (uncached 2× Strapi fetch), `inventory-cms/src/api/order/content-types/order/schema.json` (Strapi `order` has **no** `tenant_id` — split-brain), `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` (`DEFAULT_TENANT_ID || 'default'`), `admin-dashboard/src/hooks/useEntitlements.ts` (UI fail-open).
- `.planning/codebase/CONCERNS.md`, `INTEGRATIONS.md`, `STACK.md`, `.planning/PROJECT.md` — milestone constraints + audit findings.

---
*Stack research for: SaaS multi-tenant hardening (RESTO BOT v2.0)*
*Researched: 2026-06-20*
