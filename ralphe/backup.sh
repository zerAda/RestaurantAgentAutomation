#!/bin/bash
set -e

# ==============================================================================
# Ralphé Production Backup Script
# Strategy: Dump DB (Postgres) and package Media Uploads, keep for 7 days.
# ==============================================================================

BACKUP_DIR="/opt/resto/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DB_CONTAINER="project-postgres-1" # Update with actual running container name if different
DB_USER="n8n"

mkdir -p "$BACKUP_DIR"

echo "=== Starting Ralphé Automated Backup ($TIMESTAMP) ==="

# 1. Global Database Backup (All schemas and tables)
DB_BACKUP_FILE="$BACKUP_DIR/db_backup_$TIMESTAMP.sql.gz"
echo "-> Dumping PostgreSQL Databases..."
# We use pg_dumpall to grab n8n, strapi, and any other DB inside the container
docker exec -t $DB_CONTAINER pg_dumpall -U $DB_USER | gzip > $DB_BACKUP_FILE
echo "-> DB Backup Saved: $DB_BACKUP_FILE"

# 2. Strapi Media Content Backup
# Ensure this matches the absolute path of the docker volume 'project_cms_uploads'
MEDIA_VOLUME_PATH="/var/lib/docker/volumes/project_cms_uploads/_data"
MEDIA_BACKUP_FILE="$BACKUP_DIR/media_backup_$TIMESTAMP.tar.gz"

if [ -d "$MEDIA_VOLUME_PATH" ]; then
    echo "-> Compressing Strapi Media Uploads..."
    tar -czf "$MEDIA_BACKUP_FILE" -C "$MEDIA_VOLUME_PATH" .
    echo "-> Media Backup Saved: $MEDIA_BACKUP_FILE"
else
    echo "-> [WARNING] Media volume path not found at $MEDIA_VOLUME_PATH. Skipping media."
fi

# 3. Retention Policy (7 days)
echo "-> Cleaning up backups older than 7 days..."
find "$BACKUP_DIR" -type f -name "*.gz" -mtime +7 -exec rm -f {} \;

echo "=== Backup Successfully Completed ==="

# Upload to S3 (AWS CLI example):
# aws s3 cp $BACKUP_DIR/ s3://ralphe-backups/ --recursive --exclude "*" --include "*$TIMESTAMP*"
