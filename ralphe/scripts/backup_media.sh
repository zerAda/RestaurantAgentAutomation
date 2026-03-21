#!/bin/bash
set -e

# Configuration
BACKUP_ROOT="./backups/media"
VOLUME_NAME="cms_uploads"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

# Ensure backup directory exists
mkdir -p "$BACKUP_ROOT"

echo "📸 Starting Media Backup for volume: $VOLUME_NAME..."

# Create backup using temporary container
# We mount the volume to /data and the backup dir to /backup
docker run --rm \
    -v "$VOLUME_NAME":/data \
    -v "$(pwd)/$BACKUP_ROOT":/backup \
    alpine \
    sh -c "tar czf /backup/media_$TIMESTAMP.tar.gz -C /data ."

if [ $? -eq 0 ]; then
    echo "✅ Backup success: $BACKUP_ROOT/media_$TIMESTAMP.tar.gz"
else
    echo "❌ Backup failed!"
    exit 1
fi

# Cleanup old backups
echo "🧹 Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_ROOT" -name "media_*.tar.gz" -mtime +$RETENTION_DAYS -delete

echo "✨ Operation complete."
