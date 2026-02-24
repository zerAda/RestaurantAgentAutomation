#!/usr/bin/env bash
# =============================================================================
# CI/CD Workflow Validation Script
# =============================================================================
# Run this locally to validate workflow YAML syntax and configuration
# before pushing to GitHub.
#
# Usage: ./scripts/validate_cicd.sh [--vps]
#   --vps   Also test VPS connectivity (requires SSH key)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_DIR="$PROJECT_ROOT/.github/workflows"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((ERRORS++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARNINGS++)); }
log_info() { echo -e "[INFO] $1"; }

echo "=============================================="
echo "CI/CD Workflow Validation"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# 1. Check YAML syntax
# -----------------------------------------------------------------------------
echo "=== 1. YAML Syntax Check ==="

for workflow in "$WORKFLOWS_DIR"/*.yml; do
    filename=$(basename "$workflow")

    # Basic YAML validation using Python
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml; yaml.safe_load(open('$workflow'))" 2>/dev/null; then
            log_pass "$filename - YAML syntax valid"
        else
            log_fail "$filename - YAML syntax error"
        fi
    else
        log_warn "Python3 not available - skipping YAML validation for $filename"
    fi
done

echo ""

# -----------------------------------------------------------------------------
# 2. Check for common issues
# -----------------------------------------------------------------------------
echo "=== 2. Common Issues Check ==="

# Check health-monitor.yml
HEALTH_WORKFLOW="$WORKFLOWS_DIR/health-monitor.yml"
if [ -f "$HEALTH_WORKFLOW" ]; then
    # Check if HEALTH_URL contains 'console' or 'n8n.' (protected endpoints)
    if grep -q "HEALTH_URL.*console\." "$HEALTH_WORKFLOW" || grep -q "HEALTH_URL.*n8n\." "$HEALTH_WORKFLOW"; then
        log_warn "health-monitor.yml: HEALTH_URL may point to protected console endpoint"
    else
        log_pass "health-monitor.yml: HEALTH_URL appears to use API gateway"
    fi

    # Check for broken secret check pattern
    if grep -q 'if:.*secrets\..*!=' "$HEALTH_WORKFLOW"; then
        log_fail "health-monitor.yml: Contains broken 'if: secrets.X != ...' pattern"
    else
        log_pass "health-monitor.yml: No broken secret check pattern"
    fi

    # Check for secret in run block
    if grep -q '\${{ secrets\.' "$HEALTH_WORKFLOW" | grep -v '^[[:space:]]*env:' | head -1; then
        log_warn "health-monitor.yml: Direct secret access in run block detected"
    fi
else
    log_warn "health-monitor.yml not found"
fi

# Check scheduled-backup.yml
BACKUP_WORKFLOW="$WORKFLOWS_DIR/scheduled-backup.yml"
if [ -f "$BACKUP_WORKFLOW" ]; then
    # Check for broken secret check pattern
    if grep -q '\[ -n "\${{ secrets\.' "$BACKUP_WORKFLOW"; then
        log_fail "scheduled-backup.yml: Contains broken secret check pattern (if [ -n \"\${{ secrets.X }}\" ])"
    else
        log_pass "scheduled-backup.yml: No broken secret check pattern"
    fi

    # Check for hardcoded secrets
    if grep -qiE "(password|secret|key)[[:space:]]*[:=][[:space:]]*['\"][^$]" "$BACKUP_WORKFLOW"; then
        log_fail "scheduled-backup.yml: Possible hardcoded secret detected"
    else
        log_pass "scheduled-backup.yml: No hardcoded secrets detected"
    fi

    # Check for pre-checks job
    if grep -q "pre-checks:" "$BACKUP_WORKFLOW" || grep -q "Pre-checks" "$BACKUP_WORKFLOW"; then
        log_pass "scheduled-backup.yml: Contains pre-checks job"
    else
        log_warn "scheduled-backup.yml: No pre-checks job found"
    fi
else
    log_warn "scheduled-backup.yml not found"
fi

echo ""

# -----------------------------------------------------------------------------
# 3. Check required files exist
# -----------------------------------------------------------------------------
echo "=== 3. Required Files Check ==="

REQUIRED_FILES=(
    "$PROJECT_ROOT/docker-compose.hostinger.prod.yml"
    "$PROJECT_ROOT/infra/gateway/nginx.conf"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        log_pass "$(basename "$file") exists"
    else
        log_fail "$(basename "$file") missing"
    fi
done

# Check nginx has /healthz endpoint
if [ -f "$PROJECT_ROOT/infra/gateway/nginx.conf" ]; then
    if grep -q "location.*=.*/healthz" "$PROJECT_ROOT/infra/gateway/nginx.conf"; then
        log_pass "nginx.conf: /healthz endpoint defined"
    else
        log_fail "nginx.conf: /healthz endpoint not found"
    fi
fi

echo ""

# -----------------------------------------------------------------------------
# 4. VPS connectivity test (optional)
# -----------------------------------------------------------------------------
if [[ "${1:-}" == "--vps" ]]; then
    echo "=== 4. VPS Connectivity Test ==="

    VPS_HOST="${VPS_HOST:-72.60.190.192}"
    VPS_USER="${VPS_USER:-deploy}"

    log_info "Testing SSH to $VPS_USER@$VPS_HOST..."

    if ssh -o ConnectTimeout=10 -o BatchMode=yes "$VPS_USER@$VPS_HOST" "echo 'SSH OK'" 2>/dev/null; then
        log_pass "SSH connection successful"

        # Test docker access
        if ssh -o BatchMode=yes "$VPS_USER@$VPS_HOST" "docker info >/dev/null 2>&1"; then
            log_pass "Docker accessible"
        else
            log_fail "Docker not accessible (user not in docker group?)"
        fi

        # Test project directory
        PROJECT_DIR="${PROJECT_DIR:-/docker/n8n}"
        if ssh -o BatchMode=yes "$VPS_USER@$VPS_HOST" "[ -d '$PROJECT_DIR' ]"; then
            log_pass "Project directory exists: $PROJECT_DIR"
        else
            log_fail "Project directory not found: $PROJECT_DIR"
        fi

        # Test postgres
        if ssh -o BatchMode=yes "$VPS_USER@$VPS_HOST" "cd '$PROJECT_DIR' && docker compose -f docker-compose.hostinger.prod.yml exec -T postgres pg_isready -U n8n -d n8n" 2>/dev/null; then
            log_pass "PostgreSQL is ready"
        else
            log_warn "PostgreSQL not ready or not running"
        fi

        # Test local health endpoint
        LOCAL_HEALTH=$(ssh -o BatchMode=yes "$VPS_USER@$VPS_HOST" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/healthz 2>/dev/null" || echo "000")
        if [ "$LOCAL_HEALTH" = "200" ]; then
            log_pass "Local health endpoint: HTTP 200"
        else
            log_warn "Local health endpoint: HTTP $LOCAL_HEALTH"
        fi

    else
        log_fail "SSH connection failed"
    fi

    echo ""
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo "=============================================="
echo "Summary"
echo "=============================================="
echo -e "Errors:   ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}Validation FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}Validation PASSED${NC}"
    exit 0
fi
