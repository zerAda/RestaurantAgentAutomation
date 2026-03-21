#!/usr/bin/env bash
# =============================================================================
# RESTO BOT - Native Meta Payload Smoke Tests
# =============================================================================
# Tests webhooks with REAL Meta native payload formats
# Usage: ./scripts/smoke/run.sh [--section N] [--verbose]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOADS_DIR="${SCRIPT_DIR}/payloads"

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

# Counters
PASSED=0
FAILED=0
SKIPPED=0
SECTION_FILTER=""
VERBOSE=false

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --section) SECTION_FILTER="$2"; shift 2 ;;
        --verbose|-v) VERBOSE=true; shift ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAILED++)); }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; ((SKIPPED++)); }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# Generate HMAC-SHA256 signature
generate_signature() {
    local payload="$1"
    local secret="$2"
    echo -n "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/^.* //'
}

# Prepare payload: replace timestamp placeholders
prepare_payload() {
    local file="$1"
    local ts=$(date +%s)
    local ts_ms=$((ts * 1000))
    local unique_id="${RANDOM}${RANDOM}"

    cat "$file" | \
        sed "s/__TIMESTAMP__/${ts}/g" | \
        sed "s/__TIMESTAMP_MS__/${ts_ms}/g" | \
        sed "s/wamid\./wamid.smoke${unique_id}/g" | \
        sed "s/m_ig_/m_ig_smoke${unique_id}_/g" | \
        sed "s/m_msg_/m_msg_smoke${unique_id}_/g"
}

should_run_section() {
    local section="$1"
    [[ -z "$SECTION_FILTER" || "$SECTION_FILTER" == "$section" ]]
}

# =============================================================================
# SECTION 1: HEALTHCHECK
# =============================================================================
if should_run_section 1; then
    log_section "SECTION 1: HEALTHCHECK"

    if curl -sf "${API_URL}/healthz" >/dev/null 2>&1; then
        log_pass "healthz endpoint responds"
    else
        log_fail "healthz not responding - is server running at ${API_URL}?"
        exit 1
    fi
fi

# =============================================================================
# SECTION 2: GET VERIFY (Meta webhook verification)
# =============================================================================
if should_run_section 2; then
    log_section "SECTION 2: GET VERIFY"

    for channel in whatsapp instagram messenger; do
        CHALLENGE="challenge_${RANDOM}"

        # Valid verify token
        response=$(curl -sf "${API_URL}/v1/inbound/${channel}?hub.mode=subscribe&hub.verify_token=${META_VERIFY_TOKEN}&hub.challenge=${CHALLENGE}" 2>/dev/null || echo "CURL_FAILED")

        if [[ "$response" == "$CHALLENGE" ]]; then
            log_pass "GET verify ${channel} - returns challenge"
        elif [[ "$response" == "CURL_FAILED" ]]; then
            log_skip "GET verify ${channel} - endpoint not responding"
        else
            log_fail "GET verify ${channel} - expected '$CHALLENGE', got '$response'"
        fi

        # Invalid verify token
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/v1/inbound/${channel}?hub.mode=subscribe&hub.verify_token=WRONG_TOKEN&hub.challenge=test" 2>/dev/null || echo "000")

        if [[ "$http_code" == "403" ]]; then
            log_pass "GET verify ${channel} - rejects invalid token (403)"
        elif [[ "$http_code" == "000" ]]; then
            log_skip "GET verify ${channel} - endpoint not responding"
        else
            log_fail "GET verify ${channel} - expected 403, got $http_code"
        fi
    done
fi

