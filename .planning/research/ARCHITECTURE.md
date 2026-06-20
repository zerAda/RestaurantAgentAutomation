# Architecture Research — SaaS Multi-Tenant Hardening (RESTO BOT v2.0)

**Domain:** Multi-channel, multi-tenant SaaS ordering platform (n8n queue-mode mesh + Strapi 5 CMS + Postgres/Redis behind nginx/Traefik)
**Researched:** 2026-06-20
**Confidence:** HIGH (all claims grounded in repo files; integration points read directly, not inferred)

> Scope: how **real tenant resolution**, **per-tenant data scoping**, a **Redis-cached fail-closed entitlement guard**, and **entitlement auditing** integrate with the *existing* architecture. This is a hardening milestone on a live system — almost everything below is "modify an existing chokepoint," not "build a new subsystem." The good news the audit under-stated: tenant resolution scaffolding *already exists* in the inbound adapters; it just terminates at `DEFAULT_TENANT_ID` for the Meta channels.

---

## Standard Architecture

### System Overview (current, with v2.0 insertion points marked ◆)

```
┌──────────────────────────────────────────────────────────────────────────┐
│  EDGE: Traefik (TLS, BasicAuth/IP-allowlist)  →  Nginx gateway (/v1/*)    │
│        infra/gateway/nginx.conf — rate-limit zones, CORS, path normalize  │
└───────────────┬──────────────────────────────────────┬───────────────────┘
                │ Meta webhooks / kiosk                 │ admin SPA /v1/portal/*
                ▼                                        ▼
┌──────────────────────────────────────────┐  ┌────────────────────────────┐
│ n8n ORCHESTRATION MESH (queue mode)      │  │ ADMIN DASHBOARD (React SPA) │
│                                          │  │ App.tsx ─ useEntitlements ◆ │
│  W1_IN_WA / W2_IN_IG / W3_IN_MSG /       │  │  (fail-OPEN today → fix ◆)  │
│  W1_IN_TIKTOK  inbound adapters          │  └─────────────┬──────────────┘
│   ├─ B0 Parse&Canonicalize (extracts     │                │ JWT, REST
│   │   phone_number_id / recipient_id)    │                ▼
│   ├─ B0 Resolve Client (DB, api_clients) │  ┌────────────────────────────┐
│   ├─ B0 Apply Auth Context ◆ ← tenant_id │  │ STRAPI 5 CMS (source of     │
│   │   resolution lives HERE              │  │ truth)                      │
│   ├─ B0 Seal Tenant Context (HMAC)       │  │  product-module             │
│   └─ B0 Module Guard → W0_MODULE_GUARD ◆ │◄─┤  tenant-entitlement         │
│        (2 uncached Strapi GETs → cache ◆)│  │  + lifecycles.ts ◆(new)     │
│  W_KIOSK_ORDER / W_ORDER_FINALIZER ◆     │  │    audit + cache-invalidate │
│  W4_CORE → order/customer writes ◆       │  └─────────────┬──────────────┘
└───────────────┬──────────────────────────┘                │
                │                                            │
                ▼                                            ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ DATA: Postgres 15 (pgBouncer) — TWO DBs                                   │
│   n8n DB:   tenants, restaurants, api_clients ◆(channel cols), orders ◆,  │
│             customers ◆, security_events, entitlement_audit_log ◆(writers)│
│   strapi DB: product_modules, tenant_entitlements (+ uq_tenant_module ◆)  │
│ Redis 7: Bull queue · ralphe:dedupe/outbox · ralphe:entitlement:* ◆(new)  │
└──────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities (after v2.0)

| Component | Responsibility | Implementation (file) |
|-----------|----------------|------------------------|
| Inbound adapter auth node | Derive **real** `tenant_id`/`restaurant_id` from channel identity, not `DEFAULT_TENANT_ID` | `B0 - Apply Auth Context` in `workflows/W1_IN_WA.json`, `workflows/W2_IN_IG.json`, `workflows/W3_IN_MSG.json`, `workflows/W1_IN_TIKTOK.json` |
| Channel→tenant map | Map WABA `phone_number_id` / page `recipient_id` / kiosk device → `(tenant_id, restaurant_id)` | **new** table `channel_identities` in `db/` (n8n DB) |
| Module guard | Fail-closed entitlement decision, now Redis-cached | `workflows/W0_MODULE_GUARD.json` |
| Cache | `ralphe:entitlement:<tenant>:<module>` 300s TTL | Redis 7 (`W0_REDIS_HELPER.json` patterns) |
| Entitlement side-effects | On entitlement create/update/delete: write `entitlement_audit_log` **and** bust cache | **new** `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/lifecycles.ts` |
| Data scoping | `WHERE tenant_id = $ctx` on order/customer reads & writes | `workflows/W4_CORE.json`, `W4.1_ROUTER.json`, `W_KIOSK_ORDER.json`, `W_ORDER_FINALIZER.json`, `inventory-cms/src/api/order/content-types/order/lifecycles.ts` |
| UI gate | Fail-**closed**, typed, aligned module keys | `admin-dashboard/src/hooks/useEntitlements.ts`, `admin-dashboard/src/App.tsx` |

---

## Where `tenant_id` Originates Per Channel (the crux)

The inbound adapters **already parse the channel-native tenant signal** — it is captured in the canonical envelope's `meta` block and then *discarded* at auth time. Real resolution means routing that signal through a lookup instead of falling back to `DEFAULT_TENANT_ID`.

| Channel | Native tenant key | Where it is parsed today | Currently used for tenant? |
|---------|-------------------|--------------------------|----------------------------|
| **WhatsApp** | WABA **`phone_number_id`** (`value.metadata.phone_number_id`) | `workflows/W1_IN_WA.json`, `B0 - Parse & Canonicalize` → `meta.phone_number_id` (+ `display_phone_number`) | **No** — falls to `meta_signature` → `DEFAULT_TENANT_ID` |
| **Instagram** | IG **page/recipient id** (`messaging.recipient.id`) | `workflows/W2_IN_IG.json`, parser → `meta.recipient_id` | **No** — same fallback |
| **Messenger** | FB **page id** (`messaging.recipient.id`) | `workflows/W3_IN_MSG.json`, parser → `meta.recipient_id` | **No** — same fallback |
| **TikTok** | TikTok **business/account id** | `workflows/W1_IN_TIKTOK.json` parser | **No** — same fallback |
| **Kiosk** | **device / restaurant id** | `W_KIOSK_ORDER` passes `tenant_id || restaurant_id` to the guard (line ~39); order itself created via Strapi `/v1/strapi/api/orders` | Partial — depends on payload field, not a trusted device registry |
| **Authenticated API client** | `X-Api-Token` → `token_hash` | `B0 - Resolve Client (DB)` queries `api_clients` by `token_hash` (`db/bootstrap.sql:102`) | **Yes** — this path already returns real `tenant_id`/`restaurant_id` |

**Root cause, precisely:** In `B0 - Apply Auth Context`, the resolution ladder is:
`api_clients match` → else `meta_signature` (valid HMAC) → `DEFAULT_TENANT_ID` → else `legacy_shared` → `DEFAULT_TENANT_ID`. Meta channels are **token-exempt** (Meta sends no custom header), so they *always* land in the `meta_signature` branch and get the global default. `DEFAULT_TENANT_ID` is also unset in `docker-compose.hostinger.prod.yml`, so even the default collapses to `''`/`'default'`.

**The fix is a single new resolution rung** inserted *before* the `meta_signature` default: look up the parsed channel identity (`meta.phone_number_id` for WA, `meta.recipient_id` for IG/MSG) in a `channel_identities` table → real `(tenant_id, restaurant_id)`. The HMAC seal (`B0 - Seal Tenant Context`, `TENANT_CONTEXT_SECRET`) then carries the *real* tenant downstream exactly as it does today — no change to the seal mechanism.

---

## Recommended Project Structure (new + modified)

```
db/
├── migrations/
│   ├── 2026-06-2x_channel_identities.sql        # NEW: channel→tenant routing table + seed
│   ├── 2026-06-2x_tenant_scoping_indexes.sql    # NEW: orders/customers tenant_id cols+indexes
│   └── 2026-04-06_saas_modules_entitlements.sql # EXISTING: APPLY on VPS (uq_tenant_module, audit table)
inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/
└── lifecycles.ts                                # NEW: write entitlement_audit_log + bust Redis cache
inventory-cms/src/api/product-module/content-types/product-module/
└── lifecycles.ts                                # NEW (optional): bust cache on global-enable change
workflows/
├── W0_MODULE_GUARD.json                         # MODIFY: Redis cache-aside, keep fail-closed
├── W1_IN_WA.json / W2_IN_IG.json / W3_IN_MSG.json / W1_IN_TIKTOK.json  # MODIFY: resolution rung
├── W_KIOSK_ORDER.json / W_ORDER_FINALIZER.json  # MODIFY: trusted device→tenant, scope writes
└── W4_CORE.json / W4.1_ROUTER.json              # MODIFY: tenant-scoped order/customer queries
admin-dashboard/src/
├── hooks/useEntitlements.ts                     # MODIFY: fail-CLOSED, typed, remove `any`
└── App.tsx                                       # MODIFY: align nav module-keys to seeder
config/
└── product_modules.json                          # REFERENCE: module-key source of truth (align)
```

### Structure Rationale

- **`channel_identities` in the n8n DB (not strapi):** tenant resolution happens inside n8n adapters that already hold a `postgres-main` credential to the **n8n DB** (where `tenants`/`restaurants`/`api_clients` already live, `db/bootstrap.sql:48-114`). Putting the routing table there avoids a cross-DB hop and reuses the existing FK graph (`REFERENCES tenants(tenant_id)`).
- **`lifecycles.ts` on the Strapi content type:** entitlement rows are owned by Strapi; the *only* in-transaction place to observe a create/update/delete is the content-type lifecycle hook. There is currently **no** `lifecycles.ts` for `tenant-entitlement` or `product-module` (only `schema.json`) — so both the missing audit writers and the cache-invalidation signal land here.
- **Guard cache keyed `tenant:module`:** matches the entitlement grain and the suggested 5-min TTL from `CONCERNS.md`.

---

## Architectural Patterns

### Pattern 1: Channel-Identity Tenant Resolution (rung in the auth ladder)

**What:** Insert a DB lookup between "api_client match" and "meta_signature default" in `B0 - Apply Auth Context`. Key the lookup on the already-parsed channel identity.
**When:** Every Meta/TikTok inbound message (token-exempt channels).
**Trade-offs:** Adds one indexed PK lookup (sub-ms, same DB, same credential) but removes the single-tenant collapse. Must fail-**closed**: an unmapped `phone_number_id` should deny (security_events: `UNKNOWN_CHANNEL_IDENTITY`), not silently default.

```sql
-- channel_identities (n8n DB) — the routing table the system is missing
CREATE TABLE IF NOT EXISTS channel_identities (
  channel        text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok','kiosk')),
  identity       text NOT NULL,           -- WA phone_number_id | IG/MSG page recipient.id | kiosk device_id
  tenant_id      uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id  uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  is_active      boolean NOT NULL DEFAULT true,
  PRIMARY KEY (channel, identity)
);
```

```js
// new rung inside B0 - Apply Auth Context (pseudo): runs after api_clients miss, before meta default
// identity already in envelope: meta.phone_number_id (WA) | meta.recipient_id (IG/MSG)
const ci = await resolveChannelIdentity(channel, identity); // SELECT ... WHERE channel=$1 AND identity=$2 AND is_active
if (metaSigValid && ci) { tenantId = ci.tenant_id; restaurantId = ci.restaurant_id; authMode = 'channel_identity'; }
else if (metaSigValid && !ci) { authMode = 'deny'; denyReason = 'UNKNOWN_CHANNEL_IDENTITY'; } // fail-closed
```

### Pattern 2: Cache-Aside Fail-Closed Guard (Redis in front of Strapi)

**What:** `W0_MODULE_GUARD` reads `ralphe:entitlement:<tenant>:<module>` first; on miss it does the existing two Strapi GETs, then `SET ... EX 300`. **Negative results are also cached** (a `{allowed:false}` decision) to protect the guard under denial floods — but with a *shorter* TTL so a freshly-granted entitlement appears quickly.
**When:** Every gated entrypoint (8 workflows invoke the guard).
**Trade-offs:** Removes the 2 uncached Strapi round-trips per inbound message (the documented P1 latency that erodes Meta's <5s budget). Must preserve fail-closed: **a Redis error is not a grant** — on cache read error, fall through to Strapi; on Strapi error, deny (`GUARD_ERROR_FAILCLOSED`). Stale-but-bounded: cache invalidation (Pattern 3) makes the TTL a safety net, not the primary correctness mechanism.

```js
// W0_MODULE_GUARD cache-aside skeleton (keep existing Strapi logic as the miss path)
const key = `ralphe:entitlement:${tenantId}:${moduleKey}`;
const cached = await redisGet(key);                 // never throws fatally; on error → cached=null
if (cached) return [{ json: JSON.parse(cached) }];  // HIT (could be allow OR cached deny)
const decision = await queryStrapiAndDecide();      // existing 2-GET logic, unchanged, still fail-closed
if (!decision.reason?.startsWith('GUARD_ERROR'))    // do not cache transient guard errors
  await redisSet(key, JSON.stringify(decision), decision.allowed ? 300 : 60);
