---
phase: 19-entitlement-audit-and-cache-invalidation-lifecycle-hook
plan: 03
subsystem: entitlement-audit-validation
tags: [ci, node-test, ephemeral-pg, ephemeral-redis, fixtures, assertions]
requires:
  - "19-01 uuid-NULL shape decision (seed declares tenant_id uuid NULL + nullable FK)"
  - "audit-hook.ts (19-02) for the IO/helper node-test cases to run (skips gracefully until then)"
provides:
  - "db/ci-fixtures/19-entitlement-audit-seed.sql (uuid-NULL shape + tenants + tenant_entitlements)"
  - "db/ci-assertions/19-entitlement-audit.sql (row-per-op + invalid-uuid + product-module NULL path)"
  - "audit-hook.test.mjs (node --test: canonical-key contract + SET->invalidate->GET-nil + audit-row + NULL path)"
  - "scripts/test-phase19.sh (ephemeral PG + redis harness, docker DOWN)"
  - ".github/workflows/phase-19-assertions.yml (PG + redis:7-alpine + structural; Node-22 pinned)"
affects:
  - "19-02 (its helper is the seam this gate proves)"
  - "Phase 19 gate (machine-checkable AUD-01/AUD-02)"
tech-stack:
  added: []
  patterns:
    - "node --test --experimental-strip-types to import the .ts helper without a build (Node 22)"
    - "Dynamic import() in before() + test.skip — committable before the helper exists"
    - "Nested BEGIN..EXCEPTION for expected-failure SQL (no SAVEPOINT in a DO block)"
key-files:
  created:
    - "db/ci-fixtures/19-entitlement-audit-seed.sql"
    - "db/ci-assertions/19-entitlement-audit.sql"
    - "inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/__tests__/audit-hook.test.mjs"
    - "scripts/test-phase19.sh"
    - ".github/workflows/phase-19-assertions.yml"
  modified: []
decisions:
  - "CORRECTION (Blocker A): pinned actions/setup-node@v4.1.0 node-version 22 before every node step"
  - "CORRECTION (Blocker B): seed tenant_id is uuid NULL + nullable FK; assertions + node-test prove the product-module tenant_id IS NULL path"
  - "Helper import is dynamic import() in before() + test.skip (committable in Wave 1)"
metrics:
  duration: ~20m
  completed: 2026-06-20
---

# Phase 19 Plan 03: Entitlement-Audit Validation Infrastructure Summary

The machine-checkable proof of AUD-01 (a row per op, old→new captured, invalid tenant_id rejected) and
AUD-02 (no stale grant survives `invalidateCache` on the exact canonical key), without a live VPS and
without booting Strapi: a CI seed + DO-block assertions, a `node --test` driving the pure `audit-hook.ts`
helper against ephemeral PG + Redis, a local harness, and a GitHub Actions gate mirroring phase-18 with an
added `redis:7-alpine` service and a pinned Node 22.

## What was built

- **`db/ci-fixtures/19-entitlement-audit-seed.sql`** — `entitlement_audit_log` in the post-19-01 shape
  (`tenant_id uuid NULL` + nullable FK to `tenants`), minimal `tenants` (+ canonical `…0001`),
  `tenant_entitlements` (channel_whatsapp). Idempotent; proven apply-twice on ephemeral PG.
- **`db/ci-assertions/19-entitlement-audit.sql`** — 4 DO-blocks: (1) a row per op with old→new captured
  (created new-only, deleted old-only), (2) non-UUID tenant_id rejected by the column type (nested
  `BEGIN..EXCEPTION`), (3) action vocabulary present, (4) **product-module `tenant_id IS NULL` accepted by
  the nullable FK + all-zero sentinel NOT used + non-null bogus uuid still FK-rejected** (Blocker B). No
  `SAVEPOINT`/`ROLLBACK TO` in any block.
- **`audit-hook.test.mjs`** (`node --test`) — canonical-key byte-for-byte contract test, `deriveAction`/
  `validateTenantId` pure cases (incl. `validateTenantId(null)===null`), `invalidateCache`
  SET→DEL→GET-nil (AUD-02), `writeAuditRow` row-per-op (AUD-01), the product-module `tenant_id=NULL`
  write (Blocker B), and fail-loud cases (rejecting knex/redis must surface, not swallow). Helper imported
  via dynamic `import()` in `before()` + `test.skip` so the file is committable in Wave 1.
