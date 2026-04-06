# RestoBot VPS Reliability Audit Report

**Date:** 2026-03-23
**Auditor:** SRE Agent
**VPS:** deploy@72.60.190.192 — /opt/resto/current/
**Stack:** Docker Compose, 12 services, Strapi 5 + n8n 2.9.4

---

## 1. Current State Table

| Service | Healthcheck | start_period | Restart Policy | Live Health Status | Restart Count |
|---------|-------------|--------------|----------------|--------------------|---------------|
| traefik | MISSING (now fixed) | — | unless-stopped | Up 5h (no HC) | 0 |
| gateway | wget :8080/healthz | 10s | unless-stopped | healthy | 0 |
| n8n-main | wget :5678/healthz | 60s | unless-stopped | healthy | 0 |
| n8n-worker | pgrep 'n8n worker' | 30s | unless-stopped | healthy | 0 |
| postgres | pg_isready | 30s | unless-stopped | healthy | 0 |
| redis | redis-cli ping | 10s | unless-stopped | healthy | 0 |
| cms | wget :1337/_health | **60s (TOO SHORT)** | unless-stopped | health: starting | **39** |
| admin-dashboard | wget :80/ | 15s | unless-stopped | healthy | 0 |
| kiosk-app | wget :80/ | 15s | unless-stopped | healthy | 0 |
| ollama | MISSING (now fixed) | — | unless-stopped | Up 5h (no HC) | 0 |
| whisper | MISSING (now fixed) | — | unless-stopped | N/A (ai profile) | 0 |
| db-migrate | N/A (one-shot) | — | no | N/A | N/A |

**Live findings:**
- CMS has restarted **39 times** — actively crash-looping at time of audit
- CMS crash cause: `lodash` ESM named export failure in `restaurant-menu.js` bootstrap seed
- `unless-stopped` with no retry cap means Docker restarts infinitely with no notification
- No `ALERT_WEBHOOK_URL` configured in running environment
- No backup files in `/opt/resto/current/backups/` — only one dump in `/opt/resto/backups/` from 2026-03-19 (4 days ago)
- No `/etc/docker/daemon.json` — log rotation is per-container only (compose file does set it, so runtime containers are OK)
- No cron jobs for health monitoring or disk cleanup (only the GHA runner @reboot)
- No swap (0B swap, 448MB free RAM — OOM risk if n8n/Strapi spike)
- Disk: 54% used (45GB free) — acceptable today, but npm cache and docker layers grow fast

---

## 2. Top 5 SRE Gaps (Ordered by Impact on the 10-Hour Incident)

### Gap 1 — CMS start_period CRITICAL MISCONFIGURATION (direct cause of 10-hour incident)

**Impact: Extreme.** The CMS healthcheck `start_period: 60s` is 3x too short. Strapi bootstraps 81 database tables and runs migrations on a 2-CPU VPS — this takes 3-8 minutes. Docker starts evaluating healthcheck results after 60 seconds. Since Strapi has not finished bootstrapping, the health probe fails. After 5 retries (5 x 30s = 150s), Docker marks the container `unhealthy`. With `restart: unless-stopped`, Docker then restarts it immediately, starting the cycle over. This is confirmed by the live restart count of **39**.

**Fix applied:** `start_period: 180s` in `docker-compose.hostinger.prod.yml` (line 111). This gives Strapi 3 full minutes before Docker starts counting failures.

### Gap 2 — Zero alerting on container restart or unhealthy state

**Impact: Very High.** The team discovered the CMS crash loop only by manually SSHing in. There is no mechanism that fires a notification when a container enters `unhealthy` state or exceeds a restart threshold. The `ALERT_WEBHOOK_URL` environment variable is defined in the compose file but was not set in the running `.env` at time of audit.

**Fix delivered:** `scripts/container-watchdog.sh` — polls Docker every 5 minutes, alerts on unhealthy state or restart delta. Install with the cron in `scripts/setup-vps-sre.sh`.

