#!/bin/bash
# =============================================================================
# 01_apply_migrations.sh - Applied by postgres docker-entrypoint-initdb.d
# =============================================================================
# This script runs AFTER 00_bootstrap.sql during postgres first initialization.
# It applies all migrations in order.
#
# NOTE: This only runs on FRESH installs (empty data directory).
# For UPGRADES, use scripts/db_migrate_all.sh manually or via CI/CD.
# =============================================================================

set -e

echo "=== Applying database migrations ==="

MIGRATIONS_DIR="/docker-entrypoint-initdb.d/migrations"

if [ ! -d "$MIGRATIONS_DIR" ]; then
  echo "No migrations directory found at $MIGRATIONS_DIR - skipping"
  exit 0
fi

# Create schema_migrations table
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'EOF'
CREATE TABLE IF NOT EXISTS schema_migrations (
  id          serial PRIMARY KEY,
  filename    text NOT NULL UNIQUE,
  applied_at  timestamptz NOT NULL DEFAULT now(),
  checksum    text NULL
);
EOF

# Apply migrations in sorted order
for migration in $(ls -1 "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort); do
  filename=$(basename "$migration")
  echo "Applying migration: $filename"

  # Apply migration
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$migration"

  # Record migration
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -c "INSERT INTO schema_migrations (filename) VALUES ('$filename') ON CONFLICT (filename) DO NOTHING"

  echo "  -> Applied: $filename"
done

echo "=== All migrations applied ==="
