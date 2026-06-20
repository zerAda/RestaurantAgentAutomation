# ADR 0003: Entitlement Audit-Log Placement + Raw-Knex Writer + Cache-Key Contract

**Status:** Accepted
**Date:** 2026-06-20
**Phase:** 19
**Requirement:** AUD-01, AUD-02

---

## Context

The `entitlement_audit_log` table exists but has **zero writers** — it has been dead since the
Phase-16 SaaS migration created it (`db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql:114-126`).
Phase 19 (AUD-01) must give it real writers, and the ROADMAP Phase-19 **success-criterion 2** explicitly
asks the cross-DB write question: *"move the table to the strapi DB, or give the writer an explicit
n8n-DB connection — and implement the chosen path so the writer targets a table that actually exists."*

Two further questions are settled here:

- ADR 0001:101 promised the `entitlement_audit_log.tenant_id` `VARCHAR(255) → uuid` + nullable-FK
  migration would land **in Phase 19** ("Phase 19 wires the audit writers that must validate the value
  before insert — that is the right point to enforce the type").
- Phase 20 (GRD-01) will cache entitlement lookups in Redis; Phase 19's invalidation `DEL` must match the
  Phase-20 guard's `GET` key **byte-for-byte**, or a revoked grant survives in cache (the exact AUD-02
  security regression). The cache-key contract therefore must be locked here, before Phase 20 builds the
  read side.

This ADR records the placement decision, the writer mechanism, the cache-key contract, and the
open-question dispositions (O-1/O-2/O-3) so that 19-02 (the `lifecycles.ts` + `audit-hook.ts`) is a
mechanical execution against a settled design.

---

## Decision 1 — The audit table stays in the strapi DB; the writer is raw Knex.

**Chosen: Option A.** `entitlement_audit_log` stays where it already lives (the **strapi** DB) and the
lifecycle writer uses the existing `strapi.db.connection` (raw Knex) — **no cross-DB write, no second/n8n-DB
connection, no table move.**

Evidence chain:

- `entitlement_audit_log` is created by `db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql:114-126`
  — the **strapi-DB** migration pass (`db/migrations-strapi/`, applied with `PGDATABASE=strapi`).
- Strapi connects to that same DB by default: `inventory-cms/config/database.ts` → `database:
  env('DATABASE_NAME', 'strapi')`. A `tenant-entitlement` lifecycle runs *inside* that Strapi/Knex
  connection, so the writer targets a table in the **same** DB it is already connected to.
- The table is **NOT a Strapi content type** — there is no `schema.json` / UID for it anywhere in
  `inventory-cms/src` (grep-confirmed). Therefore `strapi.db.query('api::…')` / `strapi.documents` is
  **impossible** (no model). The writer MUST be raw Knex:
  `strapi.db.connection('entitlement_audit_log').insert({...})` (precedent: `agent-chat.ts:107-109`
  does `const knex = strapi.db.connection; knex('orders')…`; `control-plane.ts:76` does
  `strapi.db.connection.raw('SELECT 1')`).

| Option | Verdict | Why |
|--------|---------|-----|
| **A — table already in strapi DB; raw-Knex writer (CHOSEN)** | ✅ | The table and the writer share one connection. Zero new infra. Matches `agent-chat.ts:107` / `control-plane.ts:76` precedent. |
| B — move `entitlement_audit_log` to the n8n DB | ❌ | Would force a cross-DB writer (a *second* `pg`/Knex connection from Strapi to the n8n DB) for no benefit — the entitlement source-of-truth (`tenant_entitlements`) is in the strapi DB; co-locating the audit there is correct. |
| C — give the writer an explicit n8n-DB connection | ❌ | Only needed if (B); rejected for the same reason. Adds infra for no benefit. |

---

## Decision 2 — Cache-key contract (Phase-20 GRD-01).

**Canonical key (LOCKED):**

```
ralphe:entitlement:{tenant_id}:{module_key}
```

