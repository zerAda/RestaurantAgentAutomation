---
phase: 01-cms-stability-and-base-upgrade
plan: 01
subsystem: cms
tags: [smoke-testing, scripts, documentation, cms, strapi]
dependency_graph:
  requires: []
  provides: [smoke-cms-routes.sh, smoke-post-rebuild.sh, PATCHLOG-v3.4.6, TEST_REPORT-phase1]
  affects: [plan-02-cms-rebuild-verification]
tech_stack:
  added: []
  patterns: [curl-bearer-auth, bash-smoke-testing, exit-code-conventions]
key_files:
  created:
    - project/scripts/smoke-cms-routes.sh
    - project/scripts/smoke-post-rebuild.sh
  modified:
    - project/PATCHLOG.md
    - project/TEST_REPORT.md
decisions:
  - "Custom handler routes (control-plane/status, metrics) tested separately from collection/singleType routes"
  - "metrics endpoint accepts 200 or 401 as both indicate route exists; 404 would mean missing"
  - "smoke-post-rebuild.sh falls back to /v1/strapi/api/auth/local if /v1/portal endpoint returns non-200"
  - "Committed to inner project/.git (not outer repo) since project/ is a nested git repository"
metrics:
  duration: "3 minutes"
  completed: "2026-03-18T00:37:25Z"
  tasks_completed: 3
  files_changed: 4
requirements_covered: [CMS-01, CMS-02, CMS-03, INFRA-03]
---

# Phase 1 Plan 01: Smoke Scripts & Documentation Summary

Bash smoke scripts for all 15 Strapi CMS routes and post-rebuild verification, plus PATCHLOG/TEST_REPORT entries needed by Wave 2 plans.

## What Was Built

### Task 1: smoke-cms-routes.sh
- Authenticates via `POST /api/auth/local` to obtain JWT (jq with python3 fallback)
- Tests 13 collectionType routes: products, orders, customers, ingredients, payments, delivery-assignments, funnel-events, inbound-messages, feedbacks, suppliers, loyalty-tiers, marketing-campaigns, delivery-zones
- Tests 2 singleType routes: system-config, restaurant-brand
- Tests 2 custom handler routes: control-plane/status (expect 200), metrics (200 or 401 acceptable)
- Uses `Authorization: Bearer $TOKEN` header on every route check
- Exits 1 if any route fails; exits 0 on all pass; exits 2 on auth failure
- LF line endings, no hardcoded credentials

### Task 2: smoke-post-rebuild.sh
- Check 1: CMS health `/_health` expects HTTP 204 (Strapi 5 standard)
- Check 2: CMS login `POST /api/auth/local` expects 200 + non-empty JWT
- Check 3: Kiosk products `GET /v1/strapi/api/products` expects 200 + `"data"` array
- Check 4: Admin login via gateway `/v1/portal/api/auth/local` with fallback to `/v1/strapi/api/auth/local`
- Exits 1 on any failure, exits 0 on all pass
- LF line endings, positional args with env var defaults

### Task 3: PATCHLOG + TEST_REPORT
- `PATCHLOG.md`: v3.4.6 entry prepended with what/why/risk/rollback sections
- `TEST_REPORT.md`: Phase 1 stub prepended with PENDING rows for Node.js base image checks and smoke test results

## Verification Results

| Check | Result |
|-------|--------|
| smoke-cms-routes.sh bash -n | PASS |
| smoke-post-rebuild.sh bash -n | PASS |
| 15 route checks present | PASS (13 collectionType + 2 singleType via check_route) |
| PATCHLOG v3.4.6 grep | PASS |
| TEST_REPORT Phase 1 grep | PASS |
| LF line endings | PASS (no CRLF in file output) |

## Commits

| Task | Hash | Message |
|------|------|---------|
| Task 1+2 | a7895ae | feat(01-01): add CMS route smoke test scripts |
| Task 3 | b6ec297 | docs(01-01): add v3.4.6 PATCHLOG entry and Phase 1 TEST_REPORT stub |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Nested git repository — committed to inner project/.git**
- **Found during:** Task 1 commit
- **Issue:** `project/` directory contains its own `.git` — outer repo treats it as embedded submodule; individual files cannot be staged in outer repo
- **Fix:** All task commits made to inner `project/.git` which holds the actual codebase history (matches prior commit history: 65e84d7, e30bff3, d5fb468)
- **Files modified:** None — same files, different git repo context
- **Commit:** a7895ae, b6ec297 (in project/ repo on branch main)

**2. [Rule 1 - Bug] CRLF line endings from Write tool**
- **Found during:** Task 1 verification
- **Issue:** Write tool on Windows produces CRLF; plan requires LF for shell scripts
- **Fix:** `sed -i 's/\r//'` on both scripts immediately after write; re-verified with `file` command
- **Files modified:** project/scripts/smoke-cms-routes.sh, project/scripts/smoke-post-rebuild.sh

## Self-Check: PASSED

| Item | Status |
|------|--------|
| project/scripts/smoke-cms-routes.sh | FOUND |
| project/scripts/smoke-post-rebuild.sh | FOUND |
| project/PATCHLOG.md | FOUND |
| project/TEST_REPORT.md | FOUND |
| commit a7895ae | FOUND |
| commit b6ec297 | FOUND |
