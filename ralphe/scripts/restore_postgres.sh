#!/usr/bin/env bash
set -euo pipefail

# Restore a pg_dump custom-format backup (.dump) into the Postgres service.
#
# Safety:
# - Requires CONFIRM_RESTORE=YES
# - Supports --clean and --if-exists (recommended)
#
# Usage:
#   CONFIRM_RESTORE=YES ./scripts/restore_postgres.sh <backup.dump>
#   CONFIRM_RESTORE=YES ./scripts/restore_postgres.sh --clean --if-exists <backup.dump>

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.hostinger.prod.yml}"
PG_USER="${PG_USER:-n8n}"
PG_DB="${PG_DB:-n8n}"

CLEAN=0
IF_EXISTS=0
BACKUP_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN=1; shift ;;
    --if-exists)
      IF_EXISTS=1; shift ;;
    -h|--help)
      echo "Usage: CONFIRM_RESTORE=YES $0 [--clean] [--if-exists] <backup.dump>"; exit 0 ;;
    *)
      BACKUP_FILE="$1"; shift ;;
  esac
done

if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
  echo "❌ Backup file not found: $BACKUP_FILE" >&2
  echo "Usage: CONFIRM_RESTORE=YES $0 [--clean] [--if-exists] <backup.dump>" >&2
  exit 1
fi

if [[ "${CONFIRM_RESTORE:-}" != "YES" ]]; then
  echo "❌ Refusing to restore without CONFIRM_RESTORE=YES" >&2
  echo "Example: CONFIRM_RESTORE=YES $0 --clean --if-exists $BACKUP_FILE" >&2
  exit 1
fi

cleanOpt=""
if [[ $CLEAN -eq 1 ]]; then cleanOpt="--clean"; fi
ifExistsOpt=""
if [[ $IF_EXISTS -eq 1 ]]; then ifExistsOpt="--if-exists"; fi

echo "== Restore Postgres (pg_restore) =="
echo "Compose:  $COMPOSE_FILE"
echo "Backup:   $BACKUP_FILE"
echo "Options:  ${cleanOpt} ${ifExistsOpt}"

# Stop writers (best-effort; ignore if services absent in this compose)
echo "== Stopping app services (best-effort) =="
docker compose -f "$COMPOSE_FILE" stop n8n-main n8n-worker gateway traefik n8n || true

# Ensure postgres is up
echo "== Ensuring postgres is up =="
docker compose -f "$COMPOSE_FILE" up -d postgres

# Restore
# Note: pg_restore reads from stdin when no file argument is supplied.
echo "== Restoring into database '${PG_DB}' =="
cat "$BACKUP_FILE" | docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc \
  "pg_restore -U '$PG_USER' -d '$PG_DB' ${cleanOpt} ${ifExistsOpt} --no-owner --no-privileges --exit-on-error"

echo "== Starting stack back (best-effort) =="
docker compose -f "$COMPOSE_FILE" up -d || true

echo "✅ Restore done"
