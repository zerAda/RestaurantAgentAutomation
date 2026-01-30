#!/bin/bash
# P0-07: Test Outbound Workflows (W5/W6/W7) with Outbox + DLQ
# Usage: ./scripts/test_outbound.sh [mock_api_url]

set -e

MOCK_API_URL="${1:-http://localhost:8080}"
UNIQUE_ID="outbound_test_$(date +%s)_$$"

echo "=== P0-07: Outbound Workflow Tests ==="
echo "Mock API URL: $MOCK_API_URL"
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

# =============================================================================
# Test 1: Verify env vars are documented
# =============================================================================
echo "=== Test 1: Environment Variables Documentation ==="

ENV_EXAMPLE="./config/.env.example"
if [ -f "$ENV_EXAMPLE" ]; then
    for var in GRAPH_API_VERSION OUTBOX_MAX_ATTEMPTS OUTBOX_BASE_DELAY_SEC OUTBOX_MAX_DELAY_SEC OUTBOX_REDIS_TTL_SEC; do
        if grep -q "^${var}=" "$ENV_EXAMPLE" || grep -q "^# ${var}" "$ENV_EXAMPLE" || grep -q "${var}" "$ENV_EXAMPLE"; then
            pass "$var documented in .env.example"
        else
            fail "$var NOT found in .env.example"
        fi
    done
else
    info ".env.example not found at expected path"
fi

echo ""

# =============================================================================
# Test 2: Verify workflow JSON structure
# =============================================================================
echo "=== Test 2: Workflow JSON Structure ==="

for workflow in W5_OUT_WA W6_OUT_IG W7_OUT_MSG; do
    file="./workflows/${workflow}.json"
    if [ -f "$file" ]; then
        # Check valid JSON
        if python3 -c "import json; json.load(open('$file'))" 2>/dev/null; then
            pass "$workflow is valid JSON"
        else
            fail "$workflow is NOT valid JSON"
            continue
        fi

        # Check for required nodes
        for node in "Prepare Outbox" "Store in Outbox" "Send Message" "Send OK?" "Clear Outbox" "Prepare DLQ" "Push to DLQ"; do
            if grep -q "$node" "$file"; then
                pass "$workflow contains '$node' node"
            else
                fail "$workflow missing '$node' node"
            fi
        done
    else
        fail "$workflow.json not found"
    fi
done

echo ""

# =============================================================================
# Test 3: Check Redis Outbox keys (if Redis available)
# =============================================================================
echo "=== Test 3: Redis Outbox Pattern ==="

if command -v docker &> /dev/null; then
    # Set a test outbox key
    test_key="ralphe:outbox:wa:test_${UNIQUE_ID}"
    test_value='{"status":"pending","attempts":0}'

    result=$(docker exec redis redis-cli SET "$test_key" "$test_value" EX 60 2>/dev/null || echo "REDIS_ERROR")
    if [ "$result" = "OK" ]; then
        pass "Can SET outbox key: $test_key"

        # Verify GET
        get_result=$(docker exec redis redis-cli GET "$test_key" 2>/dev/null || echo "")
        if [ "$get_result" = "$test_value" ]; then
            pass "Can GET outbox key"
        else
            fail "GET returned unexpected value"
        fi

        # Test DELETE
        del_result=$(docker exec redis redis-cli DEL "$test_key" 2>/dev/null || echo "0")
        if [ "$del_result" = "1" ]; then
            pass "Can DELETE outbox key"
        else
            fail "DELETE failed"
        fi
    else
        info "Redis not accessible - skipping outbox key tests"
    fi
else
    info "Docker not available - skipping Redis tests"
fi

echo ""

# =============================================================================
# Test 4: Check Redis DLQ operations (if Redis available)
# =============================================================================
echo "=== Test 4: Redis DLQ Pattern ==="

if command -v docker &> /dev/null; then
    dlq_key="ralphe:dlq"
    dlq_entry='{"channel":"test","error":"TEST_ERROR","timestamp":"2026-01-29T00:00:00Z"}'

    # Push to DLQ
    push_result=$(docker exec redis redis-cli RPUSH "$dlq_key" "$dlq_entry" 2>/dev/null || echo "ERROR")
    if [[ "$push_result" =~ ^[0-9]+$ ]]; then
        pass "Can RPUSH to DLQ (length: $push_result)"

        # Pop from DLQ (cleanup)
        pop_result=$(docker exec redis redis-cli RPOP "$dlq_key" 2>/dev/null || echo "")
        if [ "$pop_result" = "$dlq_entry" ]; then
            pass "Can RPOP from DLQ"
        else
            info "RPOP returned different entry (might be from other test)"
        fi
    else
        info "Redis DLQ not accessible - skipping DLQ tests"
    fi

    # Check DLQ length
    dlq_len=$(docker exec redis redis-cli LLEN "$dlq_key" 2>/dev/null || echo "ERROR")
    if [[ "$dlq_len" =~ ^[0-9]+$ ]]; then
        info "Current DLQ length: $dlq_len"
        if [ "$dlq_len" -gt 10 ]; then
            echo -e "${YELLOW}WARNING${NC}: DLQ has $dlq_len entries - consider investigating"
        fi
    fi
