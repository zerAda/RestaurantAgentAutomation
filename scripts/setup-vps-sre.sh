#!/usr/bin/env bash
# =============================================================================
# setup-vps-sre.sh — One-time VPS SRE hardening setup
# =============================================================================
# Run once on the VPS as a user with sudo access (deploy user with NOPASSWD sudo).
# Installs: daemon.json, cron jobs, logrotate config.
#
# Usage:
#   bash /opt/resto/current/scripts/setup-vps-sre.sh [ALERT_WEBHOOK_URL]
# =============================================================================
set -euo pipefail

ALERT_WEBHOOK_URL="${1:-${ALERT_WEBHOOK_URL:-}}"
PROJECT_DIR="${PROJECT_DIR:-/opt/resto/current}"
SCRIPTS_DIR="${PROJECT_DIR}/scripts"

log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }
ok()  { echo "[OK] $*"; }
err() { echo "[ERR] $*" >&2; }

log "=== VPS SRE Setup ==="

# ---------------------------------------------------------------------------
# 1. Docker daemon.json — global log rotation + live-restore
# ---------------------------------------------------------------------------
log "1. Installing /etc/docker/daemon.json..."
if [[ -f /etc/docker/daemon.json ]]; then
  sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%s)
  log "   Backed up existing daemon.json"
fi

sudo cp "${PROJECT_DIR}/infra/docker/daemon.json" /etc/docker/daemon.json
sudo chmod 644 /etc/docker/daemon.json
ok "daemon.json installed (log rotation: 10m x 5 files, live-restore: true)"

# NOTE: daemon.json changes only affect NEW containers.
# To apply to running containers: docker restart <container>
# live-restore=true means Docker daemon restarts don't kill containers.

# ---------------------------------------------------------------------------
# 2. Cron jobs for deploy user
# ---------------------------------------------------------------------------
log "2. Installing cron jobs..."

# Build crontab content
CRON_CONTENT="@reboot tmux new-session -d -s gha-runner \"cd ~/actions-runner && ./run.sh 2>&1 | tee /tmp/runner.log\""

# Container watchdog: every 5 minutes
CRON_CONTENT="${CRON_CONTENT}
# RestoBot: Container health watchdog (every 5 min)
*/5 * * * * ALERT_WEBHOOK_URL=${ALERT_WEBHOOK_URL} COMPOSE_PROJECT=current ${SCRIPTS_DIR}/container-watchdog.sh >> /var/log/container-watchdog.log 2>&1"

# Disk cleanup: daily at 2am (only reclaims if > 75% full)
CRON_CONTENT="${CRON_CONTENT}
# RestoBot: Disk cleanup (daily 2am, only if > 75% full)
0 2 * * * ALERT_WEBHOOK_URL=${ALERT_WEBHOOK_URL} DISK_THRESHOLD_PCT=75 ${SCRIPTS_DIR}/disk-cleanup.sh >> /var/log/disk-cleanup.log 2>&1"

echo "$CRON_CONTENT" | crontab -
ok "Cron jobs installed: watchdog (*/5min), disk-cleanup (daily 2am)"

# ---------------------------------------------------------------------------
# 3. logrotate for watchdog and cleanup logs
# ---------------------------------------------------------------------------
log "3. Configuring logrotate for watchdog/cleanup logs..."
sudo tee /etc/logrotate.d/resto-sre > /dev/null << 'LOGROTATE'
/var/log/container-watchdog.log
/var/log/disk-cleanup.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 deploy deploy
}
LOGROTATE
ok "logrotate configured for /var/log/container-watchdog.log and /var/log/disk-cleanup.log"

# ---------------------------------------------------------------------------
# 4. logrotate for Docker container logs (belt-and-suspenders)
# ---------------------------------------------------------------------------
log "4. Configuring logrotate for Docker container log files..."
sudo tee /etc/logrotate.d/docker-containers > /dev/null << 'LOGROTATE'
/var/lib/docker/containers/*/*.log {
    daily
    rotate 5
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        /usr/bin/docker kill --signal=SIGHUP $(docker ps -q) 2>/dev/null || true
    endscript
}
LOGROTATE
ok "logrotate configured for Docker container JSON logs"

# ---------------------------------------------------------------------------
# 5. Create log files with correct permissions
# ---------------------------------------------------------------------------
log "5. Creating log files..."
for logfile in /var/log/container-watchdog.log /var/log/disk-cleanup.log; do
  if [[ ! -f "$logfile" ]]; then
    sudo touch "$logfile"
    sudo chown deploy:deploy "$logfile"
    sudo chmod 640 "$logfile"
    ok "Created $logfile"
  fi
done

# ---------------------------------------------------------------------------
# 6. Make scripts executable
# ---------------------------------------------------------------------------
log "6. Setting script permissions..."
chmod +x "${SCRIPTS_DIR}/container-watchdog.sh"
chmod +x "${SCRIPTS_DIR}/disk-cleanup.sh"
chmod +x "${SCRIPTS_DIR}/post-deploy-verify.sh"
ok "Scripts executable"

# ---------------------------------------------------------------------------
# 7. Test alert webhook (if provided)
# ---------------------------------------------------------------------------
if [[ -n "$ALERT_WEBHOOK_URL" ]]; then
  log "7. Testing alert webhook..."
  if curl -sf -X POST "$ALERT_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"text":"[RestoBot SRE] Watchdog and alerting setup complete. This is a test notification."}' \
    > /dev/null 2>&1; then
    ok "Alert webhook reachable"
  else
    err "Alert webhook test FAILED — check ALERT_WEBHOOK_URL"
  fi
else
  log "7. No ALERT_WEBHOOK_URL provided — skipping webhook test"
  echo "   Set ALERT_WEBHOOK_URL in /opt/resto/current/.env to enable alerts"
fi

echo ""
log "=== SRE Setup Complete ==="
log "Summary:"
log "  - Docker daemon.json: /etc/docker/daemon.json (requires daemon restart for new containers)"
log "  - Watchdog cron: */5 * * * * container-watchdog.sh"
log "  - Cleanup cron: 0 2 * * * disk-cleanup.sh"
log "  - Logs: /var/log/container-watchdog.log, /var/log/disk-cleanup.log"
echo ""
log "IMPORTANT: Restart Docker daemon to apply daemon.json (live-restore=true means no container downtime):"
log "  sudo systemctl restart docker"
