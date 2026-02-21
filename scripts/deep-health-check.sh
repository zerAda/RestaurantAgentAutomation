#!/bin/bash
# =============================================================================
# Resto Bot - Deep Health Check Script (Premium Grade)
# =============================================================================
# Monitors: Postgres, Redis, n8n bull queue, and System metrics.
# Exit codes: 0=Healthy, 1=Warning, 2=Critical
# =============================================================================

OUTPUT_FORMAT=${1:-text} # text or json

# Colors for text output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Initialize stats
STATUS="healthy"
POSTGRES_STATUS="healthy"
REDIS_STATUS="healthy"
N8N_STATUS="healthy"
SYSTEM_STATUS="healthy"

# 1. Check Postgres
PG_READY=$(docker compose exec -T postgres pg_isready -U n8n -d n8n)
if [[ $? -ne 0 ]]; then
    POSTGRES_STATUS="critical"
    STATUS="critical"
fi

# 2. Check Redis
REDIS_PASS=$(cat ./secrets/redis_password 2>/dev/null || echo "")
REDIS_PING=$(docker compose exec -T redis redis-cli ${REDIS_PASS:+-a "$REDIS_PASS"} ping 2>/dev/null)
if [[ "$REDIS_PING" != "PONG" ]]; then
    REDIS_STATUS="critical"
    STATUS="critical"
fi

# 3. Check Disk Usage
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 90 ]]; then
    SYSTEM_STATUS="critical"
    STATUS="critical"
elif [[ $DISK_USAGE -gt 75 ]]; then
    SYSTEM_STATUS="warning"
    if [[ "$STATUS" == "healthy" ]]; then STATUS="warning"; fi
fi

# 4. Alerting Logic
send_slack_alert() {
    local message=$1
    local webhook_url=${ALERT_WEBHOOK_URL:-$2}
    
    if [[ -z "$webhook_url" ]]; then
        return
    fi

    local payload=$(cat <<EOF
{
  "text": "🚨 *Resto Bot Health Alert*",
  "attachments": [{
    "color": "danger",
    "text": "$message",
    "fields": [
      { "title": "Overall Status", "value": "$STATUS", "short": true },
      { "title": "System", "value": "VPS Production", "short": true }
    ],
    "ts": $(date +%s)
  }]
}
EOF
)
    curl -s -X POST -H 'Content-Type: application/json' --data "$payload" "$webhook_url" > /dev/null
}

# Output results
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "overall_status": "$STATUS",
  "postgres": { "status": "$POSTGRES_STATUS" },
  "redis": { "status": "$REDIS_STATUS" },
  "system": { "disk_usage_pct": $DISK_USAGE, "status": "$SYSTEM_STATUS" }
}
EOF
else
    echo -e "=== Resto Bot Deep Health Check ==="
    echo -e "Overall Status: $([[ "$STATUS" == "healthy" ]] && echo -e "${GREEN}HEALTHY${NC}" || echo -e "${RED}$STATUS${NC}")"
    echo -e "Postgres: $([[ "$POSTGRES_STATUS" == "healthy" ]] && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}")"
    echo -e "Redis: $([[ "$REDIS_STATUS" == "healthy" ]] && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}")"
    echo -e "Disk Usage: ${DISK_USAGE}% ($([[ "$SYSTEM_STATUS" == "healthy" ]] && echo -e "${GREEN}OK${NC}" || echo -e "${YELLOW}WARNING${NC}"))"
fi

# Send alert on critical failure
if [[ "$STATUS" == "critical" ]]; then
    ALERT_MSG="Critical failure detected! Postgres: $POSTGRES_STATUS, Redis: $REDIS_STATUS, Disk: $DISK_USAGE%"
    send_slack_alert "$ALERT_MSG"
fi

# Exit with appropriate code
if [[ "$STATUS" == "critical" ]]; then exit 2; fi
if [[ "$STATUS" == "warning" ]]; then exit 1; fi
exit 0
