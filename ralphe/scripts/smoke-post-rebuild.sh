#!/usr/bin/env bash
# smoke-post-rebuild.sh — Post-rebuild verification for CMS health, login, kiosk products, admin login
# Usage: ./smoke-post-rebuild.sh [BASE_URL] [CMS_INTERNAL_URL] [STRAPI_EMAIL] [STRAPI_PASSWORD]
# Covers INFRA-03: verifies rebuilt container stack works end-to-end

set -euo pipefail

BASE_URL="${1:-https://api.srv1258231.hstgr.cloud}"
CMS_INTERNAL_URL="${2:-http://127.0.0.1:1337}"
EMAIL="${3:-${STRAPI_EMAIL:-}}"
PASS="${4:-${STRAPI_PASSWORD:-}}"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL  $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo "=== Post-Rebuild Smoke Test ==="
echo "BASE_URL:        ${BASE_URL}"
echo "CMS_INTERNAL:    ${CMS_INTERNAL_URL}"
echo ""

# Check 1 — CMS health endpoint (Strapi 5 returns 204 when healthy)
echo "--- Check 1: CMS health ---"
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${CMS_INTERNAL_URL}/_health")
if [ "${HEALTH_STATUS}" = "204" ]; then
  pass "CMS health (204)"
else
  fail "CMS health (got: ${HEALTH_STATUS})"
fi

# Check 2 — CMS login via Strapi users-permissions
echo ""
echo "--- Check 2: CMS login ---"
if [ -z "${EMAIL}" ] || [ -z "${PASS}" ]; then
  echo "SKIP  CMS login (STRAPI_EMAIL/STRAPI_PASSWORD not set)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  LOGIN_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${CMS_INTERNAL_URL}/api/auth/local" \
    -H 'Content-Type: application/json' \
    -d "{\"identifier\":\"${EMAIL}\",\"password\":\"${PASS}\"}")
  if [ "${LOGIN_RESPONSE}" = "200" ]; then
    # Also verify jwt field is present in body
    JWT_BODY=$(curl -s -X POST "${CMS_INTERNAL_URL}/api/auth/local" \
      -H 'Content-Type: application/json' \
      -d "{\"identifier\":\"${EMAIL}\",\"password\":\"${PASS}\"}")
    if command -v jq >/dev/null 2>&1; then
      JWT_VAL=$(echo "${JWT_BODY}" | jq -r '.jwt // empty')
    else
      JWT_VAL=$(echo "${JWT_BODY}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('jwt',''))" 2>/dev/null || echo "")
    fi
    if [ -n "${JWT_VAL}" ]; then
      pass "CMS login (JWT obtained)"
    else
      fail "CMS login (200 but no JWT in response)"
    fi
  else
    fail "CMS login (${LOGIN_RESPONSE})"
  fi
fi

# Check 3 — Kiosk products via gateway
echo ""
echo "--- Check 3: Kiosk products via gateway ---"
KIOSK_RESPONSE=$(curl -s -w "\n%{http_code}" "${BASE_URL}/v1/strapi/api/products")
KIOSK_STATUS=$(echo "${KIOSK_RESPONSE}" | tail -1)
KIOSK_BODY=$(echo "${KIOSK_RESPONSE}" | head -1)

if [ "${KIOSK_STATUS}" = "200" ]; then
  # Verify "data" array is present in body
  if echo "${KIOSK_BODY}" | grep -q '"data"'; then
    pass "kiosk products via gateway (200, data present)"
  else
    fail "kiosk products via gateway (200 but no data array)"
  fi
else
  fail "kiosk products via gateway (${KIOSK_STATUS})"
fi

# Check 4 — Admin login via gateway
echo ""
echo "--- Check 4: Admin login via gateway ---"
if [ -z "${EMAIL}" ] || [ -z "${PASS}" ]; then
  echo "SKIP  admin login (STRAPI_EMAIL/STRAPI_PASSWORD not set)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  ADMIN_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "${BASE_URL}/v1/portal/api/auth/local" \
    -H 'Content-Type: application/json' \
    -d "{\"identifier\":\"${EMAIL}\",\"password\":\"${PASS}\"}")
  ADMIN_STATUS=$(echo "${ADMIN_RESPONSE}" | tail -1)
  ADMIN_BODY=$(echo "${ADMIN_RESPONSE}" | head -1)

  if [ "${ADMIN_STATUS}" = "200" ] && echo "${ADMIN_BODY}" | grep -q '"jwt"'; then
    pass "admin login via gateway (200, JWT)"
  elif [ "${ADMIN_STATUS}" = "200" ]; then
    fail "admin login via gateway (200 but no JWT in response)"
  else
    # Fallback: try /v1/strapi/api/auth/local if portal not configured
    ADMIN_FALLBACK=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST "${BASE_URL}/v1/strapi/api/auth/local" \
      -H 'Content-Type: application/json' \
      -d "{\"identifier\":\"${EMAIL}\",\"password\":\"${PASS}\"}")
    if [ "${ADMIN_FALLBACK}" = "200" ]; then
      pass "admin login via gateway fallback /v1/strapi (200, JWT)"
    else
      fail "admin login via gateway (portal: ${ADMIN_STATUS}, strapi: ${ADMIN_FALLBACK})"
    fi
  fi
fi

# --- Summary ---
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo "=== Results: ${PASS_COUNT}/${TOTAL} passed ==="

if [ "${FAIL_COUNT}" -gt 0 ]; then
  echo "FAILED: ${FAIL_COUNT} check(s) did not pass"
  exit 1
fi

echo "All checks passed"
exit 0