- **`scripts/test-phase19.sh`** — boots ephemeral PG (system `postgres` user, `/usr/lib/postgresql/16/bin`)
  + `redis-server :63799`, applies the seed, runs `node --test --experimental-strip-types`, runs the
  DO-block assertions, tears both down on EXIT.
- **`.github/workflows/phase-19-assertions.yml`** — 3 jobs: `audit-row-sql` (postgres:15-alpine; seed +
  assertions), `cache-invalidation-redis` (postgres + **redis:7-alpine**; node-test), `hook-structural`
  (canonical-key grep, both lifecycles exist, no `@strapi/strapi`, zod uuid/guid, no swallow/SCAN/KEYS,
  product-module audit-only). Pinned checkout SHA.

## Authoritative corrections landed (supersede the plan docs)

- **Correction 1 (Blocker A) — Node 22 pinned in the CI gate.** The phase-18 mirror has no `setup-node`
  (defaults to Node 20), but `node --test --experimental-strip-types` importing the `.ts` helper needs
  Node ≥22.18. Added `actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af # v4.1.0` with
  `node-version: '22'` BEFORE the node step in both node-running jobs (`cache-invalidation-redis`,
  `hook-structural`). Verified: setup-node index < node-step index in both jobs.
- **Correction 2 (Blocker B) — product-module `tenant_id = NULL`.** Seed declares `tenant_id uuid NULL` +
  nullable FK; the SQL assertion (block 4) and the node-test both prove a product-module change writes a
  row with `tenant_id IS NULL` that the nullable FK does NOT reject, the all-zero sentinel is NOT used, and
  a non-null bogus uuid is still FK-rejected. Closes the test blind-spot.

## Verification (proven locally on ephemeral PG + Node 22)

- Seed applies idempotently (twice) on ephemeral PG.
- All 4 DO-block assertions PASS (NOTICE: a row per op; non-UUID rejected; action vocab present;
  product-module NULL-tenant accepted + no sentinel + non-null bogus FK-rejected); `psql` exit 0.
- `node --check audit-hook.test.mjs` clean; `python3 yaml.safe_load(phase-19-assertions.yml)` valid.
- Wave-1 node-test run (helper absent): **1 pass / 9 skip / 0 fail** — the fragility guard works (no
  hard crash; the canonical-key contract test passes without the helper).
- Full IO/helper node-test green-proof (SET→invalidate→GET-nil + audit-row writes incl. NULL path) is run
  after 19-02 lands `audit-hook.ts` — recorded in 19-02-SUMMARY.md.

## Deviations from Plan

**1. [Rule 3 - Blocking] Comment reword to dodge the verify grep.** The assertion file's Pitfall-5 warning
comment originally contained the literal `ROLLBACK TO` token; the plan's own `grep -iE "SAVEPOINT|ROLLBACK
TO"` verify is case-insensitive and matched the *comment*. Reworded to "transaction-control rollback
statements" without the literal tokens (no behavior change; no such statements are used).

**2. [Rule 1 - Bug] zod validator grep widened to `uuid|guid`.** Because the helper must use
`z.string().guid()` (zod 4 `.uuid()` rejects the all-zero canonical tenant — see 19-01/19-02), the
structural CI grep accepts `z.string().guid()` OR `z.string().uuid()` so it matches the correct validator.

**3. [Enhancement] Added a byte-for-byte canonical-key literal assertion** in the node-test (constructed
key === `ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp`) so the literal the
CI/plan grep expects is present AND a real drift check exists.

## 🔴 VPS-deferred (not attempted)

- None owned by this plan directly (CI/local only). The Phase-level VPS items live in 19-01/19-02.

## Commits

- `7a95ebd` feat(19-03): entitlement-audit CI seed fixture (uuid-NULL shape + tenants + FK)
- `950dcd9` feat(19-03): entitlement-audit DO-block assertions (row-per-op + NULL-tenant path)
- `76eed8d` feat(19-03): audit-hook node-test + ephemeral PG/Redis harness
- `01f59a9` feat(19-03): phase-19 CI gate (PG audit + redis:7-alpine invalidation + structural)

## Self-Check: PASSED

- FOUND: db/ci-fixtures/19-entitlement-audit-seed.sql
- FOUND: db/ci-assertions/19-entitlement-audit.sql
- FOUND: inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/__tests__/audit-hook.test.mjs
- FOUND: scripts/test-phase19.sh
- FOUND: .github/workflows/phase-19-assertions.yml
- FOUND commits: 7a95ebd, 950dcd9, 76eed8d, 01f59a9
