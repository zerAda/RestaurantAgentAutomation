# Pitfalls Research

**Domain:** SaaS multi-tenant hardening of a live, single-tenant-by-default restaurant automation platform (Strapi 5 + n8n 2.9.4 + Postgres 15 + Redis 7 on one Hostinger VPS)
**Researched:** 2026-06-20
**Confidence:** HIGH (grounded in the actual repo — `db/schema.sql`, `db/migrations/2026-04-06_saas_modules_entitlements.sql`, `workflows/W0_MODULE_GUARD.json`, `workflows/W1_IN_WA.json`, `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts`, `admin-dashboard/src/hooks/useEntitlements.ts`; cross-checked against `.planning/codebase/CONCERNS.md`)

> **Scope note.** `.planning/codebase/CONCERNS.md` already enumerates the *defects* (unset `DEFAULT_TENANT_ID`, UI fail-open vs guard fail-closed, unapplied migration, dead `entitlement_audit_log`, +2 Strapi round-trips). This file does **not** re-list those — it catalogues the **mistakes you can make while fixing them** on live data with a zero-downtime constraint.

> **Single most important finding (read first).** There are **two disjoint `tenant_id` systems** in the same database:
> - **Data plane** (`db/schema.sql:9-99`): `tenants.tenant_id uuid PRIMARY KEY`, and `orders.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id)`. Admin order queries are **already** tenant-scoped — `workflows/W12_ADMIN_ORDERS.json` runs `... FROM orders o WHERE o.tenant_id = $1` where `$1` is the UUID resolved from the caller's API-client token.
> - **Entitlement plane** (`db/migrations/2026-04-06_saas_modules_entitlements.sql:47`): `entitlement_audit_log.tenant_id VARCHAR(255)`, and the Strapi `tenant_entitlements.tenant_id` is the literal **string `'default'`** (`inventory-cms/src/bootstrap-seeds/saas-entitlements.ts:127`).
>
> The inbound path (`workflows/W1_IN_WA.json`) stamps **every** message with `tenantId = defaultTenantId` (the env UUID, or the all-zeros UUID `'00000000-0000-0000-0000-000000000000'` fallback) regardless of which WhatsApp number it arrived on, while the guard checks entitlements against the string `'default'`. **These two identities never reconcile.** Most pitfalls below stem from this split — fixing one plane while forgetting the other is the dominant failure mode.

---

## Critical Pitfalls

### Pitfall 1: Reconciling only one of the two `tenant_id` planes (UUID data plane vs VARCHAR entitlement plane)

**What goes wrong:**
You implement "real tenant derivation," map `phone_number_id` → a tenant, and wire it into *either* the data path (`orders.tenant_id` UUID) *or* the entitlement path (`tenant_entitlements.tenant_id` string), but not both with a consistent key. Result: tenant B's orders land under tenant B's UUID, but the module guard still evaluates entitlements for `'default'` — so tenant B inherits tenant A's enabled modules, or is denied everything. Worse: a `WHERE o.tenant_id = $1` query silently returns **zero rows** (no error) when a UUID is compared against a string, or throws `invalid input syntax for type uuid: "default"` if the string leaks into a UUID column.

**Why it happens:**
The two systems were built at different times by different mechanisms — the data plane via `db/schema.sql` (UUID FKs to `tenants`), the entitlement plane via Strapi auto-created tables seeded with a string literal. They look like "the same `tenant_id`" but are type-incompatible and have no FK between them. A dev fixing derivation naturally touches whichever plane they happened to open first.

**How to avoid:**
Decide **one canonical tenant key** first and write it down before any code. Recommended: the existing `tenants.tenant_id` UUID is canonical; the entitlement plane must store the **same UUID string**, not `'default'`. Add a single resolver (one n8n sub-workflow or one Strapi service) that takes channel identity → canonical tenant UUID, and have *both* planes call it. Add a `tenants` row for the real first restaurant and backfill its UUID into `tenant_entitlements` before flipping any derivation on.

