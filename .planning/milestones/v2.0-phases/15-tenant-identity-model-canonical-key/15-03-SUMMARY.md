---
phase: 15-tenant-identity-model-canonical-key
plan: 03
subsystem: tenant-identity
tags: [seeder, canonical-key, fallback-inventory, annotation, adr]
key-decisions:
  - "Seeder now uses CANONICAL_FIRST_TENANT_UUID constant; never falls back to 'default'"
  - "Node ESM assertion (no jest/vitest) proves seeder resolution is UUID, not 'default'"
  - "4 remaining fallback sites annotated with INVENTORY-15 marker referencing owning phases 17/17/17/21"
  - "W_DRIVER_ONBOARDING fallback is already UUID-safe (not 'default') — annotated and left for Phase 17"
key-files:
  created:
    - inventory-cms/src/bootstrap-seeds/assert-canonical-tenant.mjs
    - docs/adr/0002-tenant-id-fallback-inventory.md
  modified:
    - inventory-cms/src/bootstrap-seeds/saas-entitlements.ts
    - workflows/W0_MODULE_GUARD.json
    - workflows/W1_IN_WA.json
    - workflows/W_DRIVER_ONBOARDING.json
    - admin-dashboard/src/hooks/useEntitlements.ts
metrics:
  duration: "~15 minutes"
  completed: "2026-06-20"
  tasks: 2
  files: 7
---

# Phase 15 Plan 03: Seeder Fix + Fallback Inventory Summary

One-liner: Seeder line 127 replaced DEFAULT_TENANT_ID || 'default' with CANONICAL_FIRST_TENANT_UUID constant; standalone node assertion exits 0; all 5 fallback sites inventoried in ADR 0002 with phase assignments and INVENTORY-15 annotations on the 4 left-in-place sites.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Fix the seeder + standalone node seed-assertion | d305e83 | saas-entitlements.ts, assert-canonical-tenant.mjs |
| 2 | Fallback inventory ADR + 4 in-place annotations | d305e83 | docs/adr/0002-tenant-id-fallback-inventory.md, W0_MODULE_GUARD.json, W1_IN_WA.json, W_DRIVER_ONBOARDING.json, useEntitlements.ts |

## Acceptance Criteria Status

### Task 1
- [x] `node assert-canonical-tenant.mjs` exits 0 and prints PASS line (confirmed locally)
- [x] `saas-entitlements.ts` contains `CANONICAL_FIRST_TENANT_UUID` and canonical UUID literal
- [x] No `DEFAULT_TENANT_ID || 'default'` in `saas-entitlements.ts`
- [x] Assertion is a `.mjs` node script — no jest/vitest dependency added

### Task 2
- [x] `docs/adr/0002-tenant-id-fallback-inventory.md` exists and references all 5 sites
  (saas-entitlements.ts, W0_MODULE_GUARD, W1_IN_WA, W_DRIVER_ONBOARDING, useEntitlements.ts)
  with owning-phase column (values 15/17/17/17/21)
- [x] `INVENTORY-15` marker present in `useEntitlements.ts`
- [x] `INVENTORY-15` (`__inventory_15` key) present in all three workflow JSON files
- [x] All three workflow JSONs remain valid JSON (python3 json.load verified)
- [x] No runtime/behavioural change made to the 4 left-in-place sites (annotation only)

## Deviations from Plan

None — plan executed exactly as written. The INVENTORY-15 markers were added as `__inventory_15`
keys on the specific node objects in the JSON files (per plan's explicit guidance: "n8n ignores
unknown node keys").

## Self-Check: PASSED
