#!/bin/bash
# =============================================================================
# scripts/ops/deploy_to_node.sh
# =============================================================================
# Atomic per-node deployment script for Multi-Node Inventory System.
# Encapsulates all deployment logic for a single node:
#   1. Create release directory
#   2. Link shared resources (.env, secrets/)
#   3. Copy production compose file
#   4. Pull Docker images
#   5. Run migrations (primary node only)
#   6. Start services + symlink cutover
#   7. Deep health check
#
# Usage (called via SSH from the GitHub Actions runner):
#   deploy_to_node.sh \
#     --role <primary|replica> \
#     --project-dir /opt/resto \
#     --release-dir /opt/resto/releases/<deploy-id> \
#     --backup-dir /opt/resto/backups \
#     --log-dir /var/log/resto-bot \
#     --is-first-deploy <true|false> \
#     --github-owner <owner> \
#     --image-sha <commit-sha> \
#     --github-actor <actor> \
#     --github-token <token>
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)           ROLE="$2";           shift 2 ;;
    --project-dir)    PROJECT_DIR="$2";    shift 2 ;;
    --release-dir)    RELEASE_DIR="$2";    shift 2 ;;
    --backup-dir)     BACKUP_DIR="$2";     shift 2 ;;
    --log-dir)        LOG_DIR="$2";        shift 2 ;;
    --is-first-deploy) IS_FIRST="$2";      shift 2 ;;
    --github-owner)   GH_OWNER="$2";       shift 2 ;;
    --image-sha)      IMAGE_SHA="$2";      shift 2 ;;
    --github-actor)   GH_ACTOR="$2";       shift 2 ;;
    --github-token)   GH_TOKEN="$2";       shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# Validate required args
for var in ROLE PROJECT_DIR RELEASE_DIR IMAGE_SHA GH_OWNER GH_ACTOR GH_TOKEN; do
  if [ -z "${!var:-}" ]; then
    echo "::error::Missing required argument: --$(echo "$var" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    exit 1
  fi
done

# Defaults
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"
LOG_DIR="${LOG_DIR:-/var/log/resto-bot}"
IS_FIRST="${IS_FIRST:-false}"

# Image URIs (GHCR requires lowercase owner)
GH_OWNER_LC="${GH_OWNER,,}"
CMS_IMAGE="ghcr.io/${GH_OWNER_LC}/resto-bot-cms:${IMAGE_SHA}"
ADMIN_IMAGE="ghcr.io/${GH_OWNER_LC}/resto-bot-admin:${IMAGE_SHA}"
KIOSK_IMAGE="ghcr.io/${GH_OWNER_LC}/resto-bot-kiosk:${IMAGE_SHA}"

echo "============================================="
echo "Deploy to Node — Role: $ROLE"
echo "  Project:  $PROJECT_DIR"
echo "  Release:  $RELEASE_DIR"
echo "  Images:   $IMAGE_SHA"
echo "============================================="

# ---------------------------------------------------------------------------
# Step 1: Create directory structure
# ---------------------------------------------------------------------------
echo ">>> Step 1: Creating directories..."
mkdir -p "$RELEASE_DIR"
mkdir -p "$PROJECT_DIR/shared/secrets"
mkdir -p "$PROJECT_DIR/shared"
mkdir -p "$PROJECT_DIR/releases"
mkdir -p "$BACKUP_DIR"
mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# Step 2: Link shared resources
# ---------------------------------------------------------------------------
echo ">>> Step 2: Linking shared resources..."

# Link .env
if [ -f "$PROJECT_DIR/shared/.env" ]; then
  ln -sf "$PROJECT_DIR/shared/.env" "$RELEASE_DIR/.env"
elif [ -f "$PROJECT_DIR/current/.env" ] && [ "$IS_FIRST" != "true" ]; then
  cp "$PROJECT_DIR/current/.env" "$PROJECT_DIR/shared/.env"
  ln -sf "$PROJECT_DIR/shared/.env" "$RELEASE_DIR/.env"
fi

