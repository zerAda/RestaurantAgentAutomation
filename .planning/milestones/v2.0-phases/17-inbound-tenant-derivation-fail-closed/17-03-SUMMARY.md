---
phase: 17
plan: "03"
subsystem: ci-gate
tags: [ci, postgres, sql-assertions, github-actions, structural-assertions]
dependency_graph:
  requires: [db/migrations/2026-06-20_channel_identities.sql, 17-01 resolver nodes in W1/W2/W3]
  provides: [db/ci-assertions/17-tenant-resolution.sql, .github/workflows/phase-17-assertions.yml]
  affects: []
tech_stack:
  added: []
  patterns: [psql DO-block assertions with ON_ERROR_STOP=1, SAVEPOINT/ROLLBACK pattern for non-destructive test, jq structural assertions, pinned action SHA]
key_files:
  created:
    - db/ci-assertions/17-tenant-resolution.sql
    - .github/workflows/phase-17-assertions.yml
  modified: []
decisions:
  - savepoint-pattern: is_active=false test uses SAVEPOINT/ROLLBACK TO SAVEPOINT so the row is temporarily deactivated without committing, consistent with Phase 16 CI patterns
  - jsCode-level-uuid-check: W2/W3 file-level grep for UUID is exempt (UUID legitimately appears elsewhere in those files), so a separate jq-based step extracts only the B0 - Apply Auth Context jsCode and checks it independently (MANDATORY_CORRECTION #2)
  - middle-hop-assertion: CI gate explicitly asserts .connections["B0 - Resolve Channel Identity (DB)"].main[0][0].node == "B0 - Map Channel Identity Result" for W1/W2/W3 (MANDATORY_CORRECTION #3)
metrics:
  duration_minutes: 15
  completed_date: 2026-06-20
  tasks_completed: 2
  files_created: 2
---

# Phase 17 Plan 03: CI Gate — Tenant-Resolution SQL + Structural Workflow Assertions Summary

Ephemeral-Postgres CI job proves channel_identities resolver correctness (known resolves, unknown/inactive return 0 rows); structural job asserts resolver rung presence, middle-hop wiring, UNKNOWN_CHANNEL_IDENTITY fail-closed, no fallbacks, and single const metaSigValid across all five affected workflows.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 17-03-01 | Create db/ci-assertions/17-tenant-resolution.sql (4 DO-block assertions) | b2be835 | db/ci-assertions/17-tenant-resolution.sql |
| 17-03-02 | Create .github/workflows/phase-17-assertions.yml (CI gate, two jobs) | b2be835 | .github/workflows/phase-17-assertions.yml |

## Deviations from Plan

None - both MANDATORY_CORRECTION warnings were incorporated directly into the CI gate design:
- MANDATORY_CORRECTION #2: separate "No tenant fallback in W2/W3 Apply Auth Context jsCode" step using jq extraction
- MANDATORY_CORRECTION #3: "Middle connection hop present in W1/W2/W3" step asserting B0 - Resolve Channel Identity (DB) → B0 - Map Channel Identity Result wiring

## MANDATORY_CORRECTIONS Applied

All three MANDATORY_CORRECTIONS from the pre-execution plan-checker are confirmed applied:

| # | Severity | Description | Applied In | Verification |
|---|----------|-------------|------------|--------------|
| 1 | BLOCKER | Delete `__inventory_15` node-level key from B0 - Apply Auth Context in W1_IN_WA.json (and W2/W3) | 17-01 (ce9f724) | `jq -e '.nodes[]\|select(.name=="B0 - Apply Auth Context")\|has("__inventory_15")\|not' workflows/W1_IN_WA.json` returns `true` |
| 2 | WARNING | CI step extracting W2/W3 Apply Auth Context jsCode and failing on hardcoded UUID | 17-03 (b2be835) | "No tenant fallback in W2/W3 Apply Auth Context jsCode" step in workflow-structural job |
| 3 | WARNING | Assert middle connection hop B0-Resolve→B0-Map in W1/W2/W3 | 17-03 (b2be835) | "Middle connection hop present in W1/W2/W3" step in workflow-structural job |

## Verification Results

```
YAML valid
PASS: 17-tenant-resolution.sql reference present
PASS: resolver node assertion present
PASS: UNKNOWN_CHANNEL_IDENTITY assertion present
PASS: INVENTORY-17 assertion present
PASS: metaSigValid assertion present
PASS ci gate well-formed
PASS: 4 DO blocks in SQL file
PASS: channel_identities present
PASS: CI_WA_PHONE_NUMBER_ID present
PASS: CI_IG_PAGE_ID present
PASS: UNKNOWN_RANDOM_ID_XYZ present
PASS: is_active = false present
PASS: SAVEPOINT present
```

## Self-Check: PASSED

- b2be835 exists in git log
- db/ci-assertions/17-tenant-resolution.sql created in that commit (2 files, 283 insertions)
- .github/workflows/phase-17-assertions.yml created in that commit
