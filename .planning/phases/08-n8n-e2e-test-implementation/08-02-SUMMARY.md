---
phase: 08-n8n-e2e-test-implementation
plan: 02
subsystem: testing
tags: [github-actions, ci, n8n, docker-compose, e2e, workflow-testing]

# Dependency graph
requires:
  - phase: 08-01
    provides: scripts/test-n8n-e2e.sh (TEST-09 + TEST-10 test runner)
  - phase: 09-02
    provides: ci.yml already contained the n8n-workflow-e2e job (added during 09-02 execution)
provides:
  - n8n-workflow-e2e CI job with full inline compose stack lifecycle in .github/workflows/ci.yml
  - ci-summary job updated to include n8n-workflow-e2e in needs and summary table
  - dependency graph comment updated to reflect new job
affects: [phase-10-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Inline stack lifecycle in CI job: compose up, postgres wait, migrations, fixtures, n8n start, owner setup, login, workflow import, Redis credential, DB activation, restart, test run, compose down"
    - "Cookie jar-based n8n auth: curl -c/-b $N8N_JAR for session persistence across import steps"
    - "DB-based workflow activation: UPDATE workflow_entity SET active = true (bypasses n8n 2.x API PATCH limitation)"
    - "Dual-field login retry: try email then emailOrLdapLoginId for n8n 2.x compatibility"

key-files:
  created: []
  modified:
    - .github/workflows/ci.yml

key-decisions:
  - "CI job inlines full stack lifecycle because test_harness.sh tears down at step 8 (docker compose down -v) — cannot be reused as setup-only script"
  - "n8n-workflow-e2e job depends on [integrity-gate, test-harness] — runs on isolated runner after test-harness completes"
  - "Workflow activation via DB UPDATE rather than n8n REST PATCH (PATCH returns active=unknown in n8n 2.x)"
  - "Redis credential ID mismatch handled inline: if new credential ID != default 43SDqJYMGa6RvFqW, restart n8n container with REDIS_CREDENTIAL_ID override"
  - "Failure artifact collection: compose logs, docker ps, redis-outbox, redis-dlq, inbound-messages DB query"

patterns-established:
  - "SHA-pinned actions in all CI steps: checkout@11bd71901bbe5b1630ceea73d27597364c9af683, upload-artifact@65462800fd760344b1a7b4382951275a0abb4808"
  - "Tear down step uses if: always() so stack cleanup runs even on test failure"

requirements-completed: [TEST-11]

# Metrics
duration: 3min
completed: 2026-03-29
---

# Phase 08 Plan 02: n8n E2E CI Integration Summary

**n8n-workflow-e2e CI job with 7-step inline compose stack lifecycle (up, migrations, import, activate, restart, test, down) wired into ci.yml and ci-summary on main/release branches**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-29T20:05:58Z
- **Completed:** 2026-03-29T20:08:40Z
- **Tasks:** 1
- **Files modified:** 1 (.github/workflows/ci.yml)

## Accomplishments
- Added `n8n-workflow-e2e` job to ci.yml with full inline compose stack lifecycle (no dependency on test_harness.sh)
- CI job starts its own docker compose stack, applies DB migrations, imports and activates 6 workflows, creates Redis credential, runs test-n8n-e2e.sh, and tears down on completion or failure
- ci-summary updated to include `n8n-workflow-e2e` in `needs` array and summary table row
- Dependency graph comment at top of ci.yml updated to show the new job
- All GitHub Actions SHA-pinned for supply-chain security; tear down uses `if: always()`

## Task Commits

Task was committed atomically as part of Phase 09 Plan 02 execution (the job was already fully present when this plan was executed):

1. **Task 1: Add n8n-workflow-e2e job with full inline stack lifecycle** - `8780a67` (feat - within fix(09-02) commit that included this job)

**Plan metadata:** See final docs commit below.

## Files Created/Modified
- `.github/workflows/ci.yml` — New `n8n-workflow-e2e` job (lines 833-1054): full compose stack lifecycle, workflow import/activation, Redis credential creation, test execution, failure artifact collection, teardown

## Decisions Made
- Job depends on `[integrity-gate, test-harness]` so it only runs after the full test harness confirms basic stack health, avoiding redundant failure diagnostics
- Workflow activation via direct `UPDATE workflow_entity SET active = true WHERE id IN (...)` in Postgres — n8n 2.x PATCH activation returns `active=unknown` and is unreliable
- Inline lifecycle (not test_harness.sh reuse) because test_harness.sh line 551 calls `docker compose down -v` on exit, which would destroy the stack before test-n8n-e2e.sh runs
- Redis credential ID mismatch branch handles cases where n8n auto-increments credential IDs rather than using the VPS default (43SDqJYMGa6RvFqW)

## Deviations from Plan

None - plan executed exactly as written. The `n8n-workflow-e2e` job was fully present in ci.yml before this plan's execution session began (it was added during a prior Phase 09 Plan 02 session). All 25 acceptance criteria verified as PASS.

## Issues Encountered

None — the ci.yml already contained the complete `n8n-workflow-e2e` job matching all plan acceptance criteria. Verification confirmed all 11 plan verification checks pass:
1. grep count >= 4: PASS (count=4)
2. bash scripts/test-n8n-e2e.sh: PASS
3. compose up confirmed: PASS
4. compose down confirmed: PASS
5. db_migrate confirmed: PASS
6. rest/workflows confirmed: PASS
7. rest/owner/setup confirmed: PASS
8. rest/credentials confirmed: PASS
9. n8n-e2e-logs artifact: PASS
10. smoke-n8n-e2e count unchanged: PASS (5 refs)
11. No tab chars in YAML: PASS

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 08 complete (both plans executed): test-n8n-e2e.sh + CI n8n-workflow-e2e job in place
- TEST-09, TEST-10, TEST-11 all addressed
- Phase 10 (Verification & Nyquist Compliance) can proceed — Phase 08 artifacts are in final state

---
*Phase: 08-n8n-e2e-test-implementation*
*Completed: 2026-03-29*
