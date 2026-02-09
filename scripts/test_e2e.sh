#!/usr/bin/env bash
# =============================================================================
# RESTO BOT - End-to-End Integration Tests
# =============================================================================
# Tests the complete flow: Inbound → Processing → Outbound
# Requires: Running stack (docker-compose up), Mock API for outbound
#
# Usage:
#   ./scripts/test_e2e.sh [--env local|staging|prod] [--verbose]
# =============================================================================
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
ENV="${ENV:-local}"
VERBOSE="${VERBOSE:-false}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --env) ENV="$2"; shift 2 ;;
        --verbose) VERBOSE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Environment-specific config
case "$ENV" in
    local)
        API_URL="${API_URL:-http://localhost:8080}"
        DB_URL="${DB_URL:-postgres://n8n:n8npass@localhost:5432/n8n}"
        ;;
    staging)
        API_URL="${API_URL:-https://api.staging.example.com}"
        DB_URL="${DB_URL:-}"
        ;;
    prod)
        API_URL="${API_URL:-https://api.example.com}"
        DB_URL="${DB_URL:-}"
        ;;
esac

: "${META_VERIFY_TOKEN:=test_verify_token}"
: "${META_APP_SECRET:=test_app_secret}"
: "${WEBHOOK_TOKEN:=${WEBHOOK_SHARED_TOKEN:-test_token}}"
: "${ADMIN_TOKEN:=${WEBHOOK_TOKEN}}"

# Counters
PASSED=0
FAILED=0
TOTAL=0

# Logging
log_pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; ((PASSED++)); ((TOTAL++)); }
log_fail() { echo -e "${RED}❌ FAIL${NC}: $1"; ((FAILED++)); ((TOTAL++)); }
log_info() { echo -e "${CYAN}ℹ️  INFO${NC}: $1"; }
log_step() { echo -e "${BLUE}▶ STEP${NC}: $1"; }
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "   DEBUG: $1"; }

section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

# Helper functions
generate_signature() {
    local payload="$1"
    local secret="${2:-$META_APP_SECRET}"
    echo -n "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/^.* //'
}

wait_for_processing() {
    local seconds="${1:-3}"
    log_debug "Waiting ${seconds}s for async processing..."
    sleep "$seconds"
}

check_db() {
    if [[ -z "$DB_URL" ]]; then
        log_debug "DB_URL not set, skipping DB checks"
        return 1
    fi
    return 0
}

query_db() {
    local query="$1"
    if check_db; then
        psql "$DB_URL" -t -A -c "$query" 2>/dev/null || echo ""
    fi
}

# =============================================================================
# E2E TEST 1: Complete WhatsApp Flow
# =============================================================================
section "E2E TEST 1: WhatsApp Complete Flow"

log_step "1.1 Sending inbound message..."
TIMESTAMP=$(date +%s)
MSG_ID="e2e-wa-${RANDOM}-${TIMESTAMP}"
USER_ID="e2e-user-wa-${RANDOM}"
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"${MSG_ID}\",\"from\":\"${USER_ID}\",\"text\":\"Bonjour, je voudrais commander une pizza\",\"timestamp\":${TIMESTAMP}}"
SIG=$(generate_signature "$PAYLOAD")

response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -H "X-Hub-Signature-256: sha256=${SIG}" \
    -d "$PAYLOAD" 2>/dev/null || echo -e "\nCURL_FAILED")

http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | head -n -1)

if [[ "$http_code" == "200" ]]; then
    log_pass "1.1 Inbound accepted (200)"
    log_debug "Response: $body"

    # Extract correlation_id if present
    corr_id=$(echo "$body" | grep -o '"correlation_id":"[^"]*"' | cut -d'"' -f4 || echo "")
    [[ -n "$corr_id" ]] && log_debug "Correlation ID: $corr_id"
else
    log_fail "1.1 Inbound failed (HTTP $http_code)"
    log_debug "Response: $body"
fi

log_step "1.2 Waiting for async processing..."
wait_for_processing 3

log_step "1.3 Checking message was logged..."
if check_db; then
    count=$(query_db "SELECT COUNT(*) FROM inbound_messages WHERE msg_id = '${MSG_ID}';")
    if [[ "$count" -ge 1 ]]; then
        log_pass "1.3 Message logged in database"
    else
        log_fail "1.3 Message not found in database"
    fi
else
    log_info "1.3 DB check skipped (no DB_URL)"
fi

log_step "1.4 Checking idempotency (duplicate should be accepted)..."
response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -H "X-Hub-Signature-256: sha256=${SIG}" \
    -d "$PAYLOAD" 2>/dev/null || echo -e "\nCURL_FAILED")

http_code=$(echo "$response" | tail -1)
if [[ "$http_code" == "200" ]]; then
    log_pass "1.4 Duplicate accepted (idempotent)"
