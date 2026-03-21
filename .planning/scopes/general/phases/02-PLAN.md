---
phase: 02-reliability
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - project/infra/redis/entrypoint.sh
  - project/docker-compose.hostinger.prod.yml
  - project/.github/workflows/health-monitor.yml
  - project/PATCHLOG.md
  - project/TEST_REPORT.md
autonomous: true
requirements: [REL-01, REL-02, REL-03]

must_haves:
  truths:
    - "Redis never evicts Bull queue entries under memory pressure"
    - "db-migrate waits for Postgres to accept connections before running migrations"
    - "VPS disk usage above 85% triggers an alert via ALERT_WEBHOOK_URL"
  artifacts:
    - path: "project/infra/redis/entrypoint.sh"
      provides: "Redis startup with noeviction policy"
      contains: "noeviction"
    - path: "project/docker-compose.hostinger.prod.yml"
      provides: "db-migrate with service_healthy dependency on postgres"
      contains: "service_healthy"
    - path: "project/.github/workflows/health-monitor.yml"
      provides: "Disk pressure check step"
      contains: "df -h"
  key_links:
    - from: "project/infra/redis/entrypoint.sh"
      to: "redis-server"
      via: "--maxmemory-policy noeviction flag"
      pattern: "noeviction"
    - from: "docker-compose.hostinger.prod.yml db-migrate"
      to: "postgres"
      via: "condition: service_healthy"
      pattern: "service_healthy"
    - from: "health-monitor.yml"
      to: "ALERT_WEBHOOK_URL"
      via: "curl POST when disk > 85%"
      pattern: "ALERT_WEBHOOK_URL"
---

<objective>
Apply three targeted reliability fixes to prevent silent data corruption and service outages.

Purpose: These are low-risk, high-impact changes that close documented gaps:
1. Redis `allkeys-lru` eviction policy can silently drop Bull queue jobs when Redis hits 256 MB. For a job queue, `noeviction` is the correct policy — it causes Redis to return an error rather than silently drop data.
2. `db-migrate` init container depends on postgres with `condition: service_started`, meaning it can attempt to run migrations before Postgres is ready to accept connections. This causes intermittent cold-boot failures.
3. The VPS 119 GB disk is a documented risk: ENOSPC corrupts files to 0 bytes (observed in session 2026-03-14). No alert fires before the disk fills up. Adding a disk usage check to `health-monitor.yml` gives advance warning at 85%.

Output:
- `infra/redis/entrypoint.sh` with `--maxmemory-policy noeviction`
- `docker-compose.hostinger.prod.yml` `db-migrate` service fixed to `condition: service_healthy`
- `health-monitor.yml` with disk pressure SSH check + alert
- `PATCHLOG.md` and `TEST_REPORT.md` updated
</objective>

<execution_context>
@C:/Users/mon pc/Desktop/ralphé_final_patch/.claude/get-shit-done/workflows/execute-plan.md
@C:/Users/mon pc/Desktop/ralphé_final_patch/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@C:/Users/mon pc/Desktop/ralphé_final_patch/.planning/scopes/general/ROADMAP.md
@C:/Users/mon pc/Desktop/ralphé_final_patch/.planning/scopes/general/codebase/ARCHITECTURE.md
@C:/Users/mon pc/Desktop/ralphé_final_patch/.planning/scopes/general/codebase/CONCERNS.md

<!-- Key files to read before editing -->
@C:/Users/mon pc/Desktop/ralphé_final_patch/project/infra/redis/entrypoint.sh
@C:/Users/mon pc/Desktop/ralphé_final_patch/project/docker-compose.hostinger.prod.yml
@C:/Users/mon pc/Desktop/ralphé_final_patch/project/.github/workflows/health-monitor.yml
@C:/Users/mon pc/Desktop/ralphé_final_patch/project/PATCHLOG.md
@C:/Users/mon pc/Desktop/ralphé_final_patch/project/TEST_REPORT.md

<interfaces>
<!-- Current Redis entrypoint (project/infra/redis/entrypoint.sh) -->
Current line 7:
  ARGS="--appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru"

Target line 7 (only change — keep everything else identical):
  ARGS="--appendonly yes --maxmemory 256mb --maxmemory-policy noeviction"

Rationale: Bull queue jobs must never be silently dropped. With noeviction, Redis will
return OOM errors to n8n-main instead of evicting queue data. n8n handles this gracefully
by retrying queue operations.

