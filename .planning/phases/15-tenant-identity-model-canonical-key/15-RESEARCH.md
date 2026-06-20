# Phase 15: Tenant Identity Model (Canonical Key) — Research

**Researched:** 2026-06-20
**Domain:** Multi-tenant identity reconciliation — PostgreSQL schema, Strapi seeder, n8n workflow fallback paths
**Confidence:** HIGH (all claims grounded in direct file reads; no inference-only claims)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEN-01 | Establish `tenants.tenant_id` (UUID) as the single canonical key; reconcile the entitlement plane's VARCHAR `tenant_id` to it; no runtime path silently substitutes the literal `'default'`. | Findings 1–5 below directly enable: the decision record (Plan 15-01), the backfill SQL (Plan 15-02), the seeder reconciliation + fallback inventory (Plan 15-03). |
</phase_requirements>

---

## Summary

Phase 15 is the keystone for the entire v2.0 milestone. The platform has **two structurally disjoint `tenant_id` systems** in the same Postgres instance that were never reconciled. The data plane (`orders`, `conversation_state`, `api_clients`, etc.) uses `uuid NOT NULL REFERENCES tenants(tenant_id)`. The entitlement plane (`tenant_entitlements` managed by Strapi, `entitlement_audit_log` created by the SaaS migration) uses an unconstrained `VARCHAR(255)`, currently seeded with the literal string `'default'`. These two planes will never match without intervention.

The canonical key is `tenants.tenant_id` (UUID). The data plane already uses it correctly. The entitlement plane must store the same UUID in string form. The real "first restaurant" seed already exists in `db/schema.sql` and `db/bootstrap.sql` with fixed UUIDs: `tenant_id = '00000000-0000-0000-0000-000000000001'` and `restaurant_id = '00000000-0000-0000-0000-000000000000'`. Phase 15's job is to: (1) document this decision formally, (2) backfill those literal `'default'` entitlement rows to the canonical tenant UUID, (3) fix the seeder so it reads from the env var or falls back to the canonical UUID rather than the string `'default'`, and (4) produce an annotated inventory of every `|| 'default'` / `DEFAULT_TENANT_ID` fallback so nothing is undocumented.

This is a documentation + SQL + seeder change — no schema migration to the data plane, no new tables, no new libraries. The entitlement plane is entirely on the Strapi DB side (Strapi auto-creates `tenant_entitlements`), so the backfill is a SQL UPDATE or a seeder-level fix, not a schema migration. The `entitlement_audit_log` type decision (keep `VARCHAR(255)` vs migrate to `uuid`) must be made and recorded, but the migration itself is deferred to Phase 16.

**Primary recommendation:** Keep `entitlement_audit_log.tenant_id` as `VARCHAR(255)` for Phase 15 — changing it to `uuid` requires Phase 16's migration infrastructure (live-safe `ALTER TABLE`) and writers do not yet exist. Record the decision and the rationale. The backfill and seeder fix use the canonical UUID as a string, which `VARCHAR(255)` accepts. Phase 19 will add the writers that must validate this field before insert.

---

## Standard Stack

### No new dependencies

Everything needed for Phase 15 is already present:

| Tool | Version | Purpose | Where |
|------|---------|---------|-------|
| `psql` / CI ephemeral Postgres | 15-alpine | Backfill SQL and assertion SQL | `.github/workflows/migration-validate.yml` pattern |
| `@strapi/strapi` | 5.37.1 | Seeder runtime (`strapi.query`) | `inventory-cms/package.json` |
| TypeScript (ts-node in `inventory-cms`) | Already installed | Seeder edit | `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` |
| Node.js `process.env` | N/A | Read `DEFAULT_TENANT_ID` in seeder | Already used at line 127 |

No `npm install` required. No library additions.

---

## Architecture Patterns

### The Two Tenant Planes — Exact Column Types

**Data plane (n8n DB, `db/schema.sql` and `db/bootstrap.sql`):**

- `db/schema.sql:9-10`: `tenants.tenant_id uuid PRIMARY KEY DEFAULT gen_random_uuid()`
- `db/bootstrap.sql:49`: same definition in the consolidated bootstrap
- `db/schema.sql:99`: `orders.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE`
- `db/bootstrap.sql:181`: same for the full-featured `orders` table
- `db/bootstrap.sql:86-87`: `restaurants.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE`
- `db/bootstrap.sql:106-107`: `api_clients.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE`
- `db/bootstrap.sql:160-163`: `conversation_state.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE`
- `db/bootstrap.sql:284-285`: `outbound_messages.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE`
- **Type: `uuid NOT NULL`, FK-enforced. Already correct.**

