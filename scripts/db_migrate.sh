#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.hostinger.prod.yml}"

# Usage:
#   ./scripts/db_migrate.sh <migration.sql>
#   ./scripts/db_migrate.sh <compose.yml> <migration.sql>

MIGRATION_FILE="db/migrations/2026-01-21_p0_prod_patches.sql"

if [[ $# -eq 1 ]]; then
  MIGRATION_FILE="$1"
elif [[ $# -ge 2 ]]; then
  COMPOSE_FILE="$1"
  MIGRATION_FILE="$2"
fi

if [[ ! -f "$MIGRATION_FILE" ]]; then
  echo "❌ Migration file not found: $MIGRATION_FILE"
  exit 1
fi

echo "== Applying DB migration =="
echo "Compose: $COMPOSE_FILE"
echo "Migration: $MIGRATION_FILE"

# Ensure postgres is up
docker compose -f "$COMPOSE_FILE" up -d postgres

echo "== Running psql inside postgres container (idempotent) =="
docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -v ON_ERROR_STOP=1 -U n8n -d n8n < /dev/stdin" < "$MIGRATION_FILE"

echo "✅ Migration applied"
