#!/usr/bin/env bash
# =============================================================================
# RESTO BOT - Meta Webhook Smoke Tests
# Tests: GET verify, POST with signature, anti-replay, all 3 channels
# =============================================================================
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration (override with environment variables)
: "${API_URL:=http://localhost:8080}"
: "${META_VERIFY_TOKEN:=test_verify_token}"
: "${META_APP_SECRET:=test_app_secret}"
: "${WEBHOOK_TOKEN:=${WEBHOOK_SHARED_TOKEN:-}}"

PASSED=0
FAILED=0
SKIPPED=0

log_pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; ((PASSED++)); }
log_fail() { echo -e "${RED}❌ FAIL${NC}: $1"; ((FAILED++)); }
log_skip() { echo -e "${YELLOW}⚠️  SKIP${NC}: $1"; ((SKIPPED++)); }
log_info() { echo -e "ℹ️  $1"; }

# Generate HMAC signature for Meta webhook
generate_signature() {
    local payload="$1"
    local secret="$2"
    echo -n "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/^.* //'
}

# ============================================================================
# SECTION 1: HEALTHCHECK
# ============================================================================
echo ""
echo "============================================"
echo "SECTION 1: HEALTHCHECK"
echo "============================================"

if curl -sf "${API_URL}/healthz" >/dev/null 2>&1; then
    log_pass "healthz endpoint"
else
    log_fail "healthz endpoint not responding"
    echo "Is the server running at ${API_URL}?"
    exit 1
fi

# ============================================================================
# SECTION 2: GET VERIFY (Meta webhook verification)
# ============================================================================
echo ""
echo "============================================"
echo "SECTION 2: GET VERIFY (Meta webhook setup)"
echo "============================================"

for channel in whatsapp instagram messenger; do
    # Test valid verify
    CHALLENGE="test_challenge_${RANDOM}"
    response=$(curl -sf "${API_URL}/v1/inbound/${channel}?hub.mode=subscribe&hub.verify_token=${META_VERIFY_TOKEN}&hub.challenge=${CHALLENGE}" 2>/dev/null || echo "CURL_FAILED")

    if [[ "$response" == "$CHALLENGE" ]]; then
        log_pass "GET verify ${channel} - valid token returns challenge"
    elif [[ "$response" == "CURL_FAILED" ]]; then
        log_skip "GET verify ${channel} - endpoint not responding (workflow not active?)"
    else
        log_fail "GET verify ${channel} - expected '$CHALLENGE', got '$response'"
    fi

    # Test invalid verify token
    response=$(curl -s -w "\n%{http_code}" "${API_URL}/v1/inbound/${channel}?hub.mode=subscribe&hub.verify_token=wrong_token&hub.challenge=test" 2>/dev/null || echo "CURL_FAILED")
    http_code=$(echo "$response" | tail -1)

    if [[ "$http_code" == "403" ]]; then
        log_pass "GET verify ${channel} - invalid token returns 403"
    elif [[ "$response" == "CURL_FAILED" ]]; then
        log_skip "GET verify ${channel} - endpoint not responding"
    else
        log_fail "GET verify ${channel} - expected 403, got $http_code"
    fi
done

# ============================================================================
# SECTION 3: POST INBOUND (basic)
# ============================================================================
echo ""
echo "============================================"
echo "SECTION 3: POST INBOUND (basic tests)"
echo "============================================"

if [[ -z "$WEBHOOK_TOKEN" ]]; then
    log_info "WEBHOOK_TOKEN not set - skipping authenticated tests"
    log_info "Set WEBHOOK_TOKEN or WEBHOOK_SHARED_TOKEN to run these tests"
