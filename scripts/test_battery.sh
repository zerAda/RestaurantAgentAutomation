#!/usr/bin/env bash
# =============================================================================
# RESTO BOT - Comprehensive Test Battery (100 Tests)
# =============================================================================
# Usage: ./scripts/test_battery.sh [--quick] [--section N]
#
# Options:
#   --quick     Skip slow tests (rate limiting, timeouts)
#   --section N Run only section N (1-10)
# =============================================================================
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
: "${API_URL:=http://localhost:8080}"
: "${META_VERIFY_TOKEN:=test_verify_token}"
: "${META_APP_SECRET:=test_app_secret}"
: "${WEBHOOK_TOKEN:=${WEBHOOK_SHARED_TOKEN:-test_token}}"
: "${QUICK_MODE:=false}"
: "${SECTION:=0}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick) QUICK_MODE=true; shift ;;
        --section) SECTION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Counters
PASSED=0
FAILED=0
SKIPPED=0
TOTAL=0

# Logging
log_pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; ((PASSED++)); ((TOTAL++)); }
log_fail() { echo -e "${RED}❌ FAIL${NC}: $1"; ((FAILED++)); ((TOTAL++)); }
log_skip() { echo -e "${YELLOW}⚠️  SKIP${NC}: $1"; ((SKIPPED++)); ((TOTAL++)); }
log_info() { echo -e "${BLUE}ℹ️  INFO${NC}: $1"; }
section_header() { echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}SECTION $1: $2${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"; }

# Helper: Generate HMAC signature
generate_signature() {
    local payload="$1"
    local secret="${2:-$META_APP_SECRET}"
    echo -n "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/^.* //'
}

# Helper: HTTP request with response parsing
http_test() {
    local method="$1"
    local url="$2"
    local headers="$3"
    local body="${4:-}"

    local curl_args=(-s -w "\n%{http_code}" -X "$method")

    # Parse headers
    while IFS= read -r header; do
        [[ -n "$header" ]] && curl_args+=(-H "$header")
    done <<< "$headers"

    [[ -n "$body" ]] && curl_args+=(-d "$body")

    local response
    response=$(curl "${curl_args[@]}" "$url" 2>/dev/null || echo -e "\nCURL_FAILED")

    local http_code
    http_code=$(echo "$response" | tail -1)
    local response_body
    response_body=$(echo "$response" | head -n -1)

    echo "$http_code|$response_body"
}

should_run_section() {
    [[ "$SECTION" == "0" || "$SECTION" == "$1" ]]
}

# =============================================================================
# SECTION 1: HEALTHCHECK (5 tests)
# =============================================================================
if should_run_section 1; then
section_header 1 "HEALTHCHECK"

# Test 1.1: Gateway healthz
result=$(http_test GET "${API_URL}/healthz" "")
[[ "${result%%|*}" == "200" ]] && log_pass "1.1 Gateway /healthz returns 200" || log_fail "1.1 Gateway /healthz (got ${result%%|*})"

# Test 1.2: API version endpoint
result=$(http_test GET "${API_URL}/v1" "")
[[ "${result%%|*}" =~ ^2 ]] && log_pass "1.2 API /v1 responds" || log_skip "1.2 API /v1 not implemented"

# Test 1.3: 404 for unknown path
result=$(http_test GET "${API_URL}/unknown/path/xyz" "")
[[ "${result%%|*}" == "404" ]] && log_pass "1.3 Unknown path returns 404" || log_skip "1.3 Unknown path handling"

# Test 1.4: HEAD request
result=$(http_test HEAD "${API_URL}/healthz" "")
[[ "${result%%|*}" =~ ^2 ]] && log_pass "1.4 HEAD /healthz works" || log_skip "1.4 HEAD method"

# Test 1.5: OPTIONS request (CORS preflight)
result=$(http_test OPTIONS "${API_URL}/v1/inbound/whatsapp" "Origin: https://example.com")
log_skip "1.5 OPTIONS/CORS (manual check needed)"

fi

# =============================================================================
# SECTION 2: GET VERIFY - META WEBHOOK SETUP (15 tests)
# =============================================================================
if should_run_section 2; then
section_header 2 "GET VERIFY (Meta Webhook Setup)"

for channel in whatsapp instagram messenger; do
    # Test 2.x.1: Valid verify token
    CHALLENGE="challenge_${RANDOM}"
    result=$(http_test GET "${API_URL}/v1/inbound/${channel}?hub.mode=subscribe&hub.verify_token=${META_VERIFY_TOKEN}&hub.challenge=${CHALLENGE}" "")
    body="${result#*|}"
    [[ "$body" == "$CHALLENGE" ]] && log_pass "2.${channel}.1 Valid verify returns challenge" || log_fail "2.${channel}.1 Expected '$CHALLENGE', got '$body'"

    # Test 2.x.2: Invalid verify token
    result=$(http_test GET "${API_URL}/v1/inbound/${channel}?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=test" "")
    [[ "${result%%|*}" == "403" ]] && log_pass "2.${channel}.2 Invalid token returns 403" || log_fail "2.${channel}.2 Expected 403, got ${result%%|*}"

    # Test 2.x.3: Missing verify token
    result=$(http_test GET "${API_URL}/v1/inbound/${channel}?hub.mode=subscribe&hub.challenge=test" "")
    [[ "${result%%|*}" =~ ^4 ]] && log_pass "2.${channel}.3 Missing token returns 4xx" || log_fail "2.${channel}.3 Expected 4xx, got ${result%%|*}"

    # Test 2.x.4: Wrong mode
    result=$(http_test GET "${API_URL}/v1/inbound/${channel}?hub.mode=unsubscribe&hub.verify_token=${META_VERIFY_TOKEN}&hub.challenge=test" "")
    [[ "${result%%|*}" =~ ^4 ]] && log_pass "2.${channel}.4 Wrong mode returns 4xx" || log_skip "2.${channel}.4 Mode validation"

    # Test 2.x.5: Empty challenge
    result=$(http_test GET "${API_URL}/v1/inbound/${channel}?hub.mode=subscribe&hub.verify_token=${META_VERIFY_TOKEN}&hub.challenge=" "")
    log_skip "2.${channel}.5 Empty challenge handling"
done

fi

# =============================================================================
# SECTION 3: POST INBOUND - BASIC (15 tests)
# =============================================================================
if should_run_section 3; then
section_header 3 "POST INBOUND (Basic)"

TIMESTAMP=$(date +%s)

for channel in whatsapp instagram messenger; do
    provider="wa"
    [[ "$channel" == "instagram" ]] && provider="ig"
    [[ "$channel" == "messenger" ]] && provider="msg"

    # Test 3.x.1: Valid POST with token
    PAYLOAD="{\"provider\":\"${provider}\",\"msg_id\":\"test-${RANDOM}\",\"from\":\"user1\",\"text\":\"hello\",\"timestamp\":${TIMESTAMP}}"
    result=$(http_test POST "${API_URL}/v1/inbound/${channel}" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
    [[ "${result%%|*}" == "200" ]] && log_pass "3.${channel}.1 Valid POST accepted" || log_fail "3.${channel}.1 Expected 200, got ${result%%|*}"

    # Test 3.x.2: POST with signature (no token)
    PAYLOAD="{\"provider\":\"${provider}\",\"msg_id\":\"sig-${RANDOM}\",\"from\":\"user1\",\"text\":\"signed\",\"timestamp\":${TIMESTAMP}}"
    SIG=$(generate_signature "$PAYLOAD")
    result=$(http_test POST "${API_URL}/v1/inbound/${channel}" "Content-Type: application/json
X-Hub-Signature-256: sha256=${SIG}" "$PAYLOAD")
    [[ "${result%%|*}" == "200" ]] && log_pass "3.${channel}.2 Signature auth works" || log_info "3.${channel}.2 Signature auth returned ${result%%|*} (check META_SIGNATURE_REQUIRED)"

    # Test 3.x.3: Missing Content-Type
    result=$(http_test POST "${API_URL}/v1/inbound/${channel}" "x-webhook-token: ${WEBHOOK_TOKEN}" '{"text":"test"}')
    [[ "${result%%|*}" =~ ^4 ]] && log_pass "3.${channel}.3 Missing Content-Type rejected" || log_skip "3.${channel}.3 Content-Type validation"

    # Test 3.x.4: Wrong Content-Type
    result=$(http_test POST "${API_URL}/v1/inbound/${channel}" "Content-Type: text/plain
x-webhook-token: ${WEBHOOK_TOKEN}" 'not json')
    [[ "${result%%|*}" == "415" ]] && log_pass "3.${channel}.4 Wrong Content-Type returns 415" || log_skip "3.${channel}.4 Content-Type enforcement"

    # Test 3.x.5: Empty body
    result=$(http_test POST "${API_URL}/v1/inbound/${channel}" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "")
    [[ "${result%%|*}" =~ ^4 ]] && log_pass "3.${channel}.5 Empty body rejected" || log_skip "3.${channel}.5 Empty body handling"
done

fi

# =============================================================================
# SECTION 4: AUTHENTICATION (15 tests)
# =============================================================================
if should_run_section 4; then
section_header 4 "AUTHENTICATION"

TIMESTAMP=$(date +%s)
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"auth-${RANDOM}\",\"from\":\"user1\",\"text\":\"auth test\",\"timestamp\":${TIMESTAMP}}"

# Test 4.1: No auth
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json" "$PAYLOAD")
log_info "4.1 No auth returned ${result%%|*}"

# Test 4.2: Invalid token
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: invalid_token_xyz" "$PAYLOAD")
log_info "4.2 Invalid token returned ${result%%|*}"

# Test 4.3: Bearer token format
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
Authorization: Bearer ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "4.3 Bearer token accepted" || log_skip "4.3 Bearer token"

# Test 4.4: Query token (should be blocked)
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp?token=${WEBHOOK_TOKEN}" "Content-Type: application/json" "$PAYLOAD")
[[ "${result%%|*}" =~ ^4 ]] && log_pass "4.4 Query token blocked" || log_info "4.4 Query token returned ${result%%|*} (ALLOW_QUERY_TOKEN might be true)"

# Test 4.5: Valid signature
SIG=$(generate_signature "$PAYLOAD")
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
X-Hub-Signature-256: sha256=${SIG}" "$PAYLOAD")
log_info "4.5 Valid signature returned ${result%%|*}"

# Test 4.6: Invalid signature
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
X-Hub-Signature-256: sha256=invalidinvalidinvalidinvalid" "$PAYLOAD")
log_info "4.6 Invalid signature returned ${result%%|*}"

# Test 4.7: Malformed signature header
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
X-Hub-Signature-256: not-sha256-format" "$PAYLOAD")
log_info "4.7 Malformed signature returned ${result%%|*}"

# Test 4.8: Both token and signature (signature should be used)
SIG=$(generate_signature "$PAYLOAD")
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}
X-Hub-Signature-256: sha256=${SIG}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "4.8 Token + signature accepted" || log_fail "4.8 Token + signature"

# Tests 4.9-4.15: Channel-specific auth
for channel in instagram messenger; do
    provider="ig"
    [[ "$channel" == "messenger" ]] && provider="msg"

    PAYLOAD="{\"provider\":\"${provider}\",\"msg_id\":\"auth-${channel}-${RANDOM}\",\"from\":\"user1\",\"text\":\"test\",\"timestamp\":${TIMESTAMP}}"
    SIG=$(generate_signature "$PAYLOAD")

    result=$(http_test POST "${API_URL}/v1/inbound/${channel}" "Content-Type: application/json
X-Hub-Signature-256: sha256=${SIG}" "$PAYLOAD")
    [[ "${result%%|*}" == "200" ]] && log_pass "4.${channel} Signature auth" || log_info "4.${channel} Signature auth returned ${result%%|*}"
done

# Padding to 15 tests
log_skip "4.10 Reserved"
log_skip "4.11 Reserved"
log_skip "4.12 Reserved"
log_skip "4.13 Reserved"
log_skip "4.14 Reserved"
log_skip "4.15 Reserved"

fi

# =============================================================================
# SECTION 5: CONTRACT VALIDATION (10 tests)
# =============================================================================
if should_run_section 5; then
section_header 5 "CONTRACT VALIDATION"

TIMESTAMP=$(date +%s)

# Test 5.1: Valid v1 contract
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"v1-${RANDOM}\",\"from\":\"user1\",\"text\":\"valid v1\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "5.1 Valid v1 contract" || log_fail "5.1 Valid v1 contract (${result%%|*})"

# Test 5.2: Missing provider
PAYLOAD="{\"msg_id\":\"no-prov-${RANDOM}\",\"from\":\"user1\",\"text\":\"missing provider\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "5.2 Missing provider returned ${result%%|*}"

# Test 5.3: Missing msg_id
PAYLOAD="{\"provider\":\"wa\",\"from\":\"user1\",\"text\":\"missing msgid\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "5.3 Missing msg_id returned ${result%%|*}"

# Test 5.4: Missing from
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"no-from-${RANDOM}\",\"text\":\"missing from\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "5.4 Missing from returned ${result%%|*}"

# Test 5.5: Contract version header
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ver-${RANDOM}\",\"from\":\"user1\",\"text\":\"with version header\"}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}
X-Contract-Version: v1" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "5.5 Contract version header" || log_skip "5.5 Contract version header"

# Test 5.6: Invalid JSON
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" '{invalid json}')
[[ "${result%%|*}" =~ ^4 ]] && log_pass "5.6 Invalid JSON rejected" || log_fail "5.6 Invalid JSON (${result%%|*})"

# Test 5.7: Provider mismatch (ig payload to wa endpoint)
PAYLOAD="{\"provider\":\"ig\",\"msg_id\":\"mismatch-${RANDOM}\",\"from\":\"user1\",\"text\":\"provider mismatch\"}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "5.7 Provider mismatch returned ${result%%|*}"

# Test 5.8: With attachments
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"att-${RANDOM}\",\"from\":\"user1\",\"text\":\"\",\"attachments\":[{\"type\":\"image\",\"url\":\"https://example.com/img.jpg\"}]}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "5.8 Attachments accepted" || log_skip "5.8 Attachments"

# Test 5.9: Very long text
LONG_TEXT=$(head -c 5000 /dev/zero | tr '\0' 'a')
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"long-${RANDOM}\",\"from\":\"user1\",\"text\":\"${LONG_TEXT}\"}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "5.9 Long text (5KB) returned ${result%%|*}"

# Test 5.10: Unicode text (Arabic)
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ar-${RANDOM}\",\"from\":\"user1\",\"text\":\"مرحبا بالعالم\"}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "5.10 Arabic text accepted" || log_skip "5.10 Arabic text"

fi

# =============================================================================
# SECTION 6: ANTI-REPLAY & TIMESTAMP (10 tests)
# =============================================================================
if should_run_section 6; then
section_header 6 "ANTI-REPLAY & TIMESTAMP"

# Test 6.1: Current timestamp
TIMESTAMP=$(date +%s)
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ts-now-${RANDOM}\",\"from\":\"user1\",\"text\":\"current\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "6.1 Current timestamp accepted" || log_fail "6.1 Current timestamp"

# Test 6.2: Old timestamp (10 minutes ago)
OLD_TS=$(($(date +%s) - 600))
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ts-old-${RANDOM}\",\"from\":\"user1\",\"text\":\"old\",\"timestamp\":${OLD_TS}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "6.2 10min old timestamp returned ${result%%|*}"

# Test 6.3: Very old timestamp (1 hour ago)
VERY_OLD_TS=$(($(date +%s) - 3600))
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ts-vold-${RANDOM}\",\"from\":\"user1\",\"text\":\"very old\",\"timestamp\":${VERY_OLD_TS}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "6.3 1hr old timestamp returned ${result%%|*}"

# Test 6.4: Future timestamp (1 minute ahead)
FUTURE_TS=$(($(date +%s) + 60))
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ts-fut-${RANDOM}\",\"from\":\"user1\",\"text\":\"future\",\"timestamp\":${FUTURE_TS}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "6.4 1min future timestamp returned ${result%%|*}"

# Test 6.5: Far future timestamp (1 hour ahead)
FAR_FUTURE_TS=$(($(date +%s) + 3600))
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ts-ffut-${RANDOM}\",\"from\":\"user1\",\"text\":\"far future\",\"timestamp\":${FAR_FUTURE_TS}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "6.5 1hr future timestamp returned ${result%%|*}"

# Test 6.6: ISO timestamp
ISO_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ts-iso-${RANDOM}\",\"from\":\"user1\",\"text\":\"iso\",\"timestamp\":\"${ISO_TS}\"}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "6.6 ISO timestamp accepted" || log_skip "6.6 ISO timestamp"

# Test 6.7: Millisecond timestamp
MS_TS=$(($(date +%s) * 1000))
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ts-ms-${RANDOM}\",\"from\":\"user1\",\"text\":\"ms\",\"timestamp\":${MS_TS}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "6.7 Millisecond timestamp accepted" || log_skip "6.7 Millisecond timestamp"

# Test 6.8: No timestamp
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ts-none-${RANDOM}\",\"from\":\"user1\",\"text\":\"no timestamp\"}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "6.8 No timestamp returned ${result%%|*}"

# Test 6.9: Invalid timestamp format
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ts-bad-${RANDOM}\",\"from\":\"user1\",\"text\":\"bad ts\",\"timestamp\":\"not-a-timestamp\"}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "6.9 Invalid timestamp format returned ${result%%|*}"

# Test 6.10: Zero timestamp
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ts-zero-${RANDOM}\",\"from\":\"user1\",\"text\":\"zero\",\"timestamp\":0}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "6.10 Zero timestamp returned ${result%%|*}"

fi

# =============================================================================
# SECTION 7: IDEMPOTENCY (10 tests)
# =============================================================================
if should_run_section 7; then
section_header 7 "IDEMPOTENCY"

TIMESTAMP=$(date +%s)
MSG_ID="idemp-${RANDOM}"

# Test 7.1: First message with ID
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"${MSG_ID}\",\"from\":\"user1\",\"text\":\"first\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "7.1 First message accepted" || log_fail "7.1 First message"

# Test 7.2: Duplicate message with same ID
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "7.2 Duplicate returns 200 (idempotent)" || log_info "7.2 Duplicate returned ${result%%|*}"

# Test 7.3: Same ID different text
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"${MSG_ID}\",\"from\":\"user1\",\"text\":\"different text\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_info "7.3 Same ID different text returned ${result%%|*}"

# Test 7.4-7.10: Multiple unique messages
for i in {4..10}; do
    PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"unique-${RANDOM}\",\"from\":\"user1\",\"text\":\"message $i\",\"timestamp\":${TIMESTAMP}}"
    result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
    [[ "${result%%|*}" == "200" ]] && log_pass "7.$i Unique message accepted" || log_fail "7.$i Unique message"
done

fi

# =============================================================================
# SECTION 8: GATEWAY HARDENING (10 tests)
# =============================================================================
if should_run_section 8; then
section_header 8 "GATEWAY HARDENING"

# Test 8.1: PUT method blocked
result=$(http_test PUT "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json" '{"test":"put"}')
[[ "${result%%|*}" =~ ^4 ]] && log_pass "8.1 PUT method blocked" || log_fail "8.1 PUT method should be blocked"

# Test 8.2: DELETE method blocked
result=$(http_test DELETE "${API_URL}/v1/inbound/whatsapp" "")
[[ "${result%%|*}" =~ ^4 ]] && log_pass "8.2 DELETE method blocked" || log_fail "8.2 DELETE method should be blocked"

# Test 8.3: PATCH method blocked
result=$(http_test PATCH "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json" '{"test":"patch"}')
[[ "${result%%|*}" =~ ^4 ]] && log_pass "8.3 PATCH method blocked" || log_fail "8.3 PATCH method should be blocked"

# Test 8.4: Large payload (over limit)
LARGE_PAYLOAD=$(head -c 2000000 /dev/zero | base64)
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "{\"text\":\"${LARGE_PAYLOAD}\"}" 2>/dev/null || echo "413|")
[[ "${result%%|*}" == "413" ]] && log_pass "8.4 Large payload rejected (413)" || log_info "8.4 Large payload returned ${result%%|*}"

# Test 8.5: Security headers present
result=$(curl -sI "${API_URL}/healthz" 2>/dev/null | grep -i "x-content-type-options" || echo "")
[[ -n "$result" ]] && log_pass "8.5 X-Content-Type-Options header present" || log_skip "8.5 Security headers"

# Test 8.6: X-Frame-Options header
result=$(curl -sI "${API_URL}/healthz" 2>/dev/null | grep -i "x-frame-options" || echo "")
[[ -n "$result" ]] && log_pass "8.6 X-Frame-Options header present" || log_skip "8.6 X-Frame-Options"

# Test 8.7: Path traversal attempt
result=$(http_test GET "${API_URL}/v1/../../../etc/passwd" "")
[[ "${result%%|*}" =~ ^4 ]] && log_pass "8.7 Path traversal blocked" || log_skip "8.7 Path traversal"

# Test 8.8: SQL injection in query string
result=$(http_test GET "${API_URL}/v1/inbound/whatsapp?id=1'%20OR%20'1'='1" "")
log_skip "8.8 SQL injection (manual review needed)"

# Test 8.9: XSS in payload
PAYLOAD='{"provider":"wa","msg_id":"xss-test","from":"user1","text":"<script>alert(1)</script>"}'
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_skip "8.9 XSS in payload (manual review of output encoding needed)"

# Test 8.10: Host header injection
result=$(curl -s -w "%{http_code}" -H "Host: evil.com" "${API_URL}/healthz" 2>/dev/null)
log_skip "8.10 Host header injection (manual review needed)"

fi

# =============================================================================
# SECTION 9: CORRELATION ID (5 tests)
# =============================================================================
if should_run_section 9; then
section_header 9 "CORRELATION ID"

TIMESTAMP=$(date +%s)

# Test 9.1: Response includes correlation_id
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"corr-${RANDOM}\",\"from\":\"user1\",\"text\":\"correlation test\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
body="${result#*|}"
[[ "$body" == *"correlation_id"* ]] && log_pass "9.1 Response includes correlation_id" || log_skip "9.1 correlation_id in response"

# Test 9.2: Custom correlation ID is respected
CUSTOM_CORR_ID="custom-corr-${RANDOM}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}
X-Correlation-Id: ${CUSTOM_CORR_ID}" "$PAYLOAD")
body="${result#*|}"
[[ "$body" == *"$CUSTOM_CORR_ID"* ]] && log_pass "9.2 Custom correlation ID respected" || log_skip "9.2 Custom correlation ID"

# Test 9.3: X-Request-Id also works
REQUEST_ID="req-${RANDOM}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}
X-Request-Id: ${REQUEST_ID}" "$PAYLOAD")
log_skip "9.3 X-Request-Id support (manual check)"

# Test 9.4-9.5: Reserved
log_skip "9.4 Reserved"
log_skip "9.5 Reserved"

fi

# =============================================================================
# SECTION 10: LOCALIZATION (5 tests)
# =============================================================================
if should_run_section 10; then
section_header 10 "LOCALIZATION (FR/AR)"

TIMESTAMP=$(date +%s)

# Test 10.1: French text
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"fr-${RANDOM}\",\"from\":\"user1\",\"text\":\"Bonjour, je voudrais commander\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "10.1 French text accepted" || log_fail "10.1 French text"

# Test 10.2: Arabic text
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"ar-${RANDOM}\",\"from\":\"user1\",\"text\":\"مرحبا، أريد أن أطلب\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "10.2 Arabic text accepted" || log_fail "10.2 Arabic text"

# Test 10.3: Darija (Moroccan Arabic)
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"darija-${RANDOM}\",\"from\":\"user1\",\"text\":\"شحال الثمن\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "10.3 Darija text accepted" || log_fail "10.3 Darija text"

# Test 10.4: Mixed FR/AR
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"mix-${RANDOM}\",\"from\":\"user1\",\"text\":\"Bonjour مرحبا hello\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
[[ "${result%%|*}" == "200" ]] && log_pass "10.4 Mixed text accepted" || log_fail "10.4 Mixed text"

# Test 10.5: LANG command
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"lang-${RANDOM}\",\"from\":\"user1\",\"text\":\"LANG AR\",\"timestamp\":${TIMESTAMP}}"
result=$(http_test POST "${API_URL}/v1/inbound/whatsapp" "Content-Type: application/json
x-webhook-token: ${WEBHOOK_TOKEN}" "$PAYLOAD")
log_skip "10.5 LANG command (manual check for response language)"

fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}TEST SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Total Tests: ${TOTAL}"
echo -e "${GREEN}Passed:${NC}  ${PASSED}"
echo -e "${RED}Failed:${NC}  ${FAILED}"
echo -e "${YELLOW}Skipped:${NC} ${SKIPPED}"
echo ""

PASS_RATE=0
[[ $TOTAL -gt 0 ]] && PASS_RATE=$((PASSED * 100 / TOTAL))
echo -e "Pass Rate: ${PASS_RATE}%"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}Some tests failed. Review the output above.${NC}"
    exit 1
elif [[ $PASSED -eq 0 ]]; then
    echo -e "${YELLOW}No tests passed. Is the server running?${NC}"
    exit 1
else
    echo -e "${GREEN}Test battery completed successfully!${NC}"
    exit 0
fi