- Fixed by **ROADMAP:147** (Phase-20 success-criterion 1 literally specifies
  `ralphe:entitlement:<tenant_id>:<module_key>` as the cache-aside key the Redis-cached guard
  populates/reads) and the established `ralphe:` repo key-space convention (`scripts/test-redis.sh`).
- `{tenant_id}` = the canonical UUID **as a string** (`00000000-0000-0000-0000-000000000001` in CI; the
  live UUID discovered at 🔴 VPS apply per ADR 0001). `{module_key}` = `tenant-entitlement.module_key`
  (= `product-module.key`).
- The `tenant-entitlement` hook issues an **exact-key `DEL`** — O(1), **no `SCAN`/`KEYS`** on the hot path.
- The `DEL` MUST match the Phase-20 guard's `GET` **byte-for-byte**, else a stale grant survives a
  revocation — the precise AUD-02 regression. A structural CI grep asserts `audit-hook.ts` contains
  `ralphe:entitlement:`.

---

## Decision 3 — product-module = audit-only invalidation (O-1).

A `product-module` definition change (e.g. `enabled_globally` flips, `tier` changes) can affect entitlement
outcomes for *every* tenant holding that module, but the guard caches per-`(tenant,module)` with
`{module_key}` as the **last** key segment — so "flush all tenants for module X" would need a full-keyspace
`SCAN *:{key}`.

**Decision:** the `product-module` lifecycle **writes the audit row but does NOT global-flush the cache.**
The ≤5-min positive TTL (Phase 20) bounds staleness — recorded here as a **TTL-bounded known gap**. The
`SCAN *:{key}` fan-out (cursor-based, never `KEYS`) is the documented scale-out option if a later phase
shows the staleness matters. This keeps `DEL` O(1) on the hot entitlement path and keeps Phase 19 off any
prod `SCAN`/`KEYS`.

---

## Decision 4 — single-row audit now; bulk *Many out of scope (O-2).

The entitlement admin path is single-row (one tenant×module at a time), so the single-row hooks
(`afterCreate`/`afterUpdate`/`afterDelete`) cover the real operator path. Strapi's `afterUpdateMany`/
`afterDeleteMany` (bulk) are **out of scope** for this milestone — no self-serve bulk grant exists. This is
recorded as a documented gap; `*Many` hooks can be added later if a bulk-grant path is built.

---

## Decision 5 — migrate tenant_id VARCHAR→uuid now (O-3).

This **supersedes** ADR 0001:90 ("KEEP `VARCHAR(255)` through Phase 15") with **"migrate now in Phase 19"**
— the phase ADR 0001:101 named for the migration. The change lands as
`db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql`: a guarded
`ALTER … TYPE uuid USING tenant_id::uuid` (only when not already uuid) + a **nullable** FK to
`tenants(tenant_id)` (`NOT VALID` → `VALIDATE CONSTRAINT`, live-safe), mirroring
`admin_audit_log.tenant_id uuid NULL REFERENCES tenants(tenant_id)` (`db/bootstrap.sql:987-988`).

### `tenant_id` is NULLABLE — global product-module rows carry `tenant_id = NULL`

**(Authoritative correction — supersedes the plan/RESEARCH wherever they conflict.)** The
`entitlement_audit_log.tenant_id` column is migrated to **`uuid NULL`** (the FK is nullable, NULL allowed),
in direct parity with the `admin_audit_log.tenant_id uuid NULL REFERENCES tenants(tenant_id)` precedent
(ADR 0001:101-104, `db/bootstrap.sql:987-988`).

**Global product-module audit rows carry `tenant_id = NULL` (platform-scope), parity with
`admin_audit_log`; the all-zero sentinel `00000000-…-000000000000` is NOT used.** A `product-module` row
is a *global* module definition with no tenant; `NULL` is the legitimate "platform/global, not
tenant-scoped" value. Consequently the writer's `validateTenantId` **skips validation when `tenant_id` is
null/undefined** and validates only non-null values — a null `tenant_id` is allowed; a non-null,
non-canonical value (e.g. `'default'`) still throws pre-insert. The migration's FK is nullable so these
NULL-tenant rows are accepted; a non-null bogus UUID is still FK-rejected.

