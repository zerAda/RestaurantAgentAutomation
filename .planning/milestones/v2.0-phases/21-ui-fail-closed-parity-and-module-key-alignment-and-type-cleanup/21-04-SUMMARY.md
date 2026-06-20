---
phase: 21-ui-fail-closed-parity-and-module-key-alignment-and-type-cleanup
plan: 04
subsystem: cms-typescript
tags: [TYP-01, cms-ts, ts-ignore, ioredis]
requires:
  - "inventory-cms/src/api/realtime/services/realtime.ts:2 (proven constructable ioredis pattern)"
  - "inventory-cms/src/api/dispatch-log/controllers/dispatch-log.ts:5 (the 12-file @ts-ignore precedent)"
  - ".github/workflows/phase-21-assertions.yml (created by 21-02)"
provides:
  - "CMS TypeScript fully green: npx tsc --noEmit == 0 errors"
  - "cms-ts-compile job appended to phase-21-assertions.yml"
affects:
  - "inventory-cms/src/api/product-module/{controllers,routes}/product-module.ts"
  - "inventory-cms/src/api/tenant-entitlement/{controllers,routes}/tenant-entitlement.ts"
  - "inventory-cms/src/middlewares/auth-ratelimit.ts"
tech-stack:
  added: []
  patterns: ["// @ts-ignore - UID registered at runtime", "static import Redis from 'ioredis'"]
key-files:
  created: []
  modified:
    - "inventory-cms/src/api/product-module/controllers/product-module.ts"
    - "inventory-cms/src/api/product-module/routes/product-module.ts"
    - "inventory-cms/src/api/tenant-entitlement/controllers/tenant-entitlement.ts"
    - "inventory-cms/src/api/tenant-entitlement/routes/tenant-entitlement.ts"
    - "inventory-cms/src/middlewares/auth-ratelimit.ts"
    - ".github/workflows/phase-21-assertions.yml"
decisions:
  - "Full-green path taken: 4 @ts-ignore + ioredis static import -> 0 tsc errors (no residual-error compromise)"
metrics:
  tasks: 2
  files: 6
  completed: "2026-06-20"
---

# Phase 21 Plan 04: CMS TypeScript Fully Green Summary

Cleared the standing CMS TypeScript Compilation red by applying the repo's own `// @ts-ignore - UID registered at runtime` one-liner to the 4 SaaS-ContentType TS2345 sites and fixing the 5th error (`auth-ratelimit.ts:37` ioredis TS2351) with the static-import alignment. `cd inventory-cms && npx tsc --noEmit` now reaches **0 errors**, and a `cms-ts-compile` job was appended to `phase-21-assertions.yml`.

## Path taken: 4 + ioredis → FULLY GREEN (0 errors)

The full-green path succeeded exactly as planned — no fallback to the 4-only + 1-residual compromise was needed.

- **4 SaaS files** each gained the byte-identical precedent comment `// @ts-ignore - UID registered at runtime; type generator skips this custom type` directly above the `factories.create…` line: `product-module/controllers/product-module.ts`, `product-module/routes/product-module.ts`, `tenant-entitlement/controllers/tenant-entitlement.ts`, `tenant-entitlement/routes/tenant-entitlement.ts`. (Clears the 4 TS2345 "not assignable to ContentType".)
- **`auth-ratelimit.ts`:** replaced the dynamic `const Redis = (await import('ioredis')).default;` inside `getRedisClient()` with a top-of-file static `import Redis from 'ioredis';` (the constructable pattern `realtime.ts:2` uses). The TS2351 "not constructable" is cleared. `getRedisClient()` remains `async`, `USE_REDIS`-gated, with `lazyConnect: true` — the construct still happens lazily only when `USE_REDIS`; no eager connect; runtime behavior unchanged. The `let redisClient: any` was left as-is (out of TYP-01 admin scope, per plan).

## Verification

- All 4 files contain `@ts-ignore - UID registered at runtime`; `auth-ratelimit.ts` has `^import Redis from 'ioredis';` and no `await import('ioredis')`.
- `cd inventory-cms && npx tsc --noEmit` → exit 0, **0 errors** (baseline was 5).
- `phase-21-assertions.yml` parses as valid YAML with 4 jobs; `cms-ts-compile` (Node 20, `npm ci --legacy-peer-deps` → `npx tsc --noEmit`) appended; the 3 21-02 jobs intact.

## Deviations from Plan

None — the planned full-green path worked; the ioredis change did not break anything.

## VPS deferral

NONE. Pure source-comment + import-form edits in already-shipped CMS files; tsc runs locally + in CI. The CMS-TS green is a bonus gated independently in `cms-ts-compile`; it does not gate the admin-dashboard lint (the phase's primary success criterion).

## Self-Check: PASSED
