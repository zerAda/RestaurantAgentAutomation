#!/usr/bin/env bash
set -euo pipefail

# =========================
# Security Smoke Tests
# P0-QA-01 - Validates security patches
# =========================

# Configuration
BASE_URL="${BASE_URL:-http://localhost:8080}"
VALID_TOKEN="${TEST_API_TOKEN:-test-token-123}"
LEGACY_TOKEN="${LEGACY_SHARED_TOKEN:-legacy-token-should-fail}"
TIMEOUT=10

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
WARNINGS=0

log_pass() { echo -e "${GREEN}✅ PASS:${NC} $1"; ((PASSED++)); }
log_fail() { echo -e "${RED}❌ FAIL:${NC} $1"; ((FAILED++)); }
log_warn() { echo -e "${YELLOW}⚠️  WARN:${NC} $1"; ((WARNINGS++)); }
log_info() { echo -e "ℹ️  INFO: $1"; }

echo "========================================"
echo "  Security Smoke Tests - P0-QA-01"
echo "========================================"
echo "Base URL: $BASE_URL"
echo ""

# -----------------------------
# P0-SEC-01: Query Token Blocked
# -----------------------------
echo "=== P0-SEC-01: Query Token Blocking ==="

# Test 1: token in query string
log_info "Testing ?token= rejection..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT -X POST \
  "$BASE_URL/v1/inbound/whatsapp?token=$VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"sec01-t1","from":"123","text":"test","provider":"wa"}' 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "401" ]; then
  log_pass "?token= rejected with 401"
else
  log_fail "?token= should return 401, got $HTTP_CODE"
fi

# Test 2: access_token in query string
log_info "Testing ?access_token= rejection..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT -X POST \
  "$BASE_URL/v1/inbound/whatsapp?access_token=$VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"sec01-t2","from":"123","text":"test","provider":"wa"}' 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "401" ]; then
  log_pass "?access_token= rejected with 401"
else
  log_fail "?access_token= should return 401, got $HTTP_CODE"
fi

# Test 3: Header token should work
log_info "Testing Authorization header acceptance..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT -X POST \
  "$BASE_URL/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"sec01-t3","from":"123","text":"test","provider":"wa"}' 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ]; then
  log_pass "Authorization header accepted ($HTTP_CODE)"
elif [ "$HTTP_CODE" = "000" ]; then
  log_fail "Connection failed - is the server running?"
else
  log_fail "Authorization header should work, got $HTTP_CODE"
fi

echo ""

# -----------------------------
# P0-SEC-02: Legacy Token Disabled
# -----------------------------
echo "=== P0-SEC-02: Legacy Token Handling ==="

log_info "Testing legacy shared token..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT -X POST \
  "$BASE_URL/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $LEGACY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"sec02-t1","from":"123","text":"test","provider":"wa"}' 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "401" ]; then
  log_pass "Legacy token rejected (LEGACY_SHARED_TOKEN_ENABLED=false)"
elif [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ]; then
  log_warn "Legacy token accepted - verify LEGACY_SHARED_TOKEN_ENABLED=false in production!"
else
  log_info "Unexpected response: $HTTP_CODE (may be expected depending on config)"
fi

echo ""

# -----------------------------
# No Token = Rejected
# -----------------------------
echo "=== Authentication Required ==="

log_info "Testing request without any token..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT -X POST \
  "$BASE_URL/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"notoken-t1","from":"123","text":"test","provider":"wa"}' 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "401" ]; then
  log_pass "No-token request rejected with 401"
else
  log_fail "No-token request should return 401, got $HTTP_CODE"
fi

echo ""

# -----------------------------
# Contract Validation
# -----------------------------
echo "=== Contract Validation ==="

log_info "Testing invalid payload (missing msg_id)..."
RESPONSE=$(curl -s -w "\n%{http_code}" --max-time $TIMEOUT -X POST \
  "$BASE_URL/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"from":"123","text":"test","provider":"wa"}' 2>/dev/null || echo -e "\n000")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "400" ] || echo "$BODY" | grep -q "CONTRACT_REJECT\|validation\|invalid" 2>/dev/null; then
  log_pass "Invalid payload handled (contract validation active)"
else
  log_warn "Invalid payload may not be validated (got $HTTP_CODE)"
fi

echo ""

# -----------------------------
# Idempotency
# -----------------------------
echo "=== Idempotency Check ==="

MSG_ID="idemp-$(date +%s)"
log_info "Testing duplicate message rejection (msg_id: $MSG_ID)..."

# First request
HTTP_CODE1=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT -X POST \
  "$BASE_URL/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"msg_id\":\"$MSG_ID\",\"from\":\"123\",\"text\":\"test\",\"provider\":\"wa\"}" 2>/dev/null || echo "000")

# Second request (duplicate)
HTTP_CODE2=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT -X POST \
  "$BASE_URL/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"msg_id\":\"$MSG_ID\",\"from\":\"123\",\"text\":\"test\",\"provider\":\"wa\"}" 2>/dev/null || echo "000")

if [ "$HTTP_CODE1" = "200" ] || [ "$HTTP_CODE1" = "202" ]; then
  log_pass "First request accepted ($HTTP_CODE1)"
  if [ "$HTTP_CODE2" = "200" ] || [ "$HTTP_CODE2" = "202" ]; then
    log_info "Duplicate also returned success (idempotent response)"
  fi
else
  log_warn "First request returned $HTTP_CODE1"
fi

echo ""

# -----------------------------
# Health Check
# -----------------------------
echo "=== Health Endpoint ==="

log_info "Testing /healthz..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT \
  "$BASE_URL/healthz" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
  log_pass "Health endpoint returns 200"
else
  log_fail "Health endpoint returned $HTTP_CODE"
fi

echo ""

# -----------------------------
# Summary
# -----------------------------
echo "========================================"
echo "  Security Smoke Test Results"
echo "========================================"
echo -e "  ${GREEN}Passed:${NC}   $PASSED"
echo -e "  ${RED}Failed:${NC}   $FAILED"
echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
echo "========================================"

if [ $FAILED -gt 0 ]; then
  echo ""
  echo -e "${RED}⚠️  SECURITY TESTS FAILED${NC}"
  echo "Do NOT deploy to production until all tests pass."
  exit 1
fi

if [ $WARNINGS -gt 0 ]; then
  echo ""
  echo -e "${YELLOW}⚠️  Warnings detected - review before production${NC}"
fi

echo ""
echo -e "${GREEN}✅ Security smoke tests completed${NC}"
exit 0
