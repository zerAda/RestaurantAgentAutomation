# Feature Research

**Domain:** Multi-tenant SaaS hardening for a single-operator, multi-restaurant conversational-commerce platform (RESTO BOT — Strapi 5 CMS + n8n 2.9.4 + Postgres/Redis)
**Researched:** 2026-06-20
**Confidence:** HIGH (codebase-grounded) / MEDIUM (industry patterns)

> Scope note: This milestone (v2.0) is **hardening the existing scaffolding**, not greenfield. Every recommendation below is anchored to a real file/constraint in the repo. The business model is **single operator running multiple restaurants** (not a public self-serve SaaS with adversarial tenants), which materially changes what is table-stakes vs anti-feature. See `.planning/PROJECT.md:13-27` and `.planning/codebase/CONCERNS.md:101-138`.

---

## Existing-System Baseline (what already exists, so we don't re-invent)

| Capability | State | Evidence |
|------------|-------|----------|
| `tenant_id` / `restaurant_id` columns on data tables (UUID) | EXISTS — already in `restaurant_users`, `faq_entries`, `outbound_messages`, `security_events`, `api_clients` | `workflows/W4_CORE.json:52,236,360,503` |
| HMAC-sealed `tenant_context` envelope passed between workflows | EXISTS — `TENANT_CONTEXT_SECRET` seal verified, throws `TENANT_CONTEXT_TAMPERED` | `workflows/W4_CORE.json:38` |
| Token→tenant mapping for authenticated API clients | EXISTS — `api_clients.token_hash → tenant_id, restaurant_id` lookup | `workflows/W1_IN_WA.json:132` |
| Inbound adapter captures `phone_number_id` from Meta payload | EXISTS but UNUSED for tenant — captured in `meta.phone_number_id`, then `tenantId` is hard-set to `''` | `workflows/W1_IN_WA.json:31` (parse node) |
| Module/entitlement gate (`W0_MODULE_GUARD`) | EXISTS — fail-closed, reads `data[0]` | `workflows/W0_MODULE_GUARD.json:15` |
| Strapi content types `product-modules` + `tenant-entitlements` | EXISTS — seeded by bootstrap | `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts:17-124` |
| DB constraints + `entitlement_audit_log` table | EXISTS in migration, **not applied to VPS, zero writers** | `db/migrations/2026-04-06_saas_modules_entitlements.sql:45-57` |
| Admin UI entitlement hook | EXISTS — fails **open** | `admin-dashboard/src/hooks/useEntitlements.ts:52-55` |

**Key insight:** The data plane is already multi-tenant-shaped (pooled `tenant_id` model — the industry-standard starting point). The gap is **resolution** (deriving a real tenant), **scoping enforcement** (queries actually filtering by it), and **semantic consistency** (UI vs guard). This is a "close the last mile" milestone, not a "build the model" one.

---

## Feature Landscape

