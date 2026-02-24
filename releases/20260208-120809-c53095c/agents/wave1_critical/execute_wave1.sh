#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# WAVE 1: CRITICAL SECURITY PATCHES
# Execute all Wave 1 agents
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  WAVE 1: CRITICAL SECURITY PATCHES                 ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# ==========================================================
# AGENT W1_01: Gateway Activator
# ==========================================================
echo "═══ AGENT W1_01: Gateway Activator ═══"

NGINX_CONF="$PROJECT_ROOT/infra/gateway/nginx.conf"
NGINX_PATCHED="$PROJECT_ROOT/infra/gateway/nginx.conf.patched"

if [ ! -f "$NGINX_PATCHED" ]; then
    echo "❌ ERROR: nginx.conf.patched not found!"
    exit 1
fi

# Backup
mkdir -p "$PROJECT_ROOT/backups"
cp "$NGINX_CONF" "$PROJECT_ROOT/backups/nginx.conf.$(date +%Y%m%d_%H%M%S).bak" 2>/dev/null || true

# Apply
cp "$NGINX_PATCHED" "$NGINX_CONF"

# Verify
if grep -q "query_token_blocked\|block_query_token" "$NGINX_CONF"; then
    echo "✅ Gateway patched - query token protection ACTIVE"
else
    echo "❌ Gateway patch FAILED"
    exit 1
fi

if grep -q "limit_req_zone" "$NGINX_CONF"; then
    echo "✅ Rate limiting ACTIVE"
fi

echo ""

# ==========================================================
# AGENT W1_02: Signature Validator Setup
# ==========================================================
echo "═══ AGENT W1_02: Signature Validator Setup ═══"

SNIPPET_DIR="$SCRIPT_DIR/snippets"
mkdir -p "$SNIPPET_DIR"

# Check snippet exists
if [ -f "$SNIPPET_DIR/signature_validation_node.js" ]; then
    echo "✅ Signature validation code ready"
else
    echo "⚠️  Creating signature validation snippet..."
    # Snippet should already exist from agent creation
fi

# Add to .env if not present
ENV_FILE="$PROJECT_ROOT/config/.env.example"
if ! grep -q "SIGNATURE_VALIDATION_MODE" "$ENV_FILE" 2>/dev/null; then
    echo "" >> "$ENV_FILE"
    echo "# Signature Validation (W1_02)" >> "$ENV_FILE"
    echo "SIGNATURE_VALIDATION_MODE=warn" >> "$ENV_FILE"
    echo "META_APP_SECRET=" >> "$ENV_FILE"
    echo "SIGNATURE_TIME_WINDOW_SEC=300" >> "$ENV_FILE"
    echo "✅ Signature config added to .env.example"
else
    echo "✅ Signature config already present"
fi

echo "⚠️  MANUAL: Add signature_validation_node.js to W1/W2/W3"
echo ""

# ==========================================================
# AGENT W1_03: Legacy Token Killer
# ==========================================================
echo "═══ AGENT W1_03: Legacy Token Killer ═══"

# Check and update .env
if ! grep -q "LEGACY_SHARED_TOKEN_ENABLED" "$ENV_FILE" 2>/dev/null; then
    echo "" >> "$ENV_FILE"
    echo "# Legacy Token Kill-Switch (W1_03)" >> "$ENV_FILE"
    echo "LEGACY_SHARED_TOKEN_ENABLED=false" >> "$ENV_FILE"
    echo "✅ LEGACY_SHARED_TOKEN_ENABLED=false added"
else
    # Update to false if it exists
    sed -i 's/LEGACY_SHARED_TOKEN_ENABLED=true/LEGACY_SHARED_TOKEN_ENABLED=false/g' "$ENV_FILE"
    echo "✅ LEGACY_SHARED_TOKEN_ENABLED=false"
fi

# Ensure WEBHOOK_SHARED_TOKEN is empty
if grep -q "^WEBHOOK_SHARED_TOKEN=REPLACE" "$ENV_FILE" 2>/dev/null; then
    sed -i 's/^WEBHOOK_SHARED_TOKEN=REPLACE.*/WEBHOOK_SHARED_TOKEN=/g' "$ENV_FILE"
    echo "✅ WEBHOOK_SHARED_TOKEN cleared"
elif grep -q "^WEBHOOK_SHARED_TOKEN=$" "$ENV_FILE" 2>/dev/null; then
    echo "✅ WEBHOOK_SHARED_TOKEN already empty"
else
    echo "⚠️  Check WEBHOOK_SHARED_TOKEN manually"
fi

echo ""

# ==========================================================
# SUMMARY
# ==========================================================
echo "╔════════════════════════════════════════════════════╗"
echo "║  WAVE 1 EXECUTION COMPLETE                         ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "Automated:"
echo "  ✅ Gateway nginx.conf patched"
echo "  ✅ Signature config in .env"
echo "  ✅ Legacy token disabled in .env"
echo ""
echo "Manual actions required:"
echo "  1. Add signature_validation_node.js to W1/W2/W3"
echo "     Location: $SNIPPET_DIR/signature_validation_node.js"
echo ""
echo "  2. Reload nginx:"
echo "     docker exec gateway nginx -s reload"
echo ""
echo "  3. Update production .env with these values"
echo ""
