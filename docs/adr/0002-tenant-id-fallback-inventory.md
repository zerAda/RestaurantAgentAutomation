# ADR 0002: tenant_id Fallback Inventory (`|| 'default'` / DEFAULT_TENANT_ID)

**Status:** Accepted
**Date:** 2026-06-20
**Phase:** 15
**Requirement:** TEN-01

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
| 1 | `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` | 127 | `process.env.DEFAULT_TENANT_ID \|\| 'default'` | **REMOVED** (this plan) — replaced with `CANONICAL_FIRST_TENANT_UUID` constant and trimmed-env resolution | 15 |
| 2 | `workflows/W0_MODULE_GUARD.json` | node "Module Guard" (~L21) | `$input.first().json.tenant_id \|\| $env.DEFAULT_TENANT_ID \|\| 'default'` | **ANNOTATED** (`__inventory_15` key on node), left in place — Phase 17 removes this by ensuring callers always provide a real UUID from `channel_identities` | 17 |
| 3 | `workflows/W1_IN_WA.json` | node "B0 - Apply Auth Context" (~L6) | `$env.DEFAULT_TENANT_ID \|\| ''` (used as `defaultTenantId` for `meta_signature`/`legacy_shared` auth modes) | **ANNOTATED** (`__inventory_15` key on node), left in place — Phase 17 replaces with `channel_identities` lookup | 17 |
| 4 | `workflows/W_DRIVER_ONBOARDING.json` | node "Ensure Customer Profile" | `$json.tenant_id \|\| $env.DEFAULT_TENANT_ID \|\| '00000000-0000-0000-0000-000000000001'` (UUID-safe fallback, not `'default'`) | **ANNOTATED** (`__inventory_15` key on node), left in place — fallback is UUID-safe; superseded by trusted derivation in Phase 17 | 17 |
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

## Phase 17 Remaining Work (Occurrences #2, #3, #4)

Three workflow fallbacks remain **annotated and not removed** because they are in scope for Phase 17:

- **W0_MODULE_GUARD.json** — Phase 17 ensures callers always supply a real UUID derived from
  `channel_identities`, eliminating the need for a fallback. Until then, this is a documented
  fail-open risk: if `tenant_id` is `'default'`, the guard may allow/deny incorrectly.
- **W1_IN_WA.json** — Phase 17 replaces the `DEFAULT_TENANT_ID` resolution ladder with a proper
  `channel_identities` lookup. This is the root cause of the Phase 15 problem: unauthenticated
  fallback to env default.
- **W_DRIVER_ONBOARDING.json** — The fallback here is already UUID-safe (falls to the canonical
  UUID, not `'default'`). Phase 17 removes it by making derivation trustworthy upstream.

---

## Phase 21 Remaining Work (Occurrence #5)

`admin-dashboard/src/hooks/useEntitlements.ts:5` — **annotated, left for Phase 21 (ENT-01/ENT-02)**.

The default parameter `tenantId = 'default'` means the UI queries `tenant_entitlements` for the
literal string `'default'` when no authenticated context passes the real UUID. This will return
zero rows (or stale rows) after the Phase 15 backfill. Phase 21 wires authenticated tenant context
to the UI and removes this default.

---

## Post-Phase 15 State

After Phase 15:

- The **only runtime path that wrote `'default'` into `tenant_entitlements`** (the Strapi seeder)
  is eliminated. The seeder now always writes the canonical UUID.
- The remaining 4 fallback sites are **documented** with phase assignments. No silent substitution
  remains undocumented.
- The CI backfill harness (Plan 15-02) proves zero `'default'` rows survive in ephemeral Postgres.

A post-Phase-15 repo-wide grep:

```bash
grep -rn "|| 'default'" workflows/ inventory-cms/ admin-dashboard/ \
  --include='*.ts' --include='*.js' --include='*.json'
```

will return exactly **4 matches** (the 4 annotated-not-removed sites). Every match is cross-referenced
in this document with its owning phase.

---

## References

- `docs/adr/0001-canonical-tenant-key.md` — canonical key decision record
- `inventory-cms/src/bootstrap-seeds/assert-canonical-tenant.mjs` — node assertion proving seeder fix
- `db/ci-assertions/15-backfill-tenant-entitlements.sql` — idempotent backfill SQL
- `db/ci-assertions/15-tenant-canonical-key.sql` — DO-block assertion
- `.github/workflows/phase-15-assertions.yml` — CI PR gate
- `15-RESEARCH.md` "Fallback Inventory" section — research grounding these 5 occurrences
