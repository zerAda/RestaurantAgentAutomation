---
phase: 21-ui-fail-closed-parity-and-module-key-alignment-and-type-cleanup
plan: 01
subsystem: entitlements-hook
tags: [ENT-01, TYP-01, fail-closed, vitest, no-lockout]
requires:
  - "admin-dashboard/src/types/entitlements.ts (21-03 DTOs: ProductModuleRaw/TenantEntitlementRaw/unwrap)"
provides:
  - "fail-closed useEntitlements (SHARED_CORE allowlist, explicit error/status, DTO-typed, v4/v5-tolerant)"
  - "useEntitlements.test.tsx (Vitest ENT-01 proof)"
  - "EntitlementErrorBanner.tsx (explicit locked/error surface)"
  - "tree-wide npm run lint GREEN (0 errors) — TYP-01 criterion-4 gate"
affects:
  - "admin-dashboard/src/App.tsx (consumes hasModule)"
tech-stack:
  added: ["@testing-library/dom@^10.4.1 (devDep — @testing-library/react 16 peer for renderHook)"]
  patterns: ["fail-closed default + static SHARED_CORE allowlist", "v4/v5 unwrap<T>()"]
key-files:
  created:
    - "admin-dashboard/src/hooks/useEntitlements.test.tsx"
    - "admin-dashboard/src/components/EntitlementErrorBanner.tsx"
  modified:
    - "admin-dashboard/src/hooks/useEntitlements.ts"
    - "admin-dashboard/package.json"
    - "admin-dashboard/package-lock.json"
decisions:
  - "Fallback #5: KEPT-but-fail-closed-on-result (no authenticated tenant UUID in the UI)"
  - "hasModule keeps SHARED_CORE visible in EVERY state (not only loading/error) — no-lockout"
metrics:
  tasks: 3
  files: 5
  completed: "2026-06-20"
---

# Phase 21 Plan 01: Fail-Closed useEntitlements + ENT-01 Proof Summary

Flipped `useEntitlements.hasModule` from fail-OPEN (`if (loading) return true`) to fail-CLOSED in parity with `W0_MODULE_GUARD`, added an explicit `error`/`status` surface + `EntitlementErrorBanner`, typed the hook against the 21-03 DTOs (clearing all 6 `no-explicit-any`), and proved it with a 6-case Vitest test. Tree-wide `npm run lint` is now GREEN (0 errors) and the full Vitest suite is GREEN (11/11).

## What was built (TDD)

- **RED (Task 1):** `useEntitlements.test.tsx` (Vitest + `renderHook` + `vi.mock` of `strapiClient`/`authService`): false-while-loading (non-core), shared_core-visible-while-loading, false+error-on-reject (core still visible), entitled-true on success for BOTH v5-flat AND v4-attributes payloads, no-fetch-when-unauthenticated. RED against the fail-open hook (5 fail, 1 incidental pass).
- **GREEN (Task 2):** rewrote `useEntitlements.ts` — `SHARED_CORE = new Set(['platform_runtime','order_bot_core'])`; `hasModule` = SHARED_CORE always true, else false while `loading||error`, else `modules.includes(key)`; `setError(true)` in catch (no longer silent); `status: 'loading'|'error'|'ready'`; returns `{modules,loading,error,status,hasModule}`; typed `strapi.find<ProductModuleRaw>/<TenantEntitlementRaw>`, `modRes.data ?? []`, `unwrap(m)/unwrap(e)` — all 6 `any` cleared, v4/v5 tolerance preserved. `EntitlementErrorBanner.tsx` renders only when `error===true` (mirrors ToastProvider's red styling).
- **Gate (Task 3):** tree-wide `npm run lint` exit 0; full `npx vitest run` 11/11 pass.

## hasModule shape refinement (vs the brief's formula)

The brief's formula was `hasModule(key) = (loading||error) ? SHARED_CORE.has(key) : modules.includes(key)`. The implemented form is:

```
if (SHARED_CORE.has(key)) return true;     // structurally always-on, every state
if (loading || error) return false;        // fail closed for non-core
return modules.includes(key);
```

This is identical to the brief in the loading/error window (`SHARED_CORE.has(key)`), and additionally keeps SHARED_CORE visible in the ready/empty and unauthenticated states — required by the no-lockout behavior and the fallback-#5 requirement that "SHARED_CORE keeps core nav usable" even on a zero-row result. (SHARED_CORE keys never appear in the entitlements result and are never tenant-gated, so `modules.includes('platform_runtime')` would otherwise be false in the ready/empty state — a spurious hide of core nav.) The fail-open bug (`if (loading) return true`) is removed; the only `return true` is the intentional SHARED_CORE allowlist branch.

## Fallback #5 handling (ADR-0002 occurrence #5)

`authService.getUser()` exposes NO tenant UUID on the user shape (verified `authService.ts:69`), so a real authenticated-tenant context is NOT available to wire to the UI today. Decision: **KEPT-but-fail-closed-on-result.** The `tenantId='default'` query still runs (so the seeded canonical tenant's rows return once a real tenant id IS provided), but the RESULT fails closed — a zero-row / error result hides all GATED modules while SHARED_CORE keeps core nav usable (no total lockout). The INVENTORY-15 comment was updated honestly: "#5 kept-but-fail-closed-on-result — the UI has no authenticated tenant UUID to substitute; full removal needs an authenticated tenant context exposed to the UI (future work)." #5 was NOT closed cleanly because no real tenant UUID is available — confirmed, not assumed.

## No admin lockout (SHARED_CORE)

With `tenantId='default'` yielding zero rows, fail-closed hides only NON-CORE modules; SHARED_CORE (`platform_runtime`, `order_bot_core`) plus the un-gated nav (Dashboard, Stock, Customers, the isFullAdmin Advanced block) keep the operator productive. Asserted by the shared_core-visible test cases (loading, error, unauthenticated).

## Verification

- `npm run lint` (tree-wide): 0 errors (exit 0) — the standing Frontend Lint failure cleared (TYP-01 criterion 4).
- `npx vitest run` (full suite): 11 passed (setup.test.ts 1, App.lazy.test.tsx 4, useEntitlements.test.tsx 6) — exit 0.
- `npx eslint` on hook + banner: clean. No `as any`, no `if (loading) return true`.
- Zero `tsc` errors in any Phase-21-touched file (pre-existing out-of-scope `tsc -b` errors in KitchenView/QuickAdjust/etc. logged to `deferred-items.md`, NOT fixed per research "do not chase them").

## Deviations from Plan

- **[Rule 3 - blocking] Added `@testing-library/dom@^10.4.1` devDependency.** `@testing-library/react@16` declares `@testing-library/dom@^10` as a PEER dependency that was never installed (`Cannot find module '@testing-library/dom'` on `renderHook`). Added it to `package.json` + `package-lock.json` so the ENT-01 test (and CI's `npm ci`) can load `renderHook`. The research assumed `renderHook` was ready; the peer gap was the only blocker.
- **hasModule no-lockout refinement** (documented above) — keeps SHARED_CORE visible in all states, not just loading/error. Necessary to satisfy the unauthenticated/zero-row no-lockout behavior; the loading/error branch matches the brief exactly.

## VPS deferral

NONE. Pure frontend; locally + CI verifiable.

## Self-Check: PASSED
