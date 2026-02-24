#!/usr/bin/env bash
set -euo pipefail

# Postgres backup (pg_dump custom format)
# - Output: BACKUP_DIR/postgres/n8n_YYYY-MM-DD_HHMMSS.dump
# - Rotation: delete backups older than RETENTION_DAYS

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.hostinger.prod.yml}"
BACKUP_DIR="${BACKUP_DIR:-./backups/postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
PG_USER="${PG_USER:-n8n}"
PG_DB="${PG_DB:-n8n}"

mkdir -p "$BACKUP_DIR"

ts="$(date +%F_%H%M%S)"
out="$BACKUP_DIR/${PG_DB}_${ts}.dump"
sha="$out.sha256"

echo "== Backup Postgres (pg_dump -Fc) =="
echo "Compose:        $COMPOSE_FILE"
echo "Output:         $out"
echo "Retention days: $RETENTION_DAYS"

# Ensure DB is up

docker compose -f "$COMPOSE_FILE" up -d postgres

# pg_dump custom format is already compressed; keep it as binary to preserve speed/restore fidelity.
# (No secrets printed)
docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc \
  "pg_dump -U '$PG_USER' -d '$PG_DB' -Fc --no-owner --no-privileges" > "$out"

# Basic integrity
if [[ ! -s "$out" ]]; then
  echo "❌ Backup file is empty: $out" >&2
  exit 1
fi

# Checksum
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$out" | awk '{print $1}' > "$sha"
  echo "✅ sha256: $(cat "$sha")"
fi

echo "✅ Backup created: $out"

echo "== Rotation: delete backups older than ${RETENTION_DAYS} day(s) =="
# Busybox find supports -mtime; this is host-side rotation.
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${PG_DB}_*.dump" -mtime "+${RETENTION_DAYS}" -print -delete || true
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${PG_DB}_*.dump.sha256" -mtime "+${RETENTION_DAYS}" -print -delete || true

echo "✅ Rotation done"