# Link secrets
if [ -d "$PROJECT_DIR/shared/secrets" ] && [ "$(ls -A "$PROJECT_DIR/shared/secrets" 2>/dev/null)" ]; then
  ln -sf "$PROJECT_DIR/shared/secrets" "$RELEASE_DIR/secrets"
elif [ -d "$PROJECT_DIR/current/secrets" ] && [ "$IS_FIRST" != "true" ]; then
  cp -rp "$PROJECT_DIR/current/secrets/"* "$PROJECT_DIR/shared/secrets/" 2>/dev/null || true
  ln -sf "$PROJECT_DIR/shared/secrets" "$RELEASE_DIR/secrets"
fi

# ---------------------------------------------------------------------------
# Step 3: Production compose file
# ---------------------------------------------------------------------------
echo ">>> Step 3: Setting up compose file..."
if [ -f "$RELEASE_DIR/docker-compose.hostinger.prod.yml" ]; then
  cp "$RELEASE_DIR/docker-compose.hostinger.prod.yml" "$RELEASE_DIR/docker-compose.yml"
fi

# Create Docker volumes on first deploy
if [ "$IS_FIRST" = "true" ]; then
  echo "First deploy — creating Docker volumes..."
  for vol in traefik_data n8n_data postgres_data redis_data cms_uploads ollama_data; do
    docker volume create "$vol" 2>/dev/null || true
  done
fi

# ---------------------------------------------------------------------------
# Step 4: Pull images
# ---------------------------------------------------------------------------
echo ">>> Step 4: Pulling Docker images..."
cd "$RELEASE_DIR"

export GITHUB_REPOSITORY_OWNER="$GH_OWNER"
export CMS_IMAGE ADMIN_IMAGE KIOSK_IMAGE

echo "$GH_TOKEN" | docker login ghcr.io -u "$GH_ACTOR" --password-stdin
docker compose pull --quiet

# ---------------------------------------------------------------------------
# Step 5: Migrations (primary only)
# ---------------------------------------------------------------------------
if [ "$ROLE" = "primary" ]; then
  echo ">>> Step 5: Running migrations (primary node)..."
  docker compose up -d postgres redis
  echo "Waiting for PostgreSQL..."
  for i in $(seq 1 30); do
    if docker compose exec -T postgres pg_isready -U n8n -d n8n >/dev/null 2>&1; then
      echo "PostgreSQL ready"
      break
    fi
    sleep 2
  done

  docker compose up db-migrate
  MIGRATE_EXIT=$(docker compose ps db-migrate --format '{{.ExitCode}}' 2>/dev/null || echo "0")

  if [ "$MIGRATE_EXIT" != "0" ] && [ "$MIGRATE_EXIT" != "" ]; then
    echo "::error::Migration failed (exit code: $MIGRATE_EXIT)"
    docker compose logs db-migrate --tail=50
    exit 1
  fi
  echo "Migrations complete"
else
  echo ">>> Step 5: Skipping migrations (replica node)"
fi

# ---------------------------------------------------------------------------
# Step 6: Start services + symlink cutover
# ---------------------------------------------------------------------------
echo ">>> Step 6: Starting services and activating release..."
cd "$RELEASE_DIR"
docker compose up -d --remove-orphans

echo "Activating release symlink..."
ln -sfn "$RELEASE_DIR" "$PROJECT_DIR/current"
echo "Active release: $(readlink "$PROJECT_DIR/current")"
docker compose ps

# ---------------------------------------------------------------------------
# Step 7: Deep health check
# ---------------------------------------------------------------------------
echo ">>> Step 7: Running deep health check..."
if [ -f "$RELEASE_DIR/.env" ]; then set -a; source "$RELEASE_DIR/.env"; set +a; fi
if [ -f "$RELEASE_DIR/scripts/deep-health-check.sh" ]; then
  bash "$RELEASE_DIR/scripts/deep-health-check.sh"
else
  echo "::warning::deep-health-check.sh not found — skipping"
fi

echo "============================================="
echo "✅ Deploy complete — Role: $ROLE"
echo "============================================="
