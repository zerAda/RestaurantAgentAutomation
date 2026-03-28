---
phase: 03-metrics-alerting-and-audit-trail
plan: 02
subsystem: infra
tags: [n8n, workflow, queue, metrics, alerts, redis, postgres]

requires:
  - phase: 03-01
    provides: ops schema tables for audit trail
provides:
  - W_QUEUE_METRICS workflow emitting queue depth + error rate + disk CRITICAL alerts as JSON log lines
  - QUEUE_ALERT_THRESHOLD env var in production compose
affects: []

tech-stack:
  added: []
  patterns: [log-based metrics via n8n scheduled workflow, queue depth monitoring via execution_entity]

key-files:
  created:
    - workflows/W_QUEUE_METRICS.json
  modified:
    - docker-compose.hostinger.prod.yml

key-decisions:
  - "n8n queries its own execution_entity table for queue depth — no external metrics system needed"
  - "QUEUE_ALERT_THRESHOLD=50 default (10-min sustained depth triggers CRITICAL)"
  - "Disk alert at 80% of 119GB (95.2GB used) emitted as CRITICAL log line"

patterns-established:
  - "Operational alerts as structured JSON log lines via n8n scheduled workflows"

requirements-completed: [METR-01, METR-02, METR-04, METR-05]

duration: 20min
completed: 2026-03-23
---

# Phase 3 Plan 02: W_QUEUE_METRICS Workflow

**n8n scheduled workflow querying execution_entity for queue depth + disk alert, emitting structured JSON log lines every 5 minutes**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-03-23
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created W_QUEUE_METRICS.json: 7-node n8n workflow running every 5 minutes
- Queries `execution_entity` for pending/running/failed execution counts
- Emits structured JSON log line: `{"event":"queue_metrics","pending":N,"running":N,"failed_24h":N}`
- Triggers CRITICAL alert if depth > QUEUE_ALERT_THRESHOLD for two consecutive windows
- Added disk usage check emitting CRITICAL if > 80% (95.2GB on 119GB drive)
- Added `QUEUE_ALERT_THRESHOLD: "50"` to both n8n-main and n8n-worker in production compose

## Task Commits

1. **Task 1: W_QUEUE_METRICS workflow** — `56a5516` (Phase 6 bulk commit — pre-existed)
2. **Task 2: QUEUE_ALERT_THRESHOLD in compose** — `56a5516` (Phase 6 bulk commit — pre-existed)

## Files Created/Modified
- `workflows/W_QUEUE_METRICS.json` — Queue depth + disk alert n8n workflow (7 nodes)
- `docker-compose.hostinger.prod.yml` — Added QUEUE_ALERT_THRESHOLD env var to n8n-main and n8n-worker

## Decisions Made
- Used n8n's own Postgres connection rather than adding a separate monitoring service
- Disk alert threshold at 80% based on known 119GB drive size and ENOSPC history

## Deviations from Plan
None - plan executed as specified. Files pre-committed in bulk Phase 6 commit (56a5516).

## Issues Encountered
None.

## Next Phase Readiness
- Queue metrics operational; audit write workflow (03-03) can now track workflow executions

---
*Phase: 03-metrics-alerting-and-audit-trail*
*Completed: 2026-03-23*
