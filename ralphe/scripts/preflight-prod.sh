#!/bin/bash
# =============================================================================
# Preflight Production Checks
# =============================================================================
# Validates that the production environment is safe to deploy.
# Blocks deployment if dangerous dev-only values are detected.
#
# Usage: bash scripts/preflight-prod.sh
# Exit code 0 = safe to deploy, non-zero = blocked
# =============================================================================
set -euo pipefail

ERRORS=0
WARNINGS=0
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }

pass() { green "  [PASS] $*"; }
fail() { red   "  [FAIL] $*"; ERRORS=$((ERRORS + 1)); }
warn() { yellow "  [WARN] $*"; WARNINGS=$((WARNINGS + 1)); }

echo "============================================="
echo "  Preflight Production Checks"
echo "============================================="
echo ""

# -----------------------------------------------
# 1. Check .env exists
# -----------------------------------------------
echo "1. Checking .env file..."
if [ -f "$PROJECT_DIR/.env" ]; then
  pass ".env file exists"
else
  fail ".env file not found at $PROJECT_DIR/.env"
  echo ""
  red "Cannot continue without .env. Aborting."
  exit 1
fi

# Source .env for checks (without exporting to avoid side effects)
# shellcheck disable=SC1091
ENV_CONTENT=$(cat "$PROJECT_DIR/.env")

get_env_val() {
  local key="$1"
  echo "$ENV_CONTENT" | grep -E "^${key}=" | head -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//'
}

# -----------------------------------------------
# 2. Check secrets permissions
# -----------------------------------------------
echo ""
echo "2. Checking secrets permissions..."
SECRETS_DIR="$PROJECT_DIR/secrets"

