#!/usr/bin/env bash
# smoke-nginx-routing.sh — Nginx routing zone smoke test (CI-safe, stub upstreams)
# Phase 4 Plan 04-01 — Tests: TEST-01 (8 zones), TEST-02 (CORS dedup), TEST-03 (rate limit)
#
# Usage: bash scripts/smoke-nginx-routing.sh
# Requires: Docker with nginx:1.27-alpine image available
# Exit:  0 = all pass, 1 = any fail, 2 = setup error

set -euo pipefail

NGINX_PORT=18090
CONTAINER_NAME="nginx-smoke-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SMOKE_CONF="${REPO_ROOT}/infra/gateway/nginx.smoke.conf"

PASS_COUNT=0
FAIL_COUNT=0
ERRORS=()

pass() { echo "PASS  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL  $1  — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); ERRORS+=("$1: $2"); }

cleanup() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Nginx Routing Smoke Test ==="
echo "Config: ${SMOKE_CONF}"
echo ""

# Verify smoke conf exists
if [ ! -f "${SMOKE_CONF}" ]; then
  echo "ERROR: ${SMOKE_CONF} not found"
  exit 2
fi

# Start nginx container
echo "--- Starting nginx:1.27-alpine on port ${NGINX_PORT} ---"
docker run -d --name "${CONTAINER_NAME}" \
  -v "${SMOKE_CONF}:/etc/nginx/conf.d/default.conf:ro" \
  -p "${NGINX_PORT}:8080" \
  nginx:1.27-alpine >/dev/null

# Wait for nginx to be ready (max 10 seconds)
READY=0
for i in $(seq 1 20); do
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NGINX_PORT}/healthz" 2>/dev/null | grep -q "200"; then
    READY=1
    break
  fi
  sleep 0.5
done
if [ "${READY}" -eq 0 ]; then
  echo "ERROR: nginx did not become ready within 10 seconds"
  docker logs "${CONTAINER_NAME}" || true
  exit 2
fi

echo "nginx ready"
echo ""

# ============================================================
# Zone 1: /healthz — static 200 (TEST-01 zone 1)
# ============================================================
echo "--- Zone 1: /healthz ---"
status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NGINX_PORT}/healthz")
if [ "${status}" = "200" ]; then
  pass "/healthz → 200"
else
  fail "/healthz" "got ${status}, expected 200"
fi

# ============================================================
# Zone 2: /v1/inbound/whatsapp GET (Meta verify) — TEST-01 zone 2
# ============================================================
echo ""
echo "--- Zone 2: /v1/inbound/whatsapp GET ---"
status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NGINX_PORT}/v1/inbound/whatsapp")
if [ "${status}" != "404" ] && [ "${status}" != "502" ]; then
  pass "/v1/inbound/whatsapp GET → ${status} (route exists)"
else
  fail "/v1/inbound/whatsapp GET" "got ${status} (404=route missing, 502=nginx error)"
fi

# ============================================================
# Zone 3: /v1/inbound/whatsapp POST — TEST-01 zone 3
# ============================================================
echo ""
echo "--- Zone 3: /v1/inbound/whatsapp POST ---"
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "http://localhost:${NGINX_PORT}/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"smoke-1"}')
if [ "${status}" != "404" ] && [ "${status}" != "502" ]; then
  pass "/v1/inbound/whatsapp POST → ${status} (route exists)"
else
  fail "/v1/inbound/whatsapp POST" "got ${status} (404=route missing, 502=nginx error)"
fi

# Content-type guard: POST without JSON Content-Type must return 415
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "http://localhost:${NGINX_PORT}/v1/inbound/whatsapp" \
  -H "Content-Type: text/plain" \
  -d 'raw data')
if [ "${status}" = "415" ]; then
  pass "/v1/inbound/whatsapp POST no-CT → 415 (content-type guard active)"
else
  fail "/v1/inbound/whatsapp POST no-CT" "got ${status}, expected 415 (nginx content-type guard)"
fi

# ============================================================
# Zone 4: /v1/inbound/instagram — TEST-01 zone 4
# ============================================================
echo ""
echo "--- Zone 4: /v1/inbound/instagram ---"
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "http://localhost:${NGINX_PORT}/v1/inbound/instagram" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"smoke-ig"}')
if [ "${status}" != "404" ] && [ "${status}" != "502" ]; then
  pass "/v1/inbound/instagram POST → ${status} (route exists)"
else
  fail "/v1/inbound/instagram POST" "got ${status} (404=route missing)"
fi

# ============================================================
# Zone 5: /v1/inbound/messenger — TEST-01 zone 5
# ============================================================
echo ""
echo "--- Zone 5: /v1/inbound/messenger ---"
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "http://localhost:${NGINX_PORT}/v1/inbound/messenger" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"smoke-msg"}')
if [ "${status}" != "404" ] && [ "${status}" != "502" ]; then
  pass "/v1/inbound/messenger POST → ${status} (route exists)"
else
  fail "/v1/inbound/messenger POST" "got ${status} (404=route missing)"
fi

# ============================================================
# Zone 6: /v1/customer/ — TEST-01 zone 6
# ============================================================
echo ""
echo "--- Zone 6: /v1/customer/ ---"
status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NGINX_PORT}/v1/customer/test")
if [ "${status}" != "404" ] && [ "${status}" != "502" ]; then
  pass "/v1/customer/ → ${status} (route exists)"
else
  fail "/v1/customer/" "got ${status} (404=route missing)"
fi

