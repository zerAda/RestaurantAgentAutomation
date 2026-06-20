---
phase: 13-admin-dashboard-audit-log-repair
plan: "01"
subsystem: admin-dashboard, n8n-workflows
tags: [audit-log, vite, docker-compose, n8n, postgres, pagination, filters]
requires:
  - phase: 03-metrics-alerting-and-audit-trail
    provides: AuditLogView page + W_AUDIT_QUERY workflow (AUDIT-03)
  - phase: 11-vps-ops-db-migration-and-audit-chain
    provides: ops.workflow_audit table on VPS (deferred)
provides:
  - admin-dashboard image receives VITE_API_URL so AuditLogView hits the routed audit-log URL
  - W_AUDIT_QUERY honours limit, status, and channel params
  - W_AUDIT_QUERY returns a correct global total via a dedicated count node
affects: [admin-dashboard, n8n, audit-log]
tech-stack:
  added: []
  patterns:
    - "Vite build args must be passed through compose (not just declared as ARG in the Dockerfile)"
    - "n8n paginated query workflows need a separate COUNT(*) node; total != current page length"
key-files:
  created: []
  modified:
    - docker-compose.hostinger.prod.yml
    - docker-compose.base.yml
    - admin-dashboard/src/pages/AuditLogView.tsx
    - workflows/W_AUDIT_QUERY.json
status: code-complete
requirements_closed_at_code_level: [AUDIT-03]
deferred_to_vps: ["rebuild+deploy admin-dashboard image", "end-to-end verify against ops.workflow_audit (needs Phase 11 migration)"]
---

# Phase 13 — Plan 01 Summary: Admin Dashboard Audit-Log Repair

## What changed

1. **`docker-compose.hostinger.prod.yml` + `docker-compose.base.yml`** — added
   `VITE_API_URL: https://api.${DOMAIN_NAME}` to the `admin-dashboard` build args
   (matches the kiosk's existing `api.${DOMAIN_NAME}` usage). The Dockerfile already
   declared `ARG/ENV VITE_API_URL`; it was simply never passed.
2. **`admin-dashboard/src/pages/AuditLogView.tsx`** — removed the unused `n8nBase`
   constant. `apiBase` (from `VITE_API_URL`, now populated) is what builds the fetch URL
   `${apiBase}/webhook/v1/internal/audit-log`. Also clears the file's `no-unused-vars`
   lint error.
3. **`workflows/W_AUDIT_QUERY.json`** — three fixes in one:
   - parse node accepts `limit` as an alias for `page_size`;
   - parse node adds escaped `AND status = …` / `AND channel = …` WHERE clauses when those
     params are present and not `all`;
   - added a `PG - Count Audit` node that executes the existing `countQuery`; flow is now
     `Parse → Count → Query → Format`; `PG - Query Audit` reads its SQL from the parse node
     and uses `alwaysOutputData: true`; `B0 - Format Response` returns the real global
     `total` from the count node instead of `items.length`.

## Verification (local)

- `jq` confirms `W_AUDIT_QUERY.json` is valid JSON with 6 nodes.
- `node --check` passes for both Code nodes (`B0 - Parse Params`, `B0 - Format Response`);
  the workflow-name LIKE-escaping (`\%`, `\_`, `ESCAPE '\'`) round-trips correctly.
- `grep` confirms the `page_size || qs.limit` alias and the `AND status =` / `AND channel =`
  clauses are present.
- Both compose files parse as valid YAML; `VITE_API_URL` present in each admin-dashboard block.

## Requirement status

AUDIT-03 is satisfied **at code level**. Full runtime satisfaction requires (a) the
`ops.workflow_audit` table on VPS (Phase 11) and (b) rebuilding/redeploying the
admin-dashboard image so the new `VITE_API_URL` is baked in. Both are 🔴 **deferred**
(no prod SSH) and tracked in `.planning/REMAINING-WORK.md`.

## Notes

- Pre-existing `no-explicit-any` lint errors in `useEntitlements.ts` (SaaS code, unrelated to
  AUDIT-03) were intentionally left untouched, so the Frontend Lint CI check remains red on
  that baseline debt.