**Warning signs:**
`WHERE o.tenant_id = $1` returns 0 rows but the order exists; Postgres logs `invalid input syntax for type uuid: "default"`; a tenant sees the right *data* but wrong *modules* (or vice-versa); grep shows `tenant_id VARCHAR` and `tenant_id uuid` in the same schema.

**Phase to address:** **Phase 1 — Tenant identity model** (must precede all derivation/scoping work). This is the keystone; sequencing it anywhere but first guarantees rework.

---

### Pitfall 2: Leaving the default-tenant fallback in the resolution path ("fail-open tenant")

**What goes wrong:**
The resolver derives a tenant from `phone_number_id` but keeps `|| $env.DEFAULT_TENANT_ID || 'default'` (the exact pattern in `workflows/W0_MODULE_GUARD.json` line 15 and `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts:127`). When derivation fails — unknown number, typo'd mapping, new WABA not yet onboarded — the message silently routes to the **default tenant** instead of being rejected. Tenant B's customer message gets processed as tenant A, written to tenant A's orders, and answered with tenant A's menu/prices. This is **cross-tenant data leakage by fallback**, and it produces no error.

**Why it happens:**
The `|| 'default'` idiom is already in the codebase and feels safe ("never crash on a missing tenant"). It is the single-tenant assumption fossilized into a default. Removing it feels risky because today *everything* legitimately resolves to default.

**How to avoid:**
Make unknown-tenant **fail-closed**, not fall-back: if channel identity does not map to a known tenant, reject the message with an explicit `TENANT_UNRESOLVED` reason and alert — never substitute a default. Keep a **single, audited** "is this the legacy single-tenant deployment?" switch (e.g. `SINGLE_TENANT_MODE=true` with one known UUID) so the live restaurant keeps working, but make multi-tenant resolution refuse to guess. Grep the entire repo for `|| 'default'` and `DEFAULT_TENANT_ID` and treat each as a defect to justify or remove.

**Warning signs:**
Orders appearing under the default/all-zeros UUID `00000000-0000-0000-0000-000000000000` after go-live; one tenant's order volume mysteriously growing; `DEFAULT_TENANT_ID` still referenced in any inbound workflow after derivation ships; an unmapped number "just works."

**Phase to address:** **Phase 2 — Inbound tenant derivation** (the resolver + fail-closed-on-unknown). Depends on Phase 1's canonical key.

---

### Pitfall 3: Adding `tenant_id` scoping to existing order/customer queries without auditing every read AND write path

**What goes wrong:**
You add `AND tenant_id = $x` to the obvious admin list query but miss one of: an `INSERT` that omits `tenant_id` (now stamped with the default), a background analytics/cron query (`W53_DYNAMIC_KITCHEN_LOAD`, `W55_PREDICTIVE_86ING`, `W_ADMIN_PROACTIVE_AGENT`, `W51_VIP_WIN_BACK`), an AI-agent context fetch, or a customer-facing "track my order" lookup. The missed path becomes a cross-tenant read/write hole. Because the data plane already has `tenant_id uuid NOT NULL`, a forgotten `INSERT` doesn't error — it inherits the wrong default and the leak is invisible until two tenants are live.

**Why it happens:**
Order/customer access is spread across ~11 workflows (`grep -lE "FROM orders|FROM customers"` returns W12, W14, W30, W4_CORE, W51, W53, W60, W61, W_ADMIN_PROACTIVE_AGENT, W_ORDER_FINALIZER, W_THE_USUAL) plus Strapi controllers and lifecycles. "Scope the queries" is treated as one task; it is actually an exhaustive inventory task. The existing scoping in `W12_ADMIN_ORDERS` creates false confidence that it's "already done."