<!-- Current db-migrate dependency in docker-compose.hostinger.prod.yml -->
Current (CONCERNS.md line 9 — service_started):
  db-migrate:
    depends_on:
      postgres:
        condition: service_started   # <-- BUG: should be service_healthy

Target:
  db-migrate:
    depends_on:
      postgres:
        condition: service_healthy   # <-- matches n8n-main and cms pattern

Cross-reference: n8n-main and cms both use service_healthy for their postgres dependency.
db-migrate is the only service that used service_started. This is a one-word change.

<!-- health-monitor.yml existing structure -->
Existing check: GET https://api.<domain>/healthz (HTTP 200 = healthy)
SSH fallback step already exists (checks docker ps, postgres, disk, memory) when unhealthy.
We add a NEW parallel SSH step that checks disk proactively, even when HTTP is healthy.

Existing alert mechanism:
  curl -s -X POST "$ALERT_WEBHOOK_URL" -H "Content-Type: application/json" \
    -d "{\"text\": \"...\", ...}"

Disk check target threshold: 85% usage on /
Command on VPS:
  df / | awk 'NR==2{sub(/%/,""); if($5 > 85) exit 1; else exit 0}'
</interfaces>
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Fix Redis eviction policy + fix db-migrate postgres dependency</name>
  <files>project/infra/redis/entrypoint.sh, project/docker-compose.hostinger.prod.yml</files>
  <action>
**A. Fix `project/infra/redis/entrypoint.sh`**

Change line 7 only. The current line is:
```
ARGS="--appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru"
```

Change to:
```
ARGS="--appendonly yes --maxmemory 256mb --maxmemory-policy noeviction"
```

Do not change anything else in this file. The script is 15 lines; the rest is correct.

Rationale to include as a comment on the same line or the line above:
`# noeviction: queue jobs must never be silently dropped; returns OOM error instead`

**B. Fix `project/docker-compose.hostinger.prod.yml` — db-migrate service**

Find the `db-migrate` service definition. It currently has:
```yaml
depends_on:
  postgres:
    condition: service_started
```

Change `service_started` to `service_healthy`. This is a single word change.

Do NOT touch any other `depends_on` blocks in the compose file. Other services already
use `service_healthy` correctly; only `db-migrate` has this bug.

After making the change, also read the `postgres` service healthcheck definition to confirm
it has a `healthcheck:` block (it should — this change only works if postgres has a healthcheck).
If the postgres service lacks a healthcheck, add one:
```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U n8n -d n8n"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 30s
```

**VPS apply instructions (document in TEST_REPORT.md):**
These changes take effect only after container restart:
- Redis: `docker compose -f docker-compose.hostinger.prod.yml up -d redis`
  Then verify: `docker exec current-redis-1 redis-cli CONFIG GET maxmemory-policy`
  Expected: `maxmemory-policy` / `noeviction`
- db-migrate: Only runs on cold boot; verify by reading compose file after edit.
  Next time the stack is restarted from scratch, db-migrate will wait for postgres healthcheck.
  </action>
  <verify>
    <automated>
      # Verify noeviction in entrypoint.sh
      grep "noeviction" project/infra/redis/entrypoint.sh && echo "PASS: noeviction set"
      # Confirm allkeys-lru is gone
      grep "allkeys-lru" project/infra/redis/entrypoint.sh && echo "FAIL: allkeys-lru still present" || echo "PASS: allkeys-lru removed"
      # Verify db-migrate uses service_healthy
      grep -A 5 "db-migrate:" project/docker-compose.hostinger.prod.yml | grep "service_healthy" && echo "PASS: db-migrate service_healthy"
      # Verify service_started is not used by db-migrate (other services may use it for non-postgres deps)
      python3 -c "
import yaml
with open('project/docker-compose.hostinger.prod.yml') as f:
    c = yaml.safe_load(f)
svc = c['services'].get('db-migrate', {})
deps = svc.get('depends_on', {})
pg_dep = deps.get('postgres', {})
cond = pg_dep.get('condition', '')
assert cond == 'service_healthy', f'Expected service_healthy, got: {cond}'
print('PASS: db-migrate postgres condition is service_healthy')
"
    </automated>
  </verify>
  <done>
    - `infra/redis/entrypoint.sh` line 7 contains `noeviction` (not `allkeys-lru`)
    - `docker-compose.hostinger.prod.yml` `db-migrate.depends_on.postgres.condition` is `service_healthy`
    - YAML parses without errors
    - Postgres service has a `healthcheck` block (either existing or newly added)
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Add disk pressure alerting to health-monitor.yml + update docs</name>
  <files>project/.github/workflows/health-monitor.yml, project/PATCHLOG.md, project/TEST_REPORT.md</files>
  <action>