# ============================================================
# Zone 7: /v1/admin/ — TEST-01 zone 7
# ============================================================
echo ""
echo "--- Zone 7: /v1/admin/ ---"
status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NGINX_PORT}/v1/admin/test")
if [ "${status}" != "404" ] && [ "${status}" != "502" ]; then
  pass "/v1/admin/ → ${status} (route exists)"
else
  fail "/v1/admin/" "got ${status} (404=route missing)"
fi

# ============================================================
# Zone 8: /v1/strapi/ (GET) — TEST-01 zone 8 + TEST-02 CORS dedup
# ============================================================
echo ""
echo "--- Zone 8: /v1/strapi/ GET + CORS header check (TEST-02) ---"
status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NGINX_PORT}/v1/strapi/api/products")
if [ "${status}" != "404" ] && [ "${status}" != "502" ]; then
  pass "/v1/strapi/ GET → ${status} (route exists)"
else
  fail "/v1/strapi/ GET" "got ${status} (404=route missing)"
fi

# TEST-02: Count Access-Control-Allow-Origin header occurrences (must be exactly 1)
ACAO_COUNT=$(curl -sI "http://localhost:${NGINX_PORT}/v1/strapi/api/products" \
  | grep -ic "^access-control-allow-origin:" || true)
if [ "${ACAO_COUNT}" -eq 1 ]; then
  pass "/v1/strapi/ ACAO header count = 1 (no duplication)"
else
  fail "/v1/strapi/ ACAO count" "got ${ACAO_COUNT} Access-Control-Allow-Origin headers, expected exactly 1"
fi

# Zone 8b: /v1/strapi/api/orders POST
echo ""
echo "--- Zone 8b: /v1/strapi/api/orders POST ---"
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "http://localhost:${NGINX_PORT}/v1/strapi/api/orders" \
  -H "Content-Type: application/json" \
  -d '{"data":{"status":"new"}}')
if [ "${status}" != "404" ] && [ "${status}" != "502" ]; then
  pass "/v1/strapi/api/orders POST → ${status} (route exists)"
else
  fail "/v1/strapi/api/orders POST" "got ${status} (404=route missing)"
fi

# ============================================================
# Zone 9: /v1/portal/
# ============================================================
echo ""
echo "--- Zone 9: /v1/portal/ ---"
status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NGINX_PORT}/v1/portal/api/orders")
if [ "${status}" != "404" ] && [ "${status}" != "502" ]; then
  pass "/v1/portal/ → ${status} (route exists)"
else
  fail "/v1/portal/" "got ${status} (404=route missing)"
fi

# Default deny: unknown path must return 404
echo ""
echo "--- Default deny ---"
status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NGINX_PORT}/unknown-path-xyz")
if [ "${status}" = "404" ]; then
  pass "unknown path → 404 (default deny)"
else
  fail "default deny" "got ${status}, expected 404"
fi

# Security: query string token blocked
echo ""
echo "--- Security: query-string token blocked (P0-SEC-01) ---"
status=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://localhost:${NGINX_PORT}/v1/inbound/whatsapp?token=secret123")
if [ "${status}" = "401" ]; then
  pass "?token= blocked → 401 (P0-SEC-01)"
else
  fail "?token= block" "got ${status}, expected 401"
fi

# ============================================================
# TEST-03: Rate limit — 25 rapid POSTs to /v1/inbound/whatsapp
# Restart container to get fresh rate-limit zone state
# ============================================================
echo ""
echo "--- TEST-03: Rate limit (fresh container for zone state reset) ---"
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

CONTAINER_NAME="nginx-smoke-rl-$$"
docker run -d --name "${CONTAINER_NAME}" \
  -v "${SMOKE_CONF}:/etc/nginx/conf.d/default.conf:ro" \
  -p "${NGINX_PORT}:8080" \
  nginx:1.27-alpine >/dev/null

# Wait for ready
READY=0
for i in $(seq 1 20); do
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NGINX_PORT}/healthz" 2>/dev/null | grep -q "200"; then
    READY=1
    break
  fi
  sleep 0.5
done
if [ "${READY}" -eq 0 ]; then
  fail "rate-limit test" "nginx did not become ready after restart"
else
  # Send 25 rapid requests — rate=10r/s burst=20 nodelay → requests 21-25 must return 429
  THROTTLED=0
  PASS_RL=0
  for i in $(seq 1 25); do
    rl_status=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST "http://localhost:${NGINX_PORT}/v1/inbound/whatsapp" \
      -H "Content-Type: application/json" \
      -d "{\"msg_id\":\"rl-${i}\"}")
    if [ "${rl_status}" = "429" ]; then
      THROTTLED=$((THROTTLED + 1))
    else
      PASS_RL=$((PASS_RL + 1))
    fi
  done
  echo "Rate limit results: ${PASS_RL} passed, ${THROTTLED} throttled (429) in 25 requests"
  if [ "${THROTTLED}" -ge 1 ]; then
    pass "Rate limit fires 429 after burst=20 (${THROTTLED} throttled in 25 requests)"
  else
    fail "Rate limit" "0 requests throttled in 25 rapid POSTs — burst=20 nodelay should have fired at request 21"
  fi
fi

# ============================================================
# Final summary
# ============================================================
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo "=== Results: ${PASS_COUNT}/${TOTAL} passed ==="

if [ "${FAIL_COUNT}" -gt 0 ]; then
  echo ""
  echo "FAILURES:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
  exit 1
fi

echo "All nginx routing zones OK"
exit 0
