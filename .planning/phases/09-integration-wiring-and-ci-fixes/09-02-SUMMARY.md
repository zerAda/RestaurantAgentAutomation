---
phase: 09-integration-wiring-and-ci-fixes
plan: "02"
subsystem: testing
tags: [ci, github-actions, nginx, postgres, smoke-test, schema-migration]

# Dependency graph
requires:
  - phase: 04-nginx-routing-smoke
    provides: smoke-nginx-routing.sh burst-test script
  - phase: 03-observability-and-schema
    provides: ops.workflow_audit migration (AUDIT-01)
provides:
  - CI smoke-nginx-routing job using burst-test script (TEST-03)
  - CI smoke-nginx-routing job runs on PRs (TEST-04)
  - CI verifies ops.workflow_audit in both PG15 and PG16 schema checks (AUDIT-01)
affects: [ci, integration-tests, smoke-nginx-routing, ops-schema]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CI jobs that spawn their own Docker containers must not use a services: block (port conflict)"
    - "ops-schema tables verified separately from public-schema tables using table_schema='ops'"

key-files:
  created: []
  modified:
    - .github/workflows/ci.yml

key-decisions:
  - "smoke-nginx-routing.sh manages its own Docker container — the services: nginx block was a port conflict, removed"
  - "ops schema check resets MISSING=0 before the ops loop for explicit correctness (existing block already exits on MISSING > 0)"
  - "PR trigger for smoke-nginx-routing uses github.event_name == 'pull_request' to cover all PRs, not just main/release pushes"

patterns-established:
  - "Pattern: ops schema verification block appended after public schema check in CI integration-tests jobs"

requirements-completed: [TEST-03, TEST-04, AUDIT-01]

# Metrics
duration: 2min
completed: "2026-03-29"
---

# Phase 9 Plan 02: Integration Wiring & CI Fixes - CI Script and Schema Verification Summary

**Three CI blind spots closed: burst-test script wired, smoke job enabled on PRs, and ops.workflow_audit verified in both PG15/PG16 integration-tests jobs.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-29T19:58:26Z
- **Completed:** 2026-03-29T20:00:40Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Switched smoke-nginx-routing CI job from `smoke-nginx-routing-v2.sh` (no burst test) to `smoke-nginx-routing.sh` (25-POST burst test, TEST-03)
- Removed the `services: nginx` block that would have caused a port conflict with the script's self-managed Docker container
- Added `github.event_name == 'pull_request'` to the `if:` condition so the smoke job runs on all PRs (TEST-04)
- Removed `|| { echo warning }` suppression — the script now fails CI on any test failure
- Added `ops.workflow_audit` schema verification to both `integration-tests` (PG15) and `integration-tests-pg16` jobs, catching failed Phase 3 migrations (AUDIT-01)

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix smoke-nginx-routing job to use burst-test script and run on PRs** - `8780a67` (fix)
2. **Task 2: Add ops.workflow_audit to CI schema verification in both integration-tests jobs** - `590cf94` (fix)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `.github/workflows/ci.yml` - smoke-nginx-routing job updated + ops schema verification added to PG15 and PG16 jobs

## Decisions Made

- Used `github.event_name == 'pull_request'` instead of a `paths:` filter because job-level `paths:` is not supported in GitHub Actions; running on all PRs is the correct trade-off (script completes in ~30 seconds)
- `services: nginx` block removed because `smoke-nginx-routing.sh` starts its own Docker container internally — keeping it would cause port 8080 conflict
- MISSING reset to 0 before the ops schema loop for explicit safety, even though the existing block already exits before this code when MISSING > 0

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- CI now catches TEST-03 (rate-limit burst), TEST-04 (smoke on PRs), and AUDIT-01 (ops schema) in every run
- Phase 9 plan 02 complete — ready for Phase 10

---
*Phase: 09-integration-wiring-and-ci-fixes*
*Completed: 2026-03-29*

## Self-Check: PASSED

- FOUND: `.planning/phases/09-integration-wiring-and-ci-fixes/09-02-SUMMARY.md`
- FOUND: commit `8780a67` (Task 1)
- FOUND: commit `590cf94` (Task 2)