**A. Add disk pressure check to `project/.github/workflows/health-monitor.yml`**

Read the full file first to understand existing structure. Then add a new job named `disk-check`
that runs in parallel with the existing health check job (not as a dependency of it).

The `disk-check` job:
```yaml
disk-check:
  name: VPS Disk Pressure Check
  runs-on: ubuntu-latest
  timeout-minutes: 5
  steps:
    - name: Checkout code
      uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2

    - name: Setup SSH
      uses: ./.github/actions/setup-ssh
      with:
        ssh-key: ${{ secrets.VPS_SSH_KEY }}
        vps-host: ${{ env.VPS_HOST }}

    - name: Check disk usage
      id: disk
      run: |
        DISK_PCT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
          ${{ env.VPS_USER }}@${{ env.VPS_HOST }} \
          "df / | awk 'NR==2{sub(/%/,\"\"); print \$5}'")
        echo "usage_pct=${DISK_PCT}" >> $GITHUB_OUTPUT
        echo "Disk usage: ${DISK_PCT}%"
        if [ "${DISK_PCT:-0}" -ge 85 ]; then
          echo "::warning::VPS disk usage is ${DISK_PCT}% — above 85% threshold"
          echo "threshold_exceeded=true" >> $GITHUB_OUTPUT
        else
          echo "threshold_exceeded=false" >> $GITHUB_OUTPUT
        fi

    - name: Alert on disk pressure
      if: steps.disk.outputs.threshold_exceeded == 'true'
      env:
        ALERT_URL: ${{ secrets.ALERT_WEBHOOK_URL }}
        DISCORD_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
        DISK_PCT: ${{ steps.disk.outputs.usage_pct }}
        VPS_HOST: ${{ env.VPS_HOST }}
      run: |
        MSG="ALERT: VPS disk usage is ${DISK_PCT}% (threshold: 85%) on ${VPS_HOST}. Run: docker system prune -f && du -sh /opt/resto/backups/"
        if [ -n "$ALERT_URL" ]; then
          curl -s -X POST "$ALERT_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"${MSG}\"}" || true
        fi
        if [ -n "$DISCORD_URL" ]; then
          curl -s -X POST "$DISCORD_URL" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"${MSG}\"}" || true
        fi
        echo "::error::${MSG}"
        exit 1
```

Place this job definition after the existing health check job in the file.

Use the same `env:` block at the top of the workflow for `VPS_HOST` and `VPS_USER` — do not
duplicate those definitions. If the workflow does not already have a top-level `env:` block
with these, add it (check by reading the file first).

The SSH key check: If `VPS_SSH_KEY` secret is not configured, the SSH step will fail.
Add an `if: secrets.VPS_SSH_KEY != ''` guard or a `continue-on-error: true` ONLY on the
disk-check job level (not on individual steps) — the health monitor should degrade gracefully
if SSH is not configured, not block unrelated alerts.

**B. Update `project/PATCHLOG.md`**

Add a new entry at the top:
```
## 2026-03-20 — Phase 02: Reliability Fixes
- What: (1) Redis maxmemory-policy changed allkeys-lru → noeviction; (2) db-migrate depends_on postgres changed service_started → service_healthy; (3) disk pressure check added to health-monitor.yml (85% threshold)
- Why: (1) Bull queue jobs must not be evicted under memory pressure; (2) intermittent migration failures on cold boot; (3) ENOSPC corrupts files silently — advance warning at 85% prevents total failure
- Risk: Low — (1) redis container recreation required for effect; (2) compose-level change, no container restart needed until next cold boot; (3) additive CI change only
- Rollback: (1) revert entrypoint.sh; (2) revert compose file; (3) revert health-monitor.yml — all independent
```

**C. Update `project/TEST_REPORT.md`**

