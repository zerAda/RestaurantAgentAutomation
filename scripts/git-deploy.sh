#!/usr/bin/env bash
# =============================================================================
# git-deploy.sh — Git-based VPS deployment (replaces rsync model)
# =============================================================================
# Usage:
#   bash /opt/resto/scripts/git-deploy.sh [--branch main] [--service cms] [--no-rebuild]
#
# Modes:
#   Default       Full deploy: git pull + release dir + rebuild changed services
#   --no-rebuild  Config sync only (update compose/scripts, no docker build)
#   --service X   Rebuild only the specified service after git pull
#   --sha <sha>   Deploy a specific commit (default: origin/main HEAD)
#
# Environment:
#   RESTO_BASE    Base directory (default: /opt/resto)
#   KEEP_RELEASES Number of releases to keep (default: 5)
# =============================================================================
set -euo pipefail

RESTO_BASE="${RESTO_BASE:-/opt/resto}"
REPO_DIR="$RESTO_BASE/repo"
RELEASES_DIR="$RESTO_BASE/releases"
SHARED_DIR="$RESTO_BASE/shared"
CURRENT_LINK="$RESTO_BASE/current"
COMPOSE_FILE="docker-compose.hostinger.prod.yml"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
BRANCH="main"
TARGET_SHA=""
NO_REBUILD=false
TARGET_SERVICE=""
LOG_FILE="/tmp/git-deploy-$(date +%Y%m%d-%H%M%S).log"

# Colors
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[deploy]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[error]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --sha)    TARGET_SHA="$2"; shift 2 ;;
    --service) TARGET_SERVICE="$2"; shift 2 ;;
    --no-rebuild) NO_REBUILD=true; shift ;;
    *) err "Unknown argument: $1" ;;
  esac
done

log "=== git-deploy.sh starting === (log: $LOG_FILE)"
log "Branch: $BRANCH | Service: ${TARGET_SERVICE:-all} | No-rebuild: $NO_REBUILD"

# -------------------------------------------------------------------
# Step 1: Disk check (need ≥5GB free)
# -------------------------------------------------------------------
log "Step 1: Disk check"
DISK_FREE=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
if [[ "$DISK_FREE" -lt 5 ]]; then
  warn "Low disk: ${DISK_FREE}GB free. Pruning unused Docker images..."
  docker image prune -f >/dev/null 2>&1 || true
  DISK_FREE=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
  [[ "$DISK_FREE" -lt 3 ]] && err "Insufficient disk: ${DISK_FREE}GB. Aborting."
fi
log "Disk: ${DISK_FREE}GB free — OK"

# -------------------------------------------------------------------
# Step 2: Git pull / clone
# -------------------------------------------------------------------
log "Step 2: Syncing repository"
if [[ ! -d "$REPO_DIR/.git" ]]; then
  log "No repo found — cloning from GitHub..."
  git clone "https://github.com/zerAda/RestaurantAgentAutomation.git" "$REPO_DIR"
fi

# Capture current SHA before pull for change detection
PREV_SHA=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo "none")

git -C "$REPO_DIR" fetch origin
if [[ -n "$TARGET_SHA" ]]; then
  git -C "$REPO_DIR" checkout "$TARGET_SHA" --detach
  NEW_SHA="$TARGET_SHA"
else
  git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
  NEW_SHA=$(git -C "$REPO_DIR" rev-parse HEAD)
fi

log "Deployed SHA: ${NEW_SHA::7} (was: ${PREV_SHA::7})"

# -------------------------------------------------------------------
# Step 3: Create timestamped release dir
# -------------------------------------------------------------------
DEPLOY_ID="$(date +%Y%m%d-%H%M%S)-${NEW_SHA::7}"
RELEASE_DIR="$RELEASES_DIR/$DEPLOY_ID"
log "Step 3: Creating release dir: $RELEASE_DIR"

mkdir -p "$RELEASE_DIR"

# rsync from repo to release (fast — same filesystem)
rsync -a --delete \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='*.pyc' \
  "$REPO_DIR/" "$RELEASE_DIR/"

# -------------------------------------------------------------------
# Step 4: Wire shared state (secrets, .env, volumes)
# -------------------------------------------------------------------
log "Step 4: Linking shared state"
if [[ -f "$SHARED_DIR/.env" ]]; then
  ln -sfn "$SHARED_DIR/.env" "$RELEASE_DIR/.env"
  log "Linked .env from shared"
else
  warn ".env not found in $SHARED_DIR — you must create it before services start"
fi

if [[ -d "$SHARED_DIR/secrets" ]]; then
  ln -sfn "$SHARED_DIR/secrets" "$RELEASE_DIR/secrets"
  log "Linked secrets from shared"
