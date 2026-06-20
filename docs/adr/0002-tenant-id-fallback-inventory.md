# ADR 0002: tenant_id Fallback Inventory (`|| 'default'` / DEFAULT_TENANT_ID)

**Status:** Accepted
**Date:** 2026-06-20
**Phase:** 15 (inventory), 17 (removals)
**Requirement:** TEN-01, TEN-03

---

## Context

As part of Phase 15 (Tenant Identity Model — Canonical Key), a repo-wide grep over `*.ts`, `*.js`,
`*.json`, and `*.sql` was conducted to find every location where the literal string `'default'` is
used as a fallback for `tenant_id` (via `|| 'default'` or `DEFAULT_TENANT_ID`).

**5 occurrences** were found. This ADR records each one with its exact location, the pattern found,
its disposition (REMOVE vs ANNOTATE/JUSTIFIED), and the owning phase responsible for its final
removal.

The canonical UUID for CI/dev is `00000000-0000-0000-0000-000000000001` (seeded by
`db/bootstrap.sql`). See `docs/adr/0001-canonical-tenant-key.md` for the full decision record.

---

## Complete Fallback Inventory

| # | File | Line / Node | Pattern | Disposition | Owning Phase |
|---|------|-------------|---------|-------------|--------------|
| 1 | `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` | 127 | `process.env.DEFAULT_TENANT_ID \|\| 'default'` | **REMOVED** (Phase 15) — replaced with `CANONICAL_FIRST_TENANT_UUID` constant and trimmed-env resolution | 15 |
| 2 | `workflows/W0_MODULE_GUARD.json` | node "Module Guard" (~L21) | `$input.first().json.tenant_id \|\| $env.DEFAULT_TENANT_ID \|\| 'default'` | **REMOVED (Phase 17)** — fallback deleted; guard now fails closed (`allowed:false`) on blank tenant_id | 17 |
| 3 | `workflows/W1_IN_WA.json` | node "B0 - Apply Auth Context" (~L6) | `$env.DEFAULT_TENANT_ID \|\| ''` (used as `defaultTenantId` for `meta_signature`/`legacy_shared` auth modes) | **REMOVED (Phase 17)** — defaultTenantId/fallback construct removed; tenant comes from channel_identities lookup (Plan 17-01) | 17 |
| 4 | `workflows/W_DRIVER_ONBOARDING.json` | node "Ensure Customer Profile" | `$json.tenant_id \|\| $env.DEFAULT_TENANT_ID \|\| '00000000-0000-0000-0000-000000000001'` (UUID-safe fallback, not `'default'`) | **REMOVED (Phase 17)** — UUID/env fallback removed from queryParams; NOT NULL enforces correctness | 17 |
| 5 | `admin-dashboard/src/hooks/useEntitlements.ts` | 5 | `function useEntitlements(tenantId = 'default')` | **ANNOTATED** (`// INVENTORY-15:` comment), left in place — Phase 21 cleanup item (ENT-01/ENT-02); UI queries entitlements for `'default'` until authenticated context provides the real UUID | 21 |

---

## Phase 15 Action Taken (Occurrence #1)

`inventory-cms/src/bootstrap-seeds/saas-entitlements.ts:127` — **REMOVED**.

Before (Phase 14 and earlier):
```typescript
const defaultTenantId = process.env.DEFAULT_TENANT_ID || 'default';
```

After (Phase 15):
```typescript
const CANONICAL_FIRST_TENANT_UUID = '00000000-0000-0000-0000-000000000001';
const defaultTenantId = (process.env.DEFAULT_TENANT_ID || '').trim() || CANONICAL_FIRST_TENANT_UUID;
```

Rationale: the seeder writes `tenant_id` into `tenant_entitlements` on every Strapi boot. Using the
literal `'default'` created a permanent divergence from the data plane (which uses `uuid` type FK
columns). The fix ensures the seeder always writes a valid UUID — either from `DEFAULT_TENANT_ID`
env var or the canonical CI/dev UUID.

---

## Phase 17 Action Taken (Occurrences #2, #3, #4)

Three workflow fallbacks have been **removed** as part of Phase 17 (Inbound Tenant Derivation — Fail-Closed):

