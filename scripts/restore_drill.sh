#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# restore_drill.sh — Off-site Backup Restore Drill
# =============================================================================
# Downloads the latest backup from S3, decrypts it with GPG, spins up a
# temporary Postgres container, restores the dump, and verifies row counts.
#
# Usage:
#   BACKUP_NAME=daily-20260320-030000 bash scripts/restore_drill.sh
#   bash scripts/restore_drill.sh daily-20260320-030000
#
# Required env vars:
#   S3_BACKUP_BUCKET       — bucket name (e.g. resto-bot-backups)
#   S3_BACKUP_ENDPOINT     — S3 endpoint URL
#   S3_BACKUP_REGION       — region or 'auto' for R2
#   AWS_ACCESS_KEY_ID      — S3/R2 access key
#   AWS_SECRET_ACCESS_KEY  — S3/R2 secret key
#   BACKUP_GPG_PASSPHRASE  — GPG symmetric passphrase used during upload
#
# Output:
#   Prints [DRILL PASS] or [DRILL FAIL] as final line (grep-friendly for CI)
# =============================================================================

DRILL_CONTAINER="pg_drill_$$"
DRILL_PASS=false

# ---------------------------------------------------------------------------
# Cleanup: always runs on EXIT (success or failure)
# ---------------------------------------------------------------------------
cleanup() {
  echo ""
  echo "=== Cleanup ==="
  docker stop "$DRILL_CONTAINER" 2>/dev/null && docker rm "$DRILL_CONTAINER" 2>/dev/null || true
  rm -f "/tmp/${BACKUP_NAME}-db.dump.gz.gpg" \
        "/tmp/${BACKUP_NAME}-db.dump.gz" \
        "/tmp/${BACKUP_NAME}-db.dump" 2>/dev/null || true
  echo "Temp container and files removed."

  if [ "$DRILL_PASS" = "true" ]; then
    echo ""
    echo "[DRILL PASS]"
  else
    echo ""
    echo "[DRILL FAIL]"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Step 0: Resolve BACKUP_NAME
# ---------------------------------------------------------------------------
BACKUP_NAME="${1:-${BACKUP_NAME:-}}"
if [ -z "$BACKUP_NAME" ]; then
  echo "ERROR: BACKUP_NAME is required." >&2
  echo "Usage: BACKUP_NAME=daily-YYYYMMDD-HHMMSS bash scripts/restore_drill.sh" >&2
  exit 1
fi
echo "=== Restore Drill: ${BACKUP_NAME} ==="

# ---------------------------------------------------------------------------
# Step 1: Verify required env vars
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 1: Checking required env vars ==="
MISSING=""
for VAR in S3_BACKUP_BUCKET S3_BACKUP_ENDPOINT S3_BACKUP_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY BACKUP_GPG_PASSPHRASE; do
  if [ -z "${!VAR:-}" ]; then
    MISSING="$MISSING $VAR"
  fi
done
if [ -n "$MISSING" ]; then
  echo "ERROR: Missing required env vars:$MISSING" >&2
  exit 1
fi
echo "All required env vars present."

# ---------------------------------------------------------------------------
# Step 2: Download encrypted backup from S3
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 2: Downloading from S3 ==="
aws s3 cp \
  "s3://${S3_BACKUP_BUCKET}/postgres/${BACKUP_NAME}-db.dump.gz.gpg" \
  "/tmp/${BACKUP_NAME}-db.dump.gz.gpg" \
  --endpoint-url "${S3_BACKUP_ENDPOINT}" \
  --region "${S3_BACKUP_REGION}"
echo "Downloaded: /tmp/${BACKUP_NAME}-db.dump.gz.gpg"

# ---------------------------------------------------------------------------
# Step 3: Decrypt with GPG
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 3: Decrypting with GPG ==="
echo "$BACKUP_GPG_PASSPHRASE" | gpg --batch --passphrase-fd 0 \
  -d "/tmp/${BACKUP_NAME}-db.dump.gz.gpg" \
  > "/tmp/${BACKUP_NAME}-db.dump.gz"
echo "Decryption complete."

# ---------------------------------------------------------------------------
# Step 4: Decompress
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 4: Decompressing ==="
gunzip "/tmp/${BACKUP_NAME}-db.dump.gz"
echo "Decompressed: /tmp/${BACKUP_NAME}-db.dump"

# ---------------------------------------------------------------------------
# Step 5: Spin up temporary Postgres container
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 5: Starting temp Postgres container ($DRILL_CONTAINER) ==="
docker run -d \
  --name "$DRILL_CONTAINER" \
  -e POSTGRES_USER=n8n \
  -e POSTGRES_DB=n8n \
  -e POSTGRES_PASSWORD=drillpass \
  postgres:15-alpine
echo "Container started."

# ---------------------------------------------------------------------------
# Step 6: Wait for Postgres to be ready (30s timeout)
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 6: Waiting for Postgres to be ready ==="
READY=false
for i in $(seq 1 30); do
  if docker exec "$DRILL_CONTAINER" pg_isready -U n8n -d n8n -q 2>/dev/null; then
    READY=true
    echo "Postgres ready after ${i}s."
    break
  fi
  sleep 1
done
if [ "$READY" != "true" ]; then
  echo "ERROR: Postgres not ready after 30s." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 7: Restore with pg_restore
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 7: Restoring with pg_restore ==="
docker exec -i "$DRILL_CONTAINER" pg_restore \
  -U n8n -d n8n \
  --clean --no-owner --no-acl -Fc \
  < "/tmp/${BACKUP_NAME}-db.dump"
echo "Restore complete."

# ---------------------------------------------------------------------------
# Step 8: Verify row counts
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 8: Verifying row counts ==="

WORKFLOW_COUNT=$(docker exec "$DRILL_CONTAINER" \
  psql -U n8n -d n8n -At -c "SELECT COUNT(*) FROM workflow_entity" 2>/dev/null || echo "0")

EXECUTION_COUNT=$(docker exec "$DRILL_CONTAINER" \
  psql -U n8n -d n8n -At -c "SELECT COUNT(*) FROM execution_entity" 2>/dev/null || echo "0")

echo "  workflow_entity rows : $WORKFLOW_COUNT"
echo "  execution_entity rows: $EXECUTION_COUNT"

if [ "${WORKFLOW_COUNT:-0}" -gt 0 ]; then
  echo "Verification passed: workflow_entity has $WORKFLOW_COUNT rows."
  DRILL_PASS=true
else
  echo "ERROR: workflow_entity has 0 rows — restore may have failed or DB is empty." >&2
  exit 1
fi

# Cleanup and final banner are handled by trap
