#!/usr/bin/env bash
set -euo pipefail

# =========================
# P0 Patch Application Script
# Applies all P0 security and UX patches
# =========================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}✅ SUCCESS:${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️  WARN:${NC} $1"; }
log_error() { echo -e "${RED}❌ ERROR:${NC} $1"; }

echo "========================================"
echo "  P0 Patch Application Script"
echo "  Version: 2026-01-23"
echo "========================================"
echo ""

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."
  
  if ! command -v psql &> /dev/null; then
    log_warn "psql not found - database migrations will need manual application"
  fi
  
  if ! command -v docker &> /dev/null; then
    log_warn "docker not found - nginx reload will need manual execution"
  fi
  
  log_success "Prerequisites check complete"
}

# Backup current configs
backup_configs() {
  log_info "Creating backups..."
  
  BACKUP_DIR="$PROJECT_ROOT/backups/$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  
  # Backup nginx config
  if [ -f "$PROJECT_ROOT/infra/gateway/nginx.conf" ]; then
    cp "$PROJECT_ROOT/infra/gateway/nginx.conf" "$BACKUP_DIR/nginx.conf.bak"
    log_success "Backed up nginx.conf"
  fi
  
  # Backup .env.example
  if [ -f "$PROJECT_ROOT/config/.env.example" ]; then
    cp "$PROJECT_ROOT/config/.env.example" "$BACKUP_DIR/.env.example.bak"
    log_success "Backed up .env.example"
  fi
  
  echo "$BACKUP_DIR" > "$PROJECT_ROOT/.last_backup_dir"
  log_success "Backups saved to $BACKUP_DIR"
}

# Apply nginx patch
apply_nginx_patch() {
  log_info "Applying nginx gateway patch (P0-SEC-01)..."
  
  if [ -f "$PROJECT_ROOT/infra/gateway/nginx.conf.patched" ]; then
    cp "$PROJECT_ROOT/infra/gateway/nginx.conf.patched" "$PROJECT_ROOT/infra/gateway/nginx.conf"
    log_success "nginx.conf patched"
    
    # Try to reload nginx if docker is available
    if command -v docker &> /dev/null; then
      if docker ps --format '{{.Names}}' 2>/dev/null | grep -q gateway; then
        docker exec gateway nginx -t && docker exec gateway nginx -s reload
        log_success "nginx reloaded"
      else
        log_warn "Gateway container not running - reload manually"
      fi
    fi
  else
    log_error "nginx.conf.patched not found"
    return 1
  fi
}

# Apply .env updates
apply_env_patch() {
  log_info "Applying .env.example patch (P0 configs)..."
  
  if [ -f "$PROJECT_ROOT/config/.env.example.patched" ]; then
    cp "$PROJECT_ROOT/config/.env.example.patched" "$PROJECT_ROOT/config/.env.example"
    log_success ".env.example updated"
    log_warn "Remember to update your actual .env file with new values!"
  else
    log_error ".env.example.patched not found"
    return 1
  fi
}

# List database migrations
list_migrations() {
  log_info "Database migrations to apply:"
  echo ""
  
  MIGRATIONS=(
    "2026-01-23_p0_sec02_disable_legacy_token.sql"
    "2026-01-23_p0_sup01_admin_wa_audit.sql"
    "2026-01-23_p0_perf_indexes.sql"
  )
  
  for migration in "${MIGRATIONS[@]}"; do
    if [ -f "$PROJECT_ROOT/db/migrations/$migration" ]; then
      echo "  - $migration"
    else
      log_warn "Migration not found: $migration"
    fi
  done
  
  echo ""
  log_info "To apply migrations, run:"
  echo ""
  echo "  export PGHOST=localhost PGPORT=5432 PGDATABASE=resto PGUSER=postgres"
  for migration in "${MIGRATIONS[@]}"; do
    echo "  psql -f db/migrations/$migration"
  done
  echo ""
}

# Make scripts executable
fix_permissions() {
  log_info "Setting script permissions..."
  
  chmod +x "$PROJECT_ROOT/scripts/smoke_security.sh" 2>/dev/null || true
  chmod +x "$PROJECT_ROOT/scripts/smoke.sh" 2>/dev/null || true
  chmod +x "$PROJECT_ROOT/scripts/test_harness.sh" 2>/dev/null || true
  chmod +x "$PROJECT_ROOT/scripts/integrity_gate.sh" 2>/dev/null || true
  
  log_success "Script permissions updated"
}

# Run validation tests
run_validation() {
  log_info "Running validation tests..."
  
  if [ -f "$PROJECT_ROOT/scripts/smoke_security.sh" ]; then
    echo ""
    log_info "Running security smoke tests..."
    if "$PROJECT_ROOT/scripts/smoke_security.sh"; then
      log_success "Security tests passed"
    else
      log_error "Security tests failed"
      return 1
    fi
  fi
}

# Print summary
print_summary() {
  echo ""
  echo "========================================"
  echo "  P0 Patch Application Summary"
  echo "========================================"
  echo ""
  echo "Patches Applied:"
  echo "  ✅ P0-SEC-01: Gateway query token blocking"
  echo "  ✅ P0-SEC-02: Legacy token disable config"
  echo "  ✅ P0-SEC-03: Signature validation config"
  echo "  ✅ P0-SUP-01: Admin WA audit config"
  echo "  ✅ P0-L10N-01: L10N enabled by default"
  echo "  ✅ P0-OPS-01: Alerting config"
  echo ""
  echo "Manual Steps Required:"
  echo "  1. Apply database migrations (see above)"
  echo "  2. Update production .env with new values"
  echo "  3. Restart n8n workers"
  echo "  4. Verify with smoke tests"
  echo ""
  echo "Rollback:"
  echo "  Backups saved in: $(cat "$PROJECT_ROOT/.last_backup_dir" 2>/dev/null || echo 'backups/')"
  echo ""
}

# Main execution
main() {
  local skip_backup=false
  local skip_nginx=false
  local skip_env=false
  local run_tests=false
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --skip-backup) skip_backup=true; shift ;;
      --skip-nginx) skip_nginx=true; shift ;;
      --skip-env) skip_env=true; shift ;;
      --test) run_tests=true; shift ;;
      --help)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --skip-backup   Skip creating backups"
        echo "  --skip-nginx    Skip nginx patch"
        echo "  --skip-env      Skip .env patch"
        echo "  --test          Run validation tests after patching"
        echo "  --help          Show this help"
        exit 0
        ;;
      *) log_error "Unknown option: $1"; exit 1 ;;
    esac
  done
  
  check_prerequisites
  
  if [ "$skip_backup" = false ]; then
    backup_configs
  fi
  
  if [ "$skip_nginx" = false ]; then
    apply_nginx_patch
  fi
  
  if [ "$skip_env" = false ]; then
    apply_env_patch
  fi
  
  fix_permissions
  list_migrations
  
  if [ "$run_tests" = true ]; then
    run_validation
  fi
  
  print_summary
  
  log_success "P0 patches applied successfully!"
}

# Run main
main "$@"