else
    info "Docker not available - skipping DLQ tests"
fi

echo ""

# =============================================================================
# Test 5: Mock API Send Tests
# =============================================================================
echo "=== Test 5: Mock API Send Tests ==="

# Test WhatsApp mock
wa_body='{"channel":"whatsapp","to":"212600000000","text":"Test message","restaurantId":"test_rest"}'
response=$(curl -s -w "\n%{http_code}" -X POST "$MOCK_API_URL/send/wa" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test_token" \
    -d "$wa_body" 2>/dev/null || echo -e "\n000")
status=$(echo "$response" | tail -n1)
if [ "$status" = "200" ]; then
    pass "WhatsApp mock send accepted (HTTP $status)"
else
    info "WhatsApp mock send returned HTTP $status (mock may not be running)"
fi

# Test Instagram mock
ig_body='{"channel":"instagram","to":"ig_user_123","text":"Test message","restaurantId":"test_rest"}'
response=$(curl -s -w "\n%{http_code}" -X POST "$MOCK_API_URL/send/ig" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test_token" \
    -d "$ig_body" 2>/dev/null || echo -e "\n000")
status=$(echo "$response" | tail -n1)
if [ "$status" = "200" ]; then
    pass "Instagram mock send accepted (HTTP $status)"
else
    info "Instagram mock send returned HTTP $status (mock may not be running)"
fi

# Test Messenger mock
msg_body='{"channel":"messenger","to":"psid_123","text":"Test message","restaurantId":"test_rest"}'
response=$(curl -s -w "\n%{http_code}" -X POST "$MOCK_API_URL/send/msg" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test_token" \
    -d "$msg_body" 2>/dev/null || echo -e "\n000")
status=$(echo "$response" | tail -n1)
if [ "$status" = "200" ]; then
    pass "Messenger mock send accepted (HTTP $status)"
else
    info "Messenger mock send returned HTTP $status (mock may not be running)"
fi

echo ""

# =============================================================================
# Test 6: Verify GRAPH_API_VERSION in workflows
# =============================================================================
echo "=== Test 6: GRAPH_API_VERSION Consistency ==="

for workflow in W5_OUT_WA W6_OUT_IG W7_OUT_MSG; do
    file="./workflows/${workflow}.json"
    if [ -f "$file" ]; then
        if grep -q "GRAPH_API_VERSION" "$file"; then
            pass "$workflow uses GRAPH_API_VERSION env var"
        else
            fail "$workflow does NOT use GRAPH_API_VERSION"
        fi
    fi
done

echo ""

# =============================================================================
# Test 7: Verify retry/backoff configuration
# =============================================================================
echo "=== Test 7: Retry/Backoff Configuration ==="

for workflow in W5_OUT_WA W6_OUT_IG W7_OUT_MSG; do
    file="./workflows/${workflow}.json"
    if [ -f "$file" ]; then
        # Check for OUTBOX_MAX_ATTEMPTS
        if grep -q "OUTBOX_MAX_ATTEMPTS" "$file"; then
            pass "$workflow uses OUTBOX_MAX_ATTEMPTS"
        else
            fail "$workflow does NOT use OUTBOX_MAX_ATTEMPTS"
        fi

        # Check for exponential backoff pattern
        if grep -q "Math.pow" "$file" && grep -q "maxDelay" "$file"; then
            pass "$workflow has exponential backoff with maxDelay cap"
        else
            info "$workflow backoff pattern could not be verified"
        fi
    fi
done

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "=== Outbound Workflow Tests Complete ==="
echo ""
echo "Workflow structure:"
echo "  IN → Prepare Outbox → Store in Redis → Send Message → Check Result"
echo "  ├─ Success → Clear Outbox → END"
echo "  └─ Failure → Prepare DLQ → Push to DLQ → Clear Outbox → END"
echo ""
echo "Environment variables:"
echo "  GRAPH_API_VERSION     - Meta Graph API version (default: v21.0)"
echo "  OUTBOX_MAX_ATTEMPTS   - Max retry attempts (default: 3)"
echo "  OUTBOX_BASE_DELAY_SEC - Base delay for retries (default: 1)"
echo "  OUTBOX_MAX_DELAY_SEC  - Max delay cap (default: 60)"
echo "  OUTBOX_REDIS_TTL_SEC  - Outbox entry TTL (default: 604800 = 7 days)"
echo ""
echo "Redis keys:"
echo "  ralphe:outbox:{channel}:{msgId} - Pending messages"
echo "  ralphe:dlq                       - Dead letter queue (LIST)"
echo ""
echo "To monitor DLQ: docker exec redis redis-cli LLEN ralphe:dlq"
echo "To inspect DLQ: docker exec redis redis-cli LRANGE ralphe:dlq 0 9"
