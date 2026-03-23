#!/usr/bin/env bash
# =============================================================================
# post-deploy-verify.sh — Mandatory post-deployment health gate
# =============================================================================
# Run this immediately after every `docker compose up -d`.
# Exits non-zero if ANY critical service is not healthy within the timeout.
# Usage:
#   bash scripts/post-deploy-verify.sh [COMPOSE_FILE] [DOMAIN_NAME]
#
# Examples:
#   bash scripts/post-deploy-verify.sh                         # defaults
#   bash scripts/post-deploy-verify.sh docker-compose.hostinger.prod.yml srv1258231.hstgr.cloud
#
# Environment variables (override positional args):
#   COMPOSE_FILE  — path to docker compose file
#   DOMAIN_NAME   — production domain (for external smoke checks)
#   STRAPI_EMAIL  — CMS user email (for route smoke test)
#   STRAPI_PASSWORD — CMS user password (for route smoke test)
#   ALERT_WEBHOOK_URL — Slack/n8n webhook for failure notifications
# =============================================================================
set -uo pipefail

COMPOSE_FILE="${1:-${COMPOSE_FILE:-docker-compose.hostinger.prod.yml}}"
DOMAIN_NAME="${2:-${DOMAIN_NAME:-}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "${GREEN}[PASS]${NC} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAIL=$((FAIL + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; WARN=$((WARN + 1)); }
section() { echo ""; echo "--- $* ---"; }

send_alert() {
  local msg="$1"
  local url="${ALERT_WEBHOOK_URL:-}"
  if [[ -z "$url" ]]; then return; fi
  curl -sf -X POST "$url" \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"[RestoBot Deploy FAILED] ${msg}\",\"source\":\"post-deploy-verify\"}" \
    >/dev/null 2>&1 || true
}

echo "============================================================"
echo "  RestoBot Post-Deploy Health Verification"
echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  Compose: $COMPOSE_FILE"
echo "============================================================"

# =============================================================================
# PHASE 1: Wait for critical services to reach healthy state
# =============================================================================
section "PHASE 1: Container health gate"

# Services that MUST be healthy before declaring deploy success.
# Format: "service_name:max_wait_seconds:description"
CRITICAL_SERVICES=(
  "postgres:60:PostgreSQL database"
  "redis:30:Redis queue broker"
  "n8n-main:120:n8n workflow engine"
  "gateway:30:Nginx API gateway"
)

# CMS needs 3 minutes minimum (81-table Strapi bootstrap)
CMS_MAX_WAIT=200

wait_for_healthy() {
  local service="$1"
  local max_wait="$2"
  local label="$3"
  local elapsed=0
  local interval=5

  printf "  Waiting for %s to be healthy (max %ds)..." "$label" "$max_wait"

  while true; do
    status=$(docker compose -f "$COMPOSE_FILE" ps --format json 2>/dev/null \
      | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        if d.get('Service') == '$service':
            print(d.get('Health', d.get('State', 'unknown')))
            break
    except Exception:
        pass
" 2>/dev/null || echo "unknown")

    if [[ "$status" == "healthy" ]]; then
      echo ""
      pass "$label: healthy (${elapsed}s)"
      return 0
    fi

    if [[ $elapsed -ge $max_wait ]]; then
      echo ""
      fail "$label: still '$status' after ${max_wait}s"
      return 1
    fi

    printf "."
    sleep $interval
    elapsed=$((elapsed + interval))
  done
}

ALL_CRITICAL_OK=true
for entry in "${CRITICAL_SERVICES[@]}"; do
  IFS=: read -r svc wait desc <<< "$entry"
  if ! wait_for_healthy "$svc" "$wait" "$desc"; then
    ALL_CRITICAL_OK=false
  fi
done

# CMS check — warn only if unhealthy (crash-looping is the known issue)
printf "  Waiting for CMS (Strapi) to be healthy (max %ds)..." "$CMS_MAX_WAIT"
CMS_HEALTHY=false
elapsed=0
while [[ $elapsed -lt $CMS_MAX_WAIT ]]; do
  cms_status=$(docker compose -f "$COMPOSE_FILE" ps --format json 2>/dev/null \
    | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        if d.get('Service') == 'cms':
            print(d.get('Health', d.get('State', 'unknown')))
            break
    except Exception:
        pass
" 2>/dev/null || echo "unknown")

  if [[ "$cms_status" == "healthy" ]]; then
    echo ""
    pass "CMS (Strapi): healthy (${elapsed}s)"
    CMS_HEALTHY=true
    break
  fi
  printf "."
  sleep 5
  elapsed=$((elapsed + 5))
done

if [[ "$CMS_HEALTHY" == "false" ]]; then
  echo ""
  fail "CMS (Strapi): NOT healthy after ${CMS_MAX_WAIT}s — check 'docker logs current-cms-1 --tail 50'"
  docker compose -f "$COMPOSE_FILE" logs --tail 20 cms 2>/dev/null | grep -i "error\|fatal\|crash" || true
fi

# =============================================================================
# PHASE 2: Internal HTTP checks (from inside VPS)
# =============================================================================
section "PHASE 2: Internal HTTP probes"

check_http() {
  local name="$1"
  local url="$2"
  local expected="${3:-200}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")
  if [[ "$code" == "$expected" ]]; then
    pass "$name: HTTP $code"
  else
    fail "$name: expected HTTP $expected, got HTTP $code (url: $url)"
  fi
}

# Gateway healthz (direct container port via localhost — no TLS needed)
GW_CONTAINER_IP=$(docker inspect current-gateway-1 \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)
if [[ -n "$GW_CONTAINER_IP" ]]; then
  check_http "gateway /healthz" "http://${GW_CONTAINER_IP}:8080/healthz"
else
  warn "Cannot determine gateway container IP — skipping internal gateway check"
fi

# CMS health endpoint (only if CMS healthy)
if [[ "$CMS_HEALTHY" == "true" ]]; then
  CMS_CONTAINER_IP=$(docker inspect current-cms-1 \
    --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)
  if [[ -n "$CMS_CONTAINER_IP" ]]; then
    check_http "cms /_health" "http://${CMS_CONTAINER_IP}:1337/_health"
  fi
fi

# n8n healthz
N8N_CONTAINER_IP=$(docker inspect current-n8n-main-1 \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)
if [[ -n "$N8N_CONTAINER_IP" ]]; then
  check_http "n8n /healthz" "http://${N8N_CONTAINER_IP}:5678/healthz"
fi

# =============================================================================
# PHASE 3: External smoke tests (requires DOMAIN_NAME)
# =============================================================================
section "PHASE 3: External smoke tests"

if [[ -z "$DOMAIN_NAME" ]]; then
  warn "DOMAIN_NAME not set — skipping external smoke tests"
else
  API="https://api.${DOMAIN_NAME}"

  # Public gateway healthz
  code=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 15 "${API}/healthz" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    pass "External: ${API}/healthz -> HTTP 200"
  else
    fail "External: ${API}/healthz -> HTTP $code (gateway down or TLS broken)"
  fi

  # Kiosk product API (public, no auth)
  code=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 15 \
    "${API}/v1/strapi/api/products" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    pass "External: /v1/strapi/api/products -> HTTP 200"
  else
    warn "External: /v1/strapi/api/products -> HTTP $code (CMS may still be starting)"
  fi
fi

# =============================================================================
# PHASE 4: CMS route smoke (if credentials provided)
# =============================================================================
section "PHASE 4: CMS route smoke test"

if [[ -n "${STRAPI_EMAIL:-}" && -n "${STRAPI_PASSWORD:-}" ]]; then
  CMS_URL="${CMS_URL:-http://127.0.0.1:1337}"
  if [[ -n "$CMS_CONTAINER_IP" ]]; then
    CMS_URL="http://${CMS_CONTAINER_IP}:1337"
  fi
  if [[ "$CMS_HEALTHY" == "true" ]]; then
    if bash "${SCRIPT_DIR}/smoke-cms-routes.sh" "$CMS_URL" "$STRAPI_EMAIL" "$STRAPI_PASSWORD" 2>&1; then
      pass "CMS route smoke: all routes OK"
    else
      fail "CMS route smoke: one or more routes failed"
    fi
  else
    warn "Skipping CMS route smoke — CMS not healthy"
  fi
else
  warn "STRAPI_EMAIL/STRAPI_PASSWORD not set — skipping CMS route smoke"
fi

# =============================================================================
# PHASE 5: Database connectivity and backup age check
# =============================================================================
section "PHASE 5: Database and backup checks"

# Postgres reachable from n8n perspective
PG_CHECK=$(docker compose -f "$COMPOSE_FILE" exec -T postgres \
  pg_isready -U n8n -d n8n 2>/dev/null || echo "FAIL")
if echo "$PG_CHECK" | grep -q "accepting connections"; then
  pass "PostgreSQL: accepting connections"
else
  fail "PostgreSQL: not ready — $PG_CHECK"
fi

# Backup age check
BACKUP_DIR="${BACKUP_DIR:-/opt/resto/backups}"
if [[ -d "$BACKUP_DIR" ]]; then
  LATEST_BACKUP=$(find "$BACKUP_DIR" -name "*.dump*" -o -name "*.dump.gz" 2>/dev/null \
    | sort -t_ -k1 | tail -1)
  if [[ -n "$LATEST_BACKUP" ]]; then
    AGE_SECONDS=$(( $(date +%s) - $(stat -c %Y "$LATEST_BACKUP" 2>/dev/null || echo 0) ))
    AGE_HOURS=$(( AGE_SECONDS / 3600 ))
    if [[ $AGE_HOURS -lt 25 ]]; then
      pass "Latest backup: ${LATEST_BACKUP##*/} (${AGE_HOURS}h ago)"
    else
      warn "Latest backup is ${AGE_HOURS}h old — last backup: ${LATEST_BACKUP##*/}"
    fi
  else
    warn "No database backups found in $BACKUP_DIR"
  fi
else
  warn "Backup directory $BACKUP_DIR does not exist — run backup_postgres.sh"
fi

# =============================================================================
# PHASE 6: Disk and memory check
# =============================================================================
section "PHASE 6: Resource checks"

DISK_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [[ $DISK_PCT -lt 70 ]]; then
  pass "Disk usage: ${DISK_PCT}% (OK)"
elif [[ $DISK_PCT -lt 85 ]]; then
  warn "Disk usage: ${DISK_PCT}% — consider cleanup (npm cache, docker prune)"
else
  fail "Disk usage: ${DISK_PCT}% — CRITICAL, ENOSPC risk! Run: docker system prune -f"
fi

MEM_AVAIL_MB=$(free -m | awk '/^Mem:/ {print $7}')
if [[ $MEM_AVAIL_MB -gt 500 ]]; then
  pass "Memory available: ${MEM_AVAIL_MB}MB"
elif [[ $MEM_AVAIL_MB -gt 200 ]]; then
  warn "Memory available: ${MEM_AVAIL_MB}MB — low, watch for OOM"
else
  fail "Memory available: ${MEM_AVAIL_MB}MB — critical, containers may OOM"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "============================================================"
echo "  SUMMARY"
echo "  PASS: $PASS  WARN: $WARN  FAIL: $FAIL"
echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================================"

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}DEPLOY VERIFICATION FAILED — do NOT mark release as successful.${NC}"
  echo "  Review failures above. Run: docker compose -f $COMPOSE_FILE logs <service> --tail 50"
  send_alert "$FAIL checks failed. Review: docker compose -f $COMPOSE_FILE ps"
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo -e "${YELLOW}Deploy verification PASSED with $WARN warning(s).${NC}"
  echo "  Warnings are non-blocking but should be addressed."
  exit 0
else
  echo -e "${GREEN}Deploy verification PASSED — all critical services healthy.${NC}"
  exit 0
fi