if [ -d "$SECRETS_DIR" ]; then
  FIXED=0
  for secret_file in "$SECRETS_DIR"/*; do
    [ -f "$secret_file" ] || continue
    perms=$(stat -c '%a' "$secret_file" 2>/dev/null || stat -f '%Lp' "$secret_file" 2>/dev/null)
    if [ "$perms" != "600" ]; then
      chmod 600 "$secret_file"
      FIXED=$((FIXED + 1))
    fi
  done

  # Fix directory permissions
  dir_perms=$(stat -c '%a' "$SECRETS_DIR" 2>/dev/null || stat -f '%Lp' "$SECRETS_DIR" 2>/dev/null)
  if [ "$dir_perms" != "700" ]; then
    chmod 700 "$SECRETS_DIR"
    FIXED=$((FIXED + 1))
  fi

  if [ "$FIXED" -gt 0 ]; then
    warn "Fixed $FIXED file/directory permissions in secrets/"
  else
    pass "Secrets permissions OK (600 files, 700 directory)"
  fi
else
  fail "secrets/ directory not found"
fi

# -----------------------------------------------
# 3. Check ADMIN_ALLOWED_IPS
# -----------------------------------------------
echo ""
echo "3. Checking ADMIN_ALLOWED_IPS..."
ADMIN_IPS=$(get_env_val "ADMIN_ALLOWED_IPS")
if [ "$ADMIN_IPS" = "0.0.0.0/0" ]; then
  fail "ADMIN_ALLOWED_IPS=0.0.0.0/0 (open to the world!) — restrict to your IP"
elif [ -z "$ADMIN_IPS" ]; then
  fail "ADMIN_ALLOWED_IPS is empty"
else
  pass "ADMIN_ALLOWED_IPS=$ADMIN_IPS"
fi

# -----------------------------------------------
# 4. Check for dev passwords
# -----------------------------------------------
echo ""
echo "4. Checking for dev passwords..."
DEV_PATTERNS="dev_local changeme password123 admin123 secret123 n8npass"
FOUND_DEV=0
for pattern in $DEV_PATTERNS; do
  if echo "$ENV_CONTENT" | grep -qiE "PASSWORD.*=.*${pattern}|SECRET.*=.*${pattern}"; then
    fail "Found dev password pattern '$pattern' in .env"
    FOUND_DEV=1
  fi
done

# Also check secrets files
if [ -d "$SECRETS_DIR" ]; then
  for secret_file in "$SECRETS_DIR"/*; do
    [ -f "$secret_file" ] || continue
    fname=$(basename "$secret_file")
    content=$(cat "$secret_file")
    for pattern in $DEV_PATTERNS; do
      if echo "$content" | grep -qi "$pattern"; then
        fail "Secret file '$fname' contains dev pattern '$pattern'"
        FOUND_DEV=1
      fi
    done
  done
fi

if [ "$FOUND_DEV" -eq 0 ]; then
  pass "No dev passwords detected"
fi

# -----------------------------------------------
# 5. Check META_SIGNATURE_REQUIRED
# -----------------------------------------------
echo ""
echo "5. Checking META_SIGNATURE_REQUIRED..."
META_SIG=$(get_env_val "META_SIGNATURE_REQUIRED")
if [ "$META_SIG" = "off" ]; then
  fail "META_SIGNATURE_REQUIRED=off — must be 'warn' or 'enforce' in production"
elif [ "$META_SIG" = "warn" ]; then
  warn "META_SIGNATURE_REQUIRED=warn — consider 'enforce' for production"
elif [ "$META_SIG" = "enforce" ]; then
  pass "META_SIGNATURE_REQUIRED=enforce"
else
  warn "META_SIGNATURE_REQUIRED=$META_SIG (unknown value)"
fi

# -----------------------------------------------
# 6. Check Docker volumes
# -----------------------------------------------
echo ""
echo "6. Checking Docker volumes..."
VOLUMES="traefik_data n8n_data postgres_data redis_data cms_uploads ollama_data"
MISSING_VOLS=0
for vol in $VOLUMES; do
  if docker volume inspect "$vol" > /dev/null 2>&1; then
    pass "Volume $vol exists"
  else
    warn "Volume $vol missing — will be created by setup-volumes.sh"
    MISSING_VOLS=$((MISSING_VOLS + 1))
  fi
done

if [ "$MISSING_VOLS" -gt 0 ]; then
  echo "  -> Creating missing volumes..."
  bash "$PROJECT_DIR/scripts/setup-volumes.sh"
fi

# -----------------------------------------------
# 7. Validate docker-compose syntax
# -----------------------------------------------
echo ""
echo "7. Validating docker-compose syntax..."
COMPOSE_FILE="$PROJECT_DIR/docker-compose.hostinger.prod.yml"
if [ -f "$COMPOSE_FILE" ]; then
  if docker compose -f "$COMPOSE_FILE" config > /dev/null 2>&1; then
    pass "docker-compose syntax valid"
  else
    fail "docker-compose syntax error — run: docker compose -f $COMPOSE_FILE config"
  fi
else
  fail "docker-compose.hostinger.prod.yml not found"
fi

# -----------------------------------------------
# 8. Check PostgreSQL reachability (if upgrading)
# -----------------------------------------------
echo ""
echo "8. Checking PostgreSQL (if running)..."
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q postgres; then
  PG_PASSWORD=$(cat "$SECRETS_DIR/postgres_password" 2>/dev/null || echo "")
  if [ -n "$PG_PASSWORD" ]; then
    if docker exec -e PGPASSWORD="$PG_PASSWORD" "$(docker ps --filter name=postgres --format '{{.Names}}' | head -1)" \
       pg_isready -U n8n -d n8n > /dev/null 2>&1; then
      pass "PostgreSQL is reachable"
    else
      warn "PostgreSQL container exists but is not ready"
    fi
  else
    warn "Cannot check PostgreSQL — no password file"
  fi
else
  pass "PostgreSQL not running (fresh install expected)"
fi

# -----------------------------------------------
# 9. Block placeholders in .env
# -----------------------------------------------
echo ""
echo "9. Checking for placeholder values in .env..."
PLACEHOLDER_PATTERNS="REPLACE_ME REPLACE_WITH CHANGE_ME tobemodified placeholder"
FOUND_PLACEHOLDER=0
for pattern in $PLACEHOLDER_PATTERNS; do
  if echo "$ENV_CONTENT" | grep -qiE "=.*${pattern}"; then
    fail "Found placeholder '$pattern' in .env"
    FOUND_PLACEHOLDER=1
  fi
done
if [ "$FOUND_PLACEHOLDER" -eq 0 ]; then
  pass "No placeholder values in .env"
fi

# -----------------------------------------------
# 10. n8n encryption key length ≥ 32 chars
# -----------------------------------------------
echo ""
echo "10. Checking n8n encryption key length..."
if [ -f "$SECRETS_DIR/n8n_encryption_key" ]; then
  KEY_LEN=$(wc -c < "$SECRETS_DIR/n8n_encryption_key" | tr -d ' ')
  # Strip trailing newline from count
  KEY_CONTENT=$(tr -d '\n' < "$SECRETS_DIR/n8n_encryption_key")
  KEY_LEN=${#KEY_CONTENT}
  if [ "$KEY_LEN" -ge 32 ]; then
    pass "n8n_encryption_key is $KEY_LEN chars (≥32)"
  else
    fail "n8n_encryption_key is only $KEY_LEN chars (need ≥32)"
  fi
else
  fail "secrets/n8n_encryption_key not found"
fi

# -----------------------------------------------
# 11. PostgreSQL password length ≥ 16 chars
# -----------------------------------------------
echo ""
echo "11. Checking postgres password length..."
if [ -f "$SECRETS_DIR/postgres_password" ]; then
  PG_CONTENT=$(tr -d '\n' < "$SECRETS_DIR/postgres_password")
  PG_LEN=${#PG_CONTENT}
  if [ "$PG_LEN" -ge 16 ]; then
    pass "postgres_password is $PG_LEN chars (≥16)"
  else
    fail "postgres_password is only $PG_LEN chars (need ≥16)"
  fi
else
  fail "secrets/postgres_password not found"
fi

# -----------------------------------------------
# 12. Strapi secrets ≠ tobemodified
# -----------------------------------------------
echo ""
echo "12. Checking Strapi secrets..."
STRAPI_KEYS="STRAPI_ADMIN_JWT_SECRET STRAPI_JWT_SECRET STRAPI_API_TOKEN_SALT STRAPI_TRANSFER_TOKEN_SALT STRAPI_ENCRYPTION_KEY STRAPI_APP_KEYS"
STRAPI_OK=1
for key in $STRAPI_KEYS; do
  val=$(get_env_val "$key")
  if [ "$val" = "tobemodified" ] || [ "$val" = "REPLACE_ME" ] || [ -z "$val" ]; then
    fail "$key is not configured (value: '${val:-<empty>}')"
    STRAPI_OK=0
  fi
done
if [ "$STRAPI_OK" -eq 1 ]; then
  pass "All Strapi secrets configured"
fi

# -----------------------------------------------
# 13. LEGACY_SHARED_ALLOWED + WEBHOOK_SHARED_TOKEN coherence
# -----------------------------------------------
echo ""
echo "13. Checking shared token coherence..."
LEGACY_ALLOWED=$(get_env_val "LEGACY_SHARED_ALLOWED")
SHARED_TOKEN=$(get_env_val "WEBHOOK_SHARED_TOKEN")
if [ "$LEGACY_ALLOWED" = "false" ] && [ -n "$SHARED_TOKEN" ]; then
  warn "LEGACY_SHARED_ALLOWED=false but WEBHOOK_SHARED_TOKEN is set — token is unused"
else
  pass "Shared token configuration coherent"
fi

# -----------------------------------------------
# 14. No :latest images in docker-compose
# -----------------------------------------------
echo ""
echo "14. Checking for :latest images in docker-compose..."
if [ -f "$COMPOSE_FILE" ]; then
  if grep -qE 'image:.*:latest' "$COMPOSE_FILE"; then
    LATEST_IMAGES=$(grep -E 'image:.*:latest' "$COMPOSE_FILE" | sed 's/.*image: *//')
    warn "Found :latest image(s) in docker-compose: $LATEST_IMAGES"
  else
    pass "No :latest images in docker-compose"
  fi
fi

# -----------------------------------------------
# 15. Traefik dashboard port bound to 127.0.0.1
# -----------------------------------------------
echo ""
echo "15. Checking Traefik dashboard binding..."
if [ -f "$COMPOSE_FILE" ]; then
  if grep -qE '"127\.0\.0\.1:8080:8080"' "$COMPOSE_FILE"; then
    pass "Traefik dashboard bound to 127.0.0.1"
  else
    fail "Traefik dashboard port 8080 not bound to 127.0.0.1 — exposed to all interfaces"
  fi
fi

# -----------------------------------------------
# Summary
# -----------------------------------------------
echo ""
echo "============================================="
if [ "$ERRORS" -gt 0 ]; then
  red "  PREFLIGHT FAILED: $ERRORS error(s), $WARNINGS warning(s)"
  red "  Fix the errors above before deploying."
  exit 1
else
  if [ "$WARNINGS" -gt 0 ]; then
    yellow "  PREFLIGHT PASSED with $WARNINGS warning(s)"
  else
    green "  PREFLIGHT PASSED: All checks OK"
  fi
  exit 0
fi