**Entitlement plane (strapi DB, Strapi-managed):**

- `db/migrations/2026-04-06_saas_modules_entitlements.sql:47`: `tenant_id VARCHAR(255) NOT NULL` in `entitlement_audit_log`
- `tenant_entitlements.tenant_id` — Strapi auto-created from content type schema, type inferred from seed value; effectively a text/varchar column. No FK to `tenants`.
- `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts:127`: `const defaultTenantId = process.env.DEFAULT_TENANT_ID || 'default';`
- `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts:128`: seeds `tenant_id: defaultTenantId` (i.e. the literal `'default'` in all environments where `DEFAULT_TENANT_ID` is unset)
- **Type: VARCHAR (Strapi-created), no FK, currently holding the string `'default'`.**

**The incompatibility:** `orders.tenant_id` holds `'00000000-0000-0000-0000-000000000001'` (UUID string as a uuid type column). `tenant_entitlements.tenant_id` holds `'default'` (a plain string). A join or comparison between the two planes silently returns zero rows or throws `invalid input syntax for type uuid: "default"`.

### The Seed / Real First Restaurant

`db/schema.sql:381-391` and `db/bootstrap.sql:2509-2533` seed fixed-UUID rows:

```sql
-- db/bootstrap.sql:2510-2517
INSERT INTO tenants(tenant_id, name, slug, plan, status)
VALUES ('00000000-0000-0000-0000-000000000001', 'Default Chain', 'default-chain', 'professional', 'active')
ON CONFLICT (tenant_id) DO NOTHING;

-- db/bootstrap.sql:2518-2533
INSERT INTO restaurants(restaurant_id, tenant_id, name, phone, default_language, is_active)
VALUES ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001', 'Branch 1', '+213000000000', 'fr', true)
ON CONFLICT (restaurant_id) DO NOTHING;
```

The canonical UUID for the first (and currently only) tenant is therefore **`'00000000-0000-0000-0000-000000000001'`**. This is the string the entitlement plane must store. It is already used by `api_clients` in `tests/fixtures/00_seed_api_clients.sql:10`.

### Reconciliation Options for the Entitlement Plane

| Option | What it means | Trade-offs for this project |
|--------|--------------|----------------------------|
| **A: Store UUID-as-string in existing VARCHAR(255)** | UPDATE `tenant_entitlements SET tenant_id = '00000000-0000-0000-0000-000000000001' WHERE tenant_id = 'default'`; seeder uses the UUID string | Zero schema change; no ALTER TABLE; no exclusive lock; acceptable for Phase 15 because no FK is required yet; writers (Phase 19) validate before insert. **Recommended for Phase 15.** |
| B: Migrate `tenant_entitlements.tenant_id` to `uuid` + FK | ALTER TABLE (via Strapi migration or raw SQL); need to handle Strapi's auto-created column; risky without live-safe infrastructure | Requires Phase 16's `CREATE INDEX CONCURRENTLY`/attach pattern; Strapi may regenerate the column on next boot unless the content-type schema is also updated; deferred. |

**Decision: Option A for Phase 15.** The planner records Option B as the target for Phase 16 or Phase 19 (when writers are wired and can validate types). `entitlement_audit_log.tenant_id` stays `VARCHAR(255)` through Phase 15 — changing it requires the live-safe migration infrastructure that Phase 16 provides.

### `entitlement_audit_log.tenant_id` Type Decision

- Current: `VARCHAR(255)` (`db/migrations/2026-04-06_saas_modules_entitlements.sql:47`)
- The good precedent: `admin_audit_log.tenant_id uuid NULL REFERENCES tenants(tenant_id)` (`db/bootstrap.sql:987-988`)
- **Decision to record:** Keep `VARCHAR(255)` through Phase 15 (no writers exist; no ALTER needed). Mark for migration to `uuid` with a nullable FK in Phase 19, when writers are wired and can validate the value before insert. Record the rationale: the table is created by the unapplied SaaS migration and has no writers yet; changing the type now would require the Phase 16 live-safe migration apparatus and the table doesn't need a FK until Phase 19 validates and inserts into it.

---