**How to avoid:**
Enumerate **every** SQL/Strapi query touching `orders`, `customers`, `order_items`, `order_status_history` (and any table with a `tenant_id` FK in `db/schema.sql`) before changing any of them; make the list a checklist artifact. Prefer a **defense-in-depth** mechanism over per-query discipline: Postgres Row-Level Security (`ALTER TABLE orders ENABLE ROW LEVEL SECURITY` + a policy on a session `SET app.tenant_id`) so a forgotten `WHERE` cannot leak — this is the single highest-leverage control for a brownfield multi-tenant DB. At minimum, make `tenant_id` non-defaultable on writes so an omission errors loudly instead of silently defaulting.

**Warning signs:**
A query in the inventory list still has no `tenant_id` predicate; an `INSERT INTO orders` without `tenant_id` in the column list; analytics totals that include another tenant; RLS not enabled while relying on hand-written `WHERE` clauses everywhere.

**Phase to address:** **Phase 3 — Data-plane scoping & RLS**. Highest-blast-radius change on live data; schedule its own phase with a read-only audit step first.

---

### Pitfall 4: Flipping the admin/UI guard from fail-open to fail-closed and locking out the live operator

**What goes wrong:**
`admin-dashboard/src/hooks/useEntitlements.ts:52-55` returns `true` while `loading` and swallows fetch errors (returns empty `modules`, no error surfaced). You "fix" it to default `false` on error/loading. Now any transient Strapi 500, a slow Strapi cold start (3–8 min per CONCERNS.md), or an expired `STRAPI_API_TOKEN` makes the **entire admin dashboard render nothing** — the live operator is locked out of the kitchen view mid-service. Symmetrically, the server-side `W0_MODULE_GUARD` already fail-closes on any exception; if `STRAPI_API_TOKEN_INTERNAL` is missing/expired, **all 8 entrypoint workflows** (`W1_IN_WA`, `W1_IN_TIKTOK`, `W2_IN_IG`, `W3_IN_MSG`, `W30_VOICE_CALL_INIT`, `W_KIOSK_ORDER`, `W_ORDER_FINALIZER`) deny everything — a **total inbound outage** whose only signal is `GUARD_ERROR_FAILCLOSED` in logs (CONCERNS.md, P2 guard item).

**Why it happens:**
Fail-closed is the *correct* security posture, so it's applied bluntly. The mistake is conflating two distinct failure causes that fail-closed treats identically: "tenant is genuinely not entitled" (deny — correct) vs "infrastructure/secret is broken" (denying here turns a config error into an outage). The UI and guard also currently *disagree* (UI open, guard closed), so a naive "make both closed" doubles the lockout surface.

**How to avoid:**
Separate **"not entitled"** from **"cannot determine entitlement."** On *determination failure* (network/token/Strapi error), do not silently deny — page an alert and apply a **narrow, known shared-core allowlist** (the `shared_core`/`platform_runtime`/`order_bot_core` tiers from `saas-entitlements.ts`) so the live single tenant keeps operating, while *unknown/addon* modules deny. Provision and verify `STRAPI_API_TOKEN_INTERNAL` **before** tightening the guard, with a startup check that fails the deploy if it's absent. Add a distinct `GUARD_ERROR_FAILCLOSED` alert (vs `NO_ENTITLEMENT`) so a missing secret pages an engineer rather than silently dropping orders. In the UI, render an explicit "entitlements unavailable" error state, not a blank app.

**Warning signs:**
Admin dashboard blank after deploy; `GUARD_ERROR_FAILCLOSED` in n8n logs with zero `NO_ENTITLEMENT`; inbound order count drops to zero right after a Strapi restart or token rotation; no startup assertion for `STRAPI_API_TOKEN_INTERNAL`.

**Phase to address:** **Phase 4 — Fail-closed alignment + secret provisioning**. Do secret provisioning and the `GUARD_ERROR_FAILCLOSED` alert *in the same phase as* the fail-closed flip — never flip first and provision later.

---

### Pitfall 5: Applying the new `uq_tenant_module` unique constraint to a live table that already contains duplicates

