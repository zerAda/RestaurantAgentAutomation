# Phase 19: Entitlement Audit + Cache-Invalidation Lifecycle Hook — Research

**Researched:** 2026-06-20
**Domain:** Strapi 5 content-type lifecycle hooks (`tenant-entitlement` / `product-module`) → raw-Knex audit-row write into the strapi-DB `entitlement_audit_log` table + an `ioredis` `DEL` of the forward-defined entitlement cache key, with fail-loud (counter/alert) write semantics and canonical-UUID validation
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AUD-01 | `tenant-entitlement` (and `product-module`) Strapi content types gain `lifecycles.ts` that write an `entitlement_audit_log` row on create/update/delete (who/what/when/old→new). The currently-dead `entitlement_audit_log` table gets real writers (or is explicitly dropped if descoped — decision recorded). | §1 (exact `entitlement_audit_log` columns), §2 (cross-DB resolution: table is in the strapi DB, writer uses raw Knex `strapi.db.connection`, NO second connection), §3 (lifecycle event shape + old→new capture via `beforeUpdate`/`beforeDelete` → `event.state`), §4 (who via `strapi.requestContext`), §6 (fail-loud) |
| AUD-02 | The same lifecycle hook **invalidates** the Redis entitlement cache (GRD-01) on any entitlement change, so a revoked/expired entitlement cannot survive in cache. | §5 (canonical cache-key contract `ralphe:entitlement:{tenant_id}:{module_key}` forward-coupled to Phase 20 GRD-01; `ioredis` client pattern; DEL-by-exact-key vs SCAN/version decision), §7 Validation Architecture (ephemeral `redis-server` invalidation test — verified working locally) |
</phase_requirements>

---

## Summary

**Two findings collapse the two hardest open questions before planning even starts.** (1) **The cross-DB write question is already resolved in the codebase**: `entitlement_audit_log`, `tenant_entitlements`, and `product_modules` all live in the **strapi DB** (created by `db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql:114-126`), and Strapi connects to exactly that DB by default (`inventory-cms/config/database.ts:31` — `database: env('DATABASE_NAME', 'strapi')`). A `tenant-entitlement` lifecycle runs *inside* that same Strapi/Knex connection, so the writer targets a table in the **same** DB it is already connected to. **No cross-DB connection, no n8n-DB writer, no table move is needed** — criterion 2 resolves to "the table already lives in the strapi DB; the lifecycle writes it via the existing `strapi.db.connection` (Knex), nothing to relocate." (2) **`entitlement_audit_log` is NOT a Strapi content type** — there is no `schema.json` for it anywhere in `inventory-cms/src` (verified by grep), it is a raw SQL-migration table. Therefore the writer **cannot** use `strapi.db.query('api::…')` / `strapi.documents` (no UID exists); it must use **raw Knex**: `strapi.db.connection('entitlement_audit_log').insert({...})`. That exact pattern is already in the repo (`agent-chat.ts:107-109` does `const knex = strapi.db.connection; knex('orders')…`; `control-plane.ts:76` does `strapi.db.connection.raw('SELECT 1')`).

**The lifecycle mechanics have one Strapi-5 gotcha that shapes the whole design: `afterUpdate`/`afterDelete` do NOT carry the *old* value.** In Strapi 5 the lifecycle `event` exposes `event.params` (`.data`, `.where`, `.select`, `.populate`), `event.result` (the post-mutation row for create/update; the deleted row for delete), `event.action`, `event.model`, and a mutable `event.state` bag. There is **no `event.previousValue`**. To capture `old→new`, the hook must fetch the prior row in **`beforeUpdate`/`beforeDelete`** (`strapi.db.query('api::tenant-entitlement.tenant-entitlement').findOne({ where: event.params.where })`), stash it on `event.state.oldValue`, then read it back in the `after*` hook. The "who" (`changed_by`) is read with **`strapi.requestContext.get()?.state?.user?.email`** (Strapi 5 AsyncLocalStorage request context, verified — works inside lifecycles when called *inside* the hook function), falling back to `'system'` for seed/migration writes that have no HTTP context. The `afterDelete` row's `tenant_id`/`module_key` survive because `event.result` is the deleted entry — but to be safe, capture them in `beforeDelete` → `event.state` as well (the Strapi-5 draft/publish path can fire delete on a copy).

**Primary recommendation:** Split into 3 plans with disjoint file ownership. **19-01** records the cross-DB decision in an ADR (`docs/adr/0003-entitlement-audit-placement.md`) — "table stays in strapi DB; raw-Knex writer; no second connection" — and (per ADR 0001 line 101) lands the deferred `entitlement_audit_log.tenant_id` `VARCHAR(255)→uuid` + nullable FK type migration as a new idempotent `db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql` (🔴 VPS apply deferred). **19-02** factors the audit write into a **pure, Strapi-free helper** `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/audit-hook.ts` taking `(knex, redis, eventLike)` and wires `lifecycles.ts` on both `tenant-entitlement` and `product-module` (old→new capture, canonical-UUID validation via `zod`, fail-loud counter/alert — mirrors the Phase-18 fail-loud `beforeCreate` throw pattern). **19-03** adds the `ioredis` `DEL` of `ralphe:entitlement:{tenant_id}:{module_key}` into that same helper plus the validation harness (`scripts/` node-test runner + `.github/workflows/phase-19-assertions.yml` with an ephemeral Postgres **and** an ephemeral `redis-server`). 🔴 VPS: applying the uuid migration on prod strapi DB + **rebuilding the CMS** (lifecycle/attr changes need a CMS rebuild) is deferred.

---

## 1. The `entitlement_audit_log` Table — Exact Columns (the write target)

From `db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql:114-126` (strapi DB, created by the Phase-16 live-safe migration; **currently has zero writers** — this phase gives it real ones):

```sql
CREATE TABLE IF NOT EXISTS entitlement_audit_log (
  id         SERIAL PRIMARY KEY,
  tenant_id  VARCHAR(255) NOT NULL,   -- ADR 0001 line 101: migrate → uuid + nullable FK in Phase 19
  module_key VARCHAR(255) NOT NULL,
  action     VARCHAR(50)  NOT NULL,   -- 'enabled' | 'disabled' | 'expired' | 'config_changed' (+ recommend 'created'/'deleted')
  changed_by VARCHAR(255),            -- the "who"
  old_value  JSONB,                   -- old→ (null on create)
  new_value  JSONB,                   -- →new (null on delete)
  created_at TIMESTAMPTZ DEFAULT NOW()-- the "when"
);
CREATE INDEX IF NOT EXISTS idx_entitlement_audit_tenant
  ON entitlement_audit_log (tenant_id, created_at DESC);
```

