#!/usr/bin/env bash
# =============================================================================
# Security Hardening Tests — 23 automated checks
# =============================================================================
# Section 1 (T01–T15): Static tests — no running stack required
# Section 2 (T16–T23): Network tests — requires running stack (optional)
#
# Usage:
#   bash scripts/test_security_hardening.sh              # Static tests only
#   bash scripts/test_security_hardening.sh --network     # Include network tests
# =============================================================================
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.hostinger.prod.yml"
NGINX_CONF="$PROJECT_DIR/infra/gateway/nginx.conf"
ENV_FILE="$PROJECT_DIR/.env"
SECRETS_DIR="$PROJECT_DIR/secrets"
NETWORK_TESTS=false

if [[ "${1:-}" == "--network" ]]; then
  NETWORK_TESTS=true
fi

TOTAL=0
PASSED=0
FAILED=0

red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }

pass() { green "  [PASS] $*"; PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); }
fail() { red   "  [FAIL] $*"; FAILED=$((FAILED + 1)); TOTAL=$((TOTAL + 1)); }
skip() { yellow "  [SKIP] $*"; TOTAL=$((TOTAL + 1)); }

echo "============================================="
echo "  Security Hardening Tests"
echo "============================================="
echo ""
echo "=== Section 1: Static Tests ==="
echo ""