**What goes wrong:**
`db/migrations/2026-04-06_saas_modules_entitlements.sql:11-19` adds `uq_tenant_module UNIQUE (tenant_id, module_key)` and (line 39) `uq_product_module_key UNIQUE (key)`. CONCERNS.md notes the seeder dedupes by `findOne` but **concurrent writes or manual admin edits can create duplicates**, and the guard's `data[0]` read silently masks them. If duplicates already exist on the VPS, `ALTER TABLE ... ADD CONSTRAINT` **fails outright** (`could not create unique index ... Key (tenant_id, module_key) is duplicated`). The migration's `DO $$ ... IF NOT EXISTS (conname) ...` guard only checks whether the *constraint* exists — it does **not** detect or resolve pre-existing duplicate *rows*, so a re-run still fails the same way, and an unguarded `ALTER` can take an `ACCESS EXCLUSIVE` lock that blocks live entitlement reads.

**Why it happens:**
The migration was written and validated only against an **ephemeral, empty CI Postgres** (`.github/workflows/migration-validate.yml` per CONCERNS.md "Repo↔VPS schema drift, P0"), where duplicates can't exist. CI is green; the live table's actual row state was never inspected. The idempotency guard creates false confidence that the migration is "safe to apply anytime."

**How to avoid:**
Before applying: run a **read-only duplicate probe** on the live VPS — `SELECT tenant_id, module_key, count(*) FROM tenant_entitlements GROUP BY 1,2 HAVING count(*) > 1;` and the equivalent for `product_modules(key)`. If any rows return, **dedupe first** (keep the most recent `activated_at`, delete the rest, log what was removed) as an explicit pre-migration step. Build the unique index with `CREATE UNIQUE INDEX CONCURRENTLY` first (no long exclusive lock on a live table), then attach the constraint, rather than a bare `ADD CONSTRAINT`. Run the whole thing inside an explicit transaction with a `lock_timeout`/`statement_timeout` so a stuck lock aborts instead of stalling inbound.

**Warning signs:**
`ERROR: could not create unique index "uq_tenant_module" ... is duplicated`; the migration "passed in CI" but errors on the VPS; entitlement reads hang during the `ALTER`; the dedupe probe returns rows you didn't expect (manual admin edits).

**Phase to address:** **Phase 5 — Apply SaaS DB constraints (with pre-flight dedupe)**. Must include a live-data probe step; cannot be a blind `psql < migration.sql`. Pairs with closing the broader repo↔VPS migration-application gap (add a guarded VPS migration step to CD).

---

### Pitfall 6: Adding Redis entitlement caching with no (or wrong) invalidation — stale-after-change grants/denials

**What goes wrong:**
To kill the +2 synchronous Strapi round-trips per inbound message (CONCERNS.md, P1 perf), you cache module/entitlement lookups in Redis. Then: (a) an admin **disables** a module but the cached `allowed:true` survives for the full TTL → a tenant keeps using a revoked/expired module (security regression — the opposite of why the guard exists); (b) you cache the **negative** result too, so a freshly *enabled* module stays denied until TTL expiry → "I paid, why is it still off?"; (c) the cache key omits `tenant_id` (e.g. keyed on `module_key` only) → **one tenant's entitlement bleeds into another's** cache — a cross-tenant leak created by the cache itself; (d) you cache the `EXPIRED` check result, so an entitlement that expires *during* the TTL window stays `allowed`.

