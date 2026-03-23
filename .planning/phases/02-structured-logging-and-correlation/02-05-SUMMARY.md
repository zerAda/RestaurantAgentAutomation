---
phase: 02-structured-logging-and-correlation
plan: 05
subsystem: observability/smoke-tests
tags: [smoke-test, requirements, gap-closure, n8n, strapi]
dependency_graph:
  requires: [02-04]
  provides: [real-json-validation-smoke-script, OBS-02-complete]
  affects: [scripts/smoke-correlation.sh, .planning/REQUIREMENTS.md]
tech_stack:
  added: []
  patterns: [python3-json-parsing-in-bash, ndjson-validation]
key_files:
  created: []
  modified:
    - scripts/smoke-correlation.sh
    - .planning/REQUIREMENTS.md
decisions:
  - OBS-01 left as pending because VPS n8n is 1.80.0 (not 2.9.4) and 1.80.0 does not honor N8N_LOG_FORMAT=json
  - OBS-02 marked complete after smoke script confirmed 50+ JSON log lines with service='strapi-cms'
  - Smoke script OBS-01 improvement kept despite OBS-01 not passing — the real validation logic is correct
metrics:
  duration: 3 min
  completed_date: "2026-03-23"
  tasks_completed: 2
  files_modified: 2
---

# Phase 02 Plan 05: Gap Closure — Smoke Script JSON Validation and Requirements Update

**One-liner:** Replaced n8n health-check with real python3 json.loads NDJSON validation; confirmed OBS-02 complete; OBS-01 blocked on n8n version (1.80.0 does not emit JSON format).

## What Was Built

Task 1 replaced the OBS-01 section in `scripts/smoke-correlation.sh` with real JSON format validation using the same `python3 json.loads` pattern already used for OBS-02. The old code merely checked line count (container health), now it validates each log line as JSON and counts lines with `level` + `message`/`msg` fields.

Task 2 updated `REQUIREMENTS.md` to reflect the actual state of OBS-01 and OBS-02 based on live smoke test results.

## Deviations from Plan

### Auto-fixed Issues

None.

### Plan Premise Corrections

**1. [Factual Discovery] n8n version on VPS is 1.80.0, not 2.9.4**
- **Found during:** Task 1 execution (running smoke script on VPS)
- **Expected:** Plan assumed n8n 2.9.4 is running and supports N8N_LOG_FORMAT=json
- **Actual:** `docker exec current-n8n-main-1 node -e "..."` reports version 1.80.0
- **Result:** n8n logs are plain text even with N8N_LOG_FORMAT=json set — this env var is a no-op in 1.80.0
- **Sample output:**
  ```
  Enqueued execution 383561 (job 382564)
  Execution 383561 (job 382564) finished successfully
  ```
- **Impact on plan:** OBS-01 cannot be marked complete. The original smoke script comment ("n8n 1.80.0 does not support N8N_LOG_FORMAT=json") was actually correct.

**2. [Scope Adjustment] OBS-01 not marked [x] in REQUIREMENTS.md**
- **Reason:** Marking OBS-01 complete when the VPS does not satisfy it would be factually false
- **Action taken:** OBS-01 remains `[ ]` with traceability updated to "Blocked (n8n 1.80.0 no JSON format; needs upgrade)"
- **Path to completion:** Requires upgrading n8n from 1.80.0 → 2.x (tracked in REQUIREMENTS.md v2 as N8N-01)

### What Was Fully Completed

| Task | Result | Notes |
|------|--------|-------|
| Task 1: Fix OBS-01 smoke check | DONE | Real JSON validation implemented; old comments/variables removed |
| Task 2: Mark OBS-02 complete | DONE | Smoke confirmed 50 JSON lines with service='strapi-cms' |
| Task 2: Mark OBS-01 complete | DEVIATED | Cannot mark complete — n8n 1.80.0 does not emit JSON |

## Verification Results

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| grep "n8n 1.80.0" smoke script | 0 matches | 0 matches | PASS |
| grep "json.loads" smoke script | >=4 | 8 matches | PASS |
| grep "N8N_UP\|WORKER_UP" smoke script | 0 | 0 | PASS |
| OBS-01 checkbox [x] | 1 match | 0 (left pending) | DEVIATED |
| OBS-02 checkbox [x] | 1 match | 1 match | PASS |
| OBS-02 traceability Complete | present | present | PASS |
| Smoke test OBS-01 PASS | required | FAIL (n8n 1.80.0) | DEVIATED |
| Smoke test OBS-02 PASS | required | PASS (50 JSON lines) | PASS |

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1: Fix OBS-01 JSON validation | 15bb4b2 | scripts/smoke-correlation.sh |
| Task 2: REQUIREMENTS.md updates | 16596da | .planning/REQUIREMENTS.md |

## Decisions Made

1. **OBS-01 not marked complete:** The smoke script now correctly validates actual NDJSON format. n8n 1.80.0 fails this check correctly (it doesn't emit JSON). Marking it complete would misrepresent the system state.

2. **Script improvement kept:** The code change to use `json.loads` validation is correct and valuable even though OBS-01 fails. When n8n is upgraded to 2.x, the smoke check will correctly detect and validate JSON format.

3. **OBS-01 traceability updated to "Blocked":** More accurate than "Pending" since the reason is known (version constraint) and the path forward is clear (n8n upgrade).

## Self-Check: PASSED

All key files exist. Both task commits verified in git log.

- scripts/smoke-correlation.sh: FOUND
- .planning/REQUIREMENTS.md: FOUND
- .planning/phases/02-structured-logging-and-correlation/02-05-SUMMARY.md: FOUND
- Commit 15bb4b2: FOUND
- Commit 16596da: FOUND
