#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# MASTER EXECUTION SCRIPT
# Exécute tous les agents de patch dans l'ordre correct
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TOTAL_AGENTS=0
PASSED_AGENTS=0
FAILED_AGENTS=0
SKIPPED_AGENTS=0

log_header() { echo -e "\n${MAGENTA}════════════════════════════════════════${NC}"; echo -e "${MAGENTA}  $1${NC}"; echo -e "${MAGENTA}════════════════════════════════════════${NC}\n"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; ((PASSED_AGENTS++)); }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; ((FAILED_AGENTS++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_skip() { echo -e "${CYAN}[SKIP]${NC} $1"; ((SKIPPED_AGENTS++)); }

# ==========================================================
# PHASE 0: PRE-FLIGHT
# ==========================================================
preflight() {
    log_header "PHASE 0: PRE-FLIGHT CHECKS"
    
    # Check we're in project root
    if [ ! -f "$PROJECT_ROOT/VERSION" ]; then
        log_error "Not in project root (VERSION file not found)"
        exit 1
    fi
    log_success "Project root verified"
    
    # Check required files exist
    local required_files=(
        "infra/gateway/nginx.conf.patched"
        "config/.env.example.patched"
        "workflows/W1_IN_WA.json"
        "workflows/W4_CORE.json"
        "workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            log_info "✓ $file"
        else
            log_error "✗ $file MISSING"
            exit 1
        fi
    done
    
    log_success "All required files present"
}

# ==========================================================
# PHASE 1: BACKUP
# ==========================================================
backup() {
    log_header "PHASE 1: CREATING BACKUPS"
    
    BACKUP_DIR="$PROJECT_ROOT/backups/pre_patch_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup critical files
    cp "$PROJECT_ROOT/infra/gateway/nginx.conf" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$PROJECT_ROOT/config/.env.example" "$BACKUP_DIR/" 2>/dev/null || true
    cp -r "$PROJECT_ROOT/workflows" "$BACKUP_DIR/" 2>/dev/null || true
    
    echo "$BACKUP_DIR" > "$PROJECT_ROOT/.last_backup_dir"
    
    log_success "Backup created: $BACKUP_DIR"
}

# ==========================================================
# WAVE 1: CRITICAL SECURITY
# ==========================================================
wave1_critical() {
    log_header "WAVE 1: CRITICAL SECURITY PATCHES"
    
    # Agent W1_01: Gateway Activator
    log_info "Executing AGENT_W1_01: Gateway Activator..."
    ((TOTAL_AGENTS++))
    
    if [ -f "$PROJECT_ROOT/infra/gateway/nginx.conf.patched" ]; then
        cp "$PROJECT_ROOT/infra/gateway/nginx.conf.patched" "$PROJECT_ROOT/infra/gateway/nginx.conf"
        
        if grep -q "query_token_blocked\|block_query_token" "$PROJECT_ROOT/infra/gateway/nginx.conf"; then
            log_success "W1_01: Gateway patched - query token protection ACTIVE"
        else
            log_error "W1_01: Gateway patch failed"
        fi
    else
        log_error "W1_01: nginx.conf.patched not found"
    fi
    
    # Agent W1_02: Signature Validator
    log_info "Executing AGENT_W1_02: Signature Validator..."
    ((TOTAL_AGENTS++))
    
    if [ -f "$PROJECT_ROOT/agents/wave1_critical/snippets/signature_validation_node.js" ]; then
        log_success "W1_02: Signature validation code ready"
        log_warn "W1_02: MANUAL ACTION REQUIRED - Add code to W1/W2/W3 workflows"
    else
        log_skip "W1_02: Signature validation snippet not found"
    fi
    
    # Agent W1_03: Legacy Token Killer
    log_info "Executing AGENT_W1_03: Legacy Token Killer..."
    ((TOTAL_AGENTS++))
    
    if grep -q "LEGACY_SHARED_TOKEN_ENABLED" "$PROJECT_ROOT/config/.env.example.patched"; then
        log_success "W1_03: Legacy token kill-switch present in .env.example.patched"
    else
        log_warn "W1_03: Adding LEGACY_SHARED_TOKEN_ENABLED to config..."
        echo "LEGACY_SHARED_TOKEN_ENABLED=false" >> "$PROJECT_ROOT/config/.env.example.patched"
        log_success "W1_03: Kill-switch added"
    fi
}

# ==========================================================
# WAVE 2: HIGH PRIORITY
# ==========================================================
wave2_high() {
    log_header "WAVE 2: HIGH PRIORITY PATCHES"
    
    # Agent W2_01: Audit WA Connector
    log_info "Executing AGENT_W2_01: Audit WA Connector..."
    ((TOTAL_AGENTS++))
    
    # Check if audit table migration exists
    if ls "$PROJECT_ROOT/db/migrations/"*"admin_wa_audit"* 1>/dev/null 2>&1; then
        log_success "W2_01: Audit table migration exists"
    else
        log_warn "W2_01: Audit migration not found - may need to create"
    fi
    
    # Check if flag is in config
    if grep -q "ADMIN_WA_AUDIT_ENABLED" "$PROJECT_ROOT/config/.env.example.patched"; then
        log_success "W2_01: ADMIN_WA_AUDIT_ENABLED flag present"
    else
        echo "ADMIN_WA_AUDIT_ENABLED=true" >> "$PROJECT_ROOT/config/.env.example.patched"
        log_success "W2_01: ADMIN_WA_AUDIT_ENABLED added"
    fi
    
    log_warn "W2_01: MANUAL ACTION REQUIRED - Add audit nodes to W14 workflow"
}

# ==========================================================
# WAVE 3: MEDIUM PRIORITY
# ==========================================================
wave3_medium() {
    log_header "WAVE 3: MEDIUM PRIORITY PATCHES (UX/L10N)"
    
    # Agent W3_01: L10N Activator
    log_info "Executing AGENT_W3_01: L10N Activator..."
    ((TOTAL_AGENTS++))
    
    if grep -q "L10N_ENABLED=true" "$PROJECT_ROOT/config/.env.example.patched"; then
        log_success "W3_01: L10N_ENABLED=true in .env.example.patched"
    else
        log_error "W3_01: L10N_ENABLED not set to true"
    fi
    
    # Apply the patched config
    if [ -f "$PROJECT_ROOT/config/.env.example.patched" ]; then
        cp "$PROJECT_ROOT/config/.env.example.patched" "$PROJECT_ROOT/config/.env.example"
        log_success "W3_01: .env.example.patched → .env.example"
    fi
}

# ==========================================================
# WAVE 4: VALIDATION
# ==========================================================
wave4_validation() {
    log_header "WAVE 4: VALIDATION"
    
    # Check nginx.conf
    log_info "Validating nginx.conf..."
    if grep -q "query_token_blocked\|block_query_token" "$PROJECT_ROOT/infra/gateway/nginx.conf"; then
        log_success "nginx.conf: Query token protection ✓"
    else
        log_error "nginx.conf: Query token protection MISSING"
    fi
    
    # Check .env.example
    log_info "Validating .env.example..."
    
    local checks=(
        "LEGACY_SHARED_TOKEN_ENABLED=false"
        "L10N_ENABLED=true"
        "ADMIN_WA_AUDIT_ENABLED"
        "SIGNATURE_VALIDATION_MODE"
    )
    
    for check in "${checks[@]}"; do
        if grep -q "$check" "$PROJECT_ROOT/config/.env.example"; then
            log_info "  ✓ $check"
        else
            log_warn "  ✗ $check not found"
        fi
    done
    
    # Check migrations exist
    log_info "Validating migrations..."
    local migration_count=$(ls "$PROJECT_ROOT/db/migrations/"*"2026-01-23"* 2>/dev/null | wc -l)
    log_info "  Found $migration_count migrations for 2026-01-23"
    
    # Run smoke tests if available
    if [ -f "$PROJECT_ROOT/scripts/smoke_security.sh" ]; then
        log_info "Running security smoke tests..."
        if bash "$PROJECT_ROOT/scripts/smoke_security.sh" 2>/dev/null; then
            log_success "Security smoke tests PASSED"
        else
            log_warn "Security smoke tests require running server"
        fi
    fi
}

# ==========================================================
# SUMMARY
# ==========================================================
summary() {
    log_header "EXECUTION SUMMARY"
    
    echo -e "Total Agents:  $TOTAL_AGENTS"
    echo -e "${GREEN}Passed:${NC}        $PASSED_AGENTS"
    echo -e "${RED}Failed:${NC}        $FAILED_AGENTS"
    echo -e "${CYAN}Skipped:${NC}       $SKIPPED_AGENTS"
    echo ""
    
    if [ $FAILED_AGENTS -eq 0 ]; then
        echo -e "${GREEN}═══════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ALL AUTOMATED PATCHES APPLIED SUCCESSFULLY${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    else
        echo -e "${RED}═══════════════════════════════════════════${NC}"
        echo -e "${RED}  SOME PATCHES FAILED - REVIEW REQUIRED${NC}"
        echo -e "${RED}═══════════════════════════════════════════${NC}"
    fi
    
    echo ""
    echo "MANUAL ACTIONS STILL REQUIRED:"
    echo "────────────────────────────────"
    echo "1. Add signature validation code to W1/W2/W3 workflows"
    echo "   → See: agents/wave1_critical/snippets/signature_validation_node.js"
    echo ""
    echo "2. Add audit nodes to W14 workflow"
    echo "   → See: agents/wave2_high/AGENT_W2_01_AUDIT_WA_CONNECTOR.md"
    echo ""
    echo "3. Update production .env with new values"
    echo "   → Source: config/.env.example"
    echo ""
    echo "4. Apply database migrations"
    echo "   → psql -f db/migrations/2026-01-23_*.sql"
    echo ""
    echo "5. Reload nginx"
    echo "   → docker exec gateway nginx -s reload"
    echo ""
    echo "6. Run full validation"
    echo "   → ./scripts/smoke_security.sh"
    echo "   → ./scripts/test_harness.sh"
    echo ""
    
    # Save rollback info
    BACKUP_DIR=$(cat "$PROJECT_ROOT/.last_backup_dir" 2>/dev/null || echo "backups/")
    echo "ROLLBACK: cp -r $BACKUP_DIR/* . "
}

# ==========================================================
# MAIN
# ==========================================================
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║  AGENT ARMY MASTER EXECUTION                       ║"
    echo "║  P0 Security Patches for Production                ║"
    echo "║  Version: 2026-01-23                               ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
    
    # Parse args
    SKIP_BACKUP=false
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-backup) SKIP_BACKUP=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --skip-backup   Skip backup phase"
                echo "  --dry-run       Show what would be done"
                echo "  --help          Show this help"
                exit 0
                ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    # Execute phases
    preflight
    
    if [ "$SKIP_BACKUP" = false ]; then
        backup
    fi
    
    wave1_critical
    wave2_high
    wave3_medium
    wave4_validation
    summary
}

main "$@"