## Fallback Inventory — Every `|| 'default'` and `DEFAULT_TENANT_ID`

The following is a complete inventory of fallback occurrences found by repo-wide grep over `*.ts`, `*.js`, `*.json`, `*.sql`:

| # | File | Line | Pattern | Classification |
|---|------|------|---------|---------------|
| 1 | `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` | 127 | `process.env.DEFAULT_TENANT_ID \|\| 'default'` | **REMOVE** in Plan 15-03 — replace with canonical UUID constant |
| 2 | `workflows/W0_MODULE_GUARD.json` (node "Module Guard") | ~21 | `$input.first().json.tenant_id \|\| $env.DEFAULT_TENANT_ID \|\| 'default'` | **ANNOTATE / JUSTIFIED TEMPORARILY** — the guard receives `tenant_id` from the sealed context; this fallback is the fail-open risk documented in PITFALLS §2. Phase 17 removes it by ensuring the caller always provides a real UUID. For Phase 15: document it; do not remove (the guard is out of scope here). |
| 3 | `workflows/W1_IN_WA.json` (node "B0 - Apply Auth Context") | ~7-17 | `$env.DEFAULT_TENANT_ID \|\| ''` (then used as `defaultTenantId`); lines ~49, 54 assign it for `meta_signature` and `legacy_shared` auth modes | **ANNOTATE / JUSTIFIED TEMPORARILY** — this is the resolution ladder that Phase 17 will replace with a `channel_identities` lookup. For Phase 15: inventory and document; do not modify (the workflow is Phase 17 scope). |
| 4 | `workflows/W_DRIVER_ONBOARDING.json` (node "Ensure Customer Profile") | ~35 | `$json.tenant_id \|\| $env.DEFAULT_TENANT_ID \|\| '00000000-0000-0000-0000-000000000001'` in `queryParams` | **ANNOTATE / PARTIALLY JUSTIFIED** — falls back to the canonical UUID (not `'default'`), which is correct. But the fallback exists because tenant derivation is not yet trusted. Phase 17 will fix the upstream; this path becomes safe once derivation is correct. Document and flag for Phase 17. |
| 5 | `admin-dashboard/src/hooks/useEntitlements.ts` | 5 | `function useEntitlements(tenantId = 'default')` | **ANNOTATE / MARK FOR REMOVAL IN PHASE 21** — the default parameter value means the UI queries entitlements for `'default'` unless an authenticated context passes the real UUID. Out of scope for Phase 15; documented in the inventory. |

**Summary:** 5 occurrences total. Of these:
- 1 is **removed** by Plan 15-03 (the seeder)
- 1 is **annotated and left** pending Phase 17 (W0_MODULE_GUARD)
- 1 is **annotated and left** pending Phase 17 (W1_IN_WA B0 auth context)
- 1 is **annotated as partially safe** pending Phase 17 (W_DRIVER_ONBOARDING — falls to UUID, not `'default'`)
- 1 is **annotated and left** pending Phase 21 (useEntitlements.ts default param)

After Phase 15, the only runtime path that writes `'default'` into `tenant_entitlements.tenant_id` is eliminated (the seeder). The rest remain documented with phase assignments. No silent substitution remains undocumented.

---

## Backfill Approach

### What to backfill

The Strapi seeder (`saas-entitlements.ts`) runs on every CMS boot and creates `tenant_entitlements` rows with `tenant_id = 'default'`. The CI/local environment therefore has rows like:

```
tenant_entitlements.tenant_id = 'default', module_key = 'order_bot_core'
tenant_entitlements.tenant_id = 'default', module_key = 'channel_whatsapp'
... (one row per non-shared_core, non-experimental module)
```

The target is `tenant_entitlements.tenant_id = '00000000-0000-0000-0000-000000000001'` (the canonical UUID of the seeded tenant).

### Safe, idempotent backfill SQL

The `tenant_entitlements` table is in the **strapi** DB (Strapi auto-creates it). The backfill runs against the strapi DB, not the n8n DB. The SaaS migration also targets the strapi DB (it adds constraints to Strapi-created tables).