### Table Stakes (Required for v2.0 — onboarding a 2nd restaurant is unsafe without these)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Tenant resolution from channel identity** | Every inbound message must map to the correct restaurant; today everything resolves to literal `'default'` | MEDIUM | Map `meta.phone_number_id` (WA), `IG_PAGE_ID`, `MSG_PAGE_ID` → `tenant_id`/`restaurant_id` via a Strapi `restaurant-brand`/channel-registry lookup. `phone_number_id` is already parsed (`workflows/W1_IN_WA.json:31`) but discarded. Industry-standard: derive tenant from a trusted request property, never from untrusted body hints — the adapter correctly tags body hints `source: 'untrusted_payload'` already. |
| **Tenant-scoped order/customer queries** | A second restaurant's operator must never see another's orders/customers | MEDIUM | Columns already exist; the work is ensuring **every** read/write carries `WHERE tenant_id = $1`. Pooled-model risk: "one missed WHERE clause = data leak." Inventory existing queries; add the missing filters. `W4_CORE` already does this correctly for FAQ/state — use it as the reference pattern. |
| **Consistent fail-closed entitlement semantics (UI ↔ guard)** | UI shows modules a tenant isn't entitled to (fail-open) while backend denies (fail-closed) — confusing and a latent over-grant | LOW | Change `useEntitlements.hasModule()` to default **false** on loading/error (`admin-dashboard/src/hooks/useEntitlements.ts:52-55`), surface an explicit error state. Keep a small `shared_core` allowlist so the shell never hard-bricks. Aligns UI with `W0_MODULE_GUARD`'s `GUARD_ERROR_FAILCLOSED`. |
| **Module-key alignment across all sources** | A drifted key silently denies a whole channel (`NO_ENTITLEMENT`) | LOW | `App.tsx:162,171,174` references `addon_kitchen_display`, `addon_analytics`, `experimental_growth_agent` — **none exist** in the seeder (`saas-entitlements.ts`) or `config/product_modules.json` (which use `kiosk_instore`, `growth_marketing`, etc.). Pick one canonical key set, align all three sources, add a CI check (`CONCERNS.md:160-164`). |
| **Apply SaaS DB constraints to VPS** | Without `uq_tenant_module`, duplicate entitlement rows accumulate; `data[0]` reads mask them | LOW | Apply `db/migrations/2026-04-06_saas_modules_entitlements.sql` to the VPS; add a CD migration-apply step (root cause of repo↔VPS drift, `CONCERNS.md:143-147`). |
| **Entitlement change auditing (wire the writers)** | The audit table exists with **zero writers** — dead schema; no record of who enabled/disabled what | MEDIUM | Wire `entitlement_audit_log` INSERTs on entitlement create/disable/expire/config-change from the seeder and any admin entitlement mutation (`CONCERNS.md:29-30`). Capture `tenant_id, module_key, action, changed_by, old_value, new_value`. |
| **Provision `STRAPI_API_TOKEN_INTERNAL`** | If unset, the guard fail-closes on **every** inbound → total outage across 8 entrypoints | LOW | Provision the token in n8n env; add a distinct alert for `GUARD_ERROR_FAILCLOSED` vs legitimate `NO_ENTITLEMENT` so a missing token pages instead of silently dropping all orders (`CONCERNS.md:111-114`). |
| **Redis-cached entitlement lookups** | Guard adds 2 uncached synchronous Strapi round-trips per message; erodes Meta's <5s webhook budget | MEDIUM | Cache `tenant_id:module_key → {allowed, config_overrides}` in Redis (~5-min TTL); invalidate on entitlement change. `W0_REDIS_HELPER` already exists in `platform_runtime`. Strapi cold-start is 3-8min, so reducing Strapi load also helps (`CONCERNS.md:123-137`). |

### Differentiators (Worth doing — leverage existing platform strengths)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Cache invalidation on entitlement change (not just TTL)** | Operator enabling a module sees it live in seconds, not after a 5-min wait — clean operator UX | MEDIUM | Couple to the audit-writer hook: same event that writes `entitlement_audit_log` also `DEL`s the Redis key. Turns the audit hook into a dual-purpose integrity point. |
| **`GUARD_ERROR_FAILCLOSED` vs `NO_ENTITLEMENT` alerting split** | Distinguishes "infra is broken, page someone" from "tenant legitimately not entitled" — prevents a missing secret from masquerading as normal denials | LOW | Route the two reasons to different severities. Reuses existing alert plumbing. High operational value given the 8-entrypoint blast radius. |
| **`config_overrides` per tenant** | Already in the data model and guard output — lets one restaurant override config (e.g. delivery fee base) without code changes | LOW-MEDIUM | `W0_MODULE_GUARD` already returns `config_overrides` from `tenant-entitlements`; mostly a matter of consuming it downstream. Genuinely useful for a multi-restaurant operator. |
| **Channel-registry content type in Strapi** | One admin-editable mapping of `phone_number_id`/`page_id` → restaurant; operator onboards a new restaurant without redeploying | MEDIUM | Makes tenant resolution data-driven (Strapi is the config hub per `PROJECT.md:99`). Avoids hard-coding the mapping in env or workflow JSON. |
| **CI guardrails for module-key + credential-ref drift** | Prevents the exact regressions that already happened (commit `206da76` was a key-alignment fix) | LOW | Lint: every `module_key` in `workflows/` exists in seed list; reject `id: "={{$env...}}"` credential expressions (`CONCERNS.md:149-164`). |