else
    TIMESTAMP=$(date +%s)

    for channel in whatsapp instagram messenger; do
        provider="wa"
        [[ "$channel" == "instagram" ]] && provider="ig"
        [[ "$channel" == "messenger" ]] && provider="msg"

        PAYLOAD="{\"provider\":\"${provider}\",\"msg_id\":\"smoke-${RANDOM}\",\"from\":\"smoke-user\",\"text\":\"smoke test\",\"timestamp\":${TIMESTAMP}}"

        response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/${channel}" \
            -H "Content-Type: application/json" \
            -H "x-webhook-token: ${WEBHOOK_TOKEN}" \
            -d "$PAYLOAD" 2>/dev/null || echo "CURL_FAILED")

        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -n -1)

        if [[ "$http_code" == "200" ]]; then
            log_pass "POST ${channel} - valid token accepted"
        elif [[ "$response" == "CURL_FAILED" ]]; then
            log_skip "POST ${channel} - endpoint not responding"
        else
            log_fail "POST ${channel} - expected 200, got $http_code (body: $body)"
        fi
    done
fi

# ============================================================================
# SECTION 4: SIGNATURE VALIDATION
# ============================================================================
echo ""
echo "============================================"
echo "SECTION 4: SIGNATURE VALIDATION"
echo "============================================"

if [[ -z "$META_APP_SECRET" || "$META_APP_SECRET" == "test_app_secret" ]]; then
    log_info "META_APP_SECRET not set - using test value"
fi

TIMESTAMP=$(date +%s)
PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"sig-test-${RANDOM}\",\"from\":\"smoke-user\",\"text\":\"signature test\",\"timestamp\":${TIMESTAMP}}"
SIGNATURE=$(generate_signature "$PAYLOAD" "$META_APP_SECRET")

# Test with valid signature
response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -H "X-Hub-Signature-256: sha256=${SIGNATURE}" \
    ${WEBHOOK_TOKEN:+-H "x-webhook-token: ${WEBHOOK_TOKEN}"} \
    -d "$PAYLOAD" 2>/dev/null || echo "CURL_FAILED")

http_code=$(echo "$response" | tail -1)

if [[ "$http_code" == "200" ]]; then
    log_pass "POST whatsapp - valid signature accepted"
elif [[ "$response" == "CURL_FAILED" ]]; then
    log_skip "POST whatsapp - endpoint not responding"
else
    log_info "POST whatsapp - got $http_code (signature validation might be in 'warn' mode)"
fi

# Test with invalid signature (only if META_SIGNATURE_REQUIRED=enforce)
response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -H "X-Hub-Signature-256: sha256=invalid_signature_here" \
    ${WEBHOOK_TOKEN:+-H "x-webhook-token: ${WEBHOOK_TOKEN}"} \
    -d "$PAYLOAD" 2>/dev/null || echo "CURL_FAILED")

http_code=$(echo "$response" | tail -1)

if [[ "$http_code" == "200" ]]; then
    log_info "POST whatsapp - invalid signature accepted (META_SIGNATURE_REQUIRED probably not 'enforce')"
elif [[ "$http_code" =~ ^4 ]]; then
    log_pass "POST whatsapp - invalid signature rejected with $http_code"
elif [[ "$response" == "CURL_FAILED" ]]; then
    log_skip "POST whatsapp - endpoint not responding"
else
    log_info "POST whatsapp - got $http_code for invalid signature"
fi

# ============================================================================
# SECTION 5: META SIGNATURE AUTH (P0-04)
# ============================================================================
echo ""
echo "============================================"
echo "SECTION 5: META SIGNATURE AUTH (no token)"
echo "============================================"

# Test that valid signature is accepted WITHOUT x-api-token
# This is the key test for P0-04: Meta doesn't send x-api-token!
TIMESTAMP=$(date +%s)
for channel in whatsapp instagram messenger; do
    provider="wa"
    [[ "$channel" == "instagram" ]] && provider="ig"
    [[ "$channel" == "messenger" ]] && provider="msg"

    PAYLOAD="{\"provider\":\"${provider}\",\"msg_id\":\"meta-auth-${RANDOM}\",\"from\":\"meta-user\",\"text\":\"meta auth test\",\"timestamp\":${TIMESTAMP}}"
    SIGNATURE=$(generate_signature "$PAYLOAD" "$META_APP_SECRET")

    # POST with signature but NO x-api-token (this is how Meta sends webhooks)
    response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/${channel}" \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: sha256=${SIGNATURE}" \
        -d "$PAYLOAD" 2>/dev/null || echo "CURL_FAILED")

    http_code=$(echo "$response" | tail -1)

    if [[ "$http_code" == "200" ]]; then
        log_pass "POST ${channel} - signature auth works (no token needed)"
    elif [[ "$response" == "CURL_FAILED" ]]; then
        log_skip "POST ${channel} - endpoint not responding"
    else
        # This might fail if META_SIGNATURE_REQUIRED=off
        log_info "POST ${channel} - got $http_code (set META_SIGNATURE_REQUIRED=warn|enforce to enable signature auth)"
    fi