```sql
-- Backfill: replace 'default' entitlement rows with the canonical UUID
-- Idempotent: safe to run multiple times (ON CONFLICT DO NOTHING / WHERE clause)
-- Target DB: strapi

-- Step 1: assert the canonical tenant exists in the n8n DB (pre-condition check)
-- This is a CI assertion, not a migration:
-- SELECT 1 FROM tenants WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

-- Step 2: backfill tenant_entitlements
UPDATE tenant_entitlements
  SET tenant_id = '00000000-0000-0000-0000-000000000001'
WHERE tenant_id = 'default';

-- Step 3: verify (CI assertion)
-- SELECT COUNT(*) FROM tenant_entitlements WHERE tenant_id = 'default';
-- Expected: 0
```

**Idempotence:** If re-run after the seeder has already been fixed (seeder now seeds the UUID), the UPDATE affects 0 rows — safe. If a CI run seeds `'default'` and then the backfill runs, the UPDATE affects all those rows — correct. The absence of `uq_tenant_module` on the CI ephemeral Postgres (the SaaS migration may not have run) means there is no unique-constraint risk from the UPDATE itself.

**Cross-DB note:** `tenant_entitlements` is in the strapi DB; `tenants` is in the n8n DB. The backfill SQL only touches the strapi DB. The pre-condition assertion (that the canonical tenant exists) is a separate `psql` call against the n8n DB in the CI harness. Do not cross-DB JOIN in the backfill SQL.

### CI verification pattern

The existing `migration-validate.yml` applies `bootstrap.sql` then all migrations against an ephemeral Postgres. Phase 15's backfill SQL can be verified in the same job:

1. Apply `bootstrap.sql` (seeds the canonical tenant UUID in n8n DB)
2. Apply migrations (including `2026-04-06_saas_modules_entitlements.sql` which creates `entitlement_audit_log`)
3. Simulate the seeder writing `'default'` rows (a small SQL INSERT)
4. Apply the backfill SQL (the UPDATE)
5. Assert: `SELECT COUNT(*) FROM tenant_entitlements WHERE tenant_id = 'default'` returns 0
6. Assert: `SELECT COUNT(*) FROM tenant_entitlements WHERE tenant_id = '00000000-0000-0000-0000-000000000001'` matches expected count

Note: `tenant_entitlements` is a Strapi-created table, not created by `bootstrap.sql` or the current migration. The CI harness for Phase 15 must `CREATE TABLE tenant_entitlements (...)` in the ephemeral Postgres to simulate the Strapi-created table before the backfill SQL runs. This is a test-only fixture, not a production migration.

Minimal fixture for CI:

```sql
-- CI fixture only — simulates Strapi-auto-created table
CREATE TABLE IF NOT EXISTS tenant_entitlements (
  id serial PRIMARY KEY,
  tenant_id varchar(255) NOT NULL,
  module_key varchar(255) NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  activated_at timestamptz DEFAULT now(),
  activated_by varchar(255),
  notes text
);
-- Simulate seeder writing 'default'
INSERT INTO tenant_entitlements (tenant_id, module_key, enabled)
VALUES ('default', 'order_bot_core', true),
       ('default', 'channel_whatsapp', true),
       ('default', 'channel_instagram', true);
```

---

## Seeder Reconciliation (Plan 15-03)

### Current code (`saas-entitlements.ts:127`)

```typescript
const defaultTenantId = process.env.DEFAULT_TENANT_ID || 'default';
```

### Required change

Replace the string `'default'` fallback with the canonical fixed UUID:

```typescript
// The canonical UUID of the first restaurant's tenant — seeded by db/schema.sql and db/bootstrap.sql.
// This MUST match the 'Default Chain' tenant seeded at bootstrap time.
// If DEFAULT_TENANT_ID is set in env, that value is used (for future tenants).
// Never fall back to the string 'default' — that is an invalid tenant_id in the data plane.
const CANONICAL_FIRST_TENANT_UUID = '00000000-0000-0000-0000-000000000001';
const defaultTenantId = (process.env.DEFAULT_TENANT_ID || '').trim() || CANONICAL_FIRST_TENANT_UUID;
```

This is the minimal, safe change. No other lines in the seeder change. The seeder still uses `defaultTenantId` on lines 128, 163, 168, 174, 175 — all now resolve to the real UUID.

### Assertion for Plan 15-03

A unit/seed assertion can be a short TypeScript test or a `jest` test co-located in `inventory-cms/src/bootstrap-seeds/`:

```typescript
// saas-entitlements.test.ts (or a CI assertion script)
import { SAAS_MODULES } from './saas-entitlements';

describe('seedSaaSEntitlements', () => {
  it('never uses the string "default" as tenant_id', () => {
    const defaultTenantId = (process.env.DEFAULT_TENANT_ID || '').trim() || '00000000-0000-0000-0000-000000000001';
    expect(defaultTenantId).not.toBe('default');
    // UUID format check
    expect(defaultTenantId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
  });
});
```

