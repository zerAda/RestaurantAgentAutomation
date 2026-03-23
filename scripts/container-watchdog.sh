#!/usr/bin/env bash
# =============================================================================
# container-watchdog.sh — Restart-event alerter and health watcher
# =============================================================================
# Polls Docker for containers that are unhealthy or have restarted recently.
# Sends an alert webhook if a container has restarted more than RESTART_THRESHOLD
# times in the last WINDOW_MINUTES, or if its Docker healthcheck is "unhealthy".
#
# Deploy as a cron job (runs every 5 minutes):
#   */5 * * * * /opt/resto/current/scripts/container-watchdog.sh >> /var/log/container-watchdog.log 2>&1
#
# Required env vars (or set inline below):
#   ALERT_WEBHOOK_URL — Slack-compatible webhook or n8n webhook URL
#   COMPOSE_PROJECT   — Docker Compose project prefix (default: "current")
# =============================================================================
set -uo pipefail

COMPOSE_PROJECT="${COMPOSE_PROJECT:-current}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
RESTART_THRESHOLD="${RESTART_THRESHOLD:-5}"    # alert if restarts > N
DISK_WARN_PCT="${DISK_WARN_PCT:-80}"           # alert if disk > N%
DISK_CRIT_PCT="${DISK_CRIT_PCT:-90}"           # critical threshold
STATE_DIR="${STATE_DIR:-/tmp/watchdog-state}"  # tracks previous restart counts
HOSTNAME="${HOSTNAME:-$(hostname)}"

mkdir -p "$STATE_DIR"

ALERTS=()

# ---------------------------------------------------------------------------
# Helper: send a webhook notification
# ---------------------------------------------------------------------------
send_alert() {
  local level="$1"   # WARNING or CRITICAL
  local message="$2"
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  echo "[${timestamp}] [${level}] ${message}"

  if [[ -z "$ALERT_WEBHOOK_URL" ]]; then
    echo "[${timestamp}] ALERT_WEBHOOK_URL not set — alert not sent"
    return
  fi

  local color="warning"
  [[ "$level" == "CRITICAL" ]] && color="danger"

  curl -sf -X POST "$ALERT_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"text\": \"[${level}] RestoBot VPS Alert — ${HOSTNAME}\",
      \"attachments\": [{
        \"color\": \"${color}\",
        \"text\": \"${message}\",
        \"fields\": [
          {\"title\": \"Host\", \"value\": \"${HOSTNAME}\", \"short\": true},
          {\"title\": \"Time\", \"value\": \"${timestamp}\", \"short\": true}
        ]
      }]
    }" >/dev/null 2>&1 || echo "[${timestamp}] Webhook delivery failed"
}

# ---------------------------------------------------------------------------
# Check 1: Container health states and restart counts
# ---------------------------------------------------------------------------
echo "[$(date -u +%H:%M:%SZ)] Checking container states..."

# Get all containers matching this compose project
while IFS= read -r line; do
  # docker ps output: NAME STATUS RESTARTS
  container=$(echo "$line" | awk '{print $1}')
  status=$(echo "$line" | awk '{print $2}')
  restarts=$(echo "$line" | awk '{print $3}')

  [[ -z "$container" ]] && continue
  # Only care about our compose project containers
  [[ "$container" != ${COMPOSE_PROJECT}-* ]] && continue

  service="${container#${COMPOSE_PROJECT}-}"
  service="${service%-1}"  # strip trailing -1 (compose default replica suffix)

  # State file to detect NEW restarts (delta since last check)
  state_file="${STATE_DIR}/${container}.restarts"
  prev_restarts=0
  if [[ -f "$state_file" ]]; then
    prev_restarts=$(cat "$state_file" 2>/dev/null || echo 0)
  fi
  echo "$restarts" > "$state_file"

  delta=$(( restarts - prev_restarts ))

  # Alert on health = unhealthy
  if echo "$status" | grep -q "unhealthy"; then
    ALERTS+=("CRITICAL: Container ${container} is UNHEALTHY. Restart count: ${restarts}. Run: docker logs ${container} --tail 50")
  fi

  # Alert on new restarts since last poll
  if [[ $delta -gt 0 && $restarts -gt $RESTART_THRESHOLD ]]; then
    ALERTS+=("WARNING: Container ${container} restarted ${delta}x since last check (total: ${restarts}). Possible crash loop.")
  fi

  # Alert if restart count is very high (first time we notice it)
  if [[ $restarts -gt 20 && $prev_restarts -le 20 ]]; then
    ALERTS+=("CRITICAL: Container ${container} has restarted ${restarts} times total — likely crash-looping. Check logs immediately.")
  fi

done < <(docker ps --format "{{.Names}} {{.Status}} {{.Names}}" \
  | while read -r name status _; do
      restarts=$(docker inspect "$name" --format '{{.RestartCount}}' 2>/dev/null || echo 0)
      printf "%s %s %s\n" "$name" "$status" "$restarts"
    done)

# ---------------------------------------------------------------------------
# Check 2: Disk space
# ---------------------------------------------------------------------------
DISK_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
DISK_AVAIL=$(df -h / | tail -1 | awk '{print $4}')

if [[ $DISK_PCT -ge $DISK_CRIT_PCT ]]; then
  ALERTS+=("CRITICAL: Disk usage at ${DISK_PCT}% (${DISK_AVAIL} free). ENOSPC imminent. Run: docker system prune -f && npm cache clean --force in containers")
elif [[ $DISK_PCT -ge $DISK_WARN_PCT ]]; then
  ALERTS+=("WARNING: Disk usage at ${DISK_PCT}% (${DISK_AVAIL} free). Consider cleanup before it causes ENOSPC file corruption.")
fi

# ---------------------------------------------------------------------------
# Check 3: Swap usage (0B swap means OOM risk on this VPS)
# ---------------------------------------------------------------------------
SWAP_TOTAL=$(free -m | awk '/^Swap:/ {print $2}')
if [[ "$SWAP_TOTAL" == "0" ]]; then
  MEM_AVAIL=$(free -m | awk '/^Mem:/ {print $7}')
  if [[ $MEM_AVAIL -lt 300 ]]; then
    ALERTS+=("WARNING: No swap configured and only ${MEM_AVAIL}MB RAM available. OOM kill risk.")
  fi
fi

# ---------------------------------------------------------------------------
# Deliver all alerts (single webhook call if batched)
# ---------------------------------------------------------------------------
if [[ ${#ALERTS[@]} -gt 0 ]]; then
  for alert in "${ALERTS[@]}"; do
    level=$(echo "$alert" | cut -d: -f1)
    msg=$(echo "$alert" | cut -d: -f2-)
    send_alert "$level" "$msg"
  done
else
  echo "[$(date -u +%H:%M:%SZ)] All containers OK. Disk: ${DISK_PCT}%."
fi