This keeps the migration, the writer (`audit-hook.ts`), the CI seed
(`19-entitlement-audit-seed.sql`), and the assertions/node-test **mutually consistent** around a nullable
`tenant_id` with a product-module `tenant_id IS NULL` path that the nullable FK does not reject.

---

## Fail-loud posture

Validate-then-write; the *validation* throws (pre-write, loud), the *audit write* and *DEL* log-at-error/warn
+ increment a counter (post-commit, can't-rollback, but never silently swallowed):

1. **Canonical-UUID validation → throw BEFORE insert.** `validateTenantId` validates a **non-null**
   `tenant_id` to canonical-UUID form (zod) and THROWS on a non-canonical value (e.g. `'default'`),
   pre-insert — a malformed audit row is never written. (A null `tenant_id` is the legitimate global value
   and is allowed; see Decision 5.) Mirrors the Phase-18 fail-loud `beforeCreate` throw
   (`order/lifecycles.ts`).
2. **Audit-row write failure → fail-loud, but do NOT block the entitlement mutation.** After-hooks fire
   **post-commit** — the entitlement write has already committed by `afterCreate`/`afterUpdate`/`afterDelete`,
   so throwing there cannot roll it back; it would only 500 the admin while the grant silently succeeded
   (worse). The hook `await`s the write inside a try/catch that on failure does
   `strapi.log.error('[EntitlementAudit] …', err)` (error level, pageable) **and** increments a module-level
   counter — never a bare `.catch(()=>{})`, never `continueOnFail`.
3. **Cache `DEL` failure → log at warn + count, do NOT block.** A Redis outage must not break entitlement
   edits; but a failed DEL means a stale grant could survive → log at warn + count so it's visible.
   (Phase 20's guard is fail-closed on Redis error, bounding the blast radius.)

### Note on the zod UUID validator (implementation correction)

The validator is **`z.string().guid()`**, not `z.string().uuid()`. Under the pinned `zod ^4.3.6`,
`z.string().uuid()` enforces RFC-9562 version/variant bits and therefore **rejects** the canonical CI
tenant `00000000-0000-0000-0000-000000000001` (and the all-zero form) — which the Postgres `uuid` column
accepts. `z.string().guid()` accepts any `8-4-4-4-12` hex string (matching the DB `uuid` plane) while still
rejecting `'default'`, empty, and malformed values. The structural CI grep accepts either `uuid` or `guid`.

---

## 🔴 VPS Deferrals

- Apply `db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql` on the **prod strapi DB** using the
  **LIVE** tenant UUID discovered on prod (ADR 0001 — `SELECT tenant_id FROM tenants LIMIT 1`; **never**
  hardcode `…0001`).
- **Rebuild the CMS** so the new `tenant-entitlement`/`product-module` `lifecycles.ts` + `audit-hook.ts`
  take effect (Strapi lifecycle/attr changes need a build/restart).
- Confirm the prod `REDIS_URL`/`REDIS_HOST` the hook's `DEL` targets is the **SAME** Redis the Phase-20
  guard reads (else revocation won't invalidate the live cache).

---

## Consequences

**(a)** 19-02 implements a raw-Knex writer + exact-key `DEL` against this settled placement — the table
stays in the strapi DB and is written via `strapi.db.connection`.

**(b)** The DB enforces the uuid plane (`tenant_id uuid NULL` + nullable FK to `tenants`), so a non-null
bogus value is rejected at the DB too; a null (global/product-module) value is tolerated.

**(c)** The cache-key contract `ralphe:entitlement:{tenant_id}:{module_key}` is locked for Phase 20 GRD-01;
revocation invalidation is structurally asserted in CI.

**(d)** product-module changes are audit-covered but TTL-bounded for cache staleness (O-1); bulk `*Many`
ops are an out-of-scope documented gap (O-2).