- **#2 W0_MODULE_GUARD.json** node "Module Guard": The line
  `const tenantId = $input.first().json.tenant_id || $env.DEFAULT_TENANT_ID || 'default'`
  was replaced with a fail-closed guard:
  ```javascript
  const tenantId = ($input.first().json.tenant_id || '').toString().trim();
  if (!tenantId) {
    return [{ json: { allowed: false, reason: 'GUARD_ERROR: tenant_id not provided (UNKNOWN_CHANNEL_IDENTITY)' } }];
  }
  ```
  The `__inventory_15` annotation key was stripped from the node object. Phase 17 ensures callers
  always supply a real UUID derived from `channel_identities`, so the guard itself now also fails
  closed as defense-in-depth.

- **#3 W1_IN_WA.json** node "B0 - Apply Auth Context": The entire `defaultTenantId` /
  `fallbackTenantId` / `envDefaultTenantId` construct (and the `PROD_DEFAULTS_MISSING` block) were
  removed. The `meta_signature` and `legacy_shared` branches now use `ciTenantId` from the new
  `B0 - Resolve Channel Identity (DB)` → `B0 - Map Channel Identity Result` resolver rung. An
  unresolved identity sets `denyReason = 'UNKNOWN_CHANNEL_IDENTITY'` and routes through the
  existing `B0 - Token OK?` → `B0 - Log Deny (DB)` → `END - Drop/Done` path. The `__inventory_15`
  annotation key was stripped from the node object. W2_IN_IG and W3_IN_MSG had the same structural
  problem (hardcoded UUID `00000000-0000-0000-0000-000000000001` instead of env vars) — also fixed
  in the same Plan 17-01 rewrite; their duplicate `const metaSigValid` latent bug was also
  eliminated.

- **#4 W_DRIVER_ONBOARDING.json** node "Ensure Customer Profile": The queryParams expression
  `[$json.phone, $json.tenant_id || $env.DEFAULT_TENANT_ID || '00000000-0000-0000-0000-000000000001', $json.restaurant_id || $env.DEFAULT_RESTAURANT_ID || '00000000-0000-0000-0000-000000000000']`
  was replaced with `[$json.phone, $json.tenant_id, $json.restaurant_id]`. A missing tenant now
  causes a loud NOT NULL constraint violation rather than a silent wrong-tenant write. The
  `__inventory_15` annotation key was stripped from the node object.

---

## Phase 21 Remaining Work (Occurrence #5)

`admin-dashboard/src/hooks/useEntitlements.ts:5` — **annotated, left for Phase 21 (ENT-01/ENT-02)**.

The default parameter `tenantId = 'default'` means the UI queries `tenant_entitlements` for the
literal string `'default'` when no authenticated context passes the real UUID. This will return
zero rows (or stale rows) after the Phase 15 backfill. Phase 21 wires authenticated tenant context
to the UI and removes this default.

---

## Post-Phase 17 State

After Phase 17:

- A post-Phase-17 repo-wide grep for `|| 'default'` and `DEFAULT_TENANT_ID` on the **tenant path
  in `workflows/`** returns **ZERO matches**. Every workflow that previously fell back to
  `'default'` or `DEFAULT_TENANT_ID` now fails closed or derives the real tenant from the
  `channel_identities` table.
- Exactly **one annotated occurrence remains repo-wide**: occurrence #5
  (`admin-dashboard/src/hooks/useEntitlements.ts`, Phase 21 scope). This is a UI query parameter
  default and is documented above.
- The `__inventory_15` annotation keys have been stripped from all three fixed nodes
  (W0_MODULE_GUARD "Module Guard", W1_IN_WA "B0 - Apply Auth Context",
  W_DRIVER_ONBOARDING "Ensure Customer Profile").
- Structural CI assertions are encoded in `.github/workflows/phase-17-assertions.yml` and proven
  by `db/ci-assertions/17-tenant-resolution.sql`.

---

## References

- `docs/adr/0001-canonical-tenant-key.md` — canonical key decision record
- `inventory-cms/src/bootstrap-seeds/assert-canonical-tenant.mjs` — node assertion proving seeder fix
- `db/ci-assertions/15-backfill-tenant-entitlements.sql` — idempotent backfill SQL
- `db/ci-assertions/15-tenant-canonical-key.sql` — DO-block assertion
- `.github/workflows/phase-15-assertions.yml` — CI PR gate (Phase 15)
- `15-RESEARCH.md` "Fallback Inventory" section — research grounding these 5 occurrences
- `.planning/phases/17-inbound-tenant-derivation-fail-closed/17-RESEARCH.md` — Phase 17 research
- `.github/workflows/phase-17-assertions.yml` — CI PR gate (Phase 17)
- `db/ci-assertions/17-tenant-resolution.sql` — SQL assertions for resolver behavior
