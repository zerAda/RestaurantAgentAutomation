---
phase: 02-structured-logging-and-correlation
plan: "01"
subsystem: infra
tags: [nginx, correlation-id, request-id, structured-logging, json-logging, observability]

# Dependency graph
requires: []
provides:
  - "Every nginx access log entry contains request_id (32-char hex UUID)"
  - "All proxied requests carry X-Request-ID header set by nginx gateway"
  - "Correlation ID source established at gateway ingress point"
affects:
  - 02-structured-logging-and-correlation
  - 03-metrics-alerting-and-audit-trail

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "nginx $request_id built-in variable used as correlation ID source (no custom module needed)"
    - "JSON log format with structured fields including request_id per access log entry"
    - "X-Request-ID header propagated via proxy_params (n8n routes) and inline (Strapi locations)"

key-files:
  created: []
  modified:
    - infra/gateway/nginx.conf
    - infra/gateway/proxy_params

key-decisions:
  - "Use nginx built-in $request_id variable (available since 1.11.0, 32-char hex from system RNG) — no custom map block or UUID module needed"
  - "Propagate via proxy_params for n8n routes (proxy_params includes it automatically); add inline for Strapi locations that override proxy_set_header"

patterns-established:
  - "Correlation ID pattern: gateway-assigned, carried downstream via X-Request-ID header, logged in access.json"

requirements-completed: [OBS-03, OBS-04]

# Metrics
duration: 8min
completed: 2026-03-23
---

# Phase 02 Plan 01: Nginx Request ID and Correlation Header Summary

**nginx $request_id added to JSON access log and propagated via X-Request-ID header to n8n and Strapi upstreams, establishing gateway-level correlation ID source**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-23T20:10:00Z
- **Completed:** 2026-03-23T20:18:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added `"request_id":"$request_id"` field to `log_format json_audit` in nginx.conf — every access log entry now contains a unique 32-char hex correlation ID
- Added `proxy_set_header X-Request-ID $request_id;` to `proxy_params` — all n8n routes (@whatsapp_get/post, @instagram_get/post, @messenger_get/post, /v1/customer/, /v1/internal/, /v1/admin/) automatically carry the header
- Added `proxy_set_header X-Request-ID $request_id;` inline to all three Strapi proxy locations (/v1/strapi/api/orders, ^~ /v1/strapi/, ^~ /v1/portal/) that use their own proxy_set_header directives
- Deployed to VPS via SCP, passed `nginx -t` inside container, reloaded zero-downtime — healthz returns 'ok', access.json confirms request_id field populated

## Task Commits

Each task was committed atomically:

1. **Task 1: Add request_id to nginx log format and update proxy_params** - `c774d55` (feat)
2. **Task 2: Deploy nginx config to VPS and reload** - no local file changes (VPS deploy via SCP + docker exec)

## Files Created/Modified
- `infra/gateway/nginx.conf` - Updated log_format json_audit with request_id field; added X-Request-ID inline to 3 Strapi proxy locations
- `infra/gateway/proxy_params` - Added proxy_set_header X-Request-ID $request_id for n8n route propagation

## Decisions Made
- Used `$request_id` built-in nginx variable (no additional modules needed, nginx >= 1.11.0, nginx:1.27 fully supports it) — 32-char lowercase hex from system RNG, unique per request
- Strapi locations (/v1/strapi/api/orders, /v1/strapi/, /v1/portal/) use inline proxy_set_header and do NOT include proxy_params, so X-Request-ID was added to each individually

## Deviations from Plan

None — plan executed exactly as written. Both files were already partially modified from a prior session; changes matched the plan spec exactly.

## Issues Encountered
- nginx access logs go to `/var/log/nginx/access.json` inside container (not docker logs stderr). `docker logs` showed only reload notices. Verified via `docker exec ... tail -3 /var/log/nginx/access.json` which confirmed request_id field with 32-char hex values.

## User Setup Required
None — no external service configuration required. nginx reload is zero-downtime.

## Next Phase Readiness
- Correlation ID source is live at gateway ingress — OBS-03 and OBS-04 requirements satisfied
- Ready for Phase 02 Plan 02: n8n structured logging to capture X-Request-ID in workflow execution logs
- Downstream services (n8n, Strapi) now receive X-Request-ID on every proxied request; next step is consuming it in application logs

---
*Phase: 02-structured-logging-and-correlation*
*Completed: 2026-03-23*