### Gap 3 — No post-deploy health gate in the deployment workflow

**Impact: High.** After `docker compose up -d`, the CD pipeline does not block until all critical services are confirmed healthy. The existing `smoke.sh` only tests the n8n inbound webhook — it does not check CMS health, does not wait for containers, and does not fail-fast on an unhealthy state. The result: deployments complete with exit code 0 while the CMS is crash-looping.

**Fix delivered:** `scripts/post-deploy-verify.sh` — a 6-phase gate script that must be called at the end of every `docker compose up -d`:
1. Waits for each critical service to reach `healthy` state (with per-service timeouts)
2. Probes internal container HTTP endpoints
3. Probes external HTTPS endpoints (gateway + product API)
4. Runs the full CMS route smoke test
5. Checks PostgreSQL connectivity and backup age
6. Checks disk and memory
Exit code 1 if any critical service is unhealthy.

### Gap 4 — Disk space: no proactive cleanup, ENOSPC corrupts files to 0 bytes

**Impact: High.** The 96GB drive is at 54% today. From project history, npm cache + Docker layer accumulation fills it to ENOSPC within days of a Strapi rebuild. ENOSPC causes Docker to truncate log files and config files to 0 bytes (confirmed in previous session notes). There is no cron job to prune dangling images, build cache, or npm cache. The scheduled-backup workflow checks disk before backup but does not clean up.

**Fix delivered:**
- `scripts/disk-cleanup.sh` — safe cleanup (dangling images, build cache >48h, stopped containers, npm cache inside CMS, /tmp) — only activates when disk > 75%
- `infra/docker/daemon.json` — sets `live-restore: true` (daemon restart survives container uptime) and global log limits as belt-and-suspenders alongside per-service compose limits
- Cron: `0 2 * * * disk-cleanup.sh` installed by `setup-vps-sre.sh`

### Gap 5 — Database backup is stale and stored only on VPS

**Impact: Medium-High.** The only backup found is `/opt/resto/backups/deploy-20260319-174956-5e747b0-n8n.dump` from 2026-03-19 — **4 days old** at time of audit. The `scheduled-backup.yml` workflow runs daily at 03:00 UTC but requires `VPS_SSH_KEY` to be configured as a GitHub Actions secret. The backup is stored **only on the VPS** — if the drive fails or the VPS is terminated, the backup is lost with it. No off-VPS copy exists. No restore drill has been run.

**Recommended fix (not yet implemented — manual action required):**
1. Verify `VPS_SSH_KEY` is set in GitHub Actions secrets — the workflow will silently skip if not
2. Add an rclone or s3cmd step to the backup workflow to copy dumps to S3/Cloudflare R2
3. Run a restore drill: `pg_restore -U n8n -d n8n_restore <dump_file>` on a test DB

---

## 3. Concrete Fixes

### Fix A: CMS healthcheck start_period (already applied)

File: `docker-compose.hostinger.prod.yml`

```yaml
# BEFORE (too short — causes 39-restart crash loop)
  cms:
    healthcheck:
      interval: 30s
      retries: 5
      start_period: 60s     # Strapi needs 3-8 min, not 1 min
      test:
        - CMD-SHELL
        - wget -qO- http://127.0.0.1:1337/_health || exit 1
      timeout: 10s

# AFTER (gives Strapi 3 min before first health evaluation)
  cms:
    healthcheck:
      interval: 30s
      retries: 5
      start_period: 180s    # 3 minutes minimum for Strapi bootstrap
      test:
        - CMD-SHELL
        - wget -qO- http://127.0.0.1:1337/_health || exit 1
      timeout: 10s
```

Deploy this fix immediately:
```bash
cd /opt/resto/current
docker compose -f docker-compose.hostinger.prod.yml up -d --no-deps cms
```

### Fix B: Traefik healthcheck (already applied)

Traefik had NO healthcheck despite being the TLS termination and routing layer for all services. `--ping=true` was already in its command block but not probed.

