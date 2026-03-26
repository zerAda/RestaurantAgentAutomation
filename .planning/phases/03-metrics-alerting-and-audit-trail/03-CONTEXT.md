---
phase: 03-metrics-alerting-and-audit-trail
type: context
created: 2026-03-23
---

# Phase 3 Context: Metrics, Alerting & Audit Trail

## Goal

Operators can observe queue health and disk pressure in near-real-time; all inbound workflow
executions are recorded in a queryable audit table with 90-day retention.

## Approach

### Log-based, not Prometheus

The VPS has 2 CPU / 4GB RAM and is disk-pressured. No Prometheus/Grafana stack. All metrics are
emitted as structured JSON log lines (same format as Phase 2 correlation logs). Operators query them
with `docker logs` + `jq`, or via the admin dashboard's audit view. This keeps the footprint zero.

### Queue metrics via n8n scheduled workflow

n8n has direct access to the PostgreSQL `n8n` database (it IS that database). A new n8n scheduled
workflow (W_QUEUE_METRICS, every 5 min) queries `execution_entity` to count pending/running/failed
executions and emits a JSON log line. This avoids any new infrastructure.

### Disk alert via container watchdog script

A shell script mounted into a new `watchdog` container (or the existing n8n-worker entrypoint) runs
every 5 minutes, checks `df /` against 80% of 119GB (= 95.2 GB used), and emits CRITICAL log if
crossed. The watchdog also triggers the queue-depth alert if the W_QUEUE_METRICS data shows
depth > 50 for two consecutive 5-minute windows (10 min sustained, close enough to "5 min").

### Nginx rate-limit logging

The current `nginx.conf` log_format `json_audit` does NOT include `$limit_req_status`. We add a
separate `log_format json_ratelimit` and a `limit_req_log_level warn` directive, plus a dedicated
access log for 429 responses. This requires only a nginx.conf edit and `nginx -s reload` — zero
downtime.

### Workflow audit table

A new SQL migration creates `ops.workflow_audit` in the `n8n` PostgreSQL database (already has
the `ops` schema from the retention migration). The three inbound adapter workflows
(W1_IN_WA, W2_IN_IG, W3_IN_MSG) each get an HTTP Request node at the START and END of their
execution that POSTs to a new n8n internal webhook `W_AUDIT_WRITE` which writes to the table.
Using an HTTP Request node (not Postgres node directly) keeps the audit write decoupled and
non-blocking (fire-and-forget pattern already used in the codebase).

### 90-day archival

A new n8n scheduled workflow (W_AUDIT_ARCHIVE, runs daily at 03:00) moves rows older than 90 days
from `ops.workflow_audit` into `ops.workflow_audit_archive` (same schema + `archived_at` column).
The n8n DB user already has full access to the `n8n` database.

### Admin dashboard audit view

A new React page `AuditLogView.tsx` is added to the admin dashboard. It calls a new n8n internal
webhook `GET /v1/internal/audit-log` (implemented by W_AUDIT_QUERY workflow) which queries the
table and returns paginated results. Filters: date range (ISO start/end) and workflow_name.
The page is gated behind `isFullAdmin` and added to the sidebar under "Advanced".

## Key Architectural Decisions

| Decision | Rationale |
|----------|-----------|
| Audit writes via HTTP Request to W_AUDIT_WRITE | Non-blocking; inbound adapters already use this fire-and-forget pattern for outbox |
| `ops.workflow_audit` in n8n DB (not strapi DB) | n8n workflows own this data; avoids cross-DB access from n8n |
| Archive not delete | Compliance: audit trail must be queryable, not purged. Archive table keeps same schema |
| Queue metrics as log lines, not DB rows | Zero schema changes on hot path; operators grep logs |
| Watchdog as shell script in n8n-worker entrypoint | Reuses existing container; no new service |
| Dashboard reads via n8n webhook | Admin dashboard already talks to n8n via API; consistent pattern |

## Files This Phase Touches

- `db/migrations/2026-03-23_p3_workflow_audit.sql` — new migration
- `infra/gateway/nginx.conf` — add rate-limit logging
- `workflows/W_QUEUE_METRICS.json` — new workflow (queue depth + disk alert)
- `workflows/W_AUDIT_WRITE.json` — new workflow (audit write webhook)
- `workflows/W_AUDIT_QUERY.json` — new workflow (audit query webhook)
- `workflows/W_AUDIT_ARCHIVE.json` — new workflow (90-day archival)
- `workflows/W1_IN_WA.json` — add audit hooks (start + completion nodes)
- `workflows/W2_IN_IG.json` — add audit hooks (start + completion nodes)
- `workflows/W3_IN_MSG.json` — add audit hooks (start + completion nodes)
- `admin-dashboard/src/pages/AuditLogView.tsx` — new page
- `admin-dashboard/src/App.tsx` — register route + nav item
- `docker-compose.hostinger.prod.yml` — add QUEUE_ALERT_THRESHOLD, DISK_ALERT_PCT env vars

## Workflow File Naming (existing convention)

Existing: `W1_IN_WA.json`, `W17_HEALTH_MONITOR.json`, `W16_HEALTHZ.json`
New files use underscore-separated caps: `W_QUEUE_METRICS.json`, `W_AUDIT_WRITE.json`, etc.

## n8n Node Types Used

- `n8n-nodes-base.scheduleTrigger` (typeVersion 1) — cron trigger
- `n8n-nodes-base.webhook` (typeVersion 1) — HTTP webhook trigger
- `n8n-nodes-base.code` (typeVersion 2) — JavaScript code node
- `n8n-nodes-base.httpRequest` (typeVersion 4) — HTTP call (fire-and-forget to W_AUDIT_WRITE)
- `n8n-nodes-base.postgres` (typeVersion 2) — direct DB query for W_AUDIT_WRITE and W_AUDIT_QUERY

## PostgreSQL Access Pattern

The n8n DB connection credentials are already available inside n8n workflows via `$env`:
- `DB_POSTGRESDB_HOST` = postgres
- `DB_POSTGRESDB_DATABASE` = n8n
- `DB_POSTGRESDB_USER` = n8n
- `DB_POSTGRESDB_PASSWORD_FILE` = /run/secrets/postgres_password

For the Postgres node, use `Use Database Connection` credential named `RestoBot PG (n8n DB)`.
This credential already exists in n8n (it powers the existing workflows that touch execution data).

## Dependency

Phase 3 depends on Phase 2 (structured logging) per ROADMAP. However, the plans are written
defensively — they do not import Phase 2 correlation IDs as a hard runtime dependency.
The audit write includes `correlation_id` if present in `$json._timing.correlation_id`
(already set by W1_IN_WA's parse node) but falls back to `crypto.randomUUID()`.
