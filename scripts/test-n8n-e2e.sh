#!/usr/bin/env bash
# =============================================================================
# n8n E2E Test Script — TEST-09 + TEST-10
# =============================================================================
# Verifies two critical n8n workflow behaviors:
#   TEST-09: Meta-signed WA inbound -> inbound_messages DB row (direct Postgres)
#   TEST-10: Outbox retry seeding  -> Redis re-queue with attempts+1
#
# Assumes the docker-compose.test.yml stack is ALREADY running with workflows
# imported and activated. The CI job (Plan 08-02) handles stack lifecycle.
# Can also be run standalone if the stack is up.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
COMPOSE_FILE="${COMPOSE_FILE:-docker/docker-compose.test.yml}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
META_APP_SECRET="${META_APP_SECRET:-ci-test}"
N8N_URL="${N8N_URL:-http://localhost:25678}"
N8N_JAR="/tmp/n8n_e2e_cookies"
PASS=0
FAIL=0
SKIP=0

cd "$ROOT_DIR"

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------
pass() {
  PASS=$((PASS + 1))
  echo "PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "FAIL: $1 -- $2"
}

skip() {
  SKIP=$((SKIP + 1))
  echo "SKIP: $1 -- $2"
}

generate_meta_sig() {
  echo -n "$1" | openssl dgst -sha256 -hmac "${META_APP_SECRET}" | sed 's/^.* //'
}

