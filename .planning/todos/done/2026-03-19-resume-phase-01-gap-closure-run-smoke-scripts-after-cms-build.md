---
created: 2026-03-19T20:48:30.550Z
title: Resume Phase 01 gap closure — run smoke scripts after CMS build
area: planning
files:
  - .planning/phases/01-cms-stability-and-base-upgrade/01-04-PLAN.md
  - project/scripts/smoke-cms-routes.sh
  - project/scripts/smoke-post-rebuild.sh
  - project/TEST_REPORT.md
---

## Problem

Phase 01 plan 01-04 (gap closure) is in progress. The CMS Docker image rebuild was started
via `nohup docker compose build cms --no-cache` (PID 2575906 on VPS). The build takes 25-35
minutes. Once it finishes, Tasks 2 and 3 of the plan must be executed manually:

- Task 2: Run both smoke scripts on the VPS and capture output
- Task 3: Update TEST_REPORT.md with actual PASS/FAIL results (replacing BLOCKED/DEFERRED)

The plan is at `.planning/phases/01-cms-stability-and-base-upgrade/01-04-PLAN.md`.

## Solution

Once CMS build is done (check: `ssh deploy@72.60.190.192 'kill -0 2575906 2>/dev/null && echo RUNNING || echo DONE'`):

1. Start CMS: `ssh deploy@72.60.190.192 '/opt/resto/rebuild.sh cms'`
2. Wait for health: `ssh deploy@72.60.190.192 'until curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:1337/_health | grep -q 204; do sleep 15; done && echo healthy'`
3. Run smoke scripts (credentials: adel.zeriri@gmail.com / RestoBot2026):
   ```
   STRAPI_EMAIL=adel.zeriri@gmail.com STRAPI_PASSWORD=RestoBot2026 bash project/scripts/smoke-cms-routes.sh http://127.0.0.1:1337
   STRAPI_EMAIL=adel.zeriri@gmail.com STRAPI_PASSWORD=RestoBot2026 bash project/scripts/smoke-post-rebuild.sh
   ```
4. Update `project/TEST_REPORT.md` (replace BLOCKED/DEFERRED rows with actual results)
5. Create `01-04-SUMMARY.md` and run verifier to close Phase 01