**Why it happens:**
Caching is added for latency under deadline pressure (Meta's <5s webhook budget), and invalidation is the classic afterthought. The guard's *expiry* logic (`W0_MODULE_GUARD.json`: `if (ent.expires_at && new Date(ent.expires_at) < new Date())`) is time-sensitive and does **not** survive naive caching of the boolean result. Redis on this VPS is `allkeys-lru` with 256MB (CONCERNS.md), so keys can also be **silently evicted** mid-flight, making behavior non-deterministic.

**How to avoid:**
Key the cache on **`tenant_id:module_key`** (never module-only) — this also forces you to confirm Pitfall 1's canonical key. Use a **short TTL** (the suggested 5-min) **and** explicit invalidation: have every entitlement create/disable/expire/config-change event (admin dashboard + seeder) `DEL` the affected key — and wire those same events to the audit log (Pitfall 7), so cache invalidation and audit share one hook. Do **not** cache the computed `expires_at` boolean; cache the raw entitlement row (incl. `expires_at`) and re-evaluate expiry on read so a mid-TTL expiry is honored. Treat the cache as best-effort: on Redis miss/error, fall back to the live Strapi query (degraded latency) rather than fail-closed (avoid turning a cache blip into Pitfall 4's outage). Account for `allkeys-lru` eviction — never assume a key persists for the full TTL.

**Warning signs:**
A disabled/expired module still works for up to TTL minutes; a newly enabled module stays off; the same `allowed` value returned for two different tenants; Redis key pattern lacks the tenant segment; entitlement changes don't `DEL` anything; expiry edge cases pass in tests but fail in production where TTL > time-to-expiry.

**Phase to address:** **Phase 6 — Entitlement caching + invalidation**. Must ship *with* its invalidation hooks (and ideally share them with the audit writer). Depends on Phase 1 (key) and Phase 4 (fail-closed semantics) being settled.

---

### Pitfall 7: Wiring the audit log as a fire-and-forget side effect that silently loses entries (and mismatches the schema)

**What goes wrong:**
`entitlement_audit_log` exists but has **zero writers** (CONCERNS.md). You add writes from the admin dashboard / seeder, but: (a) using the platform's established `continueOnFail: true` pattern (as W1/W2/W3 audit hooks do) means a write failure — wrong column, missing table on the VPS, type mismatch — is **swallowed**, reproducing the exact "audit silently absent" failure that already broke AUDIT-02/03/04; (b) you write `tenant_id` as the canonical **UUID** but the column is `VARCHAR(255)` (`...saas_modules_entitlements.sql:47`) — it accepts anything, so a buggy value (`'default'`, empty, the all-zeros UUID) is stored with no FK to catch it, and the audit trail becomes untrustworthy for the very cross-tenant incidents it's meant to prove; (c) the table is only created if the unapplied migration runs (Pitfall 5), so writers `INSERT` into a non-existent relation and fail.

**Why it happens:**
Audit is perceived as non-critical "logging," so it's bolted on with the lowest-effort error handling and never tested for actual persistence. The `VARCHAR` column accepts garbage silently. The platform has a documented history (CONCERNS.md "continueOnFail-masked audit hooks") of audit writes failing invisibly.

