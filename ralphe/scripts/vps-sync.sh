#!/usr/bin/env bash
# =============================================================================
# vps-sync.sh — Sync project files to VPS and optionally rebuild/restart
# =============================================================================
# Usage:
#   ./scripts/vps-sync.sh                      # Sync files only (dry-preview)
#   ./scripts/vps-sync.sh --sync               # Sync files only
#   ./scripts/vps-sync.sh --sync cms           # Sync + rebuild + restart cms
#   ./scripts/vps-sync.sh --sync cms --no-cache# Sync + full rebuild cms
#   ./scripts/vps-sync.sh --sync --restart cms # Sync + restart only (no rebuild)
#   ./scripts/vps-sync.sh --sync --pull cms    # Sync + pull GHCR image + restart
#   ./scripts/vps-sync.sh --pull cms latest    # Pull GHCR tag + restart (no sync)
#
# Environment overrides:
#   VPS_HOST=72.60.190.192  VPS_USER=deploy  GHCR_OWNER=zerada
# =============================================================================
set -euo pipefail

VPS_HOST="${VPS_HOST:-72.60.190.192}"
VPS_USER="${VPS_USER:-deploy}"
VPS_PATH="/opt/resto/current"
GHCR_OWNER="${GHCR_OWNER:-zerada}"
VPS="${VPS_USER}@${VPS_HOST}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults
DO_SYNC=false
DO_REBUILD=false
DO_RESTART=false
DO_PULL=false
NO_CACHE=""
SERVICE=""
PULL_TAG="latest"
DRY_RUN=true

# ---- Parse args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sync)      DO_SYNC=true; DRY_RUN=false ;;
    --restart)   DO_RESTART=true; DO_REBUILD=false ;;
    --pull)      DO_PULL=true; DO_REBUILD=false ;;
    --no-cache)  NO_CACHE="--no-cache" ;;
    --dry-run)   DRY_RUN=true ;;
    --help|-h)
      head -20 "$0"; exit 0 ;;
    -*)
      echo "Unknown option: $1"; exit 1 ;;
    *)
      if [[ -z "$SERVICE" ]]; then
        SERVICE="$1"
      else
        PULL_TAG="$1"
      fi
      ;;
  esac
  shift
done

# If service given with --sync and no --restart/--pull, default to rebuild
if [[ -n "$SERVICE" && "$DO_SYNC" == true && "$DO_RESTART" == false && "$DO_PULL" == false ]]; then
  DO_REBUILD=true
fi

# ---- Banner ----
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " VPS Sync  →  ${VPS}:${VPS_PATH}"
[[ -n "$SERVICE" ]] && echo " Service   →  ${SERVICE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ---- Dry-run preview ----
if [[ "$DRY_RUN" == true && "$DO_SYNC" == false && "$DO_PULL" == false ]]; then
  echo ""
  echo "DRY RUN — files that would be synced:"
  rsync -az --checksum --dry-run --human-readable \
    --exclude='.git/' \
    --exclude='node_modules/' \
    --exclude='.env' \
    --exclude='secrets/' \
    --exclude='*.log' \
    --exclude='.DS_Store' \
    --exclude='__pycache__/' \
    "$PROJECT_DIR/" \
    "$VPS:$VPS_PATH/" \
    | grep -v '/$' | tail -40
  echo ""
  echo "Pass --sync to execute, or --sync <service> to sync + rebuild."
  exit 0
fi

# ---- Sync ----
if [[ "$DO_SYNC" == true ]]; then
  echo "▶ Syncing files..."
  rsync -az --checksum --human-readable \
    --exclude='.git/' \
    --exclude='node_modules/' \
    --exclude='.env' \
    --exclude='secrets/' \
    --exclude='*.log' \
    --exclude='.DS_Store' \
    --exclude='__pycache__/' \
    "$PROJECT_DIR/" \
    "$VPS:$VPS_PATH/"

  # Fix line endings for shell scripts (safe to run always)
  ssh "$VPS" "find $VPS_PATH/scripts -name '*.sh' -exec sed -i 's/\r\$//' {} \; 2>/dev/null; chmod +x $VPS_PATH/scripts/*.sh 2>/dev/null; echo 'Scripts fixed'"

  echo "✓ Sync complete"
fi

# ---- Pull GHCR image ----
if [[ "$DO_PULL" == true && -n "$SERVICE" ]]; then
  echo "▶ Pulling GHCR image: ghcr.io/${GHCR_OWNER}/resto-bot-${SERVICE}:${PULL_TAG}"
  ssh "$VPS" "docker pull ghcr.io/${GHCR_OWNER}/resto-bot-${SERVICE}:${PULL_TAG}"
  # Tag as local name so compose picks it up
  ssh "$VPS" "docker tag ghcr.io/${GHCR_OWNER}/resto-bot-${SERVICE}:${PULL_TAG} resto-bot-${SERVICE}:latest"
  echo "✓ Image pulled"
  DO_RESTART=true
fi

# ---- Rebuild from source ----
if [[ "$DO_REBUILD" == true && -n "$SERVICE" ]]; then
  echo "▶ Building ${SERVICE} on VPS${NO_CACHE:+ (no-cache)}..."
  ssh "$VPS" "bash /opt/resto/rebuild.sh $SERVICE $NO_CACHE"
fi

# ---- Restart only ----
if [[ "$DO_RESTART" == true && "$DO_REBUILD" == false && -n "$SERVICE" ]]; then
  echo "▶ Restarting ${SERVICE}..."
  ssh "$VPS" "cd $VPS_PATH && docker compose -f docker-compose.hostinger.prod.yml up -d $SERVICE"
fi

# ---- Health check ----
if [[ -n "$SERVICE" && ("$DO_REBUILD" == true || "$DO_RESTART" == true) ]]; then
  echo "▶ Waiting for service to start (5s)..."
  sleep 5

  case "$SERVICE" in
    cms)
      ssh "$VPS" "curl -sf http://127.0.0.1:1337/_health && echo '✓ CMS healthy' || echo '⚠ CMS not ready yet (check: docker logs current-cms-1)'"
      ;;
    gateway)
      ssh "$VPS" "curl -sf http://127.0.0.1:8080/healthz && echo '✓ Gateway healthy' || echo '⚠ Gateway not ready yet'"
      ;;
    *)
      ssh "$VPS" "docker ps --filter 'name=current-${SERVICE}' --format '✓ {{.Names}}: {{.Status}}'"
      ;;
  esac
fi

if [[ -z "$SERVICE" && "$DO_SYNC" == true ]]; then
  echo ""
  echo "Files synced. Next steps:"
  echo "  $0 --sync cms           # rebuild + restart cms"
  echo "  $0 --sync --restart cms # restart only (config change)"
  echo "  $0 --sync --pull cms    # use GHCR image (fast)"
fi

echo ""
echo "✓ Done"
