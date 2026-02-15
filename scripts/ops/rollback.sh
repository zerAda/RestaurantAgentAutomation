#!/bin/bash
# scripts/ops/rollback.sh
# Execute this script on the VPS to perform a rollback to the previous release.
# Environment variables required:
# - PROJECT_DIR: (Optional) Path to project root (default: /opt/resto)

set -e

PROJECT_DIR="${PROJECT_DIR:-/opt/resto}"

echo "=== Rollback Initiated ==="

# Find previous release (second newest)
# current symlink points to newest (failed) release usually, or the one being deployed.
# We want the one BEFORE the current one if current is the failed one.
# However, if deploy failed *before* symlink switch, 'current' is still the old good one.
# But this script is called when deploy-production fails.
# In `cd-deploy.yml` logic, `deploy-production` creates release dir, syncs code, migrates, then ACTIVATES.
# If failure happens *during* activation or smoke tests, we might need to revert.

# The original logic assumed we are rolling back from a failed *activation* or smoke test.
# "Find previous release (second newest)" implies we might have 2 releases.

CURRENT=$(readlink "$PROJECT_DIR/current" 2>/dev/null || echo "")
# List releases by time, exclude the basename of current (if it exists) to find the fallback
PREVIOUS=$(ls -1dt "$PROJECT_DIR"/releases/*/ 2>/dev/null | grep -v "$(basename "$CURRENT")" | head -1)

if [ -z "$PREVIOUS" ]; then
  echo "::error::No previous release found for rollback"
  exit 1
fi

echo "Rolling back to: $PREVIOUS"

# Switch symlink to previous release
ln -sfn "$PREVIOUS" "$PROJECT_DIR/current"
cd "$PROJECT_DIR/current"

# Restart with previous release
docker compose up -d --remove-orphans

echo "Waiting for services to stabilize..."
sleep 30

# Verify
if docker compose exec -T postgres pg_isready -U n8n >/dev/null 2>&1; then
  echo "Rollback successful — services running"
else
  echo "::error::Rollback may have failed — manual intervention required"
  exit 1
fi