**How to avoid:**
Apply the migration **first** (Phase 5) and assert the table exists in a post-deploy smoke before enabling writers. Write the audit entry from the **same transaction/hook** that mutates the entitlement (or the same cache-invalidation hook from Pitfall 6) so a change and its audit row are atomic — not a detached `continueOnFail` afterthought. Keep `continueOnFail` only if you also **route the failure branch to a counter/alert** (CONCERNS.md's prescribed fix), so silent audit loss is detectable. Standardize the stored `tenant_id` on the canonical key from Pitfall 1 and validate it before insert (reject empty/`'default'`/all-zeros once multi-tenant is live). Follow the existing good precedent: `admin_audit_log` (`db/migrations/2026-01-22_p1_opssecqa_scopes_admin_audit.sql:31-50`) already stores `tenant_id uuid` with FK and `(tenant_id, created_at DESC)` index — mirror that shape rather than the looser `VARCHAR` one.

**Warning signs:**
`relation "entitlement_audit_log" does not exist` swallowed in logs; entitlement changes happen but the audit table stays empty; audit rows with `tenant_id = ''` or `'default'`; no alert when an audit insert fails; the audit `tenant_id` can't be joined to `tenants` because the types differ.

**Phase to address:** **Phase 7 — Entitlement audit writers**. Must follow Phase 5 (table applied) and reuse Phase 6's invalidation hook. Include a "audit row actually written" smoke test.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Keep `\|\| 'default'` tenant fallback "for now" | Live restaurant never breaks; no resolver needed | Cross-tenant leakage the moment a 2nd tenant exists; default becomes load-bearing and undeletable | Only inside an explicit, single-flag `SINGLE_TENANT_MODE` with one known UUID — never as an implicit resolver fallback |
| Hand-written `WHERE tenant_id = $x` instead of Postgres RLS | Fast to add to the few obvious queries | One forgotten query = silent cross-tenant leak across ~11 workflows + Strapi controllers | Acceptable for read-only/admin queries already covered; never as the *only* control for write paths |
| Cache entitlement booleans without invalidation hooks | Kills the +2 Strapi round-trips immediately | Stale grants survive revocation; expiry checks bypassed; cross-tenant cache bleed | Never — invalidation must ship with the cache, not after |
| `continueOnFail: true` on audit writes (copy existing pattern) | Order flow never blocks on audit | Reproduces AUDIT-02/03/04 silent-loss class; audit trail untrustworthy in an incident | Only if paired with a failure-branch counter/alert |
| Apply migration via blind `psql < file.sql` on VPS | One command, matches existing runbook habit | Fails on pre-existing duplicates; exclusive lock can stall live inbound | Never on a constraint-adding migration against a populated live table — probe + `CONCURRENTLY` first |
| Store entitlement `tenant_id` as `VARCHAR` to "tolerate both shapes" | No type-coercion code; matches current `useEntitlements` `any` habit | Garbage tenant ids stored unvalidated; can't FK-join to `tenants`; audit untrustworthy | Never once a canonical UUID key is chosen |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Strapi `tenant_entitlements` ↔ Postgres `orders` | Treating both `tenant_id`s as the same key (string `'default'` vs UUID) | One canonical UUID; entitlement plane stores the UUID string; resolver shared by both |
| WhatsApp/Meta inbound → tenant | Assuming `phone_number_id` already maps to a tenant — it's *captured* (`W1_IN_WA` `meta.phone_number_id`) but **never used** to resolve tenant | Build an explicit `phone_number_id → tenant_uuid` mapping (new table/config); fail-closed on unknown |
| `W0_MODULE_GUARD` → Strapi | Forgetting it needs `STRAPI_API_TOKEN_INTERNAL`; missing token fail-closes all 8 entrypoints | Provision + startup-assert the token before tightening; distinct alert on `GUARD_ERROR_FAILCLOSED` |
| Redis (`allkeys-lru`, 256MB) entitlement cache | Assuming TTL keys persist; on Redis error, fail-closed | Tolerate eviction (fall back to live query on miss); cache miss/Redis-down must degrade, not deny |
| CD pipeline → VPS schema | Migration validated only on ephemeral CI Postgres; never applied to VPS (repo↔VPS drift, P0) | Add guarded VPS migration-apply step + post-deploy schema assertion |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| +2 synchronous Strapi round-trips per inbound message in `W0_MODULE_GUARD` | Guard P95 climbs; Meta <5s webhook budget eroded; retries/suspension under load | Redis cache keyed `tenant_id:module_key`, 5-min TTL, with invalidation | Under queue pressure / Strapi cold start (3–8 min); already at risk with 1 tenant |
| Adding tenant `WHERE`/RLS without an index on `tenant_id` | Order/customer list latency grows per tenant | Confirm indexes (data plane FKs are indexed; entitlement indexes are in the migration lines 22-31) before scoping | As per-tenant row counts grow |
| `ADD CONSTRAINT` taking `ACCESS EXCLUSIVE` lock on live `tenant_entitlements` | Inbound entitlement checks hang during migration | `CREATE UNIQUE INDEX CONCURRENTLY` then attach; `lock_timeout` | Any apply against a live, read-hot table |
| Caching negative/`EXPIRED` results | A just-enabled module stays denied; an expired one stays allowed | Cache the raw row, re-evaluate expiry on read; `DEL` on change | Whenever TTL > time-to-next-entitlement-change |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Default-tenant fallback left in resolver | Cross-tenant data leak (B processed as A) with no error | Fail-closed `TENANT_UNRESOLVED` on unknown; grep-and-justify every `\|\| 'default'` |
| Module-only (tenant-less) cache key | One tenant's entitlement granted to another via cache | Key on `tenant_id:module_key`; assert tenant segment present |
| UI fail-open (`useEntitlements` returns `true` while loading) | Renders modules/data a tenant isn't entitled to; Strapi 500 looks like "all modules on" | Default `false`/shared-core-allowlist on error; explicit error state |
| Trusting body-supplied tenant hints | Tenant spoofing via request body (`W1_IN_WA` already labels these "NEVER trusted") | Derive tenant only from verified channel identity (Meta-sig-validated `phone_number_id`), never from body |
| `VARCHAR` audit `tenant_id` accepting any value | Audit trail records wrong/empty tenant; untrustworthy in a breach investigation | Validate against canonical UUID before insert; mirror `admin_audit_log`'s typed+FK shape |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Blank admin dashboard on entitlement-fetch error (after fail-closed flip) | Operator locked out mid-service; can't see kitchen/orders | Explicit "entitlements unavailable, retrying" state + shared-core fallback so core admin stays usable |
| Silent channel denial on module-key drift | A WhatsApp/IG channel just stops; no operator-visible reason | Surface `NO_ENTITLEMENT` distinctly from `GUARD_ERROR_FAILCLOSED`; alert on either |
| Newly purchased module stays off (stale cache) | "I paid and nothing changed" | Invalidate cache on enable; short TTL ceiling |

## "Looks Done But Isn't" Checklist

- [ ] **Tenant derivation:** Often missing the **fail-closed-on-unknown** path — verify an unmapped `phone_number_id` is *rejected*, not silently routed to `'default'`/all-zeros UUID.
- [ ] **Query scoping:** Often missing the **write** paths and background/AI workflows — verify all ~11 order/customer workflows *and* Strapi controllers/lifecycles, not just `W12_ADMIN_ORDERS`.
- [ ] **Two-plane reconciliation:** Often missing the entitlement plane after fixing the data plane (or vice-versa) — verify `tenant_entitlements.tenant_id` uses the **same canonical key** as `orders.tenant_id`.
- [ ] **Fail-closed flip:** Often missing the **secret provisioning + startup assertion** — verify `STRAPI_API_TOKEN_INTERNAL` is present and a missing token fails the *deploy*, not production.
- [ ] **Migration apply:** Often missing the **live duplicate probe** — verify `tenant_entitlements` has no `(tenant_id, module_key)` dupes *on the VPS* before `ADD CONSTRAINT`.
- [ ] **Cache:** Often missing **invalidation** and **tenant in the key** — verify a disable event `DEL`s the key and keys contain `tenant_id`.
- [ ] **Audit:** Often missing **actual persistence** — verify a real entitlement change produces a real row (table exists on VPS; write isn't a swallowed `continueOnFail`).
- [ ] **Alerting:** Often missing the **`GUARD_ERROR_FAILCLOSED` ≠ `NO_ENTITLEMENT`** distinction — verify a missing token pages someone instead of silently dropping all inbound.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Default-tenant fallback leaked cross-tenant data | HIGH | Identify orders/customers stamped with default/all-zeros UUID after a 2nd tenant existed; manual re-attribution from channel logs; notify affected tenant; this is often *unrecoverable* cleanly — prevention is the only real control |
| Fail-closed flip locked out admin / dropped inbound | LOW–MEDIUM | Revert the guard/UI change or hot-fix the missing secret; restore shared-core fallback; the live single tenant resumes once token present |
| Constraint migration failed on duplicates | MEDIUM | Roll back the `ALTER`; run dedupe (keep latest `activated_at`); re-apply with `CONCURRENTLY`; verify counts |
| Stale cache granted revoked module | MEDIUM | `FLUSHDB`/targeted `DEL` of entitlement keys; lower TTL; add the missing invalidation hook; audit what was accessed while stale |
| Audit writes silently lost | MEDIUM | Confirm table exists on VPS; add failure-branch alert; backfill from `admin_audit_log`/n8n execution history where possible (lossy) |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. Two-plane `tenant_id` reconciliation | Phase 1 — Tenant identity model | One canonical key documented; `tenant_entitlements.tenant_id` stores the `tenants.tenant_id` UUID; no `VARCHAR` vs `uuid` join failures |
| 2. Default-tenant fallback / fail-open tenant | Phase 2 — Inbound tenant derivation | Unmapped `phone_number_id` yields `TENANT_UNRESOLVED` + alert; no `\|\| 'default'` in inbound path |
| 3. Query scoping gaps (reads + writes) | Phase 3 — Data-plane scoping & RLS | RLS enabled on `orders`/`customers`; every order/customer query enumerated; a forgotten `WHERE` cannot leak (RLS test) |
| 4. Fail-closed lockout / inbound outage | Phase 4 — Fail-closed alignment + secret provisioning | `STRAPI_API_TOKEN_INTERNAL` startup-asserted; `GUARD_ERROR_FAILCLOSED` alert distinct from `NO_ENTITLEMENT`; UI shows error state, core admin survives Strapi 500 |
| 5. Unique constraint on duplicate live data | Phase 5 — Apply SaaS constraints (pre-flight dedupe) | Live duplicate probe returns 0; constraint added via `CONCURRENTLY`; VPS schema assertion in CD |
| 6. Cache stale-after-change / cross-tenant bleed | Phase 6 — Entitlement caching + invalidation | Keys contain `tenant_id`; disable event `DEL`s key within seconds; expiry honored mid-TTL; Redis-down degrades not denies |
| 7. Audit silent loss / type mismatch | Phase 7 — Entitlement audit writers | Real change → real row on VPS; failure branch alerts; `tenant_id` validated to canonical UUID |

## Sources

- `db/schema.sql` (lines 9-99, 381-386) — UUID `tenants`/`orders` data plane, `tenant_id uuid NOT NULL REFERENCES tenants` — HIGH (direct repo read)
- `db/migrations/2026-04-06_saas_modules_entitlements.sql` (lines 11-57) — `uq_tenant_module`, `VARCHAR(255)` `tenant_id`, dead `entitlement_audit_log` — HIGH
- `db/migrations/2026-01-22_p1_opssecqa_scopes_admin_audit.sql` (lines 31-50) — `admin_audit_log` typed+FK precedent — HIGH
- `workflows/W0_MODULE_GUARD.json` (line 15 code) — `tenant_id || $env.DEFAULT_TENANT_ID || 'default'`, fail-closed `GUARD_ERROR_FAILCLOSED`, expiry check — HIGH
- `workflows/W1_IN_WA.json` — `meta.phone_number_id` captured but unused for tenant; `tenantId = defaultTenantId` for all auth modes; all-zeros UUID fallback; "body hints NEVER trusted" — HIGH
- `workflows/W12_ADMIN_ORDERS.json` — `FROM orders o WHERE o.tenant_id = $1` already token-scoped (UUID) — HIGH
- `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` (lines 17-186) — string `'default'` tenant, module key list, seeder dedupe-by-findOne — HIGH
- `admin-dashboard/src/hooks/useEntitlements.ts` (lines 42-56) — UI fail-open (`if (loading) return true`), swallowed catch — HIGH
- `.planning/codebase/CONCERNS.md` (2026-06-20) — tenant isolation P1, fail-open/closed P1, guard token P2, +2 round-trips P1, repo↔VPS drift P0, continueOnFail-masked audit P1 — HIGH

---
*Pitfalls research for: SaaS multi-tenant hardening of a live single-tenant-default platform*
*Researched: 2026-06-20*