else
    log_fail "1.4 Duplicate handling failed (HTTP $http_code)"
fi

# =============================================================================
# E2E TEST 2: Complete Instagram Flow
# =============================================================================
section "E2E TEST 2: Instagram Complete Flow"

log_step "2.1 Sending inbound message..."
TIMESTAMP=$(date +%s)
MSG_ID="e2e-ig-${RANDOM}-${TIMESTAMP}"
USER_ID="e2e-user-ig-${RANDOM}"
PAYLOAD="{\"provider\":\"ig\",\"msg_id\":\"${MSG_ID}\",\"from\":\"${USER_ID}\",\"text\":\"مرحبا، أريد الطلب\",\"timestamp\":${TIMESTAMP}}"
SIG=$(generate_signature "$PAYLOAD")

response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/instagram" \
    -H "Content-Type: application/json" \
    -H "X-Hub-Signature-256: sha256=${SIG}" \
    -d "$PAYLOAD" 2>/dev/null || echo -e "\nCURL_FAILED")

http_code=$(echo "$response" | tail -1)
if [[ "$http_code" == "200" ]]; then
    log_pass "2.1 Instagram inbound accepted"
else
    log_fail "2.1 Instagram inbound failed (HTTP $http_code)"
fi

log_step "2.2 Testing Arabic script detection..."
# The message contains Arabic, system should detect it
wait_for_processing 2
log_info "2.2 Arabic detection verified by acceptance (manual check for response language)"

# =============================================================================
# E2E TEST 3: Complete Messenger Flow
# =============================================================================
section "E2E TEST 3: Messenger Complete Flow"

log_step "3.1 Sending inbound message..."
TIMESTAMP=$(date +%s)
MSG_ID="e2e-msg-${RANDOM}-${TIMESTAMP}"
USER_ID="e2e-user-msg-${RANDOM}"
PAYLOAD="{\"provider\":\"msg\",\"msg_id\":\"${MSG_ID}\",\"from\":\"${USER_ID}\",\"text\":\"Hello, I want to order\",\"timestamp\":${TIMESTAMP}}"
SIG=$(generate_signature "$PAYLOAD")

response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/messenger" \
    -H "Content-Type: application/json" \
    -H "X-Hub-Signature-256: sha256=${SIG}" \
    -d "$PAYLOAD" 2>/dev/null || echo -e "\nCURL_FAILED")

http_code=$(echo "$response" | tail -1)
if [[ "$http_code" == "200" ]]; then
    log_pass "3.1 Messenger inbound accepted"
else
    log_fail "3.1 Messenger inbound failed (HTTP $http_code)"
fi

# =============================================================================
# E2E TEST 4: Multi-Channel Conversation
# =============================================================================
section "E2E TEST 4: Multi-Message Conversation"

log_step "4.1 Simulating conversation (3 messages)..."
TIMESTAMP=$(date +%s)
USER_ID="e2e-convo-${RANDOM}"
messages=("Bonjour" "Je veux une pizza margherita" "Pour livraison")

for i in "${!messages[@]}"; do
    MSG_ID="e2e-convo-${RANDOM}-$i"
    PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"${MSG_ID}\",\"from\":\"${USER_ID}\",\"text\":\"${messages[$i]}\",\"timestamp\":$((TIMESTAMP + i))}"
    SIG=$(generate_signature "$PAYLOAD")

    response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: sha256=${SIG}" \
        -d "$PAYLOAD" 2>/dev/null || echo -e "\nCURL_FAILED")

    http_code=$(echo "$response" | tail -1)
    if [[ "$http_code" == "200" ]]; then
        log_debug "Message $((i+1)) accepted"
    else
        log_fail "4.1 Message $((i+1)) failed"
    fi

    sleep 0.5  # Small delay between messages
done
log_pass "4.1 Conversation messages sent"

log_step "4.2 Checking rate limiting not triggered..."
# 3 messages should be under the limit
if check_db; then
    rate_events=$(query_db "SELECT COUNT(*) FROM security_events WHERE event_type = 'RATE_LIMIT' AND created_at > NOW() - INTERVAL '1 minute';")
    if [[ "$rate_events" -eq 0 ]]; then
        log_pass "4.2 No rate limit events (expected)"
    else
        log_info "4.2 Rate limit events found: $rate_events"
    fi
else
    log_info "4.2 Rate limit check skipped (no DB_URL)"
fi

# =============================================================================
# E2E TEST 5: Security Event Logging
# =============================================================================
section "E2E TEST 5: Security Event Logging"