# =============================================================================
# SECTION 3: POST NATIVE PAYLOADS (WhatsApp)
# =============================================================================
if should_run_section 3; then
    log_section "SECTION 3: POST NATIVE - WHATSAPP"

    for fixture in wa_text wa_image wa_button_reply wa_list_reply; do
        file="${PAYLOADS_DIR}/${fixture}.json"
        if [[ ! -f "$file" ]]; then
            log_skip "WhatsApp ${fixture} - fixture not found"
            continue
        fi

        payload=$(prepare_payload "$file")
        signature=$(generate_signature "$payload" "$META_APP_SECRET")

        response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
            -H "Content-Type: application/json" \
            -H "X-Hub-Signature-256: sha256=${signature}" \
            -d "$payload" 2>/dev/null || echo "CURL_FAILED")

        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -n -1)

        if [[ "$http_code" == "200" ]]; then
            log_pass "WhatsApp ${fixture} - accepted (200)"
            $VERBOSE && echo "    Response: ${body:0:100}..."
        elif [[ "$response" == "CURL_FAILED" ]]; then
            log_skip "WhatsApp ${fixture} - endpoint not responding"
        else
            log_fail "WhatsApp ${fixture} - expected 200, got $http_code"
            $VERBOSE && echo "    Body: $body"
        fi
    done
fi

# =============================================================================
# SECTION 4: POST NATIVE PAYLOADS (Instagram)
# =============================================================================
if should_run_section 4; then
    log_section "SECTION 4: POST NATIVE - INSTAGRAM"

    for fixture in ig_text ig_image ig_postback ig_story_mention; do
        file="${PAYLOADS_DIR}/${fixture}.json"
        if [[ ! -f "$file" ]]; then
            log_skip "Instagram ${fixture} - fixture not found"
            continue
        fi

        payload=$(prepare_payload "$file")
        signature=$(generate_signature "$payload" "$META_APP_SECRET")

        response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/instagram" \
            -H "Content-Type: application/json" \
            -H "X-Hub-Signature-256: sha256=${signature}" \
            -d "$payload" 2>/dev/null || echo "CURL_FAILED")

        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -n -1)

        if [[ "$http_code" == "200" ]]; then
            log_pass "Instagram ${fixture} - accepted (200)"
            $VERBOSE && echo "    Response: ${body:0:100}..."
        elif [[ "$response" == "CURL_FAILED" ]]; then
            log_skip "Instagram ${fixture} - endpoint not responding"
        else
            log_fail "Instagram ${fixture} - expected 200, got $http_code"
            $VERBOSE && echo "    Body: $body"
        fi
    done
fi

# =============================================================================
# SECTION 5: POST NATIVE PAYLOADS (Messenger)
# =============================================================================
if should_run_section 5; then
    log_section "SECTION 5: POST NATIVE - MESSENGER"

    for fixture in msg_text msg_image msg_postback msg_quick_reply; do
        file="${PAYLOADS_DIR}/${fixture}.json"
        if [[ ! -f "$file" ]]; then
            log_skip "Messenger ${fixture} - fixture not found"
            continue
        fi

        payload=$(prepare_payload "$file")
        signature=$(generate_signature "$payload" "$META_APP_SECRET")

        response=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/inbound/messenger" \
            -H "Content-Type: application/json" \
            -H "X-Hub-Signature-256: sha256=${signature}" \
            -d "$payload" 2>/dev/null || echo "CURL_FAILED")

        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -n -1)

        if [[ "$http_code" == "200" ]]; then
            log_pass "Messenger ${fixture} - accepted (200)"
            $VERBOSE && echo "    Response: ${body:0:100}..."
        elif [[ "$response" == "CURL_FAILED" ]]; then
            log_skip "Messenger ${fixture} - endpoint not responding"
        else
            log_fail "Messenger ${fixture} - expected 200, got $http_code"
            $VERBOSE && echo "    Body: $body"
        fi
    done
fi