**Column → audit-semantics mapping the writer must fill:**

| Column | Source in the lifecycle | Notes |
|--------|-------------------------|-------|
| `tenant_id` | `result.tenant_id` (create/update) / `event.state.oldValue.tenant_id` (delete) | **Validate to canonical UUID before insert** (criterion 4). The column is `VARCHAR(255)` today; 19-01 migrates to `uuid` per ADR 0001. |
| `module_key` | `result.module_key` (entitlement) / `result.key` (product-module — note the column name differs!) | `tenant-entitlement` uses `module_key`; `product-module` uses `key` — the helper must map both. |
| `action` | derived: `'created'` (afterCreate) / `'config_changed'`/`'enabled'`/`'disabled'`/`'expired'` (afterUpdate, by diffing `enabled`/`expires_at`) / `'deleted'` (afterDelete) | The existing `VARCHAR(50)` comment lists `enabled/disabled/expired/config_changed`; recommend also allowing `created`/`deleted` (no constraint forbids it). |
| `changed_by` | `strapi.requestContext.get()?.state?.user?.email ?? 'system'` | §4. |
| `old_value` | `event.state.oldValue` (JSON) — null on create | Captured in `beforeUpdate`/`beforeDelete`. |
| `new_value` | `result` (JSON) — null on delete | `event.result` post-mutation. |
| `created_at` | DB `DEFAULT NOW()` | the "when" — leave to the default. |

**`tenant-entitlement` schema** (`inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/schema.json:12-48`): `tenant_id` (string, required), `module_key` (string, required), `enabled` (bool, default true), `activated_at`, `expires_at`, `config_overrides` (json), `activated_by`, `notes`. **No `lifecycles.ts` exists yet** (only `controllers/`, `routes/`, `content-types/.../schema.json`).
**`product-module` schema** (`product-module/content-types/product-module/schema.json:12-60`): `key` (string, unique, required), `display_name`, `tier` (enum), `enabled_globally` (bool), `rollout_policy`, etc. **No `lifecycles.ts` yet.**

---

## 2. Cross-DB Resolution (criterion 2 — RESOLVED, documented here)

**Decision: the table stays where it is (strapi DB); the writer uses the existing `strapi.db.connection` (Knex); no second/n8n-DB connection is created.**

Evidence chain:
- `entitlement_audit_log` is created by `db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql` — the **strapi-DB** migration pass (`db/migrations-strapi/`, applied with `PGDATABASE=strapi` per the 16-03 wiring; ROADMAP `:90`).
- Strapi's own DB connection points at the strapi DB: `inventory-cms/config/database.ts:31` → `database: env('DATABASE_NAME', 'strapi')`.
- A `tenant-entitlement` lifecycle hook executes inside the Strapi process, so `strapi.db.connection` **is** the strapi-DB Knex pool — the same DB the audit table lives in. `tenant_entitlements` and `product_modules` are likewise strapi-DB tables (managed by Strapi as content types).
- Therefore: **no cross-DB write happens.** The n8n DB (orders/customers, Phase 18) is irrelevant here. There is nothing to "move" and no explicit n8n-DB connection to provision.

**Why this is the right call (vs the two alternatives the criterion names):**

| Option | Verdict | Why |
|--------|---------|-----|
| **A — table already in strapi DB; raw-Knex writer (CHOSEN)** | ✅ | The table and the writer share one connection. Zero new infra. Matches `agent-chat.ts:107`/`control-plane.ts:76` precedent. |
| B — move `entitlement_audit_log` to the n8n DB | ❌ | Would force a cross-DB writer (a *second* `pg`/Knex connection from Strapi to the n8n DB) for no benefit — the entitlement source-of-truth (`tenant_entitlements`) is in the strapi DB; co-locating the audit there is correct. |
| C — give the writer an explicit n8n-DB connection | ❌ | Only needed if (B); rejected for the same reason. |

**ADR to write (19-01):** `docs/adr/0003-entitlement-audit-placement.md` — records Option A, the raw-Knex-writer rationale (the table has no Strapi content-type / UID, so `strapi.db.query('api::…')` is impossible — confirmed by grep), and supersedes the ADR-0001 line-101 promise by landing the `tenant_id` uuid migration here.

---

## 3. Strapi 5 Lifecycle Event Shape + old→new Capture (the load-bearing mechanic)

**The Strapi-5 gotcha:** `afterUpdate`/`afterDelete` events do **not** include the pre-mutation value. The `event` object exposes:

| Field | Contents | Available in |
|-------|----------|--------------|
| `event.params.data` | the incoming write payload | before*/after* create+update |
| `event.params.where` | the selector | update/delete |
| `event.result` | post-mutation row (create/update) / the deleted row (delete) | after* |
| `event.action` | `'afterCreate'` \| `'afterUpdate'` \| `'afterDelete'` … | all |
| `event.model` | the model definition (table/uid) | all |
| `event.state` | **mutable bag** — the official way to pass data from a `before*` to its paired `after*` hook | all (per Strapi forum/docs) |

**old→new capture pattern (REQUIRED — mirror in 19-02):**

```typescript
// inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/lifecycles.ts
import { runEntitlementAudit, captureOld } from './audit-hook';

const UID = 'api::tenant-entitlement.tenant-entitlement';

export default {
  async beforeUpdate(event: any) {
    // afterUpdate carries no "old" value — fetch + stash it now.
    event.state.oldValue = await strapi.db.query(UID).findOne({ where: event.params.where });
  },
  async beforeDelete(event: any) {
    // afterDelete's result is the deleted row, but capture defensively (draft/publish can delete a copy).
    event.state.oldValue = await strapi.db.query(UID).findOne({ where: event.params.where });
  },
  async afterCreate(event: any) {
    await runEntitlementAudit(strapi, { action: 'created', oldValue: null, result: event.result });
  },
  async afterUpdate(event: any) {
    await runEntitlementAudit(strapi, { action: 'config_changed', oldValue: event.state.oldValue, result: event.result });
  },
  async afterDelete(event: any) {
    await runEntitlementAudit(strapi, { action: 'deleted', oldValue: event.state.oldValue, result: event.result ?? event.state.oldValue });
  },
};
```