### Anti-Features (Deliberately do NOT build — wrong for a single-operator-multi-restaurant model)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Per-tenant database / schema-per-tenant isolation** | "Real" SaaS isolation; strongest blast-radius containment | Massive operational cost on a 2-CPU / ~4GB / 119GB single VPS with no swap (`CONCERNS.md:170-179`); Strapi cold-start is already 3-8min per instance. The operator is a single trusted party, not adversarial tenants. | Keep the **pooled `tenant_id` model** that already exists — it's the recommended starting point for exactly this scale. |
| **Postgres Row-Level Security (RLS) policies** | Push tenant filtering into the DB engine; eliminate "missed WHERE clause" leaks | n8n issues raw parameterized SQL via shared credentials; RLS needs per-request `SET app.tenant_id` session context that n8n's pooled connections don't cleanly provide. High complexity, fragile with queue-mode workers. | Centralize tenant scoping in the **`tenant_context` resolver + a query-builder convention**; add the CI/test that asserts tenant-scoped queries. Revisit RLS only if a true adversarial-tenant model emerges. |
| **Full self-serve tenant signup / billing / subscription tiers** | It's "SaaS," so build the storefront | No external customers — the operator provisions restaurants manually. Building Stripe-style metered billing, signup funnels, and plan tiers is pure scope creep. | Operator-provisioned entitlements via Strapi admin + the seeder. `rollout_policy` field already models tiers without a billing engine. |
| **Per-end-user RBAC / fine-grained roles inside a tenant** | "Multi-tenant needs RBAC" | The end users are restaurant **customers** on WhatsApp/IG — they have no accounts or roles. Admins are already gated by `isFullAdmin` (`App.tsx:169`). Adding ABAC/RBAC layers solves a problem this domain doesn't have. | Keep the existing two-tier `customer` vs admin (`isFullAdmin`) split; entitlements gate **modules**, not user-level permissions. |
| **Tenant resolution from untrusted message body hints** | Convenient — the body already carries `tenant_hint`/`restaurant_hint` | Spoofable; would let a crafted payload claim another tenant's identity. The adapter already correctly tags these `source: 'untrusted_payload'`. | Resolve **only** from the trusted channel identity (`phone_number_id`/`page_id`), exactly as planned. Hints stay advisory/diagnostic. |
| **Distributed cache cluster / external feature-flag SaaS (LaunchDarkly/Unleash)** | "Use a real entitlements platform" | Adds a third-party dependency and network hop to a self-contained VPS stack; the entitlement set is tiny (14 modules) and changes rarely. | Redis (already deployed, `allkeys-lru`) with a short TTL + explicit invalidation is sufficient and keeps the stack self-contained. |
| **Fail-OPEN entitlement checks "for availability"** | General feature-flag guidance favors availability over consistency when the flag service is down | These gate **paid channel access and data boundaries**, not cosmetic UI experiments. Fail-open here = unauthorized module/data exposure. The guard already fail-closes; the UI must match. | Fail-**closed** for both layers, with a tiny hard-coded `shared_core`/`platform_runtime` allowlist so the app shell never fully bricks. |

---

## Feature Dependencies

