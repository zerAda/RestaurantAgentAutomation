#!/usr/bin/env bash
# =============================================================================
# db_migrate_all.sh - Apply ALL pending migrations (idempotent)
# =============================================================================
# Usage:
#   ./scripts/db_migrate_all.sh                    # Use default compose file
#   ./scripts/db_migrate_all.sh -f docker-compose.hostinger.prod.yml
#   ./scripts/db_migrate_all.sh --dry-run          # Show what would be applied
#
# This script:
# 1. Creates a schema_migrations tracking table
# 2. Finds all migrations in db/migrations/
# 3. Applies only migrations that haven't been applied yet
# 4. Records each successful migration
# 5. Fails fast if any migration fails (ON_ERROR_STOP)
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Defaults
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.hostinger.prod.yml}"
MIGRATIONS_DIR="db/migrations"
DRY_RUN=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--file)
      COMPOSE_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

log_info() { echo -e "[INFO] $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "=============================================="
echo "DB Migration Runner"
echo "=============================================="
echo "Compose file: $COMPOSE_FILE"
echo "Migrations:   $MIGRATIONS_DIR"
echo "Dry run:      $DRY_RUN"
echo ""

# Check migrations directory exists
if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  log_fail "Migrations directory not found: $MIGRATIONS_DIR"
  exit 1
fi

# Check compose file exists
if [[ ! -f "$COMPOSE_FILE" ]]; then
  log_fail "Compose file not found: $COMPOSE_FILE"
  exit 1
fi

# Ensure postgres is running
log_info "Ensuring postgres is running..."
docker compose -f "$COMPOSE_FILE" up -d postgres

# Wait for postgres to be ready
log_info "Waiting for postgres to be ready..."
for i in {1..30}; do
  if docker compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U n8n -d n8n >/dev/null 2>&1; then
    break
  fi
  if [[ $i -eq 30 ]]; then
    log_fail "Postgres not ready after 30 seconds"
    exit 1
  fi
  sleep 1
done
log_pass "Postgres is ready"

# Helper function to run SQL
run_sql() {
  docker compose -f "$COMPOSE_FILE" exec -T postgres \
    psql -v ON_ERROR_STOP=1 -U n8n -d n8n -t -A "$@"
}

# Create schema_migrations table if not exists
log_info "Creating schema_migrations table (if needed)..."
run_sql <<'EOF'
CREATE TABLE IF NOT EXISTS schema_migrations (
  id          serial PRIMARY KEY,
  filename    text NOT NULL UNIQUE,
  applied_at  timestamptz NOT NULL DEFAULT now(),
  checksum    text NULL
);

COMMENT ON TABLE schema_migrations IS 'Tracks applied database migrations';
EOF
log_pass "schema_migrations table ready"

# Get list of applied migrations
log_info "Fetching applied migrations..."
APPLIED=$(run_sql -c "SELECT filename FROM schema_migrations ORDER BY filename" 2>/dev/null || echo "")

# Get list of migration files (sorted by filename)
MIGRATIONS=$(ls -1 "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort)

if [[ -z "$MIGRATIONS" ]]; then
  log_warn "No migration files found in $MIGRATIONS_DIR"
  exit 0
fi

# Count pending migrations
PENDING_COUNT=0
APPLIED_COUNT=0
FAILED_COUNT=0

echo ""
echo "=== Migration Status ==="

for migration in $MIGRATIONS; do
  filename=$(basename "$migration")

  if echo "$APPLIED" | grep -qx "$filename"; then
    if $VERBOSE; then
      echo -e "${GREEN}[APPLIED]${NC} $filename"
    fi
    ((APPLIED_COUNT++))
  else
    echo -e "${YELLOW}[PENDING]${NC} $filename"
    ((PENDING_COUNT++))
  fi
done

echo ""
echo "Applied: $APPLIED_COUNT, Pending: $PENDING_COUNT"
echo ""

if [[ $PENDING_COUNT -eq 0 ]]; then
  log_pass "All migrations already applied"
  exit 0
fi

if $DRY_RUN; then
  log_warn "Dry run - no changes made"
  exit 0
fi

# Apply pending migrations
echo "=== Applying Pending Migrations ==="

for migration in $MIGRATIONS; do
  filename=$(basename "$migration")

  # Skip if already applied
  if echo "$APPLIED" | grep -qx "$filename"; then
    continue
  fi

  log_info "Applying: $filename"

  # Calculate checksum
  CHECKSUM=$(sha256sum "$migration" | cut -d' ' -f1)

  # Apply migration with ON_ERROR_STOP
  if docker compose -f "$COMPOSE_FILE" exec -T postgres \
    sh -c "psql -v ON_ERROR_STOP=1 -U n8n -d n8n" < "$migration" 2>&1; then

    # Record successful migration
    run_sql -c "INSERT INTO schema_migrations (filename, checksum) VALUES ('$filename', '$CHECKSUM')" >/dev/null

    log_pass "Applied: $filename"
  else
    log_fail "Failed: $filename"
    echo ""
    echo "=========================================="
    echo "MIGRATION FAILED - STOPPING"
    echo "=========================================="
    echo "File: $filename"
    echo ""
    echo "Please fix the migration and retry."
    echo "Rollback may be required if partial changes were made."
    exit 1
  fi
done

echo ""
echo "=============================================="
log_pass "All migrations applied successfully"
echo "=============================================="

# Show final status
echo ""
echo "=== Final Migration Status ==="
run_sql -c "SELECT filename, applied_at FROM schema_migrations ORDER BY applied_at DESC LIMIT 5"
