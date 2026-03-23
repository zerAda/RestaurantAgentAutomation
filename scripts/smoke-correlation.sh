#!/bin/bash
# smoke-correlation.sh — Phase 02: Structured Logging & Correlation
# Verifies OBS-01 through OBS-04 on the live VPS.
#
# Usage: bash scripts/smoke-correlation.sh
# Exit 0 = all checks pass
# Exit 1 = one or more checks failed
#
# Prerequisites:
# - SSH access to deploy@72.60.190.192 (key-based)
# - VPS services running: gateway, cms, n8n-main
# - Plans 02-01, 02-02, 02-03 deployed

set -euo pipefail

VPS="deploy@72.60.190.192"
API_BASE="https://api.srv1258231.hstgr.cloud"
PASS=0
FAIL=0
FAILURES=()

log_pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
log_fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }
log_info() { echo "[INFO] $1"; }

echo "========================================"
echo "Phase 02 Smoke Test: Structured Logging"
echo "========================================"
echo ""

# -- OBS-01: n8n JSON log format ----------------------------------------------
echo "--- OBS-01: n8n structured JSON logs ---"

N8N_LOGS=$(ssh "$VPS" "docker logs current-n8n-main-1 --tail 10 2>&1" 2>/dev/null || echo "")

if [ -z "$N8N_LOGS" ]; then
  log_fail "OBS-01: Could not retrieve n8n-main logs"
else
  # Check if any line is valid JSON
  JSON_LINES=$(echo "$N8N_LOGS" | python3 -c "
import sys, json
count = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        if 'level' in obj or 'Level' in obj:
            count += 1
    except Exception:
        pass
print(count)
" 2>/dev/null || echo "0")

  if [ "$JSON_LINES" -gt 0 ]; then
    log_pass "OBS-01: n8n-main emits structured JSON logs ($JSON_LINES JSON lines found)"
  else
    log_fail "OBS-01: n8n-main logs are NOT JSON format (found 0 JSON lines with 'level' field)"
    echo "  Sample log output:"
    echo "$N8N_LOGS" | head -3 | sed 's/^/  /'
  fi

  # Check n8n-worker too
  N8N_WORKER_LOGS=$(ssh "$VPS" "docker logs current-n8n-worker-1 --tail 5 2>&1" 2>/dev/null || echo "")
  WORKER_JSON=$(echo "$N8N_WORKER_LOGS" | python3 -c "
import sys, json
count = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        json.loads(line); count += 1
    except: pass
print(count)
" 2>/dev/null || echo "0")

  if [ "$WORKER_JSON" -gt 0 ]; then
    log_pass "OBS-01: n8n-worker also emits JSON logs ($WORKER_JSON JSON lines)"
  else
    log_fail "OBS-01: n8n-worker logs are NOT JSON format"
  fi
fi

echo ""
# -- OBS-02: Strapi JSON log format -------------------------------------------
echo "--- OBS-02: Strapi structured JSON logs ---"

CMS_LOGS=$(ssh "$VPS" "docker logs current-cms-1 --tail 20 2>&1" 2>/dev/null || echo "")

if [ -z "$CMS_LOGS" ]; then
  log_fail "OBS-02: Could not retrieve cms logs"
else
  CMS_JSON_LINES=$(echo "$CMS_LOGS" | python3 -c "
import sys, json
count = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if ('level' in obj or 'Level' in obj) and ('msg' in obj or 'message' in obj or 'Message' in obj):
            count += 1
    except: pass
print(count)
" 2>/dev/null || echo "0")

  if [ "$CMS_JSON_LINES" -gt 0 ]; then
    log_pass "OBS-02: Strapi CMS emits structured JSON logs ($CMS_JSON_LINES JSON lines found)"
  else
    log_fail "OBS-02: Strapi CMS logs are NOT JSON format"
    echo "  Sample log output:"
    echo "$CMS_LOGS" | head -3 | sed 's/^/  /'
  fi

  # Verify 'service' field is present
  SERVICE_FIELD=$(echo "$CMS_LOGS" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('service') == 'strapi-cms':
            print('found')
            break
    except: pass
" 2>/dev/null || echo "")

  if [ "$SERVICE_FIELD" = "found" ]; then
    log_pass "OBS-02: Strapi logs contain service='strapi-cms' field"
  else
    log_fail "OBS-02: Strapi logs missing service='strapi-cms' field"
  fi
fi

echo ""
# -- OBS-03: nginx request_id in access log -----------------------------------
echo "--- OBS-03: nginx access log contains request_id ---"

# Make a test request through the gateway
log_info "Sending test request to $API_BASE/v1/strapi/api/products?_limit=1"
curl -s --max-time 10 "$API_BASE/v1/strapi/api/products?_limit=1" -o /dev/null || true
sleep 2

NGINX_LOGS=$(ssh "$VPS" "docker logs current-gateway-1 --tail 5 2>&1" 2>/dev/null || echo "")

NGINX_REQID=$(echo "$NGINX_LOGS" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        rid = obj.get('request_id', '')
        if rid and len(rid) == 32 and all(c in '0123456789abcdef' for c in rid):
            print(rid)
            break
    except: pass
" 2>/dev/null || echo "")

if [ -n "$NGINX_REQID" ]; then
  log_pass "OBS-03: nginx access log contains request_id='$NGINX_REQID'"
else
  log_fail "OBS-03: nginx access log does NOT contain a valid 32-char hex request_id"
  echo "  Recent nginx log sample:"
  echo "$NGINX_LOGS" | head -3 | sed 's/^/  /'
fi

echo ""
# -- OBS-04: Correlation ID propagated nginx -> Strapi ------------------------
echo "--- OBS-04: X-Request-ID propagated from nginx to Strapi ---"

if [ -z "$NGINX_REQID" ]; then
  log_fail "OBS-04: Cannot test propagation -- nginx request_id not found (OBS-03 failed)"
else
  # Search Strapi logs for the same request_id value we found in nginx
  log_info "Searching Strapi logs for request_id='$NGINX_REQID'"
  CMS_LOGS_FRESH=$(ssh "$VPS" "docker logs current-cms-1 --tail 50 2>&1" 2>/dev/null || echo "")

  CMS_MATCH=$(echo "$CMS_LOGS_FRESH" | python3 -c "
import sys, json
rid = '$NGINX_REQID'
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('request_id') == rid:
            print('found')
            break
    except: pass
" 2>/dev/null || echo "")

  if [ "$CMS_MATCH" = "found" ]; then
    log_pass "OBS-04: request_id='$NGINX_REQID' found in BOTH nginx and Strapi logs -- end-to-end trace confirmed"
  else
    log_fail "OBS-04: request_id='$NGINX_REQID' found in nginx log but NOT in Strapi log"
    echo "  Hint: Check that 02-03 was deployed and CMS was rebuilt with logger.ts changes"
    echo "  CMS recent log sample:"
    echo "$CMS_LOGS_FRESH" | grep '"request_id"' | head -3 | sed 's/^/  /' || echo "  (no request_id fields found in CMS logs)"
  fi
fi

echo ""
# -- Summary ------------------------------------------------------------------
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failed checks:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

echo "All Phase 02 checks passed."
exit 0