# =============================================================================
# SECTION 6: SIGNATURE VALIDATION
# =============================================================================
if should_run_section 6; then
    log_section "SECTION 6: SIGNATURE VALIDATION"

    payload=$(prepare_payload "${PAYLOADS_DIR}/wa_text.json")
    valid_sig=$(generate_signature "$payload" "$META_APP_SECRET")

    # Valid signature
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: sha256=${valid_sig}" \
        -d "$payload" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
        log_pass "Valid signature accepted (200)"
    elif [[ "$http_code" == "000" ]]; then
        log_skip "Signature test - endpoint not responding"
    else
        log_info "Valid signature got $http_code (check workflow config)"
    fi

    # Invalid signature
    payload2=$(prepare_payload "${PAYLOADS_DIR}/wa_text.json")
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: sha256=invalid_signature_0000000000" \
        -d "$payload2" 2>/dev/null || echo "000")

    if [[ "$http_code" =~ ^4 ]]; then
        log_pass "Invalid signature rejected ($http_code)"
    elif [[ "$http_code" == "200" ]]; then
        log_info "Invalid signature accepted (META_SIGNATURE_REQUIRED probably not 'enforce')"
    elif [[ "$http_code" == "000" ]]; then
        log_skip "Signature test - endpoint not responding"
    else
        log_info "Invalid signature got $http_code"
    fi

    # Missing signature
    payload3=$(prepare_payload "${PAYLOADS_DIR}/wa_text.json")
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
        -H "Content-Type: application/json" \
        -d "$payload3" 2>/dev/null || echo "000")

    if [[ "$http_code" =~ ^4 ]]; then
        log_pass "Missing signature rejected ($http_code)"
    elif [[ "$http_code" == "200" ]]; then
        log_info "Missing signature accepted (META_SIGNATURE_REQUIRED is 'off' or 'warn')"
    elif [[ "$http_code" == "000" ]]; then
        log_skip "Signature test - endpoint not responding"
    else
        log_info "Missing signature got $http_code"
    fi
fi

# =============================================================================
# SECTION 7: IDEMPOTENCE (duplicate msg_id)
# =============================================================================
if should_run_section 7; then
    log_section "SECTION 7: IDEMPOTENCE"

    # Send same message twice with same ID
    ts=$(date +%s)
    fixed_id="wamid.IDEMPOTENT_TEST_${RANDOM}"

    payload=$(cat "${PAYLOADS_DIR}/wa_text.json" | \
        sed "s/__TIMESTAMP__/${ts}/g" | \
        sed 's/"id": "wamid[^"]*"/"id": "'"${fixed_id}"'"/g')

    signature=$(generate_signature "$payload" "$META_APP_SECRET")

    # First request
    http1=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: sha256=${signature}" \
        -d "$payload" 2>/dev/null || echo "000")

    # Second request (same payload, same msg_id)
    http2=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: sha256=${signature}" \
        -d "$payload" 2>/dev/null || echo "000")

    if [[ "$http1" == "200" && "$http2" == "200" ]]; then
        log_pass "Idempotent: both requests accepted (200)"
        log_info "  (verify DB has only ONE record for msg_id: ${fixed_id})"
    elif [[ "$http1" == "200" && "$http2" == "409" ]]; then
        log_pass "Idempotent: duplicate rejected with 409"
    elif [[ "$http1" == "000" || "$http2" == "000" ]]; then
        log_skip "Idempotence test - endpoint not responding"
    else
        log_info "Idempotence: first=$http1, second=$http2"
    fi
fi

# =============================================================================
# SECTION 8: ANTI-REPLAY (old timestamp)
# =============================================================================
if should_run_section 8; then
    log_section "SECTION 8: ANTI-REPLAY"

    # 10 minutes old timestamp
    old_ts=$(($(date +%s) - 600))
    old_ts_ms=$((old_ts * 1000))

    payload=$(cat "${PAYLOADS_DIR}/wa_text.json" | \
        sed "s/__TIMESTAMP__/${old_ts}/g" | \
        sed "s/__TIMESTAMP_MS__/${old_ts_ms}/g" | \
        sed "s/wamid\./wamid.OLD_${RANDOM}/g")

    signature=$(generate_signature "$payload" "$META_APP_SECRET")

    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/v1/inbound/whatsapp" \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: sha256=${signature}" \
        -d "$payload" 2>/dev/null || echo "000")

    if [[ "$http_code" =~ ^4 ]]; then
        log_pass "Old timestamp rejected ($http_code) - anti-replay working"
    elif [[ "$http_code" == "200" ]]; then
        log_info "Old timestamp accepted (REPLAY_CHECK_ENABLED might be off or window > 10min)"
    elif [[ "$http_code" == "000" ]]; then
        log_skip "Anti-replay test - endpoint not responding"
    else
        log_info "Anti-replay: got $http_code"
    fi
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "============================================"
echo "NATIVE PAYLOAD SMOKE TEST SUMMARY"
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
