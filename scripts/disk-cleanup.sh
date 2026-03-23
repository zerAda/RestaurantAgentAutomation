#!/usr/bin/env bash
# =============================================================================
# disk-cleanup.sh — Proactive disk space reclamation
# =============================================================================
# Safe to run at any time, including from cron.
# Does NOT remove named volumes, running containers, or non-dangling images
# that are currently in use.
#
# Cron schedule (deploy user):
#   0 2 * * * /opt/resto/current/scripts/disk-cleanup.sh >> /var/log/disk-cleanup.log 2>&1
#
# What it reclaims (safe operations only):
#   1. Docker dangling images (untagged, not referenced by any container)
#   2. Docker build cache older than 48h
#   3. Stopped containers (exited/dead, not currently running)
#   4. Unused anonymous volumes (not named, not attached)
#   5. npm cache inside CMS container (if running) — up to ~5GB
#   6. Old log files in /tmp older than 7 days
#
# What it NEVER touches:
#   - Named volumes (postgres_data, n8n_data, redis_data, etc.)
#   - Running containers
#   - Images referenced by running containers
#   - /opt/resto/backups (backup files)
# =============================================================================
set -uo pipefail

ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
DISK_THRESHOLD_PCT="${DISK_THRESHOLD_PCT:-75}"  # Only run if disk > this %

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

send_alert() {
  local msg="$1"
  if [[ -z "$ALERT_WEBHOOK_URL" ]]; then return; fi
  curl -sf -X POST "$ALERT_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"[RestoBot Disk Cleanup] ${msg}\"}" >/dev/null 2>&1 || true
}

log "=== RestoBot Disk Cleanup ==="

DISK_BEFORE_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
DISK_BEFORE_AVAIL=$(df -h / | tail -1 | awk '{print $4}')
log "Disk before: ${DISK_BEFORE_PCT}% used (${DISK_BEFORE_AVAIL} free)"

# Skip if disk usage is below threshold
if [[ $DISK_BEFORE_PCT -lt $DISK_THRESHOLD_PCT ]]; then
  log "Disk at ${DISK_BEFORE_PCT}% — below ${DISK_THRESHOLD_PCT}% threshold, no cleanup needed."
  exit 0
fi

log "Disk above threshold (${DISK_THRESHOLD_PCT}%) — starting cleanup..."

# ---------------------------------------------------------------------------
# 1. Dangling Docker images (untagged layers with no containers)
# ---------------------------------------------------------------------------
log "Step 1: Removing dangling Docker images..."
DANGLING=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
if [[ $DANGLING -gt 0 ]]; then
  docker image prune -f 2>&1 | tail -3
  log "  Removed $DANGLING dangling images"
else
  log "  No dangling images"
fi

# ---------------------------------------------------------------------------
# 2. Docker build cache older than 48h
# ---------------------------------------------------------------------------
log "Step 2: Pruning Docker build cache (older than 48h)..."
docker builder prune -f --filter "until=48h" 2>&1 | tail -3 || log "  (build cache prune not available or empty)"

# ---------------------------------------------------------------------------
# 3. Stopped containers (exited/dead)
# ---------------------------------------------------------------------------
log "Step 3: Removing stopped containers..."
STOPPED=$(docker ps -a -f "status=exited" -f "status=dead" -q 2>/dev/null | wc -l)
if [[ $STOPPED -gt 0 ]]; then
  docker container prune -f 2>&1 | tail -2
  log "  Removed $STOPPED stopped containers"
else
  log "  No stopped containers"
fi

# ---------------------------------------------------------------------------
# 4. Anonymous volumes (not named, not attached to running containers)
# ---------------------------------------------------------------------------
log "Step 4: Removing unused anonymous volumes..."
docker volume prune -f 2>&1 | tail -2 || log "  (volume prune had no effect)"

# ---------------------------------------------------------------------------
# 5. npm cache inside CMS container (large: ~3-5GB post-build)
# ---------------------------------------------------------------------------
log "Step 5: Clearing npm cache inside CMS container..."
CMS_CONTAINER=$(docker ps -qf "name=current-cms-1" 2>/dev/null | head -1)
if [[ -n "$CMS_CONTAINER" ]]; then
  docker exec "$CMS_CONTAINER" npm cache clean --force 2>/dev/null && \
    log "  CMS npm cache cleared" || \
    log "  CMS npm cache clear failed (non-fatal)"
else
  log "  CMS container not running — skipping npm cache"
fi

# ---------------------------------------------------------------------------
# 6. /tmp files older than 7 days
# ---------------------------------------------------------------------------
log "Step 6: Clearing /tmp files older than 7 days..."
find /tmp -maxdepth 2 -type f -mtime +7 -delete 2>/dev/null || true
log "  /tmp cleaned"

# ---------------------------------------------------------------------------
# Report results
# ---------------------------------------------------------------------------
DISK_AFTER_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
DISK_AFTER_AVAIL=$(df -h / | tail -1 | awk '{print $4}')
RECLAIMED=$((DISK_BEFORE_PCT - DISK_AFTER_PCT))

log "Disk after: ${DISK_AFTER_PCT}% used (${DISK_AFTER_AVAIL} free)"
log "Reclaimed: ~${RECLAIMED}% disk space"

if [[ $DISK_AFTER_PCT -ge 90 ]]; then
  msg="Disk still at ${DISK_AFTER_PCT}% after cleanup. Manual intervention required. Consider: docker system prune -a (WARNING: removes all unused images)."
  log "CRITICAL: $msg"
  send_alert "CRITICAL: $msg"
  exit 1
elif [[ $DISK_AFTER_PCT -ge 80 ]]; then
  msg="Disk at ${DISK_AFTER_PCT}% after cleanup (was ${DISK_BEFORE_PCT}%). Monitor closely."
  log "WARNING: $msg"
  send_alert "WARNING: $msg"
else
  log "Cleanup complete. Disk healthy at ${DISK_AFTER_PCT}%."
fi