Add a new entry:
```
## Phase 02 Reliability Fixes — 2026-03-20

### REL-01: Redis eviction policy
- Command: grep "noeviction" infra/redis/entrypoint.sh
- Result: PASS — line 7 contains --maxmemory-policy noeviction
- VPS apply: docker compose up -d redis (requires container recreation)
- VPS verify: docker exec <redis-container> redis-cli CONFIG GET maxmemory-policy
  Expected response: maxmemory-policy / noeviction

### REL-02: db-migrate postgres healthcheck dependency
- Command: grep -A 5 "db-migrate:" docker-compose.hostinger.prod.yml | grep service_healthy
- Result: PASS — condition: service_healthy
- Note: Takes effect on next cold boot or full stack restart

### REL-03: Disk pressure alerting
- Command: grep "disk-check" .github/workflows/health-monitor.yml
- Result: PASS — disk-check job added
- Threshold: 85% disk usage on /
- Alert targets: ALERT_WEBHOOK_URL + DISCORD_WEBHOOK_URL
```
  </action>
  <verify>
    <automated>
      # Validate YAML syntax of health-monitor.yml
      python3 -c "import yaml; yaml.safe_load(open('project/.github/workflows/health-monitor.yml'))" && echo "YAML valid"
      # Confirm disk-check job exists
      grep -n "disk-check" project/.github/workflows/health-monitor.yml
      # Confirm 85 threshold is present
      grep "85" project/.github/workflows/health-monitor.yml
      # Confirm PATCHLOG.md has new entry
      grep "Phase 02" project/PATCHLOG.md
      # Confirm TEST_REPORT.md has new entry
      grep "REL-01" project/TEST_REPORT.md
    </automated>
  </verify>
  <done>
    - `health-monitor.yml` has `disk-check` job that fires alert when disk >= 85%
    - Alert sends to both `ALERT_WEBHOOK_URL` and `DISCORD_WEBHOOK_URL`
    - `disk-check` job fails the workflow run when threshold exceeded (not silent)
    - YAML parses without errors
    - `PATCHLOG.md` has Phase 02 entry at top
    - `TEST_REPORT.md` has REL-01, REL-02, REL-03 entries
  </done>
</task>

</tasks>

<verification>
Phase 02 is complete when:
- `infra/redis/entrypoint.sh` contains `noeviction` (grep confirms)
- `docker-compose.hostinger.prod.yml` `db-migrate.depends_on.postgres.condition` equals `service_healthy`
- `health-monitor.yml` has `disk-check` job with 85% threshold and dual alert targets
- Both YAML files parse without errors
- `PATCHLOG.md` has Phase 02 entry
- `TEST_REPORT.md` has REL-01/02/03 test results

VPS apply (run after commit):
```bash
# On VPS at /opt/resto/current/
# REL-01: Recreate Redis with new eviction policy
docker compose -f docker-compose.hostinger.prod.yml up -d redis
# Verify:
docker exec current-redis-1 redis-cli CONFIG GET maxmemory-policy
# Expected: maxmemory-policy / noeviction

# REL-02: db-migrate fix takes effect on next cold boot (no immediate action needed)
# Confirm edit: grep -A 5 "db-migrate:" docker-compose.hostinger.prod.yml

# REL-03: Health monitor runs on next cron trigger (every 6 hours)
# Manual test: trigger health-monitor.yml from GitHub Actions UI
```
</verification>

<success_criteria>
- Redis queue jobs are protected from eviction: `CONFIG GET maxmemory-policy` returns `noeviction` after container recreation
- Cold-boot migration failures are prevented: `db-migrate` waits for postgres healthcheck, not just container start
- Disk pressure gives 15% warning margin: alert fires at 85% before ENOSPC at 100%
</success_criteria>

<rollback>
All three changes are independently revertable:

**REL-01 (Redis eviction):**
- Revert `infra/redis/entrypoint.sh` line 7 back to `allkeys-lru`
- Recreate Redis container: `docker compose up -d redis`
- No data loss; Redis queue is persisted via AOF

**REL-02 (db-migrate healthcheck):**
- Revert `docker-compose.hostinger.prod.yml` `db-migrate.depends_on.postgres.condition` back to `service_started`
- No immediate container restart needed; change only affects next cold boot

**REL-03 (disk alert):**
- Remove `disk-check` job from `health-monitor.yml`
- No VPS changes; CI-only modification
</rollback>

<output>
After completion, create `.planning/scopes/general/phases/02-SUMMARY.md` following the summary template.
</output>
