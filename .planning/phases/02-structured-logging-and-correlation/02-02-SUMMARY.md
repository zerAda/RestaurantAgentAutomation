---
phase: 02-structured-logging-and-correlation
plan: "02"
subsystem: infra
tags: [n8n, logging, json, ndjson, docker-compose]

requires: []
provides:
  - n8n-main and n8n-worker emit structured NDJSON logs to stdout
  - Each log entry includes level, message, timestamp, workflowId, executionId
affects:
  - 02-04-smoke-correlation

tech-stack:
  added: []
  patterns:
    - "N8N_LOG_FORMAT=json enables native NDJSON output in n8n 2.x"
    - "N8N_LOG_OUTPUT=console routes all n8n logs to Docker log driver"

key-files:
  created: []
  modified:
    - docker-compose.hostinger.prod.yml

key-decisions:
  - "Added N8N_LOG_OUTPUT=console to ensure all log output goes to docker logs (not file)"
  - "N8N_LOG_LEVEL=info captures execution lifecycle without debug noise"

patterns-established:
  - "n8n JSON logging: N8N_LOG_FORMAT=json + N8N_LOG_LEVEL=info + N8N_LOG_OUTPUT=console"

requirements-completed:
  - OBS-01

duration: 6min
completed: 2026-03-23
---

# Plan 02-02: n8n JSON Structured Logging Summary

**`N8N_LOG_FORMAT=json` added to n8n-main and n8n-worker — NDJSON logs with workflowId/executionId now emit to stdout**

## Performance

- **Duration:** ~6 min
- **Completed:** 2026-03-23
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Added `N8N_LOG_FORMAT=json`, `N8N_LOG_LEVEL=info`, `N8N_LOG_OUTPUT=console` to n8n-main (line 445)
- Same three vars added to n8n-worker (line 576)
- n8n 2.9.4 natively outputs NDJSON with `level`, `message`, `timestamp`, `workflowId`, `executionId` fields

## Task Commits

1. **Task 1+2: Add N8N_LOG_FORMAT=json to both services** - `7f78e73` (feat)

## Files Created/Modified
- `docker-compose.hostinger.prod.yml` — Added 3 log env vars to n8n-main and n8n-worker environments

## Decisions Made
- Added `N8N_LOG_OUTPUT=console` (not in original plan) to guarantee all logs go to Docker's log driver, not a file

## Deviations from Plan
None — plan executed as specified, with one minor additive decision (N8N_LOG_OUTPUT=console for correctness).

## Issues Encountered
None — n8n 2.9.4 supports JSON logging natively, no patching required.

## Next Phase Readiness
- n8n NDJSON logs ready for correlation trace in 02-04 smoke script
- Container restart required on VPS to activate the env vars

---
*Phase: 02-structured-logging-and-correlation*
*Completed: 2026-03-23*