**`bulk` variants:** Strapi also fires `afterUpdateMany`/`afterDeleteMany` for `updateMany`/`deleteMany`. The entitlement admin path is single-row (one tenant×module at a time), so the single-row hooks cover the real path; **document that bulk ops bypass the per-row audit** (acceptable for the operator-provisioned model — no self-serve bulk grant exists this milestone) or add the `*Many` hooks if the planner wants belt-and-suspenders. Recommend: cover single-row now, note bulk as a documented gap.

**Action derivation for `afterUpdate`** (diff `oldValue` vs `result`): `enabled false→true` ⇒ `'enabled'`; `true→false` ⇒ `'disabled'`; `expires_at` crossed/now in past ⇒ `'expired'`; otherwise ⇒ `'config_changed'`. Keep this in the pure helper so it is unit-testable without Strapi.

---

## 4. The "Who" — Actor Capture (criterion 1: who/what/when/old→new)

Verified Strapi-5 mechanism (search-confirmed; AsyncLocalStorage request context): inside a lifecycle, call

```typescript
const ctx = strapi.requestContext.get();
const changedBy = ctx?.state?.user?.email ?? 'system';
```

- **Must be called *inside* the hook function** (not at module load) — the AsyncLocalStorage context only exists within an HTTP request scope.
- Admin-panel edits and authenticated API writes populate `ctx.state.user`; the repo already reads `ctx.state.user?.email` in controllers (`agent-chat.ts:316`, `extensions/agent-chat/controllers/agent-chat.ts:37`).
- Seed/bootstrap writes (`saas-entitlements.ts`) and migrations have **no** HTTP context → `ctx` is `undefined` → fall back to `'system'`. The helper must tolerate `undefined` (this also makes the pure helper testable without Strapi: pass `changedBy` in explicitly).

---

## 5. Cache-Key Contract (criterion 3 — DEFINED HERE; forward-coupled to Phase 20 GRD-01)

**Canonical key (RECOMMENDED, this is the contract Phase 20 consumes):**

```
ralphe:entitlement:{tenant_id}:{module_key}
```

**This is not a free choice — it is fixed by two anchors already in the repo:**
1. **ROADMAP Phase 20 success criterion 1 (`:147`)** literally specifies `ralphe:entitlement:<tenant_id>:<module_key>` as the cache-aside key the Redis-cached guard will populate/read. Phase 19's `DEL` MUST match it byte-for-byte or revocation won't invalidate the live cache → security regression (the exact thing AUD-02 exists to prevent).
2. **The `ralphe:` prefix is the established repo convention** — `scripts/test-redis.sh` uses `ralphe:dedupe:…`; the guard's other Redis keys live under `ralphe:`. Reusing it keeps key-space hygiene.

`{tenant_id}` = the canonical UUID **as a string** (`00000000-0000-0000-0000-000000000001` in CI; the live UUID discovered at 🔴 VPS apply per ADR 0001). `{module_key}` = `tenant-entitlement.module_key` (= `product-module.key`).

**Invalidation strategy — recommendation: DEL-by-exact-key for `tenant-entitlement`; per-tenant fan-out for `product-module`.** Tradeoffs evaluated:

| Strategy | Use for | Verdict |
|----------|---------|---------|
| **`DEL ralphe:entitlement:{tenant_id}:{module_key}`** (exact) | `tenant-entitlement` create/update/delete | ✅ **CHOSEN** — the changed row maps to exactly one key. O(1), no scan, prod-hot-path-safe. Both `tenant_id` and `module_key` are on the row. |
| `SCAN ralphe:entitlement:{tenant_id}:*` then DEL | `product-module` change (affects ALL tenants holding that module) | ⚠️ acceptable but `SCAN` is the only option that finds "every tenant's copy of this module". Use **`SCAN` (cursor-based), never `KEYS`** (KEYS blocks the single-threaded server in prod). Low frequency (product-module rows rarely change) makes a bounded SCAN tolerable. |
| Per-tenant **version counter** (`INCR ralphe:entver:{tenant_id}`; key embeds the version) | future, if SCAN cost ever matters | 🔭 documented as the scale-out option; **out of scope for Phase 19** — adds a read-path dependency Phase 20 hasn't built. Recommend NOT introducing it now (keep Phase 20's guard simple). |

**`product-module` nuance:** a `product-module` change (e.g. `enabled_globally` flips, or `tier` changes from `shared_core`) can change entitlement outcomes for *every* tenant, but the guard caches per-(tenant,module). Two honest options for the planner:
- **(a) Minimal/recommended:** `product-module` lifecycle writes the audit row (full audit coverage) but does **NOT** attempt a global cache flush — document that product-module definition changes are rare and operator-driven, and the ≤5-min positive TTL (Phase 20) bounds staleness. This keeps Phase 19 off the `SCAN` path entirely.
- **(b) Thorough:** `product-module` afterUpdate issues `SCAN ralphe:entitlement:*:{key}` + DEL. More correct, but introduces a SCAN and a cross-tenant fan-out Phase 20's cache shape (`{tenant}:{module}`) makes awkward (the module is the *last* segment, so the match pattern is `*:{key}` — a full-keyspace scan).
- **Recommendation:** ship **(a)** for Phase 19 (audit always; entitlement-row DEL always; product-module = audit-only invalidation deferred to the TTL), and record the (b) option in the ADR as a known, TTL-bounded gap. This keeps `DEL` O(1) on the hot entitlement path and avoids a prod `SCAN`.

**Redis client pattern (avoid the baseline TS error):** mirror `realtime.ts:1-27`'s **static** import + 2-arg numeric constructor — `import Redis from 'ioredis'; new Redis(port, host)` — NOT the `auth-ratelimit.ts:35-37` dynamic-import `new (await import('ioredis')).default(url, …)` form, which is the source of the **pre-existing** "ioredis not constructable" TS error (CMS TypeScript Compilation is already red; Phase 19 must not add NEW type errors but need not fix that one). Use a module-level memoized client (`let entRedis: Redis | null`), attach `.on('error', …)`, and guard with `USE_REDIS = !!process.env.REDIS_URL || !!process.env.REDIS_HOST` so a no-Redis dev/test boot doesn't throw. Connection env (verified across the repo): `REDIS_URL` OR `REDIS_HOST`(default `localhost`)+`REDIS_PORT`(default `6379`)+optional `REDIS_PASSWORD`.

---

## 6. Fail-Loud Write Semantics (criterion 4 — NOT silent fire-and-forget)

