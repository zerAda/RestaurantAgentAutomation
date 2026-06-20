---
phase: 17
plan: "01"
subsystem: inbound-adapters
tags: [tenant-derivation, fail-closed, channel-identities, n8n-workflow, auth-context]
dependency_graph:
  requires: [db/migrations/2026-06-20_channel_identities.sql, credentials/postgres-main]
  provides: [W1_IN_WA resolver rung, W2_IN_IG resolver rung, W3_IN_MSG resolver rung]
  affects: [W1_IN_WA.json, W2_IN_IG.json, W3_IN_MSG.json]
tech_stack:
  added: []
  patterns: [channel_identities DB lookup, namespace shim via Code node, fail-closed UNKNOWN_CHANNEL_IDENTITY deny path]
key_files:
  created: []
  modified:
    - workflows/W1_IN_WA.json
    - workflows/W2_IN_IG.json
    - workflows/W3_IN_MSG.json
decisions:
  - namespace-shim: Added B0 - Map Channel Identity Result Code node to namespace resolver output as ci_tenant_id/ci_restaurant_id/ci_resolved, avoiding collision with B0 - Resolve Client (DB) columns of the same name
  - fail-closed-deny: UNKNOWN_CHANNEL_IDENTITY denyReason routes through existing B0 - Token OK? FALSE path to B0 - Log Deny (DB) and END - Drop/Done, reusing established deny infrastructure
  - duplicate-metaSigValid-fix: W2_IN_IG and W3_IN_MSG had a latent duplicate const metaSigValid SyntaxError; full rewrite of Apply Auth Context jsCode eliminated it
metrics:
  duration_minutes: 45
  completed_date: 2026-06-20
  tasks_completed: 2
  files_modified: 3
---

# Phase 17 Plan 01: Channel Identities Resolver Rung + Fail-Closed Apply Auth Context Summary

DB-backed channel_identities resolver inserted into all three inbound adapters (W1/W2/W3) with namespace shim and fail-closed UNKNOWN_CHANNEL_IDENTITY deny path replacing the removed DEFAULT_TENANT_ID fallback construct.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 17-01-01 | Insert B0 - Resolve Channel Identity (DB) + B0 - Map Channel Identity Result nodes | ce9f724 | W1_IN_WA.json, W2_IN_IG.json, W3_IN_MSG.json |
| 17-01-02 | Rewrite B0 - Apply Auth Context jsCode (fail-closed, remove fallbacks) | ce9f724 | W1_IN_WA.json, W2_IN_IG.json, W3_IN_MSG.json |

## Deviations from Plan

### Auto-fixed Issues

**1. [MANDATORY_CORRECTION #1 - Bug] Removed __inventory_15 node-level key from B0 - Apply Auth Context**
- **Found during:** Task 17-01-02
- **Issue:** The `B0 - Apply Auth Context` node in W1_IN_WA.json had `"__inventory_15": true` as a top-level node object property (not inside jsCode). This was required to be removed per BLOCKER correction.
- **Fix:** Deleted the `__inventory_15` key from the node object in all three files (W1/W2/W3). W2/W3 also had `__inventory_15` annotation keys on their `B0 - Apply Auth Context` nodes which were removed.
- **Files modified:** W1_IN_WA.json, W2_IN_IG.json, W3_IN_MSG.json
- **Commit:** ce9f724

**2. [Rule 1 - Bug] Fixed duplicate const metaSigValid in W2_IN_IG and W3_IN_MSG**
- **Found during:** Task 17-01-02
- **Issue:** W2 and W3 `B0 - Apply Auth Context` jsCode declared `const metaSigValid` twice in the same scope — a latent SyntaxError that would surface at runtime.
- **Fix:** Full rewrite of Apply Auth Context jsCode with exactly one `const metaSigValid` declaration.
- **Files modified:** W2_IN_IG.json, W3_IN_MSG.json
- **Commit:** ce9f724

**3. [Rule 1 - Bug] Removed hardcoded canonical UUIDs from W2_IN_IG and W3_IN_MSG Apply Auth Context**
- **Found during:** Task 17-01-02
- **Issue:** W2 and W3 had hardcoded `00000000-0000-0000-0000-000000000001` and `00000000-0000-0000-0000-000000000000` UUIDs as fallbacks inside `B0 - Apply Auth Context` jsCode.
- **Fix:** Replaced with `ciTenantId`/`ciRestaurantId` from channel_identities resolver. No hardcoded UUIDs remain in those nodes' jsCode.
- **Files modified:** W2_IN_IG.json, W3_IN_MSG.json
- **Commit:** ce9f724

## Verification Results

```
PASS: resolver present in W1_IN_WA
PASS: resolver present in W2_IN_IG
PASS: resolver present in W3_IN_MSG
PASS: middle hop present in W1_IN_WA
PASS: middle hop present in W2_IN_IG
PASS: middle hop present in W3_IN_MSG
PASS: UNKNOWN_CHANNEL_IDENTITY present in W1_IN_WA
PASS: UNKNOWN_CHANNEL_IDENTITY present in W2_IN_IG
PASS: UNKNOWN_CHANNEL_IDENTITY present in W3_IN_MSG
PASS: no __inventory_15 key on B0 - Apply Auth Context nodes
PASS: all three workflow JSONs valid
```

## Self-Check: PASSED

- ce9f724 exists in git log
- W1_IN_WA.json, W2_IN_IG.json, W3_IN_MSG.json modified in that commit
