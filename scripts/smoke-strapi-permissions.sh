#!/usr/bin/env bash
# =============================================================================
# PHASE 4 — Plan 04-02: Strapi Permission Smoke Tests
# =============================================================================
# Purpose: Validate Strapi role-based access control matrix.
#          Ensures PUBLIC users can only read allowed collections,
#          and AUTHENTICATED users can only access permitted operations.
#
# Usage:   bash scripts/smoke-strapi-permissions.sh [STRAPI_URL] [API_TOKEN]
#          Default STRAPI_URL: https://api.srv1258231.hstgr.cloud/v1/strapi
#
# Exit:    0 = all pass, 1 = any fail
# =============================================================================

set -euo pipefail

STRAPI_URL="${1:-https://api.srv1258231.hstgr.cloud/v1/strapi}"
API_TOKEN="${2:-${STRAPI_API_TOKEN:-}}"

PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { ((PASS++)); ((TOTAL++)); echo -e "${GREEN}✅ PASS${NC}: $1"; }
log_fail() { ((FAIL++)); ((TOTAL++)); echo -e "${RED}❌ FAIL${NC}: $1 — $2"; }

# Test: PUBLIC user (no token) can/cannot access endpoint
test_public() {
  local desc="$1" path="$2" method="${3:-GET}" expected="$4"
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' -X "$method" "${STRAPI_URL}${path}" -H 'Content-Type: application/json' 2>/dev/null || echo "000")
  # Normalize: 403 or 401 are both "blocked"
  if [[ "$expected" == "BLOCKED" ]]; then
    if [[ "$status" == "401" || "$status" == "403" ]]; then
      log_pass "$desc (PUBLIC → $status)"
    else
      log_fail "$desc" "Expected 401/403, got $status"
    fi
  elif [[ "$expected" == "ALLOWED" ]]; then
    if [[ "$status" == "200" ]]; then
      log_pass "$desc (PUBLIC → $status)"
    else
      log_fail "$desc" "Expected 200, got $status"
    fi
  fi
}

# Test: AUTHENTICATED user (Bearer token) can/cannot access endpoint
test_auth() {
  local desc="$1" path="$2" method="${3:-GET}" expected="$4"
  if [[ -z "$API_TOKEN" ]]; then
    echo -e "${YELLOW}⏭  SKIP${NC}: $desc (no API_TOKEN provided)"
    return
  fi
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' -X "$method" "${STRAPI_URL}${path}" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H 'Content-Type: application/json' 2>/dev/null || echo "000")
  if [[ "$expected" == "BLOCKED" ]]; then
    if [[ "$status" == "401" || "$status" == "403" ]]; then
      log_pass "$desc (AUTH → $status)"
    else
      log_fail "$desc" "Expected 401/403, got $status"
    fi
  elif [[ "$expected" == "ALLOWED" ]]; then
    if [[ "$status" == "200" ]]; then
      log_pass "$desc (AUTH → $status)"
    else
      log_fail "$desc" "Expected 200, got $status"
    fi
  fi
}

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  RESTO BOT — Strapi Permission Matrix Smoke Tests        ║"
echo "║  Target: $STRAPI_URL"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════
# PUBLIC ROLE — Read-Only for Kiosk Collections
# ═══════════════════════════════════════════════════
echo -e "${YELLOW}━━━ Public Role: Allowed Reads ━━━${NC}"
test_public "GET /api/menu-items (public read)" "/api/menu-items" "GET" "ALLOWED"
test_public "GET /api/categories (public read)" "/api/categories" "GET" "ALLOWED"
test_public "GET /api/products (public read)" "/api/products" "GET" "ALLOWED"
test_public "GET /api/restaurants (public read)" "/api/restaurants" "GET" "ALLOWED"

echo -e "\n${YELLOW}━━━ Public Role: Blocked Writes ━━━${NC}"
test_public "POST /api/menu-items (public write blocked)" "/api/menu-items" "POST" "BLOCKED"
test_public "PUT /api/menu-items/1 (public update blocked)" "/api/menu-items/1" "PUT" "BLOCKED"
test_public "DELETE /api/menu-items/1 (public delete blocked)" "/api/menu-items/1" "DELETE" "BLOCKED"

echo -e "\n${YELLOW}━━━ Public Role: Blocked Sensitive Collections ━━━${NC}"
test_public "GET /api/orders (public blocked)" "/api/orders" "GET" "BLOCKED"
test_public "GET /api/customers (public blocked)" "/api/customers" "GET" "BLOCKED"
test_public "GET /api/drivers (public blocked)" "/api/drivers" "GET" "BLOCKED"
test_public "GET /api/system-config (public blocked)" "/api/system-config" "GET" "BLOCKED"
test_public "GET /api/ai-learnings (public blocked)" "/api/ai-learnings" "GET" "BLOCKED"
test_public "GET /api/users (public blocked)" "/api/users" "GET" "BLOCKED"

# ═══════════════════════════════════════════════════
# AUTHENTICATED ROLE — Full CRUD for internal services
# ═══════════════════════════════════════════════════
echo -e "\n${YELLOW}━━━ Authenticated Role: Allowed Reads ━━━${NC}"
test_auth "GET /api/orders (auth read)" "/api/orders" "GET" "ALLOWED"
test_auth "GET /api/customers (auth read)" "/api/customers" "GET" "ALLOWED"
test_auth "GET /api/system-config (auth read)" "/api/system-config" "GET" "ALLOWED"

echo -e "\n${YELLOW}━━━ Authenticated Role: Blocked Admin Paths ━━━${NC}"
test_auth "GET /api/users (auth blocked — Strapi admin)" "/api/users" "GET" "BLOCKED"
test_auth "GET /admin (auth blocked — Strapi panel)" "/admin" "GET" "BLOCKED"

# ═══════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  RESULTS: $PASS passed / $FAIL failed / $TOTAL total"
echo "╚════════════════════════════════════════════════════════════╝"

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}⚠️  $FAIL permission tests failed!${NC}"
  exit 1
fi

echo -e "${GREEN}✅ All Strapi permission smoke tests passed!${NC}"
exit 0