The criterion forbids "bare `continueOnFail`/swallow". Two failure surfaces, two postures:

1. **Audit-row write failure → fail-loud (counter/alert), but do NOT block the entitlement mutation.** This is the subtle tension: the entitlement write itself has *already committed* by the time `afterCreate`/`afterUpdate` runs (after-hooks fire post-commit), so throwing there cannot roll it back — it would only surface a 500 to the admin while the grant silently succeeded (worse). **Recommendation:** in the `after*` hook, `await` the audit write inside a try/catch that, on failure, (a) `strapi.log.error('[EntitlementAudit] write FAILED', err)` at **error** level (pageable), and (b) increments a metric/counter the existing metrics/alerting plane can scrape — mirror how `agent-chat.ts:293` routes a non-critical write through `.catch((e)=>…)` but **upgrade the swallow to an explicit error-log + counter** (the criterion's "routes to a counter/alert"). The key contrast with a bare swallow: the failure is **logged at error + counted**, never silently `.catch(()=>{})`. Document the "after-hook can't roll back" reasoning in the ADR.
2. **Canonical-UUID validation failure → fail-loud BEFORE insert.** Validate `tenant_id` is a canonical UUID (use the already-installed **`zod` ^4.3.6** — `z.string().uuid()`) before the insert. An invalid/`'default'`-style value must throw/skip-with-error-log, never insert a malformed audit row. This is the mirror of the Phase-18 fail-loud `beforeCreate` throw (`order/lifecycles.ts:16`, `customer/lifecycles.ts:14`).
3. **Cache `DEL` failure → log at warn + count, do NOT block.** A Redis outage must not break entitlement edits; but a failed DEL means a stale grant could survive → log at **warn** and count so it's visible. (Phase 20's guard is fail-closed on Redis error, which bounds the blast radius.)