# -----------------------------------------------
# T01: secrets/ permissions = 700, files = 600
# -----------------------------------------------
echo "T01: Checking secrets/ permissions..."
if [ -d "$SECRETS_DIR" ]; then
  T01_OK=1
  dir_perms=$(stat -c '%a' "$SECRETS_DIR" 2>/dev/null || stat -f '%Lp' "$SECRETS_DIR" 2>/dev/null)
  if [ "$dir_perms" != "700" ]; then
    fail "T01 — secrets/ directory permissions are $dir_perms (expected 700)"
    T01_OK=0
  fi
  for f in "$SECRETS_DIR"/*; do
    [ -f "$f" ] || continue
    fperms=$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null)
    if [ "$fperms" != "600" ]; then
      fail "T01 — $(basename "$f") permissions are $fperms (expected 600)"
      T01_OK=0
    fi
  done
  if [ "$T01_OK" -eq 1 ]; then
    pass "T01 — secrets/ permissions OK (700 dir, 600 files)"
  fi
else
  fail "T01 — secrets/ directory not found"
fi

# -----------------------------------------------
# T02: .env does not contain dev_local
# -----------------------------------------------
echo "T02: Checking .env for dev_local..."
if [ -f "$ENV_FILE" ]; then
  if grep -qi "dev_local" "$ENV_FILE"; then
    fail "T02 — .env contains 'dev_local'"
  else
    pass "T02 — .env clean of dev_local"
  fi
else
  fail "T02 — .env not found"
fi

# -----------------------------------------------
# T03: .env does not contain REPLACE_ME / tobemodified / placeholder
# -----------------------------------------------
echo "T03: Checking .env for placeholders..."
if [ -f "$ENV_FILE" ]; then
  if grep -qiE 'REPLACE_ME|tobemodified|placeholder' "$ENV_FILE"; then
    fail "T03 — .env contains placeholder values"
  else
    pass "T03 — .env clean of placeholders"
  fi
else
  fail "T03 — .env not found"
fi

# -----------------------------------------------
# T04: ADMIN_ALLOWED_IPS ≠ 0.0.0.0/0
# -----------------------------------------------
echo "T04: Checking ADMIN_ALLOWED_IPS..."
if [ -f "$ENV_FILE" ]; then
  ADMIN_IPS=$(grep -E '^ADMIN_ALLOWED_IPS=' "$ENV_FILE" | head -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')
  if [ "$ADMIN_IPS" = "0.0.0.0/0" ]; then
    fail "T04 — ADMIN_ALLOWED_IPS=0.0.0.0/0 (open to the world)"
  else
    pass "T04 — ADMIN_ALLOWED_IPS=$ADMIN_IPS"
  fi
else
  fail "T04 — .env not found"
fi

# -----------------------------------------------
# T05: META_SIGNATURE_REQUIRED ≠ off
# -----------------------------------------------
echo "T05: Checking META_SIGNATURE_REQUIRED..."
if [ -f "$ENV_FILE" ]; then
  META_SIG=$(grep -E '^META_SIGNATURE_REQUIRED=' "$ENV_FILE" | head -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')
  if [ "$META_SIG" = "off" ]; then
    fail "T05 — META_SIGNATURE_REQUIRED=off"
  else
    pass "T05 — META_SIGNATURE_REQUIRED=$META_SIG"
  fi
else
  fail "T05 — .env not found"
fi

# -----------------------------------------------
# T06: n8n_encryption_key ≥ 32 chars
# -----------------------------------------------
echo "T06: Checking n8n_encryption_key length..."
if [ -f "$SECRETS_DIR/n8n_encryption_key" ]; then
  KEY_CONTENT=$(tr -d '\n' < "$SECRETS_DIR/n8n_encryption_key")
  KEY_LEN=${#KEY_CONTENT}
  if [ "$KEY_LEN" -ge 32 ]; then
    pass "T06 — n8n_encryption_key is $KEY_LEN chars (≥32)"
  else
    fail "T06 — n8n_encryption_key is only $KEY_LEN chars (need ≥32)"
  fi
else
  fail "T06 — secrets/n8n_encryption_key not found"
fi

# -----------------------------------------------
# T07: postgres_password ≥ 16 chars
# -----------------------------------------------
echo "T07: Checking postgres_password length..."
if [ -f "$SECRETS_DIR/postgres_password" ]; then
  PG_CONTENT=$(tr -d '\n' < "$SECRETS_DIR/postgres_password")
  PG_LEN=${#PG_CONTENT}
  if [ "$PG_LEN" -ge 16 ]; then
    pass "T07 — postgres_password is $PG_LEN chars (≥16)"
  else
    fail "T07 — postgres_password is only $PG_LEN chars (need ≥16)"
  fi
else
  fail "T07 — secrets/postgres_password not found"
fi

# -----------------------------------------------
# T08: docker-compose has no :latest images
# -----------------------------------------------
echo "T08: Checking for :latest images..."
if [ -f "$COMPOSE_FILE" ]; then
  if grep -qE 'image:.*:latest' "$COMPOSE_FILE"; then
    fail "T08 — docker-compose contains :latest image(s)"
  else
    pass "T08 — no :latest images in docker-compose"
  fi
else
  fail "T08 — docker-compose file not found"
fi

# -----------------------------------------------
# T09: Dockerfiles SPA have USER nginx
# -----------------------------------------------
echo "T09: Checking SPA Dockerfiles for USER nginx..."
T09_OK=1
for df in "$PROJECT_DIR/admin-dashboard/Dockerfile" "$PROJECT_DIR/kiosk-app/Dockerfile"; do
  if [ -f "$df" ]; then
    if ! grep -q '^USER nginx' "$df"; then
      fail "T09 — $(basename "$(dirname "$df")")/Dockerfile missing USER nginx"
      T09_OK=0
    fi
  else
    fail "T09 — $df not found"
    T09_OK=0
  fi
done
if [ "$T09_OK" -eq 1 ]; then
  pass "T09 — SPA Dockerfiles have USER nginx"
fi

# -----------------------------------------------
# T10: docker-compose has no-new-privileges on app services
# -----------------------------------------------
echo "T10: Checking no-new-privileges..."
if [ -f "$COMPOSE_FILE" ]; then
  COUNT=$(grep -c 'no-new-privileges:true' "$COMPOSE_FILE" || true)
  if [ "$COUNT" -ge 7 ]; then
    pass "T10 — no-new-privileges found $COUNT times (≥7)"
  else
    fail "T10 — no-new-privileges found only $COUNT times (need ≥7)"
  fi
else
  fail "T10 — docker-compose file not found"
fi

# -----------------------------------------------
# T11: docker-compose has cap_drop: ALL on app services
# -----------------------------------------------
echo "T11: Checking cap_drop: ALL..."
if [ -f "$COMPOSE_FILE" ]; then
  COUNT=$(grep -c 'cap_drop' "$COMPOSE_FILE" || true)
  if [ "$COUNT" -ge 7 ]; then
    pass "T11 — cap_drop found $COUNT times (≥7)"
  else
    fail "T11 — cap_drop found only $COUNT times (need ≥7)"
  fi
else
  fail "T11 — docker-compose file not found"
fi

# -----------------------------------------------
# T12: Traefik port 8080 bound to 127.0.0.1
# -----------------------------------------------
echo "T12: Checking Traefik dashboard binding..."
if [ -f "$COMPOSE_FILE" ]; then
  if grep -qE '"127\.0\.0\.1:8080:8080"' "$COMPOSE_FILE"; then
    pass "T12 — Traefik dashboard bound to 127.0.0.1"
  else
    fail "T12 — Traefik port 8080 not bound to 127.0.0.1"
  fi
else
  fail "T12 — docker-compose file not found"
fi

# -----------------------------------------------
# T13: Nginx has access_log configured
# -----------------------------------------------
echo "T13: Checking Nginx access_log..."
if [ -f "$NGINX_CONF" ]; then
  if grep -q 'access_log' "$NGINX_CONF"; then
    pass "T13 — Nginx access_log configured"
  else
    fail "T13 — Nginx access_log not configured"
  fi
else
  fail "T13 — nginx.conf not found"
fi

# -----------------------------------------------
# T14: PostgreSQL log_statement ≠ none
# -----------------------------------------------
echo "T14: Checking PostgreSQL log_statement..."
if [ -f "$COMPOSE_FILE" ]; then
  if grep -q 'log_statement=none' "$COMPOSE_FILE"; then
    fail "T14 — PostgreSQL log_statement=none (no audit trail)"
  else
    pass "T14 — PostgreSQL log_statement is not 'none'"
  fi
else
  fail "T14 — docker-compose file not found"
fi

# -----------------------------------------------
# T15: db_migrate_all.sh no raw SQL injection
# -----------------------------------------------
echo "T15: Checking db_migrate_all.sh for SQL injection..."
MIGRATE_SCRIPT="$PROJECT_DIR/scripts/db_migrate_all.sh"
if [ -f "$MIGRATE_SCRIPT" ]; then
  if grep -q "'\$filename'" "$MIGRATE_SCRIPT"; then
    fail "T15 — db_migrate_all.sh contains unescaped '\$filename' in SQL"
  else
    pass "T15 — db_migrate_all.sh SQL injection fixed"
  fi
else
  fail "T15 — db_migrate_all.sh not found"
fi

echo ""
echo "=== Section 1 Complete ==="
echo ""

# =============================================
# Section 2: Network Tests (optional)
# =============================================
if $NETWORK_TESTS; then
  echo "=== Section 2: Network Tests ==="
  echo ""

  # Detect gateway URL
  API_BASE="${API_BASE:-http://localhost:8080}"

  # -----------------------------------------------
  # T16: DELETE /v1/inbound/whatsapp → rejected
  # -----------------------------------------------
  echo "T16: DELETE /v1/inbound/whatsapp..."
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$API_BASE/v1/inbound/whatsapp" 2>/dev/null || echo "000")
  if [ "$STATUS" = "405" ] || [ "$STATUS" = "404" ] || [ "$STATUS" = "403" ]; then
    pass "T16 — DELETE rejected with $STATUS"
  else
    fail "T16 — DELETE returned $STATUS (expected 405/404/403)"
  fi

  # -----------------------------------------------
  # T17: PUT /v1/inbound/whatsapp → rejected
  # -----------------------------------------------
  echo "T17: PUT /v1/inbound/whatsapp..."
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$API_BASE/v1/inbound/whatsapp" 2>/dev/null || echo "000")
  if [ "$STATUS" = "405" ] || [ "$STATUS" = "404" ] || [ "$STATUS" = "403" ]; then
    pass "T17 — PUT rejected with $STATUS"
  else
    fail "T17 — PUT returned $STATUS (expected 405/404/403)"
  fi

  # -----------------------------------------------
  # T18: POST without Content-Type: application/json → 415
  # -----------------------------------------------
  echo "T18: POST without JSON Content-Type..."
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Content-Type: text/plain" -d '{}' "$API_BASE/v1/inbound/whatsapp" 2>/dev/null || echo "000")
  if [ "$STATUS" = "415" ]; then
    pass "T18 — Non-JSON POST rejected with 415"
  else
    fail "T18 — Non-JSON POST returned $STATUS (expected 415)"
  fi

  # -----------------------------------------------
  # T19: Unknown path → 404
  # -----------------------------------------------
  echo "T19: GET /v1/random..."
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$API_BASE/v1/random" 2>/dev/null || echo "000")
  if [ "$STATUS" = "404" ]; then
    pass "T19 — Unknown path returned 404"
  else
    fail "T19 — Unknown path returned $STATUS (expected 404)"
  fi

  # -----------------------------------------------
  # T20: /healthz → 200
  # -----------------------------------------------
  echo "T20: GET /healthz..."
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$API_BASE/healthz" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ]; then
    pass "T20 — /healthz returned 200"
  else
    fail "T20 — /healthz returned $STATUS (expected 200)"
  fi

  # -----------------------------------------------
  # T21: Burst 100 requests → at least 1x 429
  # -----------------------------------------------
  echo "T21: Burst 100 requests (rate limiting)..."
  GOT_429=0
  for i in $(seq 1 100); do
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$API_BASE/v1/inbound/whatsapp" 2>/dev/null || echo "000")
    if [ "$STATUS" = "429" ] || [ "$STATUS" = "503" ]; then
      GOT_429=1
      break
    fi
  done
  if [ "$GOT_429" -eq 1 ]; then
    pass "T21 — Rate limiting triggered (429/503 after $i requests)"
  else
    fail "T21 — No rate limiting detected after 100 requests"
  fi

  # -----------------------------------------------
  # T22: ?token=xxx → 401 with SEC-001
  # -----------------------------------------------
  echo "T22: Query string token rejection..."
  BODY=$(curl -s "$API_BASE/v1/inbound/whatsapp?token=xxx" 2>/dev/null || echo "")
  if echo "$BODY" | grep -q "SEC-001"; then
    pass "T22 — Query token rejected with SEC-001"
  else
    fail "T22 — Query token not properly rejected"
  fi

  # -----------------------------------------------
  # T23: Errors do not contain stack traces
  # -----------------------------------------------
  echo "T23: No stack traces in errors..."
  BODY=$(curl -s -X POST -H "Content-Type: application/json" -d '{"invalid":true}' "$API_BASE/v1/inbound/whatsapp" 2>/dev/null || echo "")
  if echo "$BODY" | grep -qiE 'stack|traceback|at .*\.js:|Error:.*\n.*at '; then
    fail "T23 — Error response contains stack trace"
  else
    pass "T23 — No stack traces in error responses"
  fi

  echo ""
  echo "=== Section 2 Complete ==="
else
  echo "(Section 2 skipped — use --network to run network tests)"
fi

echo ""
echo "============================================="
echo "  Results: $PASSED/$TOTAL passed, $FAILED failed"
echo "============================================="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