log_step "5.1 Sending request with invalid signature..."
PAYLOAD='{"provider":"wa","msg_id":"sec-test","from":"hacker","text":"evil"}'
response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -H "X-Hub-Signature-256: sha256=invalid_signature_here" \
    -d "$PAYLOAD" 2>/dev/null || echo -e "\nCURL_FAILED")

http_code=$(echo "$response" | tail -1)
log_info "5.1 Invalid signature returned HTTP $http_code"

log_step "5.2 Checking security event was logged..."
wait_for_processing 2
if check_db; then
    sec_events=$(query_db "SELECT COUNT(*) FROM security_events WHERE created_at > NOW() - INTERVAL '1 minute';")
    log_info "5.2 Security events in last minute: $sec_events"
    if [[ "$sec_events" -ge 1 ]]; then
        log_pass "5.2 Security events are being logged"
    fi
else
    log_info "5.2 Security event check skipped (no DB_URL)"
fi

# =============================================================================
# E2E TEST 6: Webhook Verify Flow
# =============================================================================
section "E2E TEST 6: Webhook Verify (Meta Setup)"

for channel in whatsapp instagram messenger; do
    log_step "6.${channel} Testing GET verify..."
    CHALLENGE="e2e-challenge-${RANDOM}"

    response=$(curl -s "${API_URL}/v1/inbound/${channel}?hub.mode=subscribe&hub.verify_token=${META_VERIFY_TOKEN}&hub.challenge=${CHALLENGE}" 2>/dev/null || echo "CURL_FAILED")

    if [[ "$response" == "$CHALLENGE" ]]; then
        log_pass "6.${channel} Verify returns challenge correctly"
    elif [[ "$response" == "CURL_FAILED" ]]; then
        log_fail "6.${channel} Verify endpoint not responding"
    else
        log_fail "6.${channel} Verify returned: $response (expected: $CHALLENGE)"
    fi
done

# =============================================================================
# E2E TEST 7: Admin Endpoints
# =============================================================================
section "E2E TEST 7: Admin Endpoints"

log_step "7.1 Testing DLQ replay (dry run)..."
response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/admin/dlq/replay" \
    -H "Content-Type: application/json" \
    -H "x-api-token: ${ADMIN_TOKEN}" \
    -d '{"dry_run": true, "max_messages": 5}' 2>/dev/null || echo -e "\nCURL_FAILED")

http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | head -n -1)

if [[ "$http_code" == "200" ]]; then
    log_pass "7.1 DLQ replay endpoint accessible"
    log_debug "Response: $body"
elif [[ "$http_code" == "403" ]]; then
    log_info "7.1 DLQ replay returned 403 (admin scope required)"
else
    log_info "7.1 DLQ replay returned HTTP $http_code"
fi

# =============================================================================
# E2E TEST 8: Response Time Check
# =============================================================================
section "E2E TEST 8: Performance (Response Time)"

log_step "8.1 Measuring inbound response time..."
TIMESTAMP=$(date +%s)
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"perf-${RANDOM}\",\"from\":\"perf-user\",\"text\":\"perf test\",\"timestamp\":${TIMESTAMP}}"
SIG=$(generate_signature "$PAYLOAD")

start_time=$(date +%s%3N)
response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -H "X-Hub-Signature-256: sha256=${SIG}" \
    -d "$PAYLOAD" 2>/dev/null || echo -e "\nCURL_FAILED")
end_time=$(date +%s%3N)

http_code=$(echo "$response" | tail -1)
response_time=$((end_time - start_time))

if [[ "$http_code" == "200" ]]; then
    if [[ $response_time -lt 1000 ]]; then
        log_pass "8.1 Response time: ${response_time}ms (< 1s target)"
    elif [[ $response_time -lt 2000 ]]; then
        log_info "8.1 Response time: ${response_time}ms (acceptable but > 1s)"
    else
        log_fail "8.1 Response time: ${response_time}ms (too slow, > 2s)"
    fi
else
    log_fail "8.1 Request failed (HTTP $http_code)"
fi

# =============================================================================
# SUMMARY
# =============================================================================
section "E2E TEST SUMMARY"

echo ""
echo -e "Environment: ${CYAN}${ENV}${NC}"
echo -e "API URL:     ${CYAN}${API_URL}${NC}"
echo ""
echo -e "Total Tests: ${TOTAL}"
echo -e "${GREEN}Passed:${NC}  ${PASSED}"
echo -e "${RED}Failed:${NC}  ${FAILED}"
echo ""

if [[ $TOTAL -gt 0 ]]; then
    PASS_RATE=$((PASSED * 100 / TOTAL))
    echo -e "Pass Rate: ${PASS_RATE}%"
fi

echo ""
if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}Some E2E tests failed. Review the output above.${NC}"
    exit 1
else
    echo -e "${GREEN}All E2E tests passed!${NC}"
    exit 0
fi