```
Apply SaaS DB migration to VPS (uq_tenant_module, entitlement_audit_log)
    └──required-by──> Entitlement change auditing (writers need the table)
    └──required-by──> Cache invalidation on change (audit hook = invalidation hook)

Provision STRAPI_API_TOKEN_INTERNAL
    └──required-by──> W0_MODULE_GUARD working at all (else total fail-closed outage)
        └──required-by──> Redis-cached entitlement lookups (cache wraps the guard call)

Channel-registry mapping (phone_number_id/page_id -> tenant/restaurant)
    └──required-by──> Tenant resolution from channel identity
        └──required-by──> Tenant-scoped order/customer queries (need a real tenant_id)

Module-key alignment (App.tsx <-> seeder <-> config/product_modules.json)
    └──enhances──> Consistent fail-closed UI (keys must be right before fail-closed UI is safe)

Entitlement change auditing ──pairs-with──> Cache invalidation (same event)
Fail-OPEN UI ──conflicts──> Fail-CLOSED guard (must be reconciled to fail-closed)
```

### Dependency Notes

- **Auditing requires the migration:** `entitlement_audit_log` is created by `db/migrations/2026-04-06_saas_modules_entitlements.sql:45`; writers cannot be wired until it exists on the VPS — and it currently isn't (`CONCERNS.md:26-30`).
- **Caching wraps a working guard:** Caching is meaningless until `STRAPI_API_TOKEN_INTERNAL` is provisioned and the guard reliably returns real results (`CONCERNS.md:111-114`).
- **Scoping requires resolution:** Tenant-scoped queries are pointless while every request resolves to `'default'`; resolution (channel-registry) must land first (`CONCERNS.md:101-104`).
- **Module-key alignment gates fail-closed UI:** If you flip the UI to fail-closed while `App.tsx` keys are wrong, real modules disappear from nav. Align keys first (`App.tsx:162,171,174` vs `saas-entitlements.ts:17-124`).
- **Auditing and invalidation are the same hook:** Both fire on entitlement create/disable/expire — implement once, emit both side effects.

## MVP Definition

### Launch With (v2.0 core — makes onboarding a 2nd restaurant safe)

- [ ] Tenant resolution from `phone_number_id`/`page_id` via channel-registry — replaces literal `'default'` (`W0_MODULE_GUARD.json:15`, `saas-entitlements.ts:127`)
- [ ] Tenant-scoped order/customer queries — close every missing `WHERE tenant_id`
- [ ] UI fail-closed parity (`useEntitlements.ts:52-55` → default false + error state)
- [ ] Module-key alignment across `App.tsx` / seeder / `config/product_modules.json` + CI check
- [ ] Apply SaaS migration on VPS + CD migration-apply step
- [ ] `entitlement_audit_log` writers wired
- [ ] `STRAPI_API_TOKEN_INTERNAL` provisioned + `GUARD_ERROR_FAILCLOSED` alert

### Add After Validation (v2.x)

- [ ] Redis-cached entitlement lookups w/ invalidation — trigger: guard P95 latency instrumented and shown to erode Meta budget (`CONCERNS.md:123-128`)
- [ ] `config_overrides` consumption downstream — trigger: a 2nd restaurant needs different config
- [ ] Remove `no-explicit-any` debt in `useEntitlements.ts` — trigger: typed interfaces defined (`CONCERNS.md:38-42`)

### Future Consideration (v3+)

- [ ] Channel-registry as full Strapi content type with admin UI — trigger: operator onboards restaurants frequently enough to want self-service
- [ ] Per-tenant rate/quota limits — trigger: a noisy restaurant degrades others on shared infra

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Tenant resolution from channel identity | HIGH | MEDIUM | P1 |
| Tenant-scoped order/customer queries | HIGH | MEDIUM | P1 |
| UI fail-closed parity | MEDIUM | LOW | P1 |
| Module-key alignment + CI check | HIGH | LOW | P1 |
| Apply SaaS migration on VPS | HIGH | LOW | P1 |
| `STRAPI_API_TOKEN_INTERNAL` + alert | HIGH | LOW | P1 |
| `entitlement_audit_log` writers | MEDIUM | MEDIUM | P2 |
| Redis-cached entitlement lookups | MEDIUM | MEDIUM | P2 |
| Cache invalidation on change | MEDIUM | MEDIUM | P2 |
| `config_overrides` consumption | LOW | LOW-MEDIUM | P3 |
| `no-explicit-any` cleanup | LOW | LOW | P3 |

