---
phase: 17
plan: "02"
subsystem: workflow-guard-driver
tags: [tenant-fallback-removal, fail-closed, module-guard, driver-onboarding, adr]
dependency_graph:
  requires: [17-01 resolver rung in W1/W2/W3]
  provides: [fallback-free W0_MODULE_GUARD, fallback-free W_DRIVER_ONBOARDING, updated ADR 0002]
  affects: [W0_MODULE_GUARD.json, W_DRIVER_ONBOARDING.json, docs/adr/0002-tenant-id-fallback-inventory.md]
tech_stack:
  added: []
  patterns: [fail-closed guard on blank tenant_id, NOT NULL enforcement via param removal, past-tense ADR updates]
key_files:
  created: []
  modified:
    - workflows/W0_MODULE_GUARD.json
    - workflows/W_DRIVER_ONBOARDING.json
    - docs/adr/0002-tenant-id-fallback-inventory.md
decisions:
  - guard-fail-closed: W0_MODULE_GUARD guard now returns allowed:false with reason GUARD_ERROR:tenant_id not provided (UNKNOWN_CHANNEL_IDENTITY) on blank tenant_id, acting as defense-in-depth since callers (W1/W2/W3) already derive real UUIDs from channel_identities
  - driver-not-null: W_DRIVER_ONBOARDING Ensure Customer Profile queryParams reduced to [$json.phone, $json.tenant_id, $json.restaurant_id] — missing tenant causes loud NOT NULL constraint violation rather than silent wrong-tenant write
  - adr-past-tense: ADR 0002 rows #2/#3/#4 updated to REMOVED (Phase 17) with post-Phase-17 state section documenting zero remaining workflow fallbacks
metrics:
  duration_minutes: 20
  completed_date: 2026-06-20
  tasks_completed: 2
  files_modified: 3
---

# Phase 17 Plan 02: Remove W0 + W_DRIVER Fallbacks; Update ADR 0002 Summary

Tenant fallback constructs removed from W0_MODULE_GUARD (|| DEFAULT_TENANT_ID || 'default') and W_DRIVER_ONBOARDING (|| DEFAULT_TENANT_ID || UUID), with fail-closed guards replacing them; ADR 0002 updated to past-tense with post-Phase-17 state section.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 17-02-01 | Remove tenant fallbacks from W0_MODULE_GUARD + W_DRIVER_ONBOARDING; strip __inventory_15 | 1b91f99 | W0_MODULE_GUARD.json, W_DRIVER_ONBOARDING.json |
| 17-02-02 | Update ADR 0002 to past-tense with post-Phase-17 state | 1b91f99 | docs/adr/0002-tenant-id-fallback-inventory.md |

## Deviations from Plan

None - plan executed exactly as written. The `__inventory_15` annotation key removal was performed on W0_MODULE_GUARD "Module Guard" node and W_DRIVER_ONBOARDING "Ensure Customer Profile" node as specified.

## Verification Results

```
PASS: no DEFAULT_TENANT_ID in W0_MODULE_GUARD jsCode active code
PASS: allowed:false fail-closed guard present in W0_MODULE_GUARD
PASS: GUARD_ERROR tenant_id not provided present in W0_MODULE_GUARD
PASS: no __inventory_15 on W0_MODULE_GUARD Module Guard node
PASS: queryParams reduced to 3-element form in W_DRIVER_ONBOARDING
PASS: no __inventory_15 on W_DRIVER_ONBOARDING Ensure Customer Profile node
PASS: ADR 0002 REMOVED (Phase 17) present (>= 3 occurrences)
PASS: Post-Phase 17 State section present in ADR 0002
PASS: both workflow JSONs valid
```

## Self-Check: PASSED

- 1b91f99 exists in git log
- W0_MODULE_GUARD.json, W_DRIVER_ONBOARDING.json, docs/adr/0002-tenant-id-fallback-inventory.md modified in that commit
