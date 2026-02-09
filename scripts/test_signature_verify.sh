#!/bin/bash
# P0-03: Test Meta X-Hub-Signature-256 validation for WA/IG/MSG
# Usage: ./scripts/test_signature_verify.sh [base_url]

set -e

BASE_URL="${1:-http://localhost:5678/webhook}"
APP_SECRET="${META_APP_SECRET:-test_secret_key_for_testing}"

echo "=== P0-03: Meta Signature Verification Tests ==="
echo "Base URL: $BASE_URL"
echo "App Secret: [REDACTED]"
echo ""

# Function to compute HMAC-SHA256 signature
compute_signature() {
    local body="$1"
    local secret="$2"
    echo -n "$body" | openssl dgst -sha256 -hmac "$secret" | sed 's/^.* /sha256=/'
}

# Function to test endpoint
test_endpoint() {
    local channel="$1"
    local endpoint="$2"
    local body="$3"
    local signature="$4"
    local expected_status="$5"
    local test_name="$6"

    echo -n "[$channel] $test_name: "

    if [ -n "$signature" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/$endpoint" \
            -H "Content-Type: application/json" \
            -H "X-Hub-Signature-256: $signature" \
            -d "$body" 2>/dev/null || echo -e "\n000")
    else
        response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$body" 2>/dev/null || echo -e "\n000")
    fi

    status_code=$(echo "$response" | tail -n1)

    if [ "$status_code" = "$expected_status" ]; then
        echo "PASS (HTTP $status_code)"
        return 0
    else
        echo "FAIL (expected $expected_status, got $status_code)"
        return 1
    fi
}

# Test payloads
WA_BODY='{"provider":"wa","from":"212600000000","msg_id":"test_sig_wa_1","text":"hello"}'
IG_BODY='{"provider":"ig","from":"ig_user_123","msg_id":"test_sig_ig_1","text":"hello"}'
MSG_BODY='{"provider":"msg","from":"psid_123","msg_id":"test_sig_msg_1","text":"hello"}'

# Compute valid signatures
WA_SIG=$(compute_signature "$WA_BODY" "$APP_SECRET")
IG_SIG=$(compute_signature "$IG_BODY" "$APP_SECRET")
MSG_SIG=$(compute_signature "$MSG_BODY" "$APP_SECRET")

# Invalid signature (wrong body used)
INVALID_SIG="sha256=0000000000000000000000000000000000000000000000000000000000000000"

echo "=== Test 1: Valid Signature (should PASS) ==="
test_endpoint "WA" "v1/inbound/whatsapp" "$WA_BODY" "$WA_SIG" "200" "Valid signature"
test_endpoint "IG" "v1/inbound/instagram" "$IG_BODY" "$IG_SIG" "200" "Valid signature"
test_endpoint "MSG" "v1/inbound/messenger" "$MSG_BODY" "$MSG_SIG" "200" "Valid signature"
echo ""

echo "=== Test 2: Invalid Signature (enforce mode -> 401) ==="
echo "Note: Set META_SIGNATURE_REQUIRED=enforce to test rejection"
test_endpoint "WA" "v1/inbound/whatsapp" "$WA_BODY" "$INVALID_SIG" "401" "Invalid signature" || true
test_endpoint "IG" "v1/inbound/instagram" "$IG_BODY" "$INVALID_SIG" "401" "Invalid signature" || true
test_endpoint "MSG" "v1/inbound/messenger" "$MSG_BODY" "$INVALID_SIG" "401" "Invalid signature" || true
echo ""

echo "=== Test 3: Missing Signature (enforce mode -> 401) ==="
echo "Note: Set META_SIGNATURE_REQUIRED=enforce to test rejection"
test_endpoint "WA" "v1/inbound/whatsapp" "$WA_BODY" "" "401" "Missing signature" || true
test_endpoint "IG" "v1/inbound/instagram" "$IG_BODY" "" "401" "Missing signature" || true
test_endpoint "MSG" "v1/inbound/messenger" "$MSG_BODY" "" "401" "Missing signature" || true
echo ""

echo "=== Test 4: Off Mode (should always PASS) ==="
echo "Note: Set META_SIGNATURE_REQUIRED=off to test passthrough"
test_endpoint "WA" "v1/inbound/whatsapp" "$WA_BODY" "" "200" "No sig, mode=off" || true
test_endpoint "IG" "v1/inbound/instagram" "$IG_BODY" "" "200" "No sig, mode=off" || true
test_endpoint "MSG" "v1/inbound/messenger" "$MSG_BODY" "" "200" "No sig, mode=off" || true
echo ""

echo "=== Signature Verification Tests Complete ==="
echo ""
echo "Summary of env var modes:"
echo "  META_SIGNATURE_REQUIRED=off     -> skip check, always pass"
echo "  META_SIGNATURE_REQUIRED=warn    -> check & log, but don't block"
echo "  META_SIGNATURE_REQUIRED=enforce -> reject if invalid/missing"
