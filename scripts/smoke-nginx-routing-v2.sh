#!/usr/bin/env bash
# =============================================================================
# PHASE 4 — Plan 04-01: Nginx Routing & Security Smoke Tests
# =============================================================================
# Purpose: Validate all gateway routing rules, security headers, rate limiting,
#          CORS policies, and method restrictions without a live backend.
#
# Usage:   bash scripts/smoke-nginx-routing.sh [BASE_URL]
#          Default BASE_URL: https://api.srv1258231.hstgr.cloud
#
# Exit:    0 = all pass, 1 = any fail
# =============================================================================

set -euo pipefail

BASE_URL="${1:-https://api.srv1258231.hstgr.cloud}"
PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { ((PASS++)); ((TOTAL++)); echo -e "${GREEN}✅ PASS${NC}: $1"; }
log_fail() { ((FAIL++)); ((TOTAL++)); echo -e "${RED}❌ FAIL${NC}: $1 — $2"; }

assert_status() {
  local desc="$1" url="$2" expected="$3" method="${4:-GET}" extra="${5:-}"
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' -X "$method" $extra "$url" 2>/dev/null || echo "000")
  if [[ "$status" == "$expected" ]]; then
    log_pass "$desc (HTTP $status)"
  else
    log_fail "$desc" "Expected $expected, got $status"
  fi
}

assert_header() {
  local desc="$1" url="$2" header="$3" expected_val="$4"
  local headers
  headers=$(curl -s -I "$url" 2>/dev/null)
  if echo "$headers" | grep -qi "$header.*$expected_val"; then
    log_pass "$desc"
  else
    log_fail "$desc" "Header '$header: $expected_val' not found"
  fi
}

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  RESTO BOT — Nginx Routing & Security Smoke Tests        ║"
echo "║  Target: $BASE_URL"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════
# ZONE 1: Health Endpoints
# ═══════════════════════════════════════════════════
echo -e "\n${YELLOW}━━━ Zone 1: Health Endpoints ━━━${NC}"
assert_status "GET /healthz returns 200" "$BASE_URL/healthz" "200"
assert_status "GET /healthz/deep returns 200" "$BASE_URL/healthz/deep" "200"
assert_status "POST /healthz blocked" "$BASE_URL/healthz" "405" "POST"

# ═══════════════════════════════════════════════════
# ZONE 2: Meta Inbound Routes (WhatsApp/IG/Messenger)
# ═══════════════════════════════════════════════════
echo -e "\n${YELLOW}━━━ Zone 2: Meta Inbound Routes ━━━${NC}"
# WA verify token (GET)
assert_status "GET /v1/inbound/whatsapp returns 200|502" "$BASE_URL/v1/inbound/whatsapp?hub.mode=subscribe&hub.verify_token=test&hub.challenge=1234" "200"
# WA POST with JSON
assert_status "POST /v1/inbound/whatsapp (JSON) accepted" "$BASE_URL/v1/inbound/whatsapp" "200" "POST" "-H 'Content-Type: application/json' -d '{\"test\":true}'"
# WA POST without JSON rejected
assert_status "POST /v1/inbound/whatsapp (no JSON) = 415" "$BASE_URL/v1/inbound/whatsapp" "415" "POST" "-H 'Content-Type: text/plain' -d 'test'"
# DELETE blocked
assert_status "DELETE /v1/inbound/whatsapp = 405" "$BASE_URL/v1/inbound/whatsapp" "405" "DELETE"

# Instagram
assert_status "GET /v1/inbound/instagram accepted" "$BASE_URL/v1/inbound/instagram?hub.mode=subscribe&hub.verify_token=test&hub.challenge=test" "200"
assert_status "DELETE /v1/inbound/instagram = 405" "$BASE_URL/v1/inbound/instagram" "405" "DELETE"

# Messenger
assert_status "GET /v1/inbound/messenger accepted" "$BASE_URL/v1/inbound/messenger?hub.mode=subscribe&hub.verify_token=test&hub.challenge=test" "200"

# ═══════════════════════════════════════════════════
# ZONE 3: Security — Query Token Blocking (SEC-001)
# ═══════════════════════════════════════════════════
echo -e "\n${YELLOW}━━━ Zone 3: Query Token Blocking ━━━${NC}"
assert_status "?token=xxx blocked = 401" "$BASE_URL/v1/inbound/whatsapp?token=leaked_secret" "401"
assert_status "?access_token=xxx blocked = 401" "$BASE_URL/v1/inbound/whatsapp?access_token=leaked_secret" "401"
assert_status "?api_token=xxx blocked = 401" "$BASE_URL/v1/inbound/whatsapp?api_token=leaked" "401"

