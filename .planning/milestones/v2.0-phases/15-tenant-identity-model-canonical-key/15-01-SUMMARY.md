---
phase: 15-tenant-identity-model-canonical-key
plan: 01
subsystem: tenant-identity
tags: [adr, tenant, canonical-key, documentation]
key-decisions:
  - "tenants.tenant_id (UUID) is the single canonical tenant key for the entire platform"
  - "Option A chosen: store UUID-as-string in existing VARCHAR(255) entitlement columns (no ALTER TABLE in Phase 15)"
  - "entitlement_audit_log.tenant_id stays VARCHAR(255) through Phase 15; migrates to uuid with FK in Phase 19"
  - "VPS backfill must discover live UUID via SELECT tenant_id FROM tenants LIMIT 1, never hardcode CI/dev UUID"
  - "Open Question 2 resolved: tenant-entitlement schema.json defines tenant_id as string field"
key-files:
  created:
    - docs/adr/0001-canonical-tenant-key.md
  modified: []
metrics:
  duration: "~5 minutes"
  completed: "2026-06-20"
  tasks: 1
  files: 1
---

# Phase 15 Plan 01: Canonical Tenant Key ADR Summary

One-liner: Formal ADR establishing tenants.tenant_id (UUID) as canonical key, documenting Option A reconciliation (UUID-as-string in VARCHAR), keeping entitlement_audit_log VARCHAR through Phase 15 with Phase 19 migration plan, and resolving Open Question 2 on schema.json.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write the canonical-key ADR | 0f6e8ed | docs/adr/0001-canonical-tenant-key.md |

## Acceptance Criteria Status

- [x] `docs/adr/0001-canonical-tenant-key.md` exists and is >= 60 lines (177 lines)
- [x] Contains literal canonical UUID `00000000-0000-0000-0000-000000000001`
- [x] Names `tenants.tenant_id` as canonical (grep `tenants\.tenant_id` matches)
- [x] Contains `VARCHAR(255)` AND `Phase 19`
- [x] Contains literal runtime-discovery query `SELECT tenant_id FROM tenants LIMIT 1`
- [x] Contains string `schema.json`

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED
