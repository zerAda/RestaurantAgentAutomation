---
phase: 03-metrics-alerting-and-audit-trail
plan: 01
subsystem: database
tags: [postgres, nginx, audit, migration, rate-limit]

requires: []
provides:
  - ops.workflow_audit and ops.workflow_audit_archive tables (90-day TTL partitioned)
  - Nginx json_ratelimit log format capturing 429s + limit_req_log_level warn
  - /v1/internal/ nginx proxy block for internal n8n-to-gateway calls
affects: [03-02, 03-03, 03-04, 03-05]

tech-stack:
  added: []
  patterns: [ops schema for platform-wide operational tables, structured JSON audit logging]

key-files:
  created:
    - db/migrations/2026-03-23_p3_workflow_audit.sql
  modified:
    - infra/gateway/nginx.conf

key-decisions:
  - "No Prometheus/Grafana — log-based metrics only (VPS is 2CPU/4GB, disk-pressured)"
  - "ops schema reused from Phase 1 migration (2026-01-22_p1_db_indexes_retention.sql)"
  - "90-day retention via workflow_audit_archive + DELETE on primary"

patterns-established:
  - "All platform metrics emitted as structured JSON log lines queryable with jq"
  - "ops schema for non-business operational tables (audit, metrics, config)"

requirements-completed: [METR-03, AUDIT-01]

duration: 15min
completed: 2026-03-23
---

# Phase 3 Plan 01: DB Audit Foundation + Nginx Rate-Limit Logging

**ops.workflow_audit table with indexes and 90-day archive + nginx json_ratelimit format capturing 429s**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-03-23
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created `ops.workflow_audit` table with execution tracking (workflow_name, execution_id, channel, status, duration_ms, correlation_id)
- Created `ops.workflow_audit_archive` mirror table for 90-day retention cycle
- Added indexes: started_at DESC, workflow_name+started_at, status for dashboard queries
- Added `log_format json_ratelimit` to nginx.conf with `$limit_req_status` field
- Added `limit_req_log_level warn` directive
- Added `/v1/internal/` proxy block for n8n-to-gateway internal calls

## Task Commits

1. **Task 1: DB migration** — `56a5516` (Phase 6 bulk commit — pre-existed)
2. **Task 2: Nginx rate-limit logging** — `56a5516` (Phase 6 bulk commit — pre-existed)

## Files Created/Modified
- `db/migrations/2026-03-23_p3_workflow_audit.sql` — Full audit table DDL with indexes and archive table
- `infra/gateway/nginx.conf` — Added json_ratelimit log format, limit_req_log_level warn, /v1/internal/ proxy

## Decisions Made
- Log-based metrics (no Prometheus) due to VPS resource constraints
- Used ops schema that already existed from Phase 1

## Deviations from Plan
None - plan executed as specified. Files pre-committed in bulk Phase 6 commit (56a5516).

## Issues Encountered
None.

## Next Phase Readiness
- ops.workflow_audit table ready for W_AUDIT_WRITE workflow (03-03)
- /v1/internal/ proxy ready for audit write calls from n8n workflows

---
*Phase: 03-metrics-alerting-and-audit-trail*
*Completed: 2026-03-23*