Alternatively, a grep-based CI check: `grep -r "'default'" inventory-cms/src/bootstrap-seeds/saas-entitlements.ts | grep tenant_id` must return zero matches after Plan 15-03 lands.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| UUID validation in seeder | Custom regex validator | Simple `CANONICAL_FIRST_TENANT_UUID` constant + env var read | The UUID is a fixed known value; runtime validation adds complexity with no benefit at seed time |
| Backfill as a full migration file | A new `db/migrations/2026-06-xx_backfill_tenant_id.sql` targeting the strapi DB | A CI-assertion SQL script + seeder fix | The `db/migrations/` directory targets the n8n DB (run by the `db-migrate` init container against the `n8n` DB); the strapi DB is managed by Strapi. A migration file here would be applied to the wrong DB. |
| Type migration of `tenant_entitlements.tenant_id` to `uuid` | An ALTER TABLE in Phase 15 | Deferred to Phase 16/19 with live-safe apparatus | Requires `CREATE INDEX CONCURRENTLY` + `lock_timeout`; Strapi may regenerate the column schema on next boot; no writers exist yet to benefit from the constraint |

---

## Common Pitfalls

### Pitfall 1: Backfilling the wrong database
**What goes wrong:** `tenant_entitlements` is in the **strapi** DB (Strapi auto-creates it). `tenants` is in the **n8n** DB. A backfill script that JOINs both or targets the wrong DB will fail silently or with a "table not found" error.
**How to avoid:** The backfill SQL is a plain `UPDATE tenant_entitlements SET tenant_id = '...' WHERE tenant_id = 'default'` against the strapi DB. No cross-DB join. The pre-condition assertion (`tenants` row exists) runs separately against the n8n DB.

### Pitfall 2: Treating the fixed-UUID row as a permanent production UUID
**What goes wrong:** `'00000000-0000-0000-0000-000000000001'` is a well-known dev/test UUID from `db/schema.sql`. It is the *only* tenant that exists in CI and local dev. If the VPS has a different UUID for the real restaurant (e.g. from an earlier manual Strapi setup), backfilling to the hardcoded UUID will be wrong.
**How to avoid:** The VPS backfill (marked 🔴 deferred) must query the actual `tenants.tenant_id` from the n8n DB first, then use that value. For CI (ephemeral Postgres), the fixed UUID is correct because `bootstrap.sql` seeds it. The decision record must note this distinction.

### Pitfall 3: Seeder re-seeding `'default'` after backfill
**What goes wrong:** The seeder runs on every Strapi boot. If the seeder is not fixed (Plan 15-03), every restart overwrites the backfilled UUID with `'default'` via the `findOne`-then-`create` pattern.
**How to avoid:** Fix the seeder (Plan 15-03) before or simultaneously with the backfill. The seeder's `findOne` with `where: { tenant_id: defaultTenantId, module_key: mod.key }` will then look for `'00000000-0000-0000-0000-000000000001'` and, finding it, skip creation. No re-seeding of `'default'`.

