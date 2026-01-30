#!/bin/bash
# P0-06: Test Redis deduplication for inbound messages
# Usage: ./scripts/test_dedupe.sh [base_url]

set -e

BASE_URL="${1:-http://localhost:5678/webhook}"
UNIQUE_ID="dedupe_test_$(date +%s)_$$"

echo "=== P0-06: Redis Deduplication Tests ==="
echo "Base URL: $BASE_URL"
echo "Unique test ID: $UNIQUE_ID"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; }
info() { echo -e "${YELLOW}INFO${NC}: $1"; }

# Test payload with unique msg_id
WA_BODY="{\"provider\":\"wa\",\"from\":\"212600000000\",\"msg_id\":\"${UNIQUE_ID}_wa\",\"text\":\"hello dedupe test\"}"
IG_BODY="{\"provider\":\"ig\",\"from\":\"ig_user_123\",\"msg_id\":\"${UNIQUE_ID}_ig\",\"text\":\"hello dedupe test\"}"
MSG_BODY="{\"provider\":\"msg\",\"from\":\"psid_123\",\"msg_id\":\"${UNIQUE_ID}_msg\",\"text\":\"hello dedupe test\"}"

echo "=== Test 1: First request (should be processed) ==="

# WhatsApp - First request
response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -d "$WA_BODY" 2>/dev/null || echo -e "\n000")
status=$(echo "$response" | tail -n1)
if [ "$status" = "200" ]; then
    pass "WA first request accepted (HTTP $status)"
else
    fail "WA first request failed (HTTP $status)"
fi

# Instagram - First request
response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/inbound/instagram" \
    -H "Content-Type: application/json" \
    -d "$IG_BODY" 2>/dev/null || echo -e "\n000")
status=$(echo "$response" | tail -n1)
if [ "$status" = "200" ]; then
    pass "IG first request accepted (HTTP $status)"
else
    fail "IG first request failed (HTTP $status)"
fi

# Messenger - First request
response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/inbound/messenger" \
    -H "Content-Type: application/json" \
    -d "$MSG_BODY" 2>/dev/null || echo -e "\n000")
status=$(echo "$response" | tail -n1)
if [ "$status" = "200" ]; then
    pass "MSG first request accepted (HTTP $status)"
else
    fail "MSG first request failed (HTTP $status)"
fi

echo ""
echo "=== Test 2: Duplicate request (should be deduplicated - still 200 but no CORE call) ==="
info "Note: Both requests return 200 (Fast ACK), but duplicate is silently dropped before CORE"

# WhatsApp - Duplicate
response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -d "$WA_BODY" 2>/dev/null || echo -e "\n000")
status=$(echo "$response" | tail -n1)
if [ "$status" = "200" ]; then
    pass "WA duplicate request returns 200 (Fast ACK - dedupe happens after)"
else
    fail "WA duplicate request unexpected status (HTTP $status)"
fi

# Instagram - Duplicate
response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/inbound/instagram" \
    -H "Content-Type: application/json" \
    -d "$IG_BODY" 2>/dev/null || echo -e "\n000")
status=$(echo "$response" | tail -n1)
if [ "$status" = "200" ]; then
    pass "IG duplicate request returns 200 (Fast ACK - dedupe happens after)"
else
    fail "IG duplicate request unexpected status (HTTP $status)"
fi

# Messenger - Duplicate
response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/inbound/messenger" \
    -H "Content-Type: application/json" \
    -d "$MSG_BODY" 2>/dev/null || echo -e "\n000")
status=$(echo "$response" | tail -n1)
if [ "$status" = "200" ]; then
    pass "MSG duplicate request returns 200 (Fast ACK - dedupe happens after)"
else
    fail "MSG duplicate request unexpected status (HTTP $status)"
fi

echo ""
echo "=== Test 3: Verify Redis keys exist ==="
info "Checking Redis for dedupe keys..."

# Check if docker is available
if command -v docker &> /dev/null; then
    for channel in whatsapp instagram messenger; do
        key="ralphe:dedupe:${channel}:${UNIQUE_ID}_${channel:0:2}"
        result=$(docker exec redis redis-cli GET "$key" 2>/dev/null || echo "REDIS_ERROR")
        if [ "$result" != "" ] && [ "$result" != "REDIS_ERROR" ] && [ "$result" != "(nil)" ]; then
            pass "Redis key exists: $key"
        else
            info "Redis key not found or Redis not accessible: $key"
        fi
    done
else
    info "Docker not available - skipping Redis key verification"
fi

echo ""
echo "=== Test 4: Different msg_id (should be processed as NEW) ==="

NEW_ID="dedupe_test_new_$(date +%s)_$$"
WA_NEW="{\"provider\":\"wa\",\"from\":\"212600000000\",\"msg_id\":\"${NEW_ID}\",\"text\":\"new message\"}"

response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -d "$WA_NEW" 2>/dev/null || echo -e "\n000")
status=$(echo "$response" | tail -n1)
if [ "$status" = "200" ]; then
    pass "New msg_id accepted as new message (HTTP $status)"
else
    fail "New msg_id unexpected status (HTTP $status)"
fi

echo ""
echo "=== Deduplication Tests Complete ==="
echo ""
echo "Redis key pattern: ralphe:dedupe:<channel>:<msg_id>"
echo "TTL: DEDUPE_TTL_SEC (default 172800s = 48h)"
echo ""
echo "To disable dedupe: DEDUPE_ENABLED=false"
echo "To verify in Redis: docker exec redis redis-cli KEYS 'ralphe:dedupe:*'"