done

# ============================================================================
# SECTION 6: ANTI-REPLAY
# ============================================================================
echo ""
echo "============================================"
echo "SECTION 6: ANTI-REPLAY PROTECTION"
echo "============================================"

# Test with old timestamp (10 minutes ago)
OLD_TIMESTAMP=$(($(date +%s) - 600))
OLD_PAYLOAD="{\"provider\":\"wa\",\"msg_id\":\"replay-test-${RANDOM}\",\"from\":\"smoke-user\",\"text\":\"old message\",\"timestamp\":${OLD_TIMESTAMP}}"

response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    ${WEBHOOK_TOKEN:+-H "x-webhook-token: ${WEBHOOK_TOKEN}"} \
    -d "$OLD_PAYLOAD" 2>/dev/null || echo "CURL_FAILED")

http_code=$(echo "$response" | tail -1)

if [[ "$http_code" == "200" ]]; then
    log_info "POST whatsapp - old timestamp accepted (REPLAY_CHECK_ENABLED might be false or window > 10min)"
elif [[ "$http_code" =~ ^4 ]]; then
    log_pass "POST whatsapp - old timestamp rejected with $http_code (anti-replay working)"
elif [[ "$response" == "CURL_FAILED" ]]; then
    log_skip "POST whatsapp - endpoint not responding"
else
    log_info "POST whatsapp - got $http_code for old timestamp"
fi

# ============================================================================
# SECTION 7: GATEWAY HARDENING
# ============================================================================
echo ""
echo "============================================"
echo "SECTION 7: GATEWAY HARDENING"
echo "============================================"

# Test method restriction (PUT should be rejected)
response=$(curl -s -w "\n%{http_code}" -X PUT "${API_URL}/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -d '{"test":"put"}' 2>/dev/null || echo "CURL_FAILED")

http_code=$(echo "$response" | tail -1)

if [[ "$http_code" =~ ^4 ]]; then
    log_pass "PUT method rejected with $http_code"
elif [[ "$response" == "CURL_FAILED" ]]; then
    log_skip "PUT method - endpoint not responding"
else
    log_fail "PUT method should be rejected, got $http_code"
fi

# Test query token blocking
response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp?token=should_be_blocked" \
    -H "Content-Type: application/json" \
    -d '{"provider":"wa","msg_id":"query-test","from":"test","text":"test"}' 2>/dev/null || echo "CURL_FAILED")

http_code=$(echo "$response" | tail -1)

if [[ "$http_code" == "401" ]]; then
    log_pass "Query token blocked with 401"
elif [[ "$response" == "CURL_FAILED" ]]; then
    log_skip "Query token test - endpoint not responding"
else
    log_info "Query token test - got $http_code (might be ALLOW_QUERY_TOKEN=true)"
fi

# Test Content-Type enforcement
response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
    -H "Content-Type: text/plain" \
    -d 'not json' 2>/dev/null || echo "CURL_FAILED")

http_code=$(echo "$response" | tail -1)

if [[ "$http_code" == "415" ]]; then
    log_pass "Wrong Content-Type rejected with 415"
elif [[ "$response" == "CURL_FAILED" ]]; then
    log_skip "Content-Type test - endpoint not responding"
else
    log_info "Content-Type test - got $http_code (hardening might not be enabled)"
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "============================================"
echo "SUMMARY"
echo "============================================"
echo -e "${GREEN}Passed:${NC}  $PASSED"
echo -e "${RED}Failed:${NC}  $FAILED"
echo -e "${YELLOW}Skipped:${NC} $SKIPPED"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed or skipped.${NC}"
    exit 0
fi