### Pitfall 4: Leaving `uq_tenant_module` concern to Phase 15
**What goes wrong:** The SaaS migration adds `UNIQUE (tenant_id, module_key)` to `tenant_entitlements`. If both a `'default'` row and a `'00000000-0000-0000-0000-000000000001'` row exist for the same module key, there is no conflict — they have different `tenant_id` values. The UPDATE backfill would then violate the unique constraint if there are already UUID rows.
**How to avoid:** The seeder uses `findOne` and skips existing rows, so there should be no UUID rows unless seeded twice. But check: before the backfill runs, `SELECT COUNT(*) FROM tenant_entitlements WHERE tenant_id = '00000000-0000-0000-0000-000000000001'` should be 0 (first boot). If the constraint has been applied (Phase 16's job), the backfill must dedupe first. Phase 15's backfill assumes the constraint is NOT yet applied (safe assumption since Phase 16 hasn't run).

---

## Code Examples

### Seeder fix (Plan 15-03)

```typescript
// inventory-cms/src/bootstrap-seeds/saas-entitlements.ts:127 — BEFORE:
const defaultTenantId = process.env.DEFAULT_TENANT_ID || 'default';

// AFTER:
const CANONICAL_FIRST_TENANT_UUID = '00000000-0000-0000-0000-000000000001';
const defaultTenantId = (process.env.DEFAULT_TENANT_ID || '').trim() || CANONICAL_FIRST_TENANT_UUID;
```

### Backfill SQL (Plan 15-02)

```sql
-- Target DB: strapi
-- Run: psql -h pgbouncer -U strapi -d strapi -c "UPDATE ..."
-- Idempotent: safe to run N times

-- Pre-flight: count rows to backfill
SELECT COUNT(*) AS rows_to_update FROM tenant_entitlements WHERE tenant_id = 'default';

-- Backfill
UPDATE tenant_entitlements
  SET tenant_id = '00000000-0000-0000-0000-000000000001'
WHERE tenant_id = 'default';

-- Verify: must be 0 after backfill
SELECT COUNT(*) AS remaining_default_rows FROM tenant_entitlements WHERE tenant_id = 'default';
```

### CI assertion SQL (new CI step, Plan 15-02)

```sql
-- Assert: no 'default' rows remain in tenant_entitlements
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM tenant_entitlements WHERE tenant_id = 'default';
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FAIL: % entitlement rows still use tenant_id = ''default''', v_count;
  END IF;
  RAISE NOTICE 'PASS: no default-tenant entitlement rows';
END $$;

-- Assert: canonical UUID rows exist (at least one module seeded)
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM tenant_entitlements
    WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  IF v_count = 0 THEN
    RAISE EXCEPTION 'FAIL: no entitlement rows found for canonical tenant UUID';
  END IF;
  RAISE NOTICE 'PASS: % entitlement rows under canonical UUID', v_count;
END $$;
```

### Fallback inventory annotation comments (Plan 15-03)

Comments to add inline at each fallback site:

```javascript
// W0_MODULE_GUARD.json — node "Module Guard" line ~21:
// INVENTORY-15-01: || 'default' fallback here is a documented Phase-15 artifact.
// Phase 17 will remove this by ensuring callers always provide a real UUID from channel_identities.
// If this fires with 'default', it means tenant derivation failed upstream (Phase 17 gap).
const tenantId = $input.first().json.tenant_id || $env.DEFAULT_TENANT_ID || 'default'; // TODO-TEN-01: remove in Phase 17

// W1_IN_WA.json — node "B0 - Apply Auth Context" lines ~49, 54:
// INVENTORY-15-02: defaultTenantId is used for meta_signature and legacy_shared auth modes.
// This is the Phase-17 resolution gap — real tenant should come from channel_identities.
// Not removed in Phase 15 (Phase 17 scope).

// W_DRIVER_ONBOARDING.json — node "Ensure Customer Profile" queryParams:
// INVENTORY-15-03: || DEFAULT_TENANT_ID || '00000000-...-0001' fallback is safe (UUID, not 'default').
// Will be superseded by trusted derivation from channel_identities in Phase 17.

// useEntitlements.ts line 5:
// INVENTORY-15-04: default parameter 'default' is a Phase-21 cleanup item.
// The UI queries entitlements for 'default' when no authenticated context provides the real UUID.
// Aligned with ENT-01/ENT-02 scope (Phase 21).
```

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SQL assertions via `psql` in CI (existing pattern from `migration-validate.yml`) + Jest (if `inventory-cms` has a test runner) |
| Config file | `.github/workflows/migration-validate.yml` (existing, extend for Phase 15 assertions) |
| Quick run command | `psql -h localhost -U n8n -d strapi -f db/ci-assertions/15-tenant-canonical-key.sql` |
| Full suite command | `npm run test` in `inventory-cms/` (if Jest configured) or the SQL assertion file |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEN-01-a | `tenant_entitlements` has no rows with `tenant_id = 'default'` after backfill | SQL assertion | `psql ... -c "SELECT ... WHERE tenant_id='default'" \| grep -q ' 0 '` | ❌ Wave 0 |
| TEN-01-b | `tenant_entitlements` has rows with canonical UUID `'00000000-0000-0000-0000-000000000001'` | SQL assertion | `psql ... -c "SELECT COUNT(*) FROM tenant_entitlements WHERE tenant_id='00000000-0000-0000-0000-000000000001'" \| grep -vq ' 0 '` | ❌ Wave 0 |
| TEN-01-c | Seeder (`saas-entitlements.ts`) never writes `'default'` as `tenant_id` | grep CI check | `grep -rn "'default'" inventory-cms/src/bootstrap-seeds/saas-entitlements.ts \| grep tenant_id \| wc -l \| grep -q '^0$'` | ❌ Wave 0 |
| TEN-01-d | Seeder `defaultTenantId` resolves to UUID format when `DEFAULT_TENANT_ID` unset | Unit test | `jest inventory-cms/src/bootstrap-seeds/saas-entitlements.test.ts` | ❌ Wave 0 |
| TEN-01-e | Fallback inventory is complete — every `\|\| 'default'` annotated | grep audit | `grep -rn "\|\| 'default'" workflows/ inventory-cms/ admin-dashboard/ --include="*.ts" --include="*.js" --include="*.json" \| wc -l` equals 4 (the annotated-not-removed ones) | ❌ Wave 0 (grep count assertion) |

### Sampling Rate

- **Per plan commit:** SQL assertion (TEN-01-a, TEN-01-b) against ephemeral Postgres + grep check (TEN-01-c)
- **Per wave merge:** All 5 assertions above
- **Phase gate:** All assertions green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `db/ci-assertions/15-tenant-canonical-key.sql` — covers TEN-01-a, TEN-01-b (the DO $$ blocks above)
- [ ] `inventory-cms/src/bootstrap-seeds/saas-entitlements.test.ts` — covers TEN-01-d
- [ ] CI step in `migration-validate.yml` (or a new `phase-15-assertions.yml`) — wires TEN-01-a through TEN-01-e into the PR gate
- [ ] `db/ci-fixtures/15-tenant-entitlements-fixture.sql` — the `CREATE TABLE` + INSERT fixture for the strapi-side table in ephemeral Postgres

The SQL assertion file and CI fixture are the critical Wave 0 gaps. The Jest test is optional if `inventory-cms` doesn't have a test runner configured; in that case, TEN-01-d can be a node script: `node -e "const {defaultTenantId} = require('./...'); assert.match(defaultTenantId, /^[0-9a-f-]{36}$/);"`.

---

## State of the Art

| Old Approach (current) | Current Approach (after Phase 15) | Phase Changed | Impact |
|------------------------|-----------------------------------|---------------|--------|
| Seeder uses `'default'` literal as tenant_id | Seeder uses canonical UUID `'00000000-0000-0000-0000-000000000001'` or `$env.DEFAULT_TENANT_ID` | Phase 15 | Eliminates the root cause of the entitlement plane divergence |
| `tenant_entitlements` rows have `tenant_id = 'default'` | Rows have `tenant_id = '00000000-0000-0000-0000-000000000001'` (UUID string) | Phase 15 | Guard can now compare apples-to-apples once Phase 17 resolves real UUIDs from channels |
| `|| 'default'` in guard/workflow undocumented | All occurrences inventoried with phase assignment | Phase 15 | No silent substitution remains; roadmap for removal is explicit |
| `entitlement_audit_log.tenant_id VARCHAR(255)` undefined semantics | Documented decision: stays VARCHAR for Phase 15; migrate to uuid with FK in Phase 19 | Phase 15 (decision) | Prevents confusion about the type; sets the Phase 19 contract |

---

## Open Questions

1. **VPS live `tenant_entitlements` actual UUID**
   - What we know: The seeder has been running with `'default'` since the SaaS work was committed. If the SaaS migration was never applied to the VPS (P1 concern from CONCERNS.md), `tenant_entitlements` may not exist on the VPS at all, or may exist from Strapi auto-creation.
   - What's unclear: What UUID (if any) the VPS `tenant_entitlements.tenant_id` currently holds. Could be `'default'`, could be a real UUID if `DEFAULT_TENANT_ID` was set at some point, could be missing.
   - Recommendation: The 🔴 VPS backfill step (deferred to a prod-connected session) must first `SELECT DISTINCT tenant_id FROM tenant_entitlements` to see what's actually there, then apply the backfill using the UUID from `SELECT tenant_id FROM tenants LIMIT 1` on the n8n DB. Do not hardcode `'00000000-0000-0000-0000-000000000001'` for the VPS backfill — that UUID is for CI/dev only. **This is the one decision point the planner must surface explicitly: the VPS backfill must use a runtime query, not a hardcoded UUID.**

2. **Does Strapi's `strapi.query().findOne` use `tenant_id` as a DB column or a Strapi field name?**
   - What we know: In `saas-entitlements.ts:163`, the seeder uses `where: { tenant_id: defaultTenantId }`. Strapi 5 `query()` (raw DB query layer) treats field names as column names, so `tenant_id` maps to the DB column directly.
   - What's unclear: Whether Strapi's content-type for `tenant-entitlement` defines `tenant_id` as a custom field (short text) or uses the Strapi internal `documentId`. The schema at `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/schema.json` needs to be confirmed — if `tenant_id` is a custom field, the seeder is correct; if it's not in the schema, Strapi may not be creating the column.
   - Recommendation: Read `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/schema.json` during Plan 15-01 (the decision record plan). If the field is present, the seeder is correct. If absent, the table may not have a `tenant_id` column at all (Strapi would create only its internal fields).

---

## Sources

### Primary (HIGH confidence)
- `db/schema.sql:9-10, 99` — `tenants.tenant_id uuid PRIMARY KEY`, `orders.tenant_id uuid NOT NULL REFERENCES`
- `db/bootstrap.sql:49, 86, 106, 160, 181, 284, 987, 2509-2533` — consolidated bootstrap: all UUID FKs; seed rows for `'00000000-0000-0000-0000-000000000001'` / `'00000000-0000-0000-0000-000000000000'`
- `db/migrations/2026-04-06_saas_modules_entitlements.sql:46-58` — `entitlement_audit_log.tenant_id VARCHAR(255) NOT NULL`; table definition with no FK
- `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts:127-184` — `process.env.DEFAULT_TENANT_ID || 'default'`; seeder loop writing `tenant_id: defaultTenantId`
- `workflows/W0_MODULE_GUARD.json` node "Module Guard" line ~21 — `|| $env.DEFAULT_TENANT_ID || 'default'`
- `workflows/W1_IN_WA.json` node "B0 - Apply Auth Context" lines ~7-57 — `defaultTenantId` assignment, `meta_signature` and `legacy_shared` branches using it
- `workflows/W_DRIVER_ONBOARDING.json` node "Ensure Customer Profile" — `|| $env.DEFAULT_TENANT_ID || '00000000-...'` in queryParams
- `admin-dashboard/src/hooks/useEntitlements.ts:5` — `function useEntitlements(tenantId = 'default')`
- `tests/fixtures/00_seed_api_clients.sql:10` — `tenant_id = '00000000-0000-0000-0000-000000000001'` (confirms canonical UUID in test fixtures)
- `.github/workflows/migration-validate.yml` — existing CI pattern for ephemeral Postgres SQL assertion
- `.planning/research/SUMMARY.md`, `ARCHITECTURE.md`, `PITFALLS.md` — milestone research (HIGH — all claims grounded in codebase)
- `.planning/codebase/CONCERNS.md` — SaaS migration gap, entitlement plane analysis
- `.planning/REQUIREMENTS.md:15-17` — TEN-01 wording
- `.planning/ROADMAP.md:58-73` — Phase 15 success criteria

### Secondary (MEDIUM confidence)
- `.claude/skills/05_db_safety_protocol/SKILL.md` — migration safety rules (no destructive changes without restore plan; `CREATE INDEX CONCURRENTLY`)
- `.claude/skills/02_architecture_and_security/SKILL.md` — invariant checklist; system invariant 8 (DB changes safe + idempotent)
- `.claude/skills/11_workflow_governance/SKILL.md` — tenant isolation notes

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all tools verified present
- Architecture (two planes): HIGH — directly read from schema files with line citations
- Fallback inventory: HIGH — repo-wide grep over all TS/JS/JSON/SQL; 5 occurrences confirmed
- Backfill approach: HIGH (logic) / MEDIUM (VPS execution) — CI logic is verified; VPS execution deferred with a documented caveat about runtime UUID discovery
- Pitfalls: HIGH — grounded in PITFALLS.md which was itself grounded in direct file reads

**Research date:** 2026-06-20
**Valid until:** 2026-07-20 (stable domain; no fast-moving dependencies)

**One decision the planner must surface:** The VPS backfill (🔴 deferred) must use `SELECT tenant_id FROM tenants LIMIT 1` on the n8n DB to discover the real production UUID — it must NOT hardcode `'00000000-0000-0000-0000-000000000001'` (that is the CI/dev seed UUID only). Plans 15-01 and 15-02 should make this explicit.