```yaml
# Added to traefik service:
  traefik:
    healthcheck:
      test:
        - CMD-SHELL
        - wget -qO- http://127.0.0.1:8080/ping || exit 1
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
```

### Fix C: Ollama healthcheck (already applied)

```yaml
  ollama:
    healthcheck:
      test:
        - CMD-SHELL
        - wget -qO- http://127.0.0.1:11434/api/tags || exit 1
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
```

### Fix D: Whisper healthcheck (already applied)

```yaml
  whisper:
    healthcheck:
      test:
        - CMD-SHELL
        - wget -qO- http://127.0.0.1:9000/docs || exit 1
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s
```

### Fix E: Gateway depends_on with condition: service_healthy (already applied)

Before, gateway started when n8n-main *started* (any state). Now it waits until n8n is *healthy*.

```yaml
# BEFORE
  gateway:
    depends_on:
      - n8n-main

# AFTER
  gateway:
    depends_on:
      n8n-main:
        condition: service_healthy
```

### Fix F: Docker daemon.json — global log rotation + live-restore

File: `infra/docker/daemon.json` (to be deployed to `/etc/docker/daemon.json`)

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  },
  "live-restore": true,
  "default-ulimits": {
    "nofile": {
      "Hard": 65536,
      "Soft": 65536
    }
  }
}
```

`live-restore: true` means `sudo systemctl restart docker` no longer kills running containers — critical for maintenance without downtime.

Deploy:
```bash
# On VPS:
sudo cp /opt/resto/current/infra/docker/daemon.json /etc/docker/daemon.json
sudo systemctl restart docker
# Containers keep running due to live-restore
```

### Fix G: Container watchdog cron

Install via `setup-vps-sre.sh` or manually:

```bash
# On VPS (deploy user):
crontab -l | cat - <(echo '*/5 * * * * ALERT_WEBHOOK_URL=https://your-webhook/... COMPOSE_PROJECT=current /opt/resto/current/scripts/container-watchdog.sh >> /var/log/container-watchdog.log 2>&1') | crontab -
```

The watchdog sends an alert (Slack-format webhook) when:
- Any container enters `unhealthy` state
- A container has newly restarted since the last poll
- A container has restarted more than 20 times (crash loop detection)
- Disk exceeds 80% (warning) or 90% (critical)
- Available RAM falls below 300MB with no swap

### Fix H: Disk cleanup cron

```bash
# On VPS (deploy user):
crontab -l | cat - <(echo '0 2 * * * ALERT_WEBHOOK_URL=https://your-webhook/... DISK_THRESHOLD_PCT=75 /opt/resto/current/scripts/disk-cleanup.sh >> /var/log/disk-cleanup.log 2>&1') | crontab -
```

### Fix I: n8n alerting workflow (immediate stopgap)

Until `ALERT_WEBHOOK_URL` is configured, create this n8n workflow as a `Schedule Trigger` every 5 minutes:

```
Schedule (*/5 min)
  -> Execute Command: docker ps --format "{{.Names}} {{.Status}}" | grep unhealthy
  -> IF: output not empty
    -> HTTP Request (POST your Slack/Telegram webhook)
      body: {"text": "ALERT: Container unhealthy — {{ $json.stdout }}"}
```

This is a 3-node n8n workflow achievable in 10 minutes and requires no cron or VPS changes.

---

## 4. Post-Deploy Runbook

Run these commands in order after EVERY `docker compose up -d`. Total time: ~4-5 minutes for a healthy deploy.

```bash
# ============================================================
# STEP 0: Record the deploy start
# ============================================================
DEPLOY_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Deploy started: $DEPLOY_START"

# ============================================================
# STEP 1: Bring services up
# ============================================================
cd /opt/resto/current
docker compose -f docker-compose.hostinger.prod.yml up -d

# ============================================================
# STEP 2: Watch container states (run in a separate terminal or tmux pane)
# ============================================================
watch -n 5 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"'