fi

# -------------------------------------------------------------------
# Step 5: Detect changed services (for selective rebuild)
# -------------------------------------------------------------------
log "Step 5: Detecting changed services"
CHANGED_SERVICES=""
if [[ "$PREV_SHA" != "none" && "$PREV_SHA" != "$NEW_SHA" ]]; then
  # Check which build contexts changed
  declare -A SERVICE_PATHS=(
    ["cms"]="inventory-cms/"
    ["admin-dashboard"]="admin-dashboard/"
    ["kiosk-app"]="kiosk-app/"
  )
  for svc in "${!SERVICE_PATHS[@]}"; do
    path="${SERVICE_PATHS[$svc]}"
    if git -C "$REPO_DIR" diff --quiet "$PREV_SHA".."$NEW_SHA" -- "$path" 2>/dev/null; then
      :
    else
      CHANGED_SERVICES="$CHANGED_SERVICES $svc"
    fi
  done
  log "Changed services:${CHANGED_SERVICES:-none}"
else
  log "First deploy or same SHA — treating all buildable services as changed"
  CHANGED_SERVICES="cms admin-dashboard kiosk-app"
fi

# -------------------------------------------------------------------
# Step 6: Rebuild changed services (skip if --no-rebuild)
# -------------------------------------------------------------------
if [[ "$NO_REBUILD" == "false" ]]; then
  BUILD_TARGETS="${TARGET_SERVICE:-$CHANGED_SERVICES}"
  if [[ -n "${BUILD_TARGETS// /}" ]]; then
    log "Step 6: Rebuilding services: $BUILD_TARGETS"
    for svc in $BUILD_TARGETS; do
      log "  Building $svc..."
      docker compose -f "$RELEASE_DIR/$COMPOSE_FILE" -p current build "$svc" 2>&1 | \
        tee -a "$LOG_FILE" | tail -3
    done
  else
    log "Step 6: No services to rebuild (no source changes)"
  fi
else
  log "Step 6: Skipping rebuilds (--no-rebuild)"
fi

# -------------------------------------------------------------------
# Step 7: Atomic switchover
# -------------------------------------------------------------------
log "Step 7: Switching current → $RELEASE_DIR"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

# -------------------------------------------------------------------
# Step 8: Restart changed services
# -------------------------------------------------------------------
log "Step 8: Restarting services"
COMPOSE="$RELEASE_DIR/$COMPOSE_FILE"

if [[ -n "${TARGET_SERVICE:-}" ]]; then
  docker compose -f "$COMPOSE" -p current up -d "$TARGET_SERVICE" 2>&1 | tee -a "$LOG_FILE"
elif [[ -n "${CHANGED_SERVICES// /}" && "$NO_REBUILD" == "false" ]]; then
  for svc in $CHANGED_SERVICES; do
    docker compose -f "$COMPOSE" -p current up -d "$svc" 2>&1 | tee -a "$LOG_FILE"
  done
  # Always reload nginx to pick up any config changes
  docker exec current-gateway-1 nginx -s reload 2>/dev/null || true
else
  # Config-only change — reload gateway and nothing else
  docker exec current-gateway-1 nginx -s reload 2>/dev/null && log "Gateway config reloaded" || true
fi

# -------------------------------------------------------------------
# Step 9: Health check
# -------------------------------------------------------------------
log "Step 9: Health check"
MAX_WAIT=60
ELAPSED=0
while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:1337/_health 2>/dev/null || echo "000")
  if [[ "$HTTP" == "204" ]]; then
    log "CMS health: 204 OK"
    break
  fi
  warn "CMS health: $HTTP (waiting...)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done
[[ "$HTTP" != "204" ]] && warn "CMS health check timed out — check logs"

# -------------------------------------------------------------------
# Step 10: Prune old releases
# -------------------------------------------------------------------
log "Step 10: Pruning old releases (keep $KEEP_RELEASES)"
CURRENT_REAL=$(readlink -f "$CURRENT_LINK")
ls -dt "$RELEASES_DIR"/*/ 2>/dev/null | tail -n +$((KEEP_RELEASES + 1)) | while read -r old; do
  [[ "$old" == "$CURRENT_REAL/" || "$old" == "$CURRENT_REAL" ]] && continue
  log "  Removing old release: $(basename "$old")"
  rm -rf "$old"
done

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------
log ""
log "=== Deploy complete ==="
log "  Release : $DEPLOY_ID"
log "  SHA     : ${NEW_SHA::7}"
log "  Log     : $LOG_FILE"
log ""
docker ps --filter "name=current-" --format "  {{.Names}}  {{.Status}}"