**Priority key:** P1 = required to safely onboard a 2nd restaurant · P2 = hardening/perf after correctness lands · P3 = polish.

## Competitor / Pattern Analysis

| Pattern | Industry default (public SaaS) | Existing in repo | Our approach (single-operator) |
|---------|-------------------------------|------------------|-------------------------------|
| Tenant identity source | JWT/OAuth claim, validated per request | HMAC-sealed `tenant_context` envelope (`W4_CORE.json:38`); token→tenant for API (`W1_IN_WA.json:132`) | Derive from trusted channel identity (`phone_number_id`); keep the HMAC seal between workflows |
| Data isolation | Pooled `tenant_id`, sometimes RLS | Pooled `tenant_id` columns already present | Pooled + enforced `WHERE` + CI/test; **no** RLS, **no** schema-per-tenant |
| Entitlement store | LaunchDarkly/Unleash/Stripe Entitlements | Strapi `tenant-entitlements` + `product-modules` | Keep Strapi as store; **no** external flag SaaS |
| Cache | SDK-local + CDN edge cache | None (uncached guard) | Redis short-TTL + explicit invalidation |
| Failure mode | Often fail-open for availability | Guard fail-closed; UI fail-open (mismatch) | Fail-closed both layers + `shared_core` allowlist |
| Change audit | Append-only audit log of entitlement mutations | Table exists, zero writers | Wire writers; reuse as cache-invalidation hook |

## Sources

- Codebase (HIGH confidence): `.planning/PROJECT.md`, `.planning/codebase/CONCERNS.md`, `workflows/W0_MODULE_GUARD.json`, `workflows/W1_IN_WA.json`, `workflows/W4_CORE.json`, `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts`, `db/migrations/2026-04-06_saas_modules_entitlements.sql`, `admin-dashboard/src/hooks/useEntitlements.ts`, `admin-dashboard/src/App.tsx`, `config/product_modules.json`
- [WorkOS — developer's guide to SaaS multi-tenant architecture](https://workos.com/blog/developers-guide-saas-multi-tenant-architecture) (MEDIUM)
- [WorkOS — how to design multi-tenant RBAC SaaS](https://workos.com/blog/how-to-design-multi-tenant-rbac-saas) (MEDIUM)
- [Security Boulevard — Tenant Isolation in Multi-Tenant Systems](https://securityboulevard.com/2025/12/tenant-isolation-in-multi-tenant-systems-architecture-identity-and-security/) (MEDIUM)
- [Redis — Data isolation in multi-tenant SaaS](https://redis.io/blog/data-isolation-multi-tenant-saas/) (MEDIUM)
- [OneUptime — Multi-tenant data isolation with Row-Level Security on Azure SQL](https://oneuptime.com/blog/post/2026-02-16-how-to-design-a-multi-tenant-data-isolation-strategy-on-azure-sql-database-using-row-level-security/view) (MEDIUM)
- [Unleash — feature flag best practices at scale](https://docs.getunleash.io/guides/best-practices-using-feature-flags-at-scale) (MEDIUM)
- [LaunchDarkly — what are feature flags](https://launchdarkly.com/blog/what-are-feature-flags/) (MEDIUM)
- [DraftKings Engineering — Mastering Feature Flags: Performance and Resilience](https://medium.com/draftkings-engineering/mastering-feature-flags-performance-and-resilience-69b7351abe56) (LOW)

---
*Feature research for: multi-tenant SaaS hardening (single-operator-multi-restaurant)*
*Researched: 2026-06-20*
