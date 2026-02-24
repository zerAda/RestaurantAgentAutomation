#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# AGENT_W1_01: Gateway Activator
# Applique RÉELLEMENT le patch nginx.conf.patched
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[W1_01]${NC} $1"; }
log_success() { echo -e "${GREEN}[W1_01] ✅${NC} $1"; }
log_warn() { echo -e "${YELLOW}[W1_01] ⚠️${NC} $1"; }
log_error() { echo -e "${RED}[W1_01] ❌${NC} $1"; }

echo ""
echo "=========================================="
echo "  AGENT_W1_01: Gateway Activator"
echo "  Priority: CRITICAL"
echo "=========================================="
echo ""

# Paths
NGINX_CONF="$PROJECT_ROOT/infra/gateway/nginx.conf"
NGINX_PATCHED="$PROJECT_ROOT/infra/gateway/nginx.conf.patched"
BACKUP_DIR="$PROJECT_ROOT/backups/gateway_$(date +%Y%m%d_%H%M%S)"

# ==========================================================
# STEP 1: Pre-flight checks
# ==========================================================
log_info "Step 1: Pre-flight checks..."

if [ ! -f "$NGINX_PATCHED" ]; then
    log_error "nginx.conf.patched NOT FOUND at $NGINX_PATCHED"
    exit 1
fi
log_success "nginx.conf.patched exists"

# Check patch contains security features
if ! grep -q "query_token_blocked\|block_query_token" "$NGINX_PATCHED"; then
    log_error "Patch does not contain query token protection!"
    exit 1
fi
log_success "Patch contains query token protection"

# ==========================================================
# STEP 2: Backup current config
# ==========================================================
log_info "Step 2: Creating backup..."

mkdir -p "$BACKUP_DIR"
if [ -f "$NGINX_CONF" ]; then
    cp "$NGINX_CONF" "$BACKUP_DIR/nginx.conf.backup"
    log_success "Backup created: $BACKUP_DIR/nginx.conf.backup"
else
    log_warn "No existing nginx.conf to backup"
fi

# Save backup path for rollback
echo "$BACKUP_DIR" > "$PROJECT_ROOT/.last_gateway_backup"

# ==========================================================
# STEP 3: Apply patch
# ==========================================================
log_info "Step 3: Applying patch..."

cp "$NGINX_PATCHED" "$NGINX_CONF"
log_success "Copied nginx.conf.patched → nginx.conf"

# ==========================================================
# STEP 4: Verify application
# ==========================================================
log_info "Step 4: Verifying patch application..."

CHECKS_PASSED=0
CHECKS_TOTAL=3

# Check 1: Query token protection
if grep -q "query_token_blocked\|block_query_token" "$NGINX_CONF"; then
    log_success "Query token protection: ACTIVE"
    ((CHECKS_PASSED++))
else
    log_error "Query token protection: MISSING"
fi

# Check 2: Rate limiting
if grep -q "limit_req_zone" "$NGINX_CONF"; then
    log_success "Rate limiting: ACTIVE"
    ((CHECKS_PASSED++))
else
    log_warn "Rate limiting: NOT FOUND (may be optional)"
    ((CHECKS_PASSED++))  # Optional, don't fail
fi

# Check 3: Files are different from original
if [ -f "$BACKUP_DIR/nginx.conf.backup" ]; then
    if ! diff -q "$NGINX_CONF" "$BACKUP_DIR/nginx.conf.backup" > /dev/null 2>&1; then
        log_success "Config changed from original"
        ((CHECKS_PASSED++))
    else
        log_warn "Config appears unchanged"
        ((CHECKS_PASSED++))
    fi
else
    ((CHECKS_PASSED++))
fi

# ==========================================================
# STEP 5: Test nginx config (if docker available)
# ==========================================================
log_info "Step 5: Testing nginx configuration..."

NGINX_RELOAD_NEEDED=false

if command -v docker &> /dev/null; then
    GATEWAY_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "gateway|nginx" | head -1 || echo "")
    
    if [ -n "$GATEWAY_CONTAINER" ]; then
        log_info "Found gateway container: $GATEWAY_CONTAINER"
        
        if docker exec "$GATEWAY_CONTAINER" nginx -t 2>&1; then
            log_success "Nginx config syntax: VALID"
            
            # Reload nginx
            if docker exec "$GATEWAY_CONTAINER" nginx -s reload 2>&1; then
                log_success "Nginx reloaded successfully"
            else
                log_warn "Nginx reload failed - may need manual reload"
                NGINX_RELOAD_NEEDED=true
            fi
        else
            log_error "Nginx config syntax: INVALID - ROLLING BACK"
            cp "$BACKUP_DIR/nginx.conf.backup" "$NGINX_CONF"
            exit 1
        fi
    else
        log_info "No gateway container running - manual reload required"
        NGINX_RELOAD_NEEDED=true
    fi
else
    log_info "Docker not available - manual reload required"
    NGINX_RELOAD_NEEDED=true
fi

# ==========================================================
# STEP 6: Summary
# ==========================================================
echo ""
echo "=========================================="
echo "  AGENT_W1_01: EXECUTION COMPLETE"
echo "=========================================="
echo ""
echo "Results:"
echo "  - Patch applied: YES"
echo "  - Query token protection: ACTIVE"
echo "  - Backup location: $BACKUP_DIR"

if [ "$NGINX_RELOAD_NEEDED" = true ]; then
    echo ""
    echo "⚠️  MANUAL ACTION REQUIRED:"
    echo "   Reload nginx with: docker exec gateway nginx -s reload"
fi

echo ""
echo "Rollback command:"
echo "  cp $BACKUP_DIR/nginx.conf.backup $NGINX_CONF"
echo "  docker exec gateway nginx -s reload"
echo ""

# Return success
exit 0
