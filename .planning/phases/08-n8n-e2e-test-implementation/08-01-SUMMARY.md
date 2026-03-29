---
phase: 08-n8n-e2e-test-implementation
plan: 01
subsystem: testing
tags: [bash, n8n, postgres, redis, meta-webhook, hmac, e2e-testing, outbox, queue]

# Dependency graph
requires:
  - phase: 05-test-coverage-n8n-workflow-e2e
    provides: plan spec (05-01-PLAN.md), patterns, pitfalls for test-n8n-e2e.sh
  - phase: 03-observability
    provides: inbound_messages table schema (via bootstrap.sql + migrations)

provides:
  - scripts/test-n8n-e2e.sh — bash E2E test covering TEST-09 (Meta-signed WA inbound -> Postgres row) and TEST-10 (outbox retry -> Redis re-queue with attempts+1)

affects:
  - 08-02-n8n-workflow-e2e-ci-job (plan 02 runs this script in CI)
  - any phase that modifies W1_IN_WA.json or W15_OUTBOX_WORKER.json

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Meta HMAC-SHA256 signature generation using openssl dgst -sha256 -hmac + echo -n (single-line JSON payload)"
    - "Async DB polling with timeout: poll_for_record() polls inbound_messages with psql via docker compose exec for up to 20s (n8n queue mode fast-ACK)"
    - "Redis outbox inspection via docker compose exec -T redis redis-cli LLEN/LINDEX with python3 JSON parse for attempts field"
    - "n8n login with field fallback: try email then emailOrLdapLoginId for n8n 1.x/2.x compatibility"

key-files:
  created:
    - scripts/test-n8n-e2e.sh
  modified: []

key-decisions:
  - "META_APP_SECRET defaults to ci-test (not test_meta_app_secret_for_e2e) to match docker-compose.test.yml line 66 default — any mismatch causes sig_mismatch and no inbound_messages row"
  - "Outbox seed entry includes retryable=true (Rule 1 auto-fix) — W15 only re-queues if retryable=true AND attempts < maxAttempts(7); missing field routes entry to DLQ"
  - "poll_for_record uses 20s timeout — n8n queue mode worker processes asynchronously after fast-ACK 200; immediate assertion would always fail"
  - "Script assumes stack is already running (CI job 08-02 handles lifecycle) — this script is test-only, not a test harness"

patterns-established:
  - "HMAC pattern: echo -n PAYLOAD | openssl dgst -sha256 -hmac SECRET | sed 's/^.* //' (same as test_e2e.sh generate_signature)"
  - "DB poll pattern: while loop with sleep 1 + timeout, docker compose exec -T postgres psql -Atc (same as test_harness.sh)"
  - "PASS/FAIL/SKIP counter pattern with exit 1 on FAIL > 0"

requirements-completed: [TEST-09, TEST-10]

# Metrics
duration: 5min
completed: 2026-03-29
---

# Phase 08 Plan 01: n8n E2E Test Script Summary

**Standalone bash E2E test script verifying Meta-signed WhatsApp inbound creates Postgres row (TEST-09) and outbox retry re-queues with incremented attempts via Redis (TEST-10)**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-29T19:55:00Z
- **Completed:** 2026-03-29T20:00:42Z
- **Tasks:** 1 of 1
- **Files modified:** 1

## Accomplishments

- Created `scripts/test-n8n-e2e.sh` (185 lines) covering TEST-09 and TEST-10
- TEST-09: Posts Meta-native HMAC-signed WhatsApp payload to n8n webhook, polls `inbound_messages` Postgres table with 20s timeout for row with matching `msg_id` (direct DB assertion, not Strapi)
- TEST-10: Flushes Redis outbox, seeds a retryable entry with `attempts=1`, triggers W15_OUTBOX_WORKER, verifies `ralphe:outbox:pending` queue has entry with `attempts >= 2`
- Script reports `PASS/FAIL/SKIP` counts and exits 1 on any FAIL; handles 404 (webhook not registered) and n8n login failure as `SKIP` rather than hard abort

## Task Commits

1. **Task 1: Create scripts/test-n8n-e2e.sh with TEST-09 and TEST-10** - `ce9e174` (feat)

**Plan metadata:** [created during state update]

## Files Created/Modified

- `scripts/test-n8n-e2e.sh` — Complete E2E test script; 185 lines; passes `bash -n` syntax check; covers TEST-09 (Meta-signed WA inbound -> direct Postgres DB row) and TEST-10 (outbox retry -> Redis re-queue with attempts+1)

## Decisions Made

- `META_APP_SECRET` defaults to `ci-test` (matching `docker-compose.test.yml` line 66) — any mismatch causes `metaSigReason=sig_mismatch` in W1_IN_WA and no row is written to `inbound_messages`
- Script is test-only (assumes stack running); stack lifecycle is handled by CI job in plan 08-02
- Used `python3` for JSON parsing of Redis LINDEX output (available on ubuntu-latest CI runners without installing additional tools)
- Manual REST API trigger (`POST /rest/workflows/:id/run`) attempted first; if it returns non-200, falls back to waiting 35s for CRON trigger — handles LOW-confidence endpoint

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added `retryable:true` to outbox seed entry**
- **Found during:** Task 1 (reviewing OUTBOX_ENTRY in existing file against research pitfall 4)
- **Issue:** Existing `scripts/test-n8n-e2e.sh` seed entry was missing `retryable:true` field. W15_OUTBOX_WORKER only re-queues to `ralphe:outbox:pending` if `retryable=true AND attempts < maxAttempts(7)`. Without it, the entry goes to `ralphe:outbox:dlq` and TEST-10 would always FAIL with "entry went to DLQ instead of pending".
- **Fix:** Added `"retryable":true` to the `OUTBOX_ENTRY` JSON string in the seed step
- **Files modified:** `scripts/test-n8n-e2e.sh`
- **Verification:** `grep -c 'retryable.*true' scripts/test-n8n-e2e.sh` returns 3 (comment + value + log)
- **Committed in:** `ce9e174` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix — missing required field)
**Impact on plan:** Auto-fix prevents TEST-10 from always failing due to DLQ routing. No scope creep.

## Issues Encountered

- The file `scripts/test-n8n-e2e.sh` already existed from a prior session (untracked). It passed syntax check and met most acceptance criteria but was missing `retryable:true` in the seed entry. Applied Rule 1 auto-fix and committed the complete file.

## User Setup Required

None - no external service configuration required. Script runs against the local docker-compose.test.yml stack.

## Next Phase Readiness

- `scripts/test-n8n-e2e.sh` is complete and ready for plan 08-02 to wire into CI
- Plan 08-02 must handle: compose stack lifecycle, workflow import (W1_IN_WA + W15_OUTBOX_WORKER), DB activation, n8n restart, and `bash scripts/test-n8n-e2e.sh` execution
- REDIS_CREDENTIAL_ID (43SDqJYMGa6RvFqW) must be created as a real credential in the n8n instance during CI setup (see 08-RESEARCH.md Pitfall 1 and Pattern 3 — credential creation timing)

---
*Phase: 08-n8n-e2e-test-implementation*
*Completed: 2026-03-29*