return [{ json: decision }];
```

### Pattern 3: Lifecycle-Driven Audit + Cache Invalidation (write path)

**What:** A new `tenant-entitlement/lifecycles.ts` runs on `afterCreate`/`afterUpdate`/`afterDelete`: (a) INSERT into `entitlement_audit_log` (the dead table from `2026-04-06_saas_modules_entitlements.sql` finally gets writers), (b) `DEL ralphe:entitlement:<tenant>:<module>` so the next guard call re-reads truth.
**When:** Any entitlement mutation — admin SPA edit via `/v1/portal/*`, the bootstrap seeder, or a manual Strapi admin edit. The lifecycle hook is the **one** place that catches all three.
**Trade-offs:** Couples Strapi to Redis (Strapi already holds a Redis connection for SSE `order_updates` in `inventory-cms/src/index.ts`, so no new dependency). If Redis DEL fails, the 300s TTL still bounds staleness — acceptable degradation, not a correctness break.

```ts
// inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/lifecycles.ts
export default {
  async afterUpdate(event) {
    const { tenant_id, module_key } = event.result;
    await writeEntitlementAudit({ tenant_id, module_key, action: 'config_changed', new_value: event.result });
    await redis.del(`ralphe:entitlement:${tenant_id}:${module_key}`); // bust guard cache
  },
  // afterCreate → action:'enabled'; afterDelete → action:'disabled'
};
```

---

## Data Flow

### Inbound (after v2.0) — real tenant from channel identity, cached guard

```
Meta POST /v1/inbound/whatsapp
   ↓ (Traefik → nginx meta_inbound zone → n8n)
W1_IN_WA · B0 Parse&Canonicalize  → envelope.meta.phone_number_id   [parsed today]
   ↓
B0 Resolve Client (api_clients by token_hash)  → miss (Meta is token-exempt)
   ↓
B0 Apply Auth Context · NEW RUNG: channel_identities[whatsapp, phone_number_id]
   → real (tenant_id, restaurant_id)   |   unmapped → DENY (security_events)
   ↓
B0 Seal Tenant Context (HMAC, unchanged) — now seals the REAL tenant
   ↓
B0 Module Guard → W0_MODULE_GUARD
   → Redis GET ralphe:entitlement:<tenant>:channel_whatsapp
      HIT → decision      |      MISS → 2× Strapi GET → SET EX 300
   ↓ allowed
W4_CORE / W4.1_ROUTER → order & customer queries SCOPED by tenant_id
```

### Entitlement change → cache invalidation path

```
Admin SPA edits entitlement → /v1/portal/* → Strapi tenant_entitlements UPDATE
   ↓ (in-transaction)
tenant-entitlement/lifecycles.ts · afterUpdate
   ├─ INSERT entitlement_audit_log (tenant_id, module_key, action, old/new, changed_by)
   └─ Redis DEL ralphe:entitlement:<tenant>:<module>
        ↓
next W0_MODULE_GUARD call for that pair → cache MISS → re-reads Strapi → fresh decision
```

### UI gate (after v2.0) — fail-closed, key-aligned

```
useEntitlements() → Strapi product-modules + tenant-entitlements (this tenant)
   loading|error → hasModule() returns FALSE (was: returns true)   ← security fix
   App.tsx nav: hasModule('addon_kitchen_display' …) keys MATCH seeder SAAS_MODULES keys
```

---

## Build Order (honors dependencies)

The ordering is dictated by hard prerequisites: you cannot cache or audit entitlements whose DB constraints aren't applied; you cannot scope data before you can resolve a real tenant; you should not flip the UI to fail-closed until the backend actually returns correct entitlements.

| Step | Work | Why this order |
|------|------|----------------|
| **0. Pre-req: apply migrations on VPS** | Apply `db/migrations/2026-04-06_saas_modules_entitlements.sql` (uq_tenant_module, indexes, `entitlement_audit_log`); provision `STRAPI_API_TOKEN_INTERNAL` + `DEFAULT_TENANT_ID` | Everything else assumes the constraint + audit table + guard token exist. The repo↔VPS schema-drift gap (`CONCERNS.md` P0) blocks all SaaS work until closed. |
| **1. Channel routing table + seed** | New `channel_identities` migration; seed the live tenant's WABA `phone_number_id` + page ids | Tenant resolution (step 2) needs the lookup target to exist. Pure additive DB change, zero runtime impact. |
| **2. Real tenant resolution rung** | Add `channel_identities` lookup to `B0 - Apply Auth Context` in `W1_IN_WA`/`W2_IN_IG`/`W3_IN_MSG`/`W1_IN_TIKTOK`; fail-closed on unmapped identity; trusted device→tenant for `W_KIOSK_ORDER` | Must precede data scoping — scoping needs a correct `tenant_id`. Backward-compatible: existing single tenant maps its own ids, behaviour unchanged for it. |
| **3. Per-tenant data scoping** | Add `tenant_id` columns/indexes to orders/customers (migration); add `WHERE tenant_id` to reads/writes in `W4_CORE`/`W4.1_ROUTER`/`W_KIOSK_ORDER`/`W_ORDER_FINALIZER` and `order/lifecycles.ts` | Depends on real tenant (step 2). Backfill existing rows to the default tenant before enforcing NOT NULL. |
| **4. Entitlement audit + cache-invalidation hook** | New `tenant-entitlement/lifecycles.ts`: write `entitlement_audit_log` + Redis DEL | Must exist **before** caching (step 5) so the cache is never stale-forever. Audit alone is also valuable independently. |
| **5. Redis-cached guard** | Add cache-aside to `W0_MODULE_GUARD`; keep fail-closed; cache positive (300s) + negative (60s) | Depends on step 4 (invalidation) to be safe. Delivers the P1 latency win (removes 2 Strapi GETs/message). |
| **6. UI fail-closed + key alignment + type debt** | `useEntitlements.ts` → default `false` on loading/error, typed interfaces, remove `any`; align `App.tsx` nav keys to `SAAS_MODULES` | Do **after** backend (steps 2–5) returns correct entitlements, otherwise flipping to fail-closed would hide modules the tenant legitimately has while the backend is still wrong. Lowest blast radius last. |

**Critical sequencing rule:** never enable the cache (5) before invalidation (4); never flip the UI to fail-closed (6) before resolution+scoping (2–3) are correct. Steps 1 and 4 are independently shippable and safe to land early.

---

## Anti-Patterns

### Anti-Pattern 1: Trusting payload-supplied tenant hints
**What people do:** Resolve tenant from `body.tenant_id` / `tenant_hint`.
**Why it's wrong:** The adapters explicitly mark these `source: 'untrusted_payload'` and "NEVER trusted" — a caller could impersonate any tenant.
**Do this instead:** Resolve only from server-observed identity: `api_clients.token_hash`, HMAC-verified `phone_number_id`/`recipient_id` via `channel_identities`, or a trusted kiosk device registry. Keep the existing `tenant_context` HMAC seal.

### Anti-Pattern 2: Treating a cache/Redis error as "allowed"
**What people do:** `if (cacheError) proceed()` to avoid dropping messages.
**Why it's wrong:** Converts an infra blip into an entitlement bypass — the exact inconsistency the audit flags (UI fails open, guard fails closed). Redis is a *performance* layer, not the source of truth.
**Do this instead:** On Redis read error → fall through to Strapi (still authoritative, still fail-closed). On Strapi error → deny (`GUARD_ERROR_FAILCLOSED`). Never cache a transient guard error.

### Anti-Pattern 3: Defaulting unmapped channel identities to `DEFAULT_TENANT_ID`
**What people do:** Keep the `meta_signature → DEFAULT_TENANT_ID` fallback "just in case."
**Why it's wrong:** Re-introduces the single-tenant collapse and lets a second tenant's traffic be processed as the first.
**Do this instead:** Unmapped identity = deny + `security_events` UNKNOWN_CHANNEL_IDENTITY. `DEFAULT_TENANT_ID` is only legitimate for an explicitly single-tenant deployment flag, not as a silent fallback.

### Anti-Pattern 4: Module-key drift across the three sources
**What people do:** Add a nav key in `App.tsx` or a workflow `module_key` without updating the seeder.
**Why it's wrong:** Keys must match exactly across `App.tsx`, `workflows/*` guard calls, `config/product_modules.json`, and `SAAS_MODULES` in `saas-entitlements.ts`; a mismatch silently denies (`NO_ENTITLEMENT`). `App.tsx` already gates on `addon_kitchen_display`, `addon_analytics`, `experimental_growth_agent` — verify each exists in the seeder.
**Do this instead:** Add a CI check that every `module_key` referenced in `workflows/` and `App.tsx` exists in `SAAS_MODULES`.

---

## Integration Points

### Modified Components

| File | Change | Type |
|------|--------|------|
| `workflows/W1_IN_WA.json` (`B0 - Apply Auth Context`) | Add `channel_identities` resolution rung keyed on `meta.phone_number_id` | MODIFY |
| `workflows/W2_IN_IG.json`, `W3_IN_MSG.json` (`B0 - Apply Auth Context`) | Same, keyed on `meta.recipient_id` (page id) | MODIFY |
| `workflows/W1_IN_TIKTOK.json` | Same, keyed on TikTok account id | MODIFY |
| `workflows/W0_MODULE_GUARD.json` | Redis cache-aside; keep fail-closed; negative-cache short TTL | MODIFY |
| `workflows/W_KIOSK_ORDER.json`, `W_ORDER_FINALIZER.json` | Trusted device→tenant; tenant-scoped writes | MODIFY |
| `workflows/W4_CORE.json`, `W4.1_ROUTER.json` | `WHERE tenant_id` on order/customer queries | MODIFY |
| `inventory-cms/src/api/order/content-types/order/lifecycles.ts` | Stamp/scope `tenant_id` on order side-effects | MODIFY |
| `admin-dashboard/src/hooks/useEntitlements.ts` | Fail-closed default; typed interfaces; remove 6× `any` | MODIFY |
| `admin-dashboard/src/App.tsx` | Align nav `hasModule(...)` keys to `SAAS_MODULES` | MODIFY |
| `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` | Optionally seed `channel_identities` for default tenant | MODIFY |

### New Components

| File | Purpose | Type |
|------|---------|------|
| `db/migrations/2026-06-2x_channel_identities.sql` | Channel→tenant routing table + seed for live tenant | NEW |
| `db/migrations/2026-06-2x_tenant_scoping.sql` | `tenant_id` cols + indexes on orders/customers; backfill | NEW |
| `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/lifecycles.ts` | Write `entitlement_audit_log` + bust Redis cache | NEW |
| `inventory-cms/src/api/product-module/content-types/product-module/lifecycles.ts` | (Optional) bust cache on `enabled_globally` change | NEW |

### External / Infra Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| n8n adapter ↔ n8n DB | `postgres-main` credential (existing) | `channel_identities` lives in n8n DB next to `tenants`/`api_clients` — no new credential |
| W0_MODULE_GUARD ↔ Redis | n8n Redis credential (`REDIS_CREDENTIAL_ID`) | Same Redis as dedupe/outbox; new namespace `ralphe:entitlement:*`. NB: this credential indirection is a known fragility (`CONCERNS.md`) — verify it resolves before relying on the cache |
| W0_MODULE_GUARD ↔ Strapi | `STRAPI_API_TOKEN_INTERNAL` (the guard's miss path) | Must be provisioned (currently unconfirmed; a missing token = total fail-closed outage) |
| Strapi lifecycle ↔ Redis | `ioredis` (already present for SSE `order_updates`) | Reuse existing Redis connection in `inventory-cms/src/index.ts`; no new dependency |
| Admin SPA ↔ Strapi | JWT via `/v1/portal/*` | Entitlement edits flow through here and trigger the lifecycle hook |

### Cache-Invalidation Path (summary)

```
Mutation source            →  Catch point (always)                         →  Effect
admin SPA /v1/portal edit  →  tenant-entitlement/lifecycles.ts afterUpdate →  DEL ralphe:entitlement:<t>:<m> + audit row
Strapi admin manual edit   →  same lifecycle hook                          →  same
bootstrap seeder           →  afterCreate                                  →  audit row (cache cold anyway)
TTL expiry                 →  300s positive / 60s negative                 →  safety net if DEL missed
```

---

## Scaling Considerations

| Scale | Adjustment |
|-------|------------|
| 1 tenant (today) | Map the one tenant's `phone_number_id`/page ids into `channel_identities`; behaviour identical to current, now correct-by-construction |
| 2–50 tenants | Cache is the load lever: 300s TTL collapses N inbound messages/tenant into ~1 Strapi read per 5 min per (tenant,module). `idx_entitlements_tenant`/`idx_entitlements_active` (from the SaaS migration) keep miss-path GETs fast |
| 50+ tenants | Per-tenant order/customer indexes on `tenant_id` become essential; consider Postgres partial indexes or partitioning by `tenant_id`; raise n8n worker concurrency (single worker is a pre-existing P2 limit) |

### Scaling Priorities
1. **First bottleneck (today):** the 2 uncached Strapi GETs per inbound message — fixed by Pattern 2.
2. **Second bottleneck:** unscoped order/customer table scans once multiple tenants share the table — fixed by `tenant_id` indexes (step 3) before onboarding tenant #2.

---

## Confidence Assessment

| Area | Confidence | Basis |
|------|------------|-------|
| Tenant-id origin per channel | HIGH | Read parsers directly: `W1_IN_WA.json` `meta.phone_number_id`, `W2_IN_IG.json` `meta.recipient_id` |
| Resolution insertion point | HIGH | `B0 - Apply Auth Context` node read in full; ladder logic explicit |
| Existing tenant/api_clients tables | HIGH | `db/bootstrap.sql:48-114` (tenants, restaurants, api_clients with tenant_id FKs) |
| Missing lifecycle hooks | HIGH | Directory listing confirms only `schema.json` for both SaaS content types |
| Cache primitives available | HIGH | Redis already used for dedupe/outbox; `W0_REDIS_HELPER.json` present; Strapi already holds a Redis conn for SSE |
| Build order | MEDIUM-HIGH | Derived from explicit data dependencies; exact n8n node wiring for scoping queries needs phase-level inspection of `W4_CORE`/`W4.1_ROUTER` |

## Open Questions (for phase-level research)

- Exact order/customer SQL nodes inside `W4_CORE.json` / `W4.1_ROUTER.json` that need `tenant_id` predicates (not enumerated here — both are large).
- Whether kiosk should resolve tenant from a signed device token vs. a `channel_identities` device row (security model for unauthenticated kiosk POST `/v1/strapi/api/orders`).
- Whether `entitlement_audit_log` should live in the n8n DB (where the SaaS migration creates it) while the writer is a Strapi lifecycle hook bound to the **strapi** DB — this is a **cross-DB write** that needs an explicit connection (the guard already crosses n8n→Strapi over HTTP; the audit writer may need the same, or the table should move to the strapi DB).

---
*Architecture research for: SaaS multi-tenant hardening of a live n8n/Strapi ordering platform*
*Researched: 2026-06-20*