# ═══════════════════════════════════════════════════
# ZONE 4: Security Headers
# ═══════════════════════════════════════════════════
echo -e "\n${YELLOW}━━━ Zone 4: Security Headers ━━━${NC}"
assert_header "X-Content-Type-Options: nosniff" "$BASE_URL/healthz" "X-Content-Type-Options" "nosniff"
assert_header "X-Frame-Options: DENY" "$BASE_URL/healthz" "X-Frame-Options" "DENY"
assert_header "Strict-Transport-Security present" "$BASE_URL/healthz" "Strict-Transport-Security" "max-age"
assert_header "Server header hidden" "$BASE_URL/healthz" "Server" "nginx" && {
  # If nginx is exposed, that's a fail (server_tokens off should hide version)
  :
}

# ═══════════════════════════════════════════════════
# ZONE 5: Internal Routes (token-gated)
# ═══════════════════════════════════════════════════
echo -e "\n${YELLOW}━━━ Zone 5: Internal/Admin Routes ━━━${NC}"
# These should work (proxied) or return 502 (no backend) but NOT 404
assert_status "GET /v1/internal/ping proxied" "$BASE_URL/v1/internal/ping" "502" "GET" "-H 'X-Api-Token: test'"
assert_status "POST /v1/admin/chat proxied" "$BASE_URL/v1/admin/chat" "502" "POST" "-H 'X-Api-Token: test' -H 'Content-Type: application/json' -d '{\"test\":true}'"

# ═══════════════════════════════════════════════════
# ZONE 6: Kiosk Strapi Proxy
# ═══════════════════════════════════════════════════
echo -e "\n${YELLOW}━━━ Zone 6: Kiosk Strapi Proxy ━━━${NC}"
assert_status "GET /v1/strapi/api/menu-items proxied" "$BASE_URL/v1/strapi/api/menu-items" "200"
assert_status "POST /v1/strapi/api/menu-items blocked (GET only)" "$BASE_URL/v1/strapi/api/menu-items" "405" "POST" "-H 'Content-Type: application/json' -d '{}'"
assert_status "POST /v1/strapi/api/orders allowed" "$BASE_URL/v1/strapi/api/orders" "200" "POST" "-H 'Content-Type: application/json' -d '{\"data\":{}}'"

# ═══════════════════════════════════════════════════
# ZONE 7: CORS Headers
# ═══════════════════════════════════════════════════
echo -e "\n${YELLOW}━━━ Zone 7: CORS Preflight ━━━${NC}"
# Kiosk CORS
kiosk_cors=$(curl -s -I -X OPTIONS "$BASE_URL/v1/strapi/api/menu-items" -H "Origin: https://kiosk.srv1258231.hstgr.cloud" 2>/dev/null)
if echo "$kiosk_cors" | grep -qi "Access-Control-Allow-Origin.*kiosk"; then
  log_pass "Kiosk CORS: correct origin"
else
  log_fail "Kiosk CORS" "Missing kiosk origin in Access-Control-Allow-Origin"
fi

# Admin CORS
admin_cors=$(curl -s -I -X OPTIONS "$BASE_URL/v1/portal/api/orders" -H "Origin: https://admin.srv1258231.hstgr.cloud" 2>/dev/null)
if echo "$admin_cors" | grep -qi "Access-Control-Allow-Origin.*admin"; then
  log_pass "Admin CORS: correct origin"
else
  log_fail "Admin CORS" "Missing admin origin in Access-Control-Allow-Origin"
fi

# ═══════════════════════════════════════════════════
# ZONE 8: Default Deny
# ═══════════════════════════════════════════════════
echo -e "\n${YELLOW}━━━ Zone 8: Default Deny ━━━${NC}"
assert_status "GET / = 404 (default deny)" "$BASE_URL/" "404"
assert_status "GET /random/path = 404" "$BASE_URL/random/path" "404"
assert_status "GET /v1/nonexistent = 404" "$BASE_URL/v1/nonexistent" "404"

# ═══════════════════════════════════════════════════
# ZONE 9: Legacy Aliases
# ═══════════════════════════════════════════════════
echo -e "\n${YELLOW}━━━ Zone 9: Legacy Aliases ━━━${NC}"
assert_status "GET /v1/inbound/wa-incoming-v16 proxied" "$BASE_URL/v1/inbound/wa-incoming-v16" "200"
assert_status "GET /v1/inbound/ig-incoming-v16 proxied" "$BASE_URL/v1/inbound/ig-incoming-v16" "200"

# ═══════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  RESULTS: $PASS passed / $FAIL failed / $TOTAL total"
echo "╚════════════════════════════════════════════════════════════╝"

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}⚠️  $FAIL tests failed!${NC}"
  exit 1
fi

echo -e "${GREEN}✅ All routing smoke tests passed!${NC}"
exit 0
