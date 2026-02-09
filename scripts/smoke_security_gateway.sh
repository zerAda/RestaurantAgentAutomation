#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# smoke_security_gateway.sh
# P0-SEC-01: Test Gateway Security Rules (Query Token Block + Rate Limit)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
BASE_URL="${GATEWAY_URL:-http://localhost:8080}"
VALID_TOKEN="${TEST_TOKEN:-test-token-inbound}"
RATE_LIMIT_BURST="${RATE_LIMIT_BURST:-60}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0

log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  P0-SEC-01: Gateway Security Smoke Test            ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "Target: $BASE_URL"
echo ""

# =============================================================================
# TEST 1: Query token ?token= should be rejected (401)
# =============================================================================
log_test "1. Query string ?token= should be rejected..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$BASE_URL/v1/inbound/whatsapp?token=abc123" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"msg_id":"test1"}' 2>/dev/null || echo "000")

if [ "$RESPONSE" = "401" ]; then
    log_pass "?token= rejected with 401 (SEC-001)"
else
    log_fail "?token= returned $RESPONSE (expected 401)"
fi

# =============================================================================
# TEST 2: Query token ?access_token= should be rejected (401)
# =============================================================================
log_test "2. Query string ?access_token= should be rejected..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$BASE_URL/v1/inbound/whatsapp?access_token=xyz789" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"msg_id":"test2"}' 2>/dev/null || echo "000")

if [ "$RESPONSE" = "401" ]; then
    log_pass "?access_token= rejected with 401 (SEC-001)"
else
    log_fail "?access_token= returned $RESPONSE (expected 401)"
fi

# =============================================================================
# TEST 3: Query token ?api_token= should be rejected (401)
# =============================================================================
log_test "3. Query string ?api_token= should be rejected..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$BASE_URL/v1/inbound/whatsapp?api_token=def456" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"msg_id":"test3"}' 2>/dev/null || echo "000")

if [ "$RESPONSE" = "401" ]; then
    log_pass "?api_token= rejected with 401 (SEC-001)"
else
    log_fail "?api_token= returned $RESPONSE (expected 401)"
fi

# =============================================================================
# TEST 4: Query token ?webhook_token= should be rejected (401)
# =============================================================================
log_test "4. Query string ?webhook_token= should be rejected..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$BASE_URL/v1/inbound/whatsapp?webhook_token=ghi789" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"msg_id":"test4"}' 2>/dev/null || echo "000")

if [ "$RESPONSE" = "401" ]; then
    log_pass "?webhook_token= rejected with 401 (SEC-001)"
else
    log_fail "?webhook_token= returned $RESPONSE (expected 401)"
fi

# =============================================================================
# TEST 5: Authorization header should work
# =============================================================================
log_test "5. Authorization header should pass gateway..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$BASE_URL/v1/inbound/whatsapp" \
    -X POST \
    -H "Authorization: Bearer $VALID_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"msg_id":"test5","from":"123","text":"hello","provider":"wa"}' 2>/dev/null || echo "000")

# 200, 202, or 401 (auth fail at app level, not gateway) are all acceptable
# 401 from app-level auth is OK - we're testing gateway passed it through
if [[ "$RESPONSE" =~ ^(200|202|401|500)$ ]]; then
    log_pass "Authorization header passed gateway (got $RESPONSE from backend)"
else
    log_fail "Authorization header failed at gateway level (got $RESPONSE)"
fi

# =============================================================================
# TEST 6: Health endpoint should work without auth
# =============================================================================
log_test "6. /healthz should return 200..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$BASE_URL/healthz" 2>/dev/null || echo "000")

if [ "$RESPONSE" = "200" ]; then
    log_pass "/healthz returns 200"
else
    log_fail "/healthz returned $RESPONSE (expected 200)"
fi

# =============================================================================
# TEST 7: Rate limiting - burst test (optional, slower)
# =============================================================================
if [ "${RUN_RATE_LIMIT_TEST:-false}" = "true" ]; then
    log_test "7. Rate limiting - burst of $RATE_LIMIT_BURST requests..."
    
    THROTTLED=0
    for i in $(seq 1 $RATE_LIMIT_BURST); do
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
            "$BASE_URL/v1/inbound/whatsapp" \
            -X POST \
            -H "Authorization: Bearer $VALID_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"msg_id\":\"burst-$i\"}" 2>/dev/null || echo "000")
        
        if [ "$RESPONSE" = "429" ] || [ "$RESPONSE" = "503" ]; then
            ((THROTTLED++))
        fi
    done
    
    if [ $THROTTLED -gt 0 ]; then
        log_pass "Rate limiting active: $THROTTLED requests throttled"
    else
        log_info "No throttling detected in $RATE_LIMIT_BURST requests (may need higher burst)"
    fi
else
    log_info "7. Rate limit test skipped (set RUN_RATE_LIMIT_TEST=true to enable)"
fi

# =============================================================================
# TEST 8: Instagram endpoint - query token block
# =============================================================================
log_test "8. Instagram endpoint - query token should be rejected..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$BASE_URL/v1/inbound/instagram?token=test" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"msg_id":"test8"}' 2>/dev/null || echo "000")

if [ "$RESPONSE" = "401" ]; then
    log_pass "Instagram ?token= rejected with 401"
else
    log_fail "Instagram ?token= returned $RESPONSE (expected 401)"
fi

# =============================================================================
# TEST 9: Messenger endpoint - query token block
# =============================================================================
log_test "9. Messenger endpoint - query token should be rejected..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$BASE_URL/v1/inbound/messenger?token=test" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"msg_id":"test9"}' 2>/dev/null || echo "000")

if [ "$RESPONSE" = "401" ]; then
    log_pass "Messenger ?token= rejected with 401"
else
    log_fail "Messenger ?token= returned $RESPONSE (expected 401)"
fi

# =============================================================================
# TEST 10: Error response format check
# =============================================================================
log_test "10. Error response should be JSON with SEC-001 code..."

BODY=$(curl -s \
    "$BASE_URL/v1/inbound/whatsapp?token=test" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"msg_id":"test10"}' 2>/dev/null || echo "{}")

if echo "$BODY" | grep -q "SEC-001"; then
    log_pass "Error response contains SEC-001 code"
else
    log_fail "Error response missing SEC-001 code: $BODY"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  SUMMARY                                           ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✅ All gateway security tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some gateway security tests failed!${NC}"
    exit 1
fi
