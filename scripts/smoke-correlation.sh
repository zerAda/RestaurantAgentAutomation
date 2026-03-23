#!/bin/bash
# smoke-correlation.sh — Phase 02: Structured Logging & Correlation
# Verifies OBS-01 through OBS-04 on the live VPS.
#
# Usage: bash scripts/smoke-correlation.sh
#   Can be run locally (SSH access to VPS required) or directly on the VPS.
#
# Exit 0 = all checks pass
# Exit 1 = one or more checks failed
#
# Prerequisites:
# - SSH access to deploy@72.60.190.192 (key-based) OR run directly on VPS
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

# All JSON parsing runs ON the VPS (where python3 is available).
# This makes the script cross-platform (runs from Windows/Mac/Linux).
vps() { ssh "$VPS" "$@" 2>/dev/null; }

echo "========================================"
echo "Phase 02 Smoke Test: Structured Logging"
echo "========================================"
echo ""

# -- OBS-01: n8n structured JSON logs -----------------------------------------
# n8n 2.9.4 with N8N_LOG_FORMAT=json emits NDJSON to stdout.
echo "--- OBS-01: n8n structured JSON logs ---"

N8N_MAIN_JSON=$(vps "docker logs current-n8n-main-1 --tail 20 2>&1 | python3 -c \"
import sys, json
count = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if ('level' in obj) and ('message' in obj or 'msg' in obj):
            count += 1
    except: pass
print(count)
\"" || echo "0")

if [ "$N8N_MAIN_JSON" -gt 0 ]; then
  log_pass "OBS-01: n8n-main emits structured JSON logs ($N8N_MAIN_JSON JSON lines found)"
else
  log_fail "OBS-01: n8n-main logs are NOT JSON format"
  echo "  Sample log output:"
  vps "docker logs current-n8n-main-1 --tail 3 2>&1" | head -3 | sed 's/^/  /' || true
fi

N8N_WORKER_JSON=$(vps "docker logs current-n8n-worker-1 --tail 20 2>&1 | python3 -c \"
import sys, json
count = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if ('level' in obj) and ('message' in obj or 'msg' in obj):
            count += 1
    except: pass
print(count)
\"" || echo "0")

if [ "$N8N_WORKER_JSON" -gt 0 ]; then
  log_pass "OBS-01: n8n-worker emits structured JSON logs ($N8N_WORKER_JSON JSON lines found)"
else
  log_fail "OBS-01: n8n-worker logs are NOT JSON format"
  echo "  Sample log output:"
  vps "docker logs current-n8n-worker-1 --tail 3 2>&1" | head -3 | sed 's/^/  /' || true
fi

echo ""
# -- OBS-02: Strapi JSON log format -------------------------------------------
echo "--- OBS-02: Strapi structured JSON logs ---"

CMS_JSON_COUNT=$(vps "docker logs current-cms-1 --tail 50 2>&1 | python3 -c \"
import sys, json
count = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if ('level' in obj) and ('message' in obj or 'msg' in obj):
            count += 1
    except: pass
print(count)
\"" || echo "0")

if [ "$CMS_JSON_COUNT" -gt 0 ]; then
  log_pass "OBS-02: Strapi CMS emits structured JSON logs ($CMS_JSON_COUNT JSON lines found)"
else
  log_fail "OBS-02: Strapi CMS logs are NOT JSON format"
  echo "  Sample log output:"
  vps "docker logs current-cms-1 --tail 5 2>&1" | head -3 | sed 's/^/  /' || true
fi

CMS_SERVICE=$(vps "docker logs current-cms-1 --tail 50 2>&1 | python3 -c \"
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
\"" || echo "")

if [ "$CMS_SERVICE" = "found" ]; then
  log_pass "OBS-02: Strapi logs contain service='strapi-cms' field"
else
  log_fail "OBS-02: Strapi logs missing service='strapi-cms' field"
fi

echo ""
# -- OBS-03: nginx request_id in JSON access log ------------------------------
# Note: nginx logs to /var/log/nginx/access.json inside the container (not stdout).
echo "--- OBS-03: nginx access log contains request_id ---"

log_info "Sending test request to $API_BASE/healthz"
curl -s --max-time 10 "$API_BASE/healthz" -o /dev/null || true
sleep 2

NGINX_REQID=$(vps "docker exec current-gateway-1 tail -n 5 /var/log/nginx/access.json 2>/dev/null | python3 -c \"
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
\"" || echo "")

if [ -n "$NGINX_REQID" ]; then
  log_pass "OBS-03: nginx access log contains request_id='$NGINX_REQID'"
else
  log_fail "OBS-03: nginx access log does NOT contain a valid 32-char hex request_id"
  echo "  Recent nginx log sample:"
  vps "docker exec current-gateway-1 tail -n 3 /var/log/nginx/access.json 2>/dev/null" | sed 's/^/  /' || true
fi

echo ""
# -- OBS-04: Correlation ID propagated nginx -> Strapi ------------------------
echo "--- OBS-04: X-Request-ID propagated from nginx to Strapi ---"

if [ -z "$NGINX_REQID" ]; then
  log_fail "OBS-04: Cannot test propagation -- nginx request_id not found (OBS-03 failed)"
else
  # Trigger a Strapi-proxied request and capture the request_id from nginx
  log_info "Sending Strapi-proxied request for correlation test"
  curl -s --max-time 10 "$API_BASE/v1/strapi/api/products?_limit=1" -o /dev/null || true
  sleep 3

  # Get the latest request_id for a Strapi-proxied URI
  STRAPI_REQID=$(vps "docker exec current-gateway-1 tail -n 10 /var/log/nginx/access.json 2>/dev/null | python3 -c \"
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        rid = obj.get('request_id', '')
        uri = obj.get('uri', '')
        if rid and len(rid)==32 and ('strapi' in uri or '/v1/' in uri):
            print(rid)
            break
    except: pass
\"" || echo "")

  if [ -z "$STRAPI_REQID" ]; then
    STRAPI_REQID="$NGINX_REQID"
    log_info "No Strapi-proxied request found; using healthz request_id: $STRAPI_REQID"
  else
    log_info "Testing correlation with Strapi request_id: $STRAPI_REQID"
  fi

  # Search Strapi logs for the same request_id
  CMS_MATCH=$(vps "docker logs current-cms-1 --tail 100 2>&1 | python3 -c \"
import sys, json
rid = '$STRAPI_REQID'
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('request_id') == rid and rid != '':
            print('found')
            break
    except: pass
\"" || echo "")

  if [ "$CMS_MATCH" = "found" ]; then
    log_pass "OBS-04: request_id='$STRAPI_REQID' found in BOTH nginx and Strapi logs -- end-to-end trace confirmed"
  else
    log_fail "OBS-04: request_id not correlated across nginx and Strapi logs"
    echo "  Hint: A non-empty request_id requires a Strapi-proxied request; healthz requests may not reach CMS."
    echo "  CMS JSON lines with any request_id:"
    vps "docker logs current-cms-1 --tail 50 2>&1 | python3 -c \"
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        rid = obj.get('request_id', '')
        if rid:
            print(line[:120])
            break
    except: pass
\"" | sed 's/^/  /' || echo "  (no request_id fields in CMS logs)" || true
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
