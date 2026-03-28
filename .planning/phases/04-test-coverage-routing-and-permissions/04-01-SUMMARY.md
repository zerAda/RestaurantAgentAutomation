---
phase: 04-test-coverage-routing-and-permissions
plan: "01"
subsystem: testing
tags: [nginx, bash, smoke-test, docker, rate-limit, cors]

requires: []
provides:
  - infra/gateway/nginx.smoke.conf — CI-safe nginx with all production security rules + stub upstreams
  - scripts/smoke-nginx-routing.sh — 8-zone routing smoke test with CORS dedup and rate-limit assertions
affects: [04-03]

tech-stack:
  added: []
  patterns: [local Docker nginx smoke test with trap-cleanup, bash PASS/FAIL counter pattern]

key-files:
  created:
    - infra/gateway/nginx.smoke.conf
    - scripts/smoke-nginx-routing.sh

key-decisions:
  - "nginx.smoke.conf uses return stubs instead of proxy_pass — CI needs no live backends"
  - "smoke-nginx-routing.sh spins fresh Docker container per test run — isolated state"
  - "Rate-limit test uses second fresh container to reset zone counters"

patterns-established:
  - "Smoke tests start their own Docker service, trap EXIT for cleanup"
  - "PASS_COUNT/FAIL_COUNT pattern from smoke-cms-routes.sh"

requirements-completed: [TEST-01, TEST-02, TEST-03]

duration: 20min
completed: 2026-03-28
---

# Phase 4 Plan 01: Nginx Smoke Config + 8-Zone Routing Test

**nginx.smoke.conf with all 4 rate-limit zones and stub upstreams + smoke-nginx-routing.sh covering all 8 zones, CORS dedup, and rate-limit 429 assertion**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-03-28
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created `infra/gateway/nginx.smoke.conf` — 175-line nginx config replicating all production rate-limit zones (meta_inbound/10r/s, internal_token/20r/s, conn_per_ip, kiosk_menu/30r/s), content-type guard, CORS headers, zero proxy_pass directives
- Created `scripts/smoke-nginx-routing.sh` — 299-line smoke test: zones 1-9, ACAO header count assertion (exactly 1), 25-request rate-limit burst test

## Task Commits

1. **Task 1: nginx.smoke.conf** — `535d736` (feat(04-01))
2. **Task 2: smoke-nginx-routing.sh** — `e5dc23d` (feat(04-01))

## Files Created/Modified
- `infra/gateway/nginx.smoke.conf` — CI-safe stub nginx config (no proxy_pass)
- `scripts/smoke-nginx-routing.sh` — 8-zone Docker-based smoke test

## Decisions Made
- Two-container approach: first for functional tests, second fresh container for rate-limit test (zone state reset)
- Accepts 200/4xx/5xx from route zones except 404/502 (which indicate missing route)

## Deviations from Plan
- `smoke-nginx-routing-v2.sh` pre-existed (tests live VPS); `smoke-nginx-routing.sh` is the local Docker-based CI version as planned

## Issues Encountered
None.

## Next Phase Readiness
- nginx.smoke.conf ready for CI job mounting (04-03)
- smoke-nginx-routing.sh ready for CI invocation

---
*Phase: 04-test-coverage-routing-and-permissions*
*Completed: 2026-03-28*