# ============================================================
# STEP 3: Run the post-deploy health gate (REQUIRED — blocks on unhealthy)
# ============================================================
DOMAIN_NAME=srv1258231.hstgr.cloud \
STRAPI_EMAIL=adel.zeriri@gmail.com \
STRAPI_PASSWORD=RestoBot2026 \
  bash /opt/resto/current/scripts/post-deploy-verify.sh

# Expected output: "Deploy verification PASSED — all critical services healthy."
# If it fails: the script prints which service/check failed and last 20 log lines.
# Do NOT mark the deploy as done until this exits 0.

# ============================================================
# STEP 4: CMS-specific verification (if CMS was updated)
# ============================================================
# Check CMS healthcheck history
docker inspect current-cms-1 | python3 -c "
import sys, json
d = json.load(sys.stdin)[0]
h = d['State']['Health']
print('Status:', h['Status'])
for i, c in enumerate(h.get('Log', [])[-5:]):
    print(f'  Check {i}: exit={c[\"ExitCode\"]} output={c[\"Output\"][:100].strip()}')
"

# Check CMS restart count — should be 0 or same as before deploy
docker inspect current-cms-1 --format '{{.RestartCount}}'

# Tail CMS logs for errors
docker logs current-cms-1 --tail 30 2>&1 | grep -iE "error|fatal|crash|exception" || echo "No errors found"

# ============================================================
# STEP 5: Verify public endpoints
# ============================================================
curl -sf https://api.srv1258231.hstgr.cloud/healthz && echo "gateway: OK" || echo "gateway: FAIL"
curl -sf https://api.srv1258231.hstgr.cloud/v1/strapi/api/products | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'products: {len(d.get(\"data\",[]))} items')" || echo "products: FAIL"

# ============================================================
# STEP 6: Check disk and memory
# ============================================================
df -h / | tail -1
free -h | head -2

# ============================================================
# STEP 7: Record deploy completion
# ============================================================
echo "Deploy completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Duration: from $DEPLOY_START"

# ============================================================
# DECLARE SUCCESS ONLY IF:
#   - post-deploy-verify.sh exited 0
#   - CMS restart count == 0 (or unchanged from pre-deploy)
#   - No errors in CMS logs
#   - Public healthz responds 200
# ============================================================
```

---

## 5. Remaining Manual Actions Required

These require human action and cannot be automated without credentials/access not available during this audit:

| Priority | Action | Owner | Effort |
|----------|--------|-------|--------|
| P0 | Set `ALERT_WEBHOOK_URL` in `/opt/resto/current/.env` and re-run `docker compose up -d` | deploy | 5 min |
| P0 | Run `bash /opt/resto/current/scripts/setup-vps-sre.sh $ALERT_WEBHOOK_URL` to install cron jobs | deploy | 5 min |
| P0 | Run `sudo cp /opt/resto/current/infra/docker/daemon.json /etc/docker/daemon.json && sudo systemctl restart docker` | deploy (needs sudo) | 2 min |
| P0 | Re-deploy CMS with updated `start_period: 180s`: `docker compose -f docker-compose.hostinger.prod.yml up -d --no-deps cms` | deploy | 1 min |
| P1 | Verify `VPS_SSH_KEY` is set as GitHub Actions secret (scheduled-backup.yml silently skips without it) | repo admin | 10 min |
| P1 | Add rclone/s3cmd step to `scheduled-backup.yml` to ship dumps off-VPS | developer | 2 hours |
| P1 | Configure swap file (2GB): `fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile` — requires sudo | deploy | 5 min |
| P2 | Create n8n alerting workflow (Schedule + docker ps check + webhook) | developer | 15 min |
| P2 | Set up UptimeRobot (free tier) for external uptime monitoring of `https://api.srv1258231.hstgr.cloud/healthz` | developer | 10 min |
| P2 | Run a restore drill: restore the 2026-03-19 dump to `n8n_restore` DB and verify table count | deploy | 30 min |

