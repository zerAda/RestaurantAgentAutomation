#!/bin/bash
# scripts/ops/backup.sh
# Execute this script on the VPS to perform a pre-deployment backup.
# Environment variables required:
# - BACKUP_NAME: Name of the backup (e.g., deploy-20231010-...)
# - VERSION: Version string
# - COMMIT: Commit SHA
# - PROJECT_DIR: (Optional) Path to project root (default: /opt/resto)
# - BACKUP_DIR: (Optional) Path to backup directory (default: /opt/resto/backups)

set -e

# Defaults
PROJECT_DIR="${PROJECT_DIR:-/opt/resto}"
BACKUP_DIR="${BACKUP_DIR:-/opt/resto/backups}"

echo "=== deployment backup start: $BACKUP_NAME ==="

# Ensure directories exist
mkdir -p "$BACKUP_DIR"

# Navigate to project
if [ -d "$PROJECT_DIR/current" ]; then
    cd "$PROJECT_DIR/current"
else
    cd "$PROJECT_DIR"
fi

echo "Workdir: $(pwd)"

# Find the postgres container (works regardless of compose project name).
# docker compose exec fails when loaded from a symlink with a different project name.
PG_CONTAINER="$(docker ps -qf "ancestor=postgres" -f "status=running" | head -1)"
if [ -z "$PG_CONTAINER" ]; then
    # Fallback: search by container name pattern
    PG_CONTAINER="$(docker ps -qf "name=postgres" -f "status=running" | head -1)"
fi

if [ -z "$PG_CONTAINER" ]; then
    echo "::error::No running postgres container found"
    exit 1
fi
echo "Using postgres container: $PG_CONTAINER"

# 1. Backup n8n database
echo "=== Backup: n8n database ==="
if docker exec -i "$PG_CONTAINER" pg_dump -U n8n -d n8n --no-owner --no-acl -Fc > "$BACKUP_DIR/${BACKUP_NAME}-n8n.dump"; then
    echo "n8n DB backed up."
else
    echo "::error::Failed to backup n8n DB"
    exit 1
fi

# 2. Backup strapi database
echo "=== Backup: strapi database ==="
if docker exec -i "$PG_CONTAINER" pg_dump -U n8n -d strapi --no-owner --no-acl -Fc > "$BACKUP_DIR/${BACKUP_NAME}-strapi.dump" 2>/dev/null; then
    echo "Strapi DB backed up."
else
    echo "::warning::Strapi DB not found or failed (ignoring if first deploy)"
fi

# 3. Backup configuration
echo "=== Backup: config ==="
tar -czf "$BACKUP_DIR/${BACKUP_NAME}-config.tar.gz" .env secrets/ 2>/dev/null || true
echo "Config backed up."

# 4. Verify integrity
if [ ! -s "$BACKUP_DIR/${BACKUP_NAME}-n8n.dump" ]; then
    echo "::error::n8n backup is empty"
    exit 1
fi

# 5. Create Metadata
cat > "$BACKUP_DIR/${BACKUP_NAME}-meta.json" << METAEOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "version": "${VERSION}",
  "commit": "${COMMIT}",
  "type": "pre-deploy"
}
METAEOF

ls -lh "$BACKUP_DIR/${BACKUP_NAME}"*
echo "Backup complete: ${BACKUP_NAME}"
