#!/usr/bin/env bash
set -euo pipefail

# Redis backup (for persistent redis volume)
#
# This project uses Redis for n8n queue mode (Bull) and stores state in a persistent volume.
# Backup strategy: archive /data (AOF/RDB) from the redis container.
#
# Output: BACKUP_DIR/redis_YYYY-MM-DD_HHMMSS.tgz
# Rotation: delete backups older than RETENTION_DAYS

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.hostinger.prod.yml}"
BACKUP_DIR="${BACKUP_DIR:-./backups/redis}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

mkdir -p "$BACKUP_DIR"

ts="$(date +%F_%H%M%S)"
out="$BACKUP_DIR/redis_${ts}.tgz"

echo "== Backup Redis (/data archive) =="
echo "Compose:        $COMPOSE_FILE"
echo "Output:         $out"
echo "Retention days: $RETENTION_DAYS"

# Ensure redis is up

docker compose -f "$COMPOSE_FILE" up -d redis

# Force AOF fsync to minimize loss window (best-effort)
docker compose -f "$COMPOSE_FILE" exec -T redis sh -lc "redis-cli ping >/dev/null 2>&1 && redis-cli BGREWRITEAOF >/dev/null 2>&1 || true" || true

# Archive /data from inside container
# (No secrets printed)
docker compose -f "$COMPOSE_FILE" exec -T redis sh -lc "tar -C /data -czf - ." > "$out"

if [[ ! -s "$out" ]]; then
  echo "❌ Backup file is empty: $out" >&2
  exit 1
fi

echo "✅ Backup created: $out"

echo "== Rotation: delete backups older than ${RETENTION_DAYS} day(s) =="
find "$BACKUP_DIR" -maxdepth 1 -type f -name "redis_*.tgz" -mtime "+${RETENTION_DAYS}" -print -delete || true

echo "✅ Rotation done"
