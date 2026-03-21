#!/usr/bin/env bash
# smoke-cms-routes.sh — Verify all 15 critical Strapi CMS API routes
# Usage: ./smoke-cms-routes.sh [CMS_URL] [STRAPI_EMAIL] [STRAPI_PASSWORD]
# Defaults: CMS_URL=http://127.0.0.1:1337, credentials from env vars

set -euo pipefail

CMS_URL="${1:-http://127.0.0.1:1337}"
EMAIL="${2:-${STRAPI_EMAIL:-}}"
PASS="${3:-${STRAPI_PASSWORD:-}}"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS  $1  ($2)"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL  $1  ($2)"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo "=== CMS Route Smoke Test ==="
echo "CMS_URL: ${CMS_URL}"
echo ""

# Obtain JWT token
echo "--- Obtaining JWT token ---"
if [ -z "${EMAIL}" ] || [ -z "${PASS}" ]; then
  echo "ERROR: STRAPI_EMAIL and STRAPI_PASSWORD must be set (env vars or positional args)"
  exit 2
fi

AUTH_RESPONSE=$(curl -s -X POST "${CMS_URL}/api/auth/local" \
  -H 'Content-Type: application/json' \
  -d "{\"identifier\":\"${EMAIL}\",\"password\":\"${PASS}\"}")

# Try jq first, fall back to python3
if command -v jq >/dev/null 2>&1; then
  TOKEN=$(echo "${AUTH_RESPONSE}" | jq -r '.jwt // empty')
else
  TOKEN=$(echo "${AUTH_RESPONSE}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('jwt',''))" 2>/dev/null || echo "")
fi

if [ -z "${TOKEN}" ]; then
  echo "ERROR: Could not obtain JWT — check credentials"
  echo "Response: ${AUTH_RESPONSE}"
  exit 2
fi

echo "JWT obtained successfully"
echo ""

# Helper: check a single route
check_route() {
  local route="$1"
  local url="${CMS_URL}/api/${route}"
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    "${url}")
  if [ "${status}" = "200" ]; then
    pass "${route}" "${status}"
  else
    fail "${route}" "${status}"
  fi
}

# --- collectionType routes (13) ---
echo "--- Collection Type Routes ---"
check_route "products"
check_route "orders"
check_route "customers"
check_route "ingredients"
check_route "payments"
check_route "delivery-assignments"
check_route "funnel-events"
check_route "inbound-messages"
check_route "feedbacks"
check_route "suppliers"
check_route "loyalty-tiers"
check_route "marketing-campaigns"
check_route "delivery-zones"

# --- singleType routes (2) ---
echo ""
echo "--- Single Type Routes ---"
check_route "system-config"
check_route "restaurant-brand"

# --- custom handler routes ---
echo ""
echo "--- Custom Handler Routes ---"
CTRL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  "${CMS_URL}/api/control-plane/status")
if [ "${CTRL_STATUS}" = "200" ]; then
  pass "control-plane/status" "${CTRL_STATUS}"
else
  fail "control-plane/status" "${CTRL_STATUS}"
fi

METRICS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  "${CMS_URL}/api/metrics")
# 200 or 401 are both acceptable for metrics endpoint
if [ "${METRICS_STATUS}" = "200" ] || [ "${METRICS_STATUS}" = "401" ]; then
  pass "metrics (200 or 401 acceptable)" "${METRICS_STATUS}"
else
  fail "metrics" "${METRICS_STATUS}"
fi

# --- Summary ---
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo "=== Results: ${PASS_COUNT}/${TOTAL} passed ==="

if [ "${FAIL_COUNT}" -gt 0 ]; then
  echo "FAILED: ${FAIL_COUNT} route(s) did not return expected status"
  exit 1
fi

echo "All routes OK"
exit 0