**Net posture:** validate-then-write; the *validation* throws (pre-write, loud), the *audit write* and *DEL* log-at-error/warn + increment a counter (post-commit, can't-rollback, but never silently swallowed). No `continueOnFail`, no bare `.catch(()=>{})`.

---

## 7. Validation Architecture

> `workflow.nyquist_validation: true` in `.planning/config.json` — this section is REQUIRED.

### The testable seam (the hard part — designed to avoid a full Strapi boot)

Booting full Strapi in CI is heavy and the CMS TS compile is already red. **Factor the audit-write + cache-DEL into a pure helper** that takes injected `(knex, redis, eventLike)` so it can be unit-tested in plain Node against an **ephemeral Postgres** (strapi-DB schema) + an **ephemeral `redis-server`** — **no Strapi boot, no Strapi types on the test path**:

```
audit-hook.ts  exports:
  deriveAction(oldValue, newValue) -> string         (pure, no IO — unit test in isolation)
  validateTenantId(tenant_id) -> string | throws     (zod, pure)
  writeAuditRow(knex, {tenant_id, module_key, action, changed_by, old_value, new_value}) -> Promise
  invalidateCache(redis, tenant_id, module_key) -> Promise   (DEL exact key)
lifecycles.ts  is the thin Strapi adapter that calls the above with strapi.db.connection / the ioredis client.
```

The CI/local test imports `audit-hook.ts` directly (it has no `@strapi/strapi` import — only `knex`/`ioredis`/`zod` types) and drives it against the two ephemeral services.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | **`node --test`** (Node 22.22.2, TAP — verified available) for the helper unit/integration test; **Bash + psql + redis-cli** for the CI assertion shell, mirroring Phase 18 | 
| Config file | `.github/workflows/phase-19-assertions.yml` (new, Wave 0) — mirror `phase-18-assertions.yml` + add a `redis:7-alpine` service |
| Quick run (local helper test) | `node --test inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/__tests__/audit-hook.test.mjs` (or a `scripts/test-phase19.sh` harness that boots ephemeral PG + redis first) |
| Full suite (CI) | push PR → `phase-19-assertions.yml` (SQL job + redis job + structural jq job) |
| **Local Postgres (docker DOWN)** | system `postgres` user + `/usr/lib/postgresql/16/bin` (verified end-to-end in Phase 18) — see below |
| **Local Redis (docker DOWN)** | `redis-server --port 7390 --save "" --appendonly no` then `redis-cli -p 7390` — **VERIFIED working locally 2026-06-20** (SET→DEL→GET nil round-trip on the exact canonical key) |

### Local ephemeral services (both verified on this host 2026-06-20)

**Redis (binary present at `/usr/bin/redis-server` + `/usr/bin/redis-cli`; not running by default):**
```bash
redis-server --port 7390 --daemonize yes --save "" --appendonly no --dir /tmp
redis-cli -p 7390 set "ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp" 1
redis-cli -p 7390 get "ralphe:entitlement:...:channel_whatsapp"   # -> "1"
# run invalidateCache() helper here
redis-cli -p 7390 get "ralphe:entitlement:...:channel_whatsapp"   # -> (nil)  ✅ proven
redis-cli -p 7390 shutdown nosave
```
**Postgres (docker DOWN; root cannot `initdb`):** as the `postgres` system user via `/usr/lib/postgresql/16/bin` (identical mechanism to Phase 18 §5 — `initdb -A trust`, `pg_ctl start -o '-p 55433 -k <socket>'`, apply the `entitlement_audit_log` DDL, run the helper, assert the row).

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUD-01 | `afterCreate` writes one `entitlement_audit_log` row (action=`created`, new_value set, old_value null) | node-test + psql | `node --test …/audit-hook.test.mjs` → asserts `SELECT count(*)` = 1 after a create | ❌ Wave 0 |
| AUD-01 | `afterUpdate` writes a row capturing old→new (old_value = pre-row, new_value = post-row) | node-test + psql | same harness, update path | ❌ Wave 0 |
| AUD-01 | `afterDelete` writes a row (action=`deleted`, old_value set, new_value null) | node-test + psql | same harness, delete path | ❌ Wave 0 |
| AUD-01 | writer targets the strapi-DB `entitlement_audit_log` (table exists) — cross-DB resolved | psql schema check | `psql … -c "SELECT to_regclass('entitlement_audit_log')"` ≠ null | ❌ Wave 0 |
| AUD-01 | `lifecycles.ts` present on BOTH `tenant-entitlement` and `product-module` | structural | `test -f …/tenant-entitlement/content-types/tenant-entitlement/lifecycles.ts && test -f …/product-module/.../lifecycles.ts` | ❌ Wave 0 |
| AUD-01 | `tenant_id` validated to canonical UUID before insert (invalid → no row) | node-test | drive helper with `tenant_id='default'` → asserts throw/skip + 0 rows | ❌ Wave 0 |
| AUD-01 | audit write failure is NOT silently swallowed (error-log + counter) | node-test | inject a knex that rejects → assert the error path logs/counts (no bare swallow) | ❌ Wave 0 |
| AUD-02 | a key present before a mutation is **gone** after (no stale grant) | node-test + redis-cli | SET key → run `invalidateCache()` → `GET` returns nil (**proven locally**) | ❌ Wave 0 |
| AUD-02 | `DEL` uses the canonical `ralphe:entitlement:{tenant_id}:{module_key}` key (matches Phase-20 GRD-01) | structural grep | `grep -q "ralphe:entitlement:" …/audit-hook.ts` | ❌ Wave 0 |
| AUD-02 | no NEW CMS TS errors introduced (baseline ioredis-not-constructable allowed) | tsc-diff | `cd inventory-cms && npx tsc --noEmit` error count ≤ baseline | ⚠️ baseline red |

### Sampling Rate
- **Per task commit:** `node --test` on the helper (quick, no Strapi); structural grep for the canonical cache-key + lifecycle-file presence; `npx tsc --noEmit` error-count must not exceed baseline.
- **Per wave merge:** full `phase-19-assertions.yml` (PG job + redis job + structural job).
- **Phase gate:** full suite green + ADR 0003 recorded before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `.github/workflows/phase-19-assertions.yml` — PG (`postgres:15-alpine`) + Redis (`redis:7-alpine`) services + structural jq job (mirror `phase-18-assertions.yml`)
- [ ] `db/ci-fixtures/19-entitlement-audit-seed.sql` — `entitlement_audit_log` DDL (from §1) + a `tenant_entitlements` seed row under the canonical UUID
- [ ] `db/ci-assertions/19-entitlement-audit.sql` — psql DO-block: assert a row exists per op (nested `BEGIN..EXCEPTION` for the invalid-uuid negative case; **NEVER `SAVEPOINT`/`ROLLBACK TO` in a DO block**)
- [ ] `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/__tests__/audit-hook.test.mjs` — node-test driving the pure helper against ephemeral PG + redis
- [ ] `scripts/test-phase19.sh` — local harness booting ephemeral PG (system `postgres` user) + ephemeral `redis-server`, then running the node-test (so the whole suite is locally runnable with docker DOWN)
- [ ] (no framework install — `node --test`, `psql`, `redis-cli`, `jq` all present)

---

## Standard Stack

### Core (all already in repo — milestone constraint: NO new runtime libraries)

| Component | Version | Purpose | Source |
|-----------|---------|---------|--------|
| Strapi 5 lifecycles (`beforeUpdate`/`afterCreate`/`afterUpdate`/`afterDelete`) | 5.37.1 | The audit + invalidation hook surface on `tenant-entitlement` + `product-module` | `inventory-cms/src/api/*/content-types/*/lifecycles.ts` (4 exist: order/customer/payment/conversation-state) |
| `strapi.db.connection` (Knex) | bundled | Raw insert into the non-content-type `entitlement_audit_log` table (strapi DB) | `agent-chat.ts:107`, `control-plane.ts:76` |
| `ioredis` | ^5.10.0 | `DEL` the entitlement cache key | `inventory-cms/package.json:21`; `realtime.ts:1-27` (static-import constructable pattern) |
| `pg` | ^8.18.0 | (transitive, via Knex/Strapi) the strapi-DB driver | `inventory-cms/package.json:22` |
| `zod` | ^4.3.6 | Canonical-UUID validation of `tenant_id` before insert | `inventory-cms/package.json:27` |
| `strapi.requestContext` | bundled | Actor capture (`changed_by`) — AsyncLocalStorage | Strapi 5 docs (verified) |
| `node --test` | Node 22.22.2 | Pure-helper unit/integration test (no Strapi boot) | host-verified |
| ephemeral `redis-server` / `redis-cli` | system `/usr/bin/redis*` | Local + CI invalidation test | host-verified (round-trip proven) |
| ephemeral Postgres 16 (local) / 15-alpine (CI) | `/usr/lib/postgresql/16/bin` | Local + CI audit-row assertion | Phase 18 §5 mechanism |

**Installation:** None. No new packages, no new credentials (Redis env already wired; strapi DB already connected).

**Version verification (2026-06-20, from `inventory-cms/package.json`):** `@strapi/strapi 5.37.1`, `ioredis ^5.10.0`, `pg ^8.18.0`, `zod ^4.3.6`. No registry fetch needed — these are the pinned, already-installed versions the milestone forbids changing.

---

## Architecture Patterns

### Recommended file layout (disjoint ownership for 3 plans)
```
inventory-cms/src/api/
├── tenant-entitlement/content-types/tenant-entitlement/
│   ├── lifecycles.ts          # 19-02 — thin Strapi adapter (before/after hooks)
│   ├── audit-hook.ts          # 19-02/19-03 — PURE helper (knex, redis, zod) — the testable seam
│   └── __tests__/audit-hook.test.mjs   # 19-03 — node --test
└── product-module/content-types/product-module/
    └── lifecycles.ts          # 19-02 — same helper, maps `key`→module_key, audit-only invalidation
db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql   # 19-01 — VARCHAR→uuid + nullable FK (🔴 VPS)
db/ci-fixtures/19-entitlement-audit-seed.sql                 # 19-03
db/ci-assertions/19-entitlement-audit.sql                    # 19-03
.github/workflows/phase-19-assertions.yml                    # 19-03
docs/adr/0003-entitlement-audit-placement.md                 # 19-01
scripts/test-phase19.sh                                      # 19-03
```

### Pattern 1: Pure helper + thin Strapi adapter (the testability keystone)
**What:** All logic (action derivation, uuid validation, knex insert, redis DEL) lives in `audit-hook.ts` with **zero `@strapi/strapi` imports** — it accepts `(knex, redis, eventLike)`. `lifecycles.ts` only wires `strapi.db.connection` + the memoized ioredis client + `strapi.requestContext` into it.
**When:** Always — it is what makes CI fast (no Strapi boot) and keeps the CMS TS-red boot off the test path.
**Anti-pattern:** putting the insert directly in `lifecycles.ts` (then you can only test by booting Strapi).

### Pattern 2: Capture-old-in-before, write-in-after
**What:** `beforeUpdate`/`beforeDelete` fetch the prior row and stash on `event.state.oldValue`; `afterUpdate`/`afterDelete` read it back. (§3.)
**When:** Any time the audit needs `old→new` — Strapi 5 `after*` events don't carry the old value.

### Pattern 3: Validate-throw, write-log-and-count
**What:** uuid validation throws pre-write (loud); the post-commit audit insert + cache DEL log-at-error/warn + increment a counter on failure (never a bare swallow). (§6.)

### Anti-Patterns to Avoid
- **`strapi.db.query('api::entitlement-audit-log…')`** — there is NO such content type/UID; this throws. Use raw Knex `strapi.db.connection('entitlement_audit_log')`.
- **Dynamic `new (await import('ioredis')).default(url,…)`** — the source of the baseline "not constructable" TS error. Use the static `import Redis from 'ioredis'; new Redis(port, host)` form (`realtime.ts`).
- **Throwing in `afterCreate`/`afterUpdate` to "block" a bad audit** — the entitlement write already committed; throwing only 500s the admin while the grant stuck. Log+count instead.
- **`KEYS` in the invalidation path** — blocks the single-threaded Redis server. Use exact `DEL` (entitlement) or bounded `SCAN` (product-module, option b only).
- **A second/n8n-DB connection for the audit writer** — unnecessary; the table is in the strapi DB Strapi already connects to.
- **`SAVEPOINT`/`ROLLBACK TO` inside a psql `DO` block** in the CI assertion — disallowed; use nested `BEGIN..EXCEPTION` for the invalid-uuid negative test (Phase 18 §5 pitfall 5).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Insert into a non-content-type table | A bespoke `pg.Client` from scratch | `strapi.db.connection` (the existing Knex) | Same DB, pooled, already the strapi-DB connection (`agent-chat.ts:107`). |
| UUID validation | A hand-rolled regex | `zod` `z.string().uuid()` (already installed) | Milestone bans new libs; zod is in `package.json`. |
| Acting-user lookup in a lifecycle | Threading `ctx` through manually | `strapi.requestContext.get()?.state?.user?.email` | Strapi-5 AsyncLocalStorage; works inside lifecycles (verified). |
| Redis client | A new connection per hook call | A module-memoized `ioredis` client (`realtime.ts` pattern) | Avoids socket churn + the not-constructable dynamic-import bug. |
| Cache-key format | Inventing a new key shape | `ralphe:entitlement:{tenant_id}:{module_key}` (ROADMAP `:147`) | MUST match Phase-20 GRD-01 or revocation won't invalidate. |
| CI DB/Redis in this env | Waiting on docker | system `postgres` user + ephemeral `redis-server` | docker is DOWN; both verified locally. |

**Key insight:** Phase 19's hard parts are *decisions already settled by the codebase* (table-in-strapi-DB, raw-Knex writer, fixed cache key) and *one Strapi-5 mechanic* (old-value capture in before-hooks). The mechanism is small; the discipline (fail-loud not swallow, validate-before-insert, exact-key DEL) is the load-bearing part.

---

## Common Pitfalls

### Pitfall 1: Assuming `entitlement_audit_log` is a Strapi content type
**What goes wrong:** Writing `strapi.db.query('api::entitlement-audit-log.entitlement-audit-log').create(...)` — throws "model not found".
**Why:** It's a raw SQL-migration table; no `schema.json` exists (grep-confirmed).
**Avoid:** Raw Knex `strapi.db.connection('entitlement_audit_log').insert({...})`.

### Pitfall 2: `afterUpdate`/`afterDelete` have no old value
**What goes wrong:** `event.params.data` only has the *changed* fields (a partial), and there's no `previousValue` — so `old_value` ends up null/partial.
**Avoid:** Fetch + stash the full prior row in `beforeUpdate`/`beforeDelete` → `event.state.oldValue` (§3).

### Pitfall 3: `product-module` key column is `key`, not `module_key`
**What goes wrong:** The shared helper reads `result.module_key` and gets `undefined` for product-module rows.
**Avoid:** Map `product-module.key` → the audit `module_key` column in the product-module adapter.

### Pitfall 4: Throwing in an after-hook to block a bad audit
**What goes wrong:** The entitlement row already committed (after-hooks fire post-commit); the throw 500s the admin while the grant silently stuck — worse than no audit.
**Avoid:** Validate (uuid) in/ before the write and throw there; for the post-commit insert/DEL, log-at-error + count, don't throw (§6).

### Pitfall 5: Stale grant survives because the DEL key doesn't match the guard's GET key
**What goes wrong:** Phase 20's guard reads `ralphe:entitlement:{t}:{m}` but Phase 19 DELs a differently-shaped key → revocation leaves a live cached grant — the exact security regression AUD-02 exists to stop.
**Avoid:** Lock the key to `ralphe:entitlement:{tenant_id}:{module_key}` (ROADMAP `:147`) and add a structural grep asserting it; record it in ADR 0003 as the Phase-20 contract.

### Pitfall 6: Redis client lifecycle — connection leak / not-constructable
**What goes wrong:** Constructing a new `ioredis` per hook call leaks sockets; the dynamic-import form re-triggers the baseline TS error.
**Avoid:** Module-memoized client (`let entRedis: Redis|null`) with static `import Redis from 'ioredis'` + `.on('error')` (`realtime.ts`). Guard with `USE_REDIS` so a no-Redis test/dev boot doesn't throw.

### Pitfall 7: `afterDelete` losing `tenant_id`
**What goes wrong:** Relying solely on `event.result` for the delete audit; under Strapi-5 draft/publish, delete can fire on a copy with surprising fields.
**Avoid:** Capture `tenant_id`/`module_key` in `beforeDelete` → `event.state` and prefer those for the delete row.

### Pitfall 8: Adding NEW CMS TypeScript errors
**What goes wrong:** CMS TypeScript Compilation is already red (baseline `ioredis not constructable` in `auth-ratelimit.ts:37`). New `any`-untyped event handling could add fresh errors and confuse the gate.
**Avoid:** Type the helper cleanly (it imports only `knex`/`ioredis`/`zod`), keep `event: any` in the thin adapter (matches the existing lifecycle files), and gate on `tsc --noEmit` **error-count ≤ baseline**, not zero.

---

## State of the Art

| Old Approach | Current Approach (Phase 19) | When | Impact |
|--------------|-----------------------------|------|--------|
| `entitlement_audit_log` table exists but has **zero writers** (dead table since the Phase-16 migration) | A `lifecycles.ts` raw-Knex writer on `tenant-entitlement` (+`product-module`) fills it on every op | Phase 19 | Audit coverage actually exists; the ADR-0001 "writers come in Phase 19" promise is kept |
| `entitlement_audit_log.tenant_id VARCHAR(255)` (string plane) | migrate → `uuid` + nullable FK to `tenants` (mirrors `admin_audit_log.tenant_id`) | Phase 19 (ADR 0001 `:101`) | Audit rows join the canonical UUID plane; bad values rejected at the DB too |
| Guard has **no cache** (2 Strapi `fetch()` per inbound msg, `W0_MODULE_GUARD.json` confirmed) | Phase 19 *defines + invalidates* the cache key; Phase 20 *populates* it | P19 then P20 | The invalidation hook MUST land before caching is turned on, else revocation can't evict (security regression) — this is why P19 precedes P20 in the chain |
| Strapi 4 `entityService` audit examples (the official blog) | Strapi 5 raw-Knex + `requestContext` + before-hook old-capture | Strapi 5 | The blog's `strapi.entityService.create` + `result.createdBy` pattern is outdated for a non-content-type table; use raw Knex |

**Deprecated/outdated:** `strapi.entityService.*` (Strapi 4 era) for this write — the target isn't a content type; `result.createdBy` for "who" (unreliable) → use `requestContext`.

---

## Open Questions

1. **O-1: `product-module` cache invalidation breadth.** A `product-module` definition change can affect every tenant holding that module, but the cache is per-(tenant,module).
   - Known: the canonical key puts `module_key` **last** (`…:{module_key}`), so a "flush all tenants for module X" needs `SCAN *:{key}` (full-keyspace) — costly.
   - Recommendation (sensible default): **audit-only on `product-module`** (write the row, do NOT global-flush); rely on Phase-20's ≤5-min positive TTL to bound staleness; record as a TTL-bounded known gap in ADR 0003. Adopt the `SCAN` fan-out only if a later phase shows staleness matters. (Avoids a prod `SCAN`/`KEYS`.)

2. **O-2: Bulk ops (`updateMany`/`deleteMany`) audit coverage.** Single-row hooks don't fire per-row for bulk.
   - Recommendation: cover single-row (the real operator path) now; document bulk as out-of-scope for this milestone (no self-serve bulk grant exists). Add `*Many` hooks only if the planner wants completeness.

3. **O-3: `entitlement_audit_log.tenant_id` uuid migration timing.** ADR 0001 assigned the `VARCHAR→uuid` + FK migration to Phase 19.
   - Recommendation: land it in 19-01 as a new idempotent `db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql` (ADD nothing if already uuid; `ALTER … TYPE uuid USING tenant_id::uuid`; add nullable FK; idempotent guards). 🔴 VPS apply deferred. The CI/local schema for the assertion can create the table already-uuid so the helper test exercises the post-migration shape. **Decision needed:** keep `VARCHAR` for Phase 19 (defer uuid again) vs migrate now — recommend **migrate now** since this is the phase ADR 0001 named and the writer is the right enforcement point.

---

## 🔴 VPS Deferrals
- Applying `2026-06-20_entitlement_audit_uuid.sql` to the **production strapi DB** (and the live-tenant-UUID discovery rule from ADR 0001 — never hardcode `…0001` on prod).
- **Rebuilding the CMS on prod** — `lifecycles.ts` + any schema/attr change requires a Strapi build/restart to take effect (RoadMap `:69-70` AUD-01/AUD-02 "rebuild CMS on VPS").
- Provisioning/confirming the prod `REDIS_URL`/`REDIS_HOST` the hook's `DEL` targets (must be the SAME Redis the Phase-20 guard reads).

---

## Sources

### Primary (HIGH confidence — direct repo reads, line-cited)
- `db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql:114-126` — exact `entitlement_audit_log` columns (strapi DB)
- `inventory-cms/config/database.ts:25-44` — Strapi → strapi DB (`DATABASE_NAME` default `strapi`)
- `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/schema.json` — entitlement attrs; **no lifecycles.ts**
- `inventory-cms/src/api/product-module/content-types/product-module/schema.json` — `key` (not `module_key`); **no lifecycles.ts**
- `inventory-cms/src/api/order/content-types/order/lifecycles.ts:9-18` + `customer/.../lifecycles.ts:10-17` — Phase-18 fail-loud `beforeCreate` throw pattern to mirror
- `inventory-cms/src/api/realtime/services/realtime.ts:1-27` — constructable `import Redis from 'ioredis'; new Redis(port,host)` memoized-client pattern
- `inventory-cms/src/middlewares/auth-ratelimit.ts:29-44` — the baseline "not constructable" dynamic-import form to AVOID; Redis env (`REDIS_URL`/`REDIS_HOST`/`REDIS_PORT`)
- `inventory-cms/src/api/system-config/controllers/agent-chat.ts:107-109,293,316` — raw-Knex (`strapi.db.connection`) + `ctx.state.user.email` + non-blocking `.catch` precedents
- `inventory-cms/src/api/control-plane/controllers/control-plane.ts:76` — `strapi.db.connection.raw`
- `workflows/W0_MODULE_GUARD.json` — guard has NO cache today; queries `tenant-entitlements` by `tenant_id`+`module_key`+`enabled` (the read shape the cache key must mirror)
- `inventory-cms/package.json:21,22,27` — `ioredis ^5.10.0`, `pg ^8.18.0`, `zod ^4.3.6` (already installed)
- `docs/adr/0001-canonical-tenant-key.md:88-104` — Phase-19-owns the `entitlement_audit_log.tenant_id` uuid migration + writers validate before insert; canonical CI UUID `…0001`
- `.github/workflows/phase-18-assertions.yml` — CI structure to mirror (ephemeral PG + structural jq jobs)
- `.planning/ROADMAP.md:126-141` (Phase 19), `:147` (Phase-20 cache key `ralphe:entitlement:<tenant_id>:<module_key>`)
- `.planning/REQUIREMENTS.md:30-31` (AUD-01, AUD-02)
- `scripts/test-redis.sh` + `scripts/db_migrate_all.sh:28,104-122` — `ralphe:` key convention; strapi-pass migration mechanism
- Local probes (2026-06-20): `redis-server`/`redis-cli` present at `/usr/bin`, ephemeral redis SET→DEL→GET-nil **round-trip proven** on the canonical key; `node --test` (Node 22.22.2) available; `/usr/lib/postgresql/16/bin/initdb` present; docker DOWN

### Secondary (MEDIUM confidence — official docs / verified web)
- Strapi 5 Models / lifecycle docs — event shape (`params`/`result`/`state`/`action`), full hook list incl. `*Many`, draft/publish delete-on-copy nuance: https://docs.strapi.io/cms/backend-customization/models
- Strapi 5 `strapi.requestContext.get()` to reach `ctx.state.user` inside a lifecycle (AsyncLocalStorage; must call inside the hook): https://docs.strapi.io/cms/backend-customization/requests-responses
- Strapi audit-log blog (pattern reference; note it uses the Strapi-4 `entityService` + `result.createdBy`, superseded here): https://strapi.io/blog/how-to-use-lifecyle-hooks-for-audit-logs-in-strapi

### Tertiary (LOW — flagged)
- Community forum threads on sharing state between before/after delete (corroborates `event.state` usage) — corroborated by the official docs above, so treated as MEDIUM.

---

## Metadata

**Confidence breakdown:**
- Cross-DB resolution (table in strapi DB, raw-Knex writer, no 2nd connection): **HIGH** — `database.ts` + migration path + grep (no content-type) all direct-read
- Audit table columns / write mapping: **HIGH** — exact DDL read with line numbers
- Cache-key contract: **HIGH** — fixed by ROADMAP `:147` + `ralphe:` repo convention; DEL/GET round-trip proven locally
- Strapi-5 lifecycle event shape + old-value capture: **MEDIUM-HIGH** — official docs + repo precedent; the `event.state` before→after pattern is the documented idiom
- Actor capture (`requestContext`): **MEDIUM-HIGH** — Strapi-5 docs verified; repo already reads `ctx.state.user.email` in controllers
- Validation architecture (ephemeral PG + redis, no Strapi boot): **HIGH** — redis round-trip + PG mechanism both verified on this host
- Fail-loud semantics: **HIGH** — mirrors Phase-18 throw pattern + the "after-hook can't roll back" reasoning is sound

**Research date:** 2026-06-20
**Valid until:** 2026-07-20 (stable — schemas, migration SQL, lifecycle files, and the pinned Strapi/ioredis/zod versions are static; cache-key contract is locked by the ROADMAP)

---

## RESEARCH COMPLETE

**Phase:** 19 — Entitlement Audit + Cache-Invalidation Lifecycle Hook
**Confidence:** HIGH

### Key Findings
- **Cross-DB question is already resolved by the codebase:** `entitlement_audit_log` lives in the **strapi DB** (the same DB Strapi connects to by default — `database.ts:31`), so the lifecycle writes it via the **existing `strapi.db.connection` (raw Knex)** — NO cross-DB connection, NO table move. And the table is **not** a Strapi content type (grep-confirmed), so it MUST be written with raw Knex, not `strapi.db.query('api::…')`.
- **Strapi-5 mechanic that shapes the design:** `afterUpdate`/`afterDelete` carry no *old* value — capture it in `beforeUpdate`/`beforeDelete` (`findOne({where: event.params.where})`) and stash on `event.state.oldValue`. "Who" = `strapi.requestContext.get()?.state?.user?.email ?? 'system'`.
- **Cache-key contract is locked:** `ralphe:entitlement:{tenant_id}:{module_key}` (ROADMAP `:147`, Phase-20 GRD-01 consumer) — exact-key `DEL` for entitlement rows (O(1), no SCAN); product-module → audit-only invalidation (TTL-bounded) to avoid a prod `SCAN`.
- **`redis-server` AND `redis-cli` ARE available locally** (`/usr/bin/`); ephemeral-redis SET→DEL→GET-nil **round-trip proven on the canonical key 2026-06-20**. The invalidation test runs locally with docker DOWN. Postgres assertion uses the Phase-18 system-`postgres`-user mechanism.
- **Fail-loud (criterion 4):** validate `tenant_id` to a canonical UUID (zod, already installed) and throw *before* the write; the post-commit audit insert + cache DEL log-at-error/warn + increment a counter (never a bare swallow) — after-hooks fire post-commit so throwing there can't roll back the grant.

### File Created
`.planning/phases/19-entitlement-audit-and-cache-invalidation-lifecycle-hook/19-RESEARCH.md`

### Confidence Assessment
| Area | Level | Reason |
|------|-------|--------|
| Cross-DB resolution | HIGH | `database.ts` + strapi-DB migration path + grep (no content-type) |
| Audit columns / write mapping | HIGH | Exact DDL line-cited |
| Cache-key contract | HIGH | ROADMAP-locked + local DEL/GET round-trip proven |
| Strapi-5 lifecycle old-value capture + requestContext | MEDIUM-HIGH | Official docs + repo precedent |
| Validation architecture (PG + redis, no Strapi boot) | HIGH | Both ephemeral services verified locally |

### Open Questions
1. O-1: `product-module` invalidation breadth — recommend **audit-only** (TTL-bounded), avoid prod SCAN.
2. O-2: bulk `*Many` audit coverage — recommend single-row now, document bulk as out-of-scope.
3. O-3: `entitlement_audit_log.tenant_id` `VARCHAR→uuid` migration timing — recommend **migrate now** in 19-01 (the phase ADR 0001 named); 🔴 VPS apply deferred.

### Ready for Planning
Proposed **3 plans**, disjoint file ownership:
- **19-01** — ADR `docs/adr/0003-entitlement-audit-placement.md` (cross-DB decision: strapi-DB, raw-Knex writer) + `db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql` (VARCHAR→uuid + nullable FK, idempotent; 🔴 VPS apply)
- **19-02** — `tenant-entitlement` + `product-module` `lifecycles.ts` + the pure `audit-hook.ts` (old→new capture, zod canonical-UUID validation, fail-loud counter/alert)
- **19-03** — Redis exact-key `DEL` in `audit-hook.ts` + validation harness: `inventory-cms/.../__tests__/audit-hook.test.mjs` (node --test), `db/ci-fixtures/19-*.sql`, `db/ci-assertions/19-*.sql`, `.github/workflows/phase-19-assertions.yml` (PG + `redis:7-alpine` + structural jobs), `scripts/test-phase19.sh`

**🔴 VPS deferred:** apply the uuid migration on prod strapi DB (live-tenant-UUID discovery, not `…0001`), **rebuild the CMS** for the lifecycle/attr changes, confirm the prod Redis the `DEL` targets matches the Phase-20 guard's Redis.
