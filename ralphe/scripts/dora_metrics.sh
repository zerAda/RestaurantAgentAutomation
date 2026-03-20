#!/usr/bin/env bash
set -euo pipefail

# Usage: dora_metrics.sh <version> <commit> <status> <start_epoch> [log_dir]

VERSION="${1:?Usage: dora_metrics.sh <version> <commit> <status> <start_epoch> [log_dir]}"
COMMIT="${2:?}"
STATUS="${3:?}"
START_EPOCH="${4:?}"
LOG_DIR="${5:-/var/log/resto-bot}"

mkdir -p "$LOG_DIR"
METRICS_FILE="$LOG_DIR/dora_metrics.jsonl"

NOW_EPOCH=$(date +%s)
DEPLOY_DURATION=$((NOW_EPOCH - START_EPOCH))

# Lead time: time from commit to deploy complete
COMMIT_EPOCH=$(git log -1 --format=%ct "$COMMIT" 2>/dev/null || echo "$START_EPOCH")
LEAD_TIME=$((NOW_EPOCH - COMMIT_EPOCH))

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Append JSONL record
echo "{\"timestamp\":\"${TIMESTAMP}\",\"version\":\"${VERSION}\",\"commit\":\"${COMMIT}\",\"status\":\"${STATUS}\",\"lead_time_sec\":${LEAD_TIME},\"deploy_duration_sec\":${DEPLOY_DURATION}}" >> "$METRICS_FILE"

echo "DORA metrics recorded: version=$VERSION status=$STATUS lead_time=${LEAD_TIME}s deploy_duration=${DEPLOY_DURATION}s"
