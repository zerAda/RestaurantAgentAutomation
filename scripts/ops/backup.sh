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

# Find the PRODUCTION postgres container.
# Strategy: prefer a container whose compose project label matches the production
# project (basename of PROJECT_DIR, e.g. "resto") over staging containers.
# Staging containers use project name "resto-staging" — exclude them.
PROD_PROJECT="$(basename "$PROJECT_DIR")"

# First: look for container with production compose project label
PG_CONTAINER="$(docker ps --format '{{.ID}} {{.Label "com.docker.compose.project"}}' \
  | grep " ${PROD_PROJECT}$" \
  | awk '{print $1}' \
  | while read cid; do
      img="$(docker inspect --format '{{.Config.Image}}' "$cid" 2>/dev/null)"
      echo "$img $cid"
    done \
  | grep "^postgres" | awk '{print $2}' | head -1)"

if [ -z "$PG_CONTAINER" ]; then
    # Fallback: any postgres container that is NOT from a staging project
    PG_CONTAINER="$(docker ps --format '{{.ID}} {{.Label "com.docker.compose.project"}}' \
      | grep -v "staging" \
      | awk '{print $1}' \
      | while read cid; do
          img="$(docker inspect --format '{{.Config.Image}}' "$cid" 2>/dev/null)"
          echo "$img $cid"
        done \
      | grep "^postgres" | awk '{print $2}' | head -1)"
fi

if [ -z "$PG_CONTAINER" ]; then
    # Last resort: any running postgres container
    PG_CONTAINER="$(docker ps -qf "ancestor=postgres" -f "status=running" | head -1)"
    if [ -z "$PG_CONTAINER" ]; then
        PG_CONTAINER="$(docker ps -qf "name=postgres" -f "status=running" | head -1)"
    fi
fi

if [ -z "$PG_CONTAINER" ]; then
    echo "::warning::No running postgres container found — skipping DB backup"
    # Create empty sentinel so deploy-production can distinguish skip vs failure
    touch "$BACKUP_DIR/${BACKUP_NAME:-unknown}-n8n.dump.skipped"
    exit 0
fi
echo "Using postgres container: $PG_CONTAINER (project: $PROD_PROJECT)"

# 1. Backup n8n database (with retry for transient pg_dump errors)
# pg_dump can fail with "query returned 0 rows instead of one: EXECUTE dumpFunc"
# when n8n's background executions modify the catalog concurrently.
# Retry up to 3 times with a short delay to let concurrent DDL complete.
echo "=== Backup: n8n database ==="
N8N_BACKUP_OK=false
for ATTEMPT in 1 2 3; do
    echo "pg_dump attempt $ATTEMPT/3..."
    if docker exec -i "$PG_CONTAINER" pg_dump -U n8n -d n8n --no-owner --no-acl --lock-wait-timeout=60000 -Fc > "$BACKUP_DIR/${BACKUP_NAME}-n8n.dump" 2>/tmp/pgdump_err.log; then
        echo "n8n DB backed up on attempt $ATTEMPT."
        N8N_BACKUP_OK=true
        break
    else
        echo "::warning::pg_dump attempt $ATTEMPT failed: $(cat /tmp/pgdump_err.log 2>/dev/null)"
        rm -f "$BACKUP_DIR/${BACKUP_NAME}-n8n.dump"
        if [ "$ATTEMPT" -lt 3 ]; then
            echo "Waiting 10s before retry..."
            sleep 10
        fi
    fi
done
rm -f /tmp/pgdump_err.log

if [ "$N8N_BACKUP_OK" != "true" ]; then
    echo "::error::Failed to backup n8n DB after 3 attempts"
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
