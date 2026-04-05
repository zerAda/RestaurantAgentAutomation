---
description: Run the most relevant test/lint/build flow and summarize failures
agent: build
---

Run the most relevant test/lint/build flow and summarize failures with next actions.

Workflow:

1. Detect the current working area from the active NID or recent git changes:
   - Run: `git diff --name-only HEAD~3 2>/dev/null || git diff --name-only`

2. Based on affected files, run the relevant validations:

   **If `admin-dashboard/` changed:**
   - `cd admin-dashboard && npm run lint 2>&1 | tail -30`
   - `cd admin-dashboard && npm run build 2>&1 | tail -30`

   **If `kiosk-app/` changed:**
   - `cd kiosk-app && npm run lint 2>&1 | tail -30`
   - `cd kiosk-app && npm run build 2>&1 | tail -30`

   **If `inventory-cms/` changed:**
   - `cd inventory-cms && npm run lint 2>&1 | tail -30`
   - `cd inventory-cms && npm run build 2>&1 | tail -30`

   **If `infra/` or `docker-compose*.yml` changed:**
   - `docker compose -f docker-compose.base.yml config --quiet`
   - `docker compose -f docker-compose.hostinger.prod.yml config --quiet`

   **If `db/migrations/` changed:**
   - Check SQL syntax and idempotency patterns

   **If `scripts/` changed:**
   - `bash -n <changed-script>`

   **If `.github/workflows/` changed:**
   - Validate YAML syntax

   **Always run:**
   - `bash scripts/integrity_gate.sh 2>&1 | tail -20` (if it exists)

3. Summarize results:
   - **Passed**: list
   - **Failed**: list with root cause
   - **Skipped**: list with reason
   - **Fix surfaces**: where to look for fixes

4. Update the active NID note with test results

5. Return: pass/fail summary + recommended next command