poll_for_record() {
  local msg_id="$1" max_wait="${2:-20}" waited=0 count
  while [ "${waited}" -lt "${max_wait}" ]; do
    count=$(docker compose -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
      "psql -U n8n -d n8n -Atc \"SELECT COUNT(*) FROM inbound_messages WHERE msg_id = '${msg_id}';\"" \
      | tr -d '\r\n')
    [ "${count:-0}" -ge 1 ] && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

n8n_login() {
  local login_ok=false
  for field in email emailOrLdapLoginId; do
    rm -f "$N8N_JAR"
    code="$(curl -s -o /dev/null -w "%{http_code}" -c "$N8N_JAR" \
      -X POST "${N8N_URL}/rest/login" \
      -H "Content-Type: application/json" \
      -d "{\"$field\":\"test@example.com\",\"password\":\"TestPassw0rd!\"}")"
    if [ "$code" = "200" ]; then login_ok=true; break; fi
  done
  [ "$login_ok" = "true" ] || { echo "WARN: n8n login failed (code=$code)"; return 1; }
}

# ---------------------------------------------------------------------------
# TEST-09: Meta-signed WA inbound -> inbound_messages DB row
# ---------------------------------------------------------------------------
echo ""
echo "=== TEST-09: Meta-signed WA inbound -> inbound_messages DB row ==="

MSG_ID="e2e-wa-$(date +%s)-$$"
TIMESTAMP="$(date +%s)"
PAYLOAD="{\"object\":\"whatsapp_business_account\",\"entry\":[{\"id\":\"TEST_WA_ID\",\"changes\":[{\"value\":{\"messaging_product\":\"whatsapp\",\"metadata\":{\"display_phone_number\":\"15550000000\",\"phone_number_id\":\"TEST_PHONE_ID\"},\"messages\":[{\"from\":\"15551234567\",\"id\":\"${MSG_ID}\",\"timestamp\":\"${TIMESTAMP}\",\"text\":{\"body\":\"Bonjour je veux commander\"},\"type\":\"text\"}]},\"field\":\"messages\"}]}]}"
SIG="sha256=$(generate_meta_sig "$PAYLOAD")"

set +e
WH_STATUS=$(curl -s -o /tmp/wh_resp.json -w "%{http_code}" \
  -X POST "${N8N_URL}/webhook/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: ${SIG}" \
  -d "${PAYLOAD}")
set -e

if [ "$WH_STATUS" = "404" ]; then
  skip "TEST-09" "Webhook route not registered (404). Is W1_IN_WA activated and n8n restarted?"
elif [ "$WH_STATUS" = "200" ] || [ "$WH_STATUS" = "000" ]; then
  # 200 = ACK (queue mode), must poll DB — n8n processes asynchronously
  if poll_for_record "${MSG_ID}" 20; then
    pass "TEST-09: inbound_messages row created for msg_id=${MSG_ID}"
  else
    fail "TEST-09" "No inbound_messages row after 20s poll (msg_id=${MSG_ID}). Check n8n execution logs."
  fi
else
  fail "TEST-09" "Webhook returned HTTP ${WH_STATUS} (expected 200)"
fi

# ---------------------------------------------------------------------------
# TEST-10: Outbox retry seeding -> Redis re-queue with attempts+1
# ---------------------------------------------------------------------------
echo ""
echo "=== TEST-10: Outbox retry -> Redis re-queue with attempts+1 ==="

# Login to n8n for REST API access (needed for manual trigger)
LOGIN_FAILED=false
n8n_login || LOGIN_FAILED=true

if [ "$LOGIN_FAILED" = "true" ]; then
  skip "TEST-10" "n8n login failed, cannot trigger W15"
else
  # Flush Redis outbox before test to avoid leftover entries
  docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli DEL ralphe:outbox:pending ralphe:outbox:dlq > /dev/null 2>&1

  # Seed a failing entry (attempts=1, well below maxAttempts=7).
  # retryable=true is REQUIRED: W15 only re-queues if retryable=true AND attempts < maxAttempts(7).
  # Without retryable=true the entry goes to DLQ instead of pending.
  OUTBOX_ID="e2e-retry-$(date +%s)-$$"
  OUTBOX_ENTRY="{\"channel\":\"whatsapp\",\"payload\":{\"userId\":\"retry-test-${RANDOM}\",\"replyText\":\"test retry\"},\"attempts\":1,\"retryable\":true,\"nextRetryAt\":null,\"outboxMsgId\":\"${OUTBOX_ID}\"}"
  docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli LPUSH ralphe:outbox:pending "${OUTBOX_ENTRY}" > /dev/null

  # Find W15 workflow ID from DB
  W15_ID=$(docker compose -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
    "psql -U n8n -d n8n -Atc \"SELECT id FROM workflow_entity WHERE name LIKE '%Outbox%Worker%' OR name LIKE '%W15%' LIMIT 1;\"" \
    | tr -d '\r\n')

  if [ -z "${W15_ID}" ]; then
    skip "TEST-10" "W15_OUTBOX_WORKER not found in DB"
  else
    # Try manual trigger via REST API
    set +e
    TRIGGER_RESP=$(curl -s -o /dev/null -w "%{http_code}" -b "${N8N_JAR}" \
      -X POST "${N8N_URL}/rest/workflows/${W15_ID}/run" \
      -H "Content-Type: application/json" \
      -d '{}')
    set -e

    if [ "$TRIGGER_RESP" != "200" ]; then
      echo "WARN: Manual trigger returned ${TRIGGER_RESP}. Waiting 35s for CRON trigger..."
      sleep 35
    else
      sleep 5  # Allow execution to complete
    fi

    # Check if entry was re-queued with attempts=2 OR went to DLQ
    set +e
    PENDING_LEN=$(docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli LLEN ralphe:outbox:pending | tr -d '\r\n')
    DLQ_LEN=$(docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli LLEN ralphe:outbox:dlq | tr -d '\r\n')
    set -e

    if [ "${PENDING_LEN:-0}" -ge 1 ]; then
      LAST_ENTRY=$(docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli LINDEX ralphe:outbox:pending 0 | tr -d '\r\n')
      # Parse attempts using python3 (available on CI ubuntu runners) or jq
      ATTEMPTS=$(echo "${LAST_ENTRY}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('attempts',0))" 2>/dev/null || echo "0")
      if [ "${ATTEMPTS}" -ge 2 ]; then
        pass "TEST-10: entry re-queued with attempts=${ATTEMPTS} (expected >= 2)"
      else
        fail "TEST-10" "entry re-queued but attempts=${ATTEMPTS} (expected >= 2)"
      fi
    elif [ "${DLQ_LEN:-0}" -ge 1 ]; then
      fail "TEST-10" "entry went to DLQ instead of being re-queued (PENDING_LEN=0, DLQ_LEN=${DLQ_LEN}). Check seed entry structure."
    else
      fail "TEST-10" "entry disappeared: PENDING_LEN=${PENDING_LEN:-0}, DLQ_LEN=${DLQ_LEN:-0}. W15 may not have run or Redis credential is missing."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "  PASS: ${PASS}  FAIL: ${FAIL}  SKIP: ${SKIP}"
echo "=============================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