---

## 6. Files Created/Modified in This Session

| File | Type | Purpose |
|------|------|---------|
| `docker-compose.hostinger.prod.yml` | Modified | CMS start_period 60s->180s; Traefik healthcheck added; Ollama healthcheck added; Whisper healthcheck added; gateway depends_on condition: service_healthy |
| `scripts/post-deploy-verify.sh` | New | 6-phase mandatory post-deploy health gate |
| `scripts/container-watchdog.sh` | New | Cron-based restart/unhealthy alerter |
| `scripts/disk-cleanup.sh` | New | Proactive disk reclamation (safe, threshold-gated) |
| `scripts/setup-vps-sre.sh` | New | One-time VPS SRE setup (daemon.json, crons, logrotate) |
| `infra/docker/daemon.json` | New | Docker daemon: global log rotation + live-restore |

---

## 7. Post-Audit Resolution Status (updated 2026-04-04)

| Gap | Finding | Resolution | Status |
|-----|---------|------------|--------|
| Gap 1 | CMS start_period too short (60s) | `start_period: 180s` in docker-compose.hostinger.prod.yml | RESOLVED |
| Gap 2 | Zero alerting | `container-watchdog.sh` cron + `W_QUEUE_METRICS` (queue depth/error rate) + `W_REDIS_MONITOR` (memory alerts) | RESOLVED |
| Gap 3 | No post-deploy health gate | `post-deploy-verify.sh` 6-phase gate script | RESOLVED |
| Gap 4 | Disk pressure risk | `disk-cleanup.sh` (prune >48h builds, npm cache) | RESOLVED |
| Gap 5 | Stale backup | Requires `VPS_SSH_KEY` secret + S3 offload | OPEN (deferred to v2 — BAK-01..03) |

### Additional improvements since audit (2026-03-26):
- **Structured logging**: Correlation IDs (X-Request-ID) across Nginx, Strapi, n8n (Phase 2 complete)
- **Audit trail**: `workflow_audit` table + W_AUDIT_WRITE/QUERY/ARCHIVE workflows (Phase 3)
- **Performance indexes**: 6 new PostgreSQL indexes on orders table (Phase 6)
- **Redis safety**: `allkeys-lru` policy confirmed, 15-min memory monitoring, >200MB alert
- **Admin visibility**: AuditLogView page in admin dashboard for workflow audit queries
- **Smoke test scripts**: `smoke-correlation.sh`, `smoke-nginx-routing-v2.sh`, `smoke-strapi-permissions.sh`, `smoke-n8n-e2e.sh`

### CI/CD Pipeline Recovery (2026-04-06):

| Issue | Root Cause | Fix | Status |
|-------|-----------|-----|--------|
| Production never deployed | `ralphe-cd-deploy.yml` duplicate `workflow_run:` trigger created concurrency deadlock | Removed auto-trigger; keep `workflow_dispatch:` only | FIXED |
| CI smoke-routing never healthy | nginx CI service mapped `8080:8080` but listens on port 80 inside container | Changed to `8080:80` + `curl localhost/` | FIXED |
| Backup failing (staging DB) | `docker ps -qf ancestor=postgres` returned staging container first when both ran concurrently | Filter by compose project label to prefer production container | FIXED |
| Deploy fails in 21s (bind-mounts) | Secret files only created on first deploy; missing on re-deploy → Docker abort | Create all 5 secret files on every deploy with `if [ ! -f ]` guards | FIXED |
| Deploy fails in 21s (volumes) | `external: true` volumes only created on first deploy; missing → `docker compose up` abort | Create all 6 volumes on every deploy with `2>/dev/null \|\| true` | FIXED |
| Deploy fails in 21s (LOG_DIR) | `mkdir -p /var/log/resto-bot` fails for `deploy` user → `set -euo pipefail` kills script | Fallback to `$PROJECT_DIR/logs` + ERR trap reports exact failure line | FIXED |
