---
phase: 20-redis-cached-fail-closed-guard-and-internal-token-provisioning
plan: 01
subsystem: infra
tags: [n8n, redis, cache-aside, entitlement, fail-closed, node-test, jq, ci]

# Dependency graph
requires:
  - phase: 19-entitlement-audit-and-cache-invalidation
    provides: "The Phase-19 DEL side (audit-hook.ts:122) on the LOCKED key ralphe:entitlement:{tenant_id}:{module_key} — Phase 20 is the GET/SET (populate/read) half on the same key"
provides:
  - "W0_MODULE_GUARD.json restructured into a Redis cache-aside topology (Redis GET/SET nodes around Code nodes, 2 Strapi httpRequest on the miss branch only)"
  - "scripts/guard/entitlement-decision.mjs — pure decision seam (buildCacheKey + decideFromCache + evaluateLive) with node --test"
  - "scripts/test-phase20.sh — docker-free local harness"
  - ".github/workflows/phase-20-assertions.yml — CI gate (structural-jq + node-test jobs); 20-02/20-03 append jobs"
affects: [20-02, 20-03, guard, redis, entitlement, alerting]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Redis nodes (n8n-nodes-base.redis) around a pure-logic Code node — queue-mode-safe cache-aside (mirrors W0_CONFIG_READER)"
    - "Pure .mjs decision seam + node --test proving 'cache HIT -> 0 Strapi fetches' as a call-count assertion (no n8n boot)"
    - "Graph-reachability jq assertion (walk connections from IF HIT branch) proving 0 Strapi round-trips on hit directly from the workflow graph"

key-files:
  created:
    - scripts/guard/entitlement-decision.mjs
    - scripts/guard/__tests__/entitlement-decision.test.mjs
    - scripts/test-phase20.sh
    - .github/workflows/phase-20-assertions.yml
  modified:
    - workflows/W0_MODULE_GUARD.json

key-decisions:
  - "Authored the decision seam as plain ESM .mjs (no types to strip) — sidesteps Phase-19's Node-20 --experimental-strip-types blocker entirely; CI still pins Node 22 for parity"
  - "Strapi calls converted to httpRequest nodes on the MISS branch only (O-1) so '0 round-trips on hit' is a structural/jq-verifiable property, not just a code assertion"
  - "Cache stores the RAW entitlement row + fetchedAt (not a boolean) so expires_at is re-evaluated on every read; transient GUARD_ERROR_FAILCLOSED is never cached (IF-Cacheable FALSE skips the SET)"
  - "Input-error item carries _cacheUsable:false AND _cacheable:false so it terminates as a deny with no spurious cache read/write (plan-checker warning #3)"

patterns-established:
  - "Pure decision seam + thin n8n adapter (inlined copy in Code nodes) — the seam is the spec + test source of truth"
  - "Graph-reachability CI assertion for branch-isolation invariants"

requirements-completed: [GRD-01]

# Metrics
duration: 5min
completed: 2026-06-20
---

# Phase 20 Plan 01: Redis Cache-Aside Fail-Closed Guard Summary

**W0_MODULE_GUARD restructured into a Redis cache-aside topology on the locked key `ralphe:entitlement:{tenant_id}:{module_key}` — a HIT skips both Strapi round-trips (graph-proven) while the guard still fails closed on Strapi error, with all correctness logic isolated in a pure `.mjs` seam unit-tested at 20/20 green.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-06-20T18:33:34Z
- **Completed:** 2026-06-20T18:39:03Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments
- Pure, Strapi-free, n8n-free decision seam (`entitlement-decision.mjs`) encoding the full §4 fail-closed/fall-through matrix: HIT->0 fetches, Redis-err->fall-through, Strapi-err->`GUARD_ERROR_FAILCLOSED` DENY (never cached), expired raw row re-evaluated on read, positive TTL 300 / negative TTL 60. 20/20 node --test green.
- `W0_MODULE_GUARD.json` rewritten as a 12-node cache-aside flow mirroring `W0_CONFIG_READER`: Redis GET/SET keyed byte-for-byte to the Phase-19 DEL key; exactly 2 Strapi httpRequest nodes on the miss branch; error/input-error paths skip the SET.
- Graph-reachability jq assertion proves ZERO `n8n-nodes-base.httpRequest` nodes are reachable from the IF HIT (`main[0]`) branch — "0 Strapi round-trips on hit" directly from the workflow graph.
- Docker-free harness + `phase-20-assertions.yml` CI gate (structural-jq + node-test jobs, pinned Node 22).

## Task Commits

1. **Task 1: Pure decision seam + node --test** - `d05f39a` (feat)
2. **Task 2: Restructure W0_MODULE_GUARD into Redis cache-aside** - `9163936` (feat)
3. **Task 3: Local harness + phase-20-assertions CI gate** - `24dcf25` (feat)

## Files Created/Modified
- `scripts/guard/entitlement-decision.mjs` - Pure decision seam: buildCacheKey + decideFromCache (re-eval expiry on read) + evaluateLive (fail-closed, computes cacheable + ttl)
- `scripts/guard/__tests__/entitlement-decision.test.mjs` - node --test (20 tests): HIT->0 fetches, Redis-err->fallthrough, Strapi-err->DENY, expired re-eval, key byte-for-byte, TTL overrides
- `workflows/W0_MODULE_GUARD.json` - Redis cache-aside guard (GET/SET nodes + IF branches + 2 Strapi httpRequest on the miss branch)
- `scripts/test-phase20.sh` - Docker-free harness: node-test + jq structural + graph-reachability + optional ephemeral-redis round-trip
- `.github/workflows/phase-20-assertions.yml` - CI gate: guard-decision-node-test + guard-structural jobs (pinned checkout v4.2.2 / setup-node v4.1.0 / Node 22)

## Decisions Made
- `.mjs` not `.ts` for the seam — no type-strip dependency, sidesteps Phase-19 BLOCKER A; Node 22 still pinned in CI.
- httpRequest nodes (not in-Code fetch) for the two Strapi calls (O-1) for structural jq-verifiability of "0 on hit".
- Single computed-ttl SET (Evaluate node owns positive-vs-negative TTL choice).
- Folded in plan-checker warning #1 (graph-reachability assertion in the structural job + the harness) and #3 (input-error passthrough carries both `_cacheUsable:false` and `_cacheable:false`).

## Deviations from Plan

None - plan executed exactly as written. The two non-blocking plan-checker warnings folded into this plan (graph-reachability assertion; input-validate passthrough flags) were applied as designed.

## Issues Encountered
- Initial `phase-20-assertions.yml` failed `yaml.safe_load` because a step `name:` contained an unquoted `ralphe:entitlement:` colon-space (YAML read it as a mapping). Fixed by quoting the step name. Re-validated: YAML OK, harness PASS.

## User Setup Required
None in this plan. 🔴 VPS-deferred (tracked, not attempted): importing the restructured `W0_MODULE_GUARD.json` on prod n8n (wires `REDIS_CREDENTIAL_ID` -> live `43SDqJYMGa6RvFqW`), confirming the guard's Redis == the Phase-19 DEL Redis, and the prod `allkeys-lru`/maxmemory policy.

## Next Phase Readiness
- 20-02 (token wiring) and 20-03 (alert classifier) append jobs to `phase-20-assertions.yml`; this plan created the structural-jq + guard-seam halves and left clean append points.
- The guard emits stable reason prefixes (`GUARD_ERROR_FAILCLOSED`, `NO_ENTITLEMENT`, `MODULE_NOT_FOUND`, `EXPIRED`) for 20-03's classifier to key off unchanged.

## Self-Check: PASSED

- FOUND: scripts/guard/entitlement-decision.mjs
- FOUND: scripts/guard/__tests__/entitlement-decision.test.mjs
- FOUND: workflows/W0_MODULE_GUARD.json
- FOUND: scripts/test-phase20.sh
- FOUND: .github/workflows/phase-20-assertions.yml
- FOUND commits: d05f39a, 9163936, 24dcf25

---
*Phase: 20-redis-cached-fail-closed-guard-and-internal-token-provisioning*
*Completed: 2026-06-20*
