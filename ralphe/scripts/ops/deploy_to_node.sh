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

# Force unbuffered output so SSH sessions flush each line immediately
export PYTHONUNBUFFERED=1
# Use line-buffered stdout for all commands (critical for SSH output visibility)
if command -v stdbuf >/dev/null 2>&1; then
  exec 1> >(stdbuf -oL cat)
fi

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
# Variable names MUST match docker-compose.ghcr.yml: GHCR_IMAGE_CMS, GHCR_IMAGE_ADMIN, GHCR_IMAGE_KIOSK
GH_OWNER_LC="${GH_OWNER,,}"
GHCR_IMAGE_CMS="ghcr.io/${GH_OWNER_LC}/resto-bot-cms:${IMAGE_SHA}"
GHCR_IMAGE_ADMIN="ghcr.io/${GH_OWNER_LC}/resto-bot-admin:${IMAGE_SHA}"
GHCR_IMAGE_KIOSK="ghcr.io/${GH_OWNER_LC}/resto-bot-kiosk:${IMAGE_SHA}"

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
# Step 1.5: Initialize minimum secrets to prevent directory-mount errors on empty VPS
# ---------------------------------------------------------------------------
if [ "$IS_FIRST" = "true" ]; then
  echo ">>> Step 1.5: Initializing minimum secrets on first deploy..."

  if [ ! -f "$PROJECT_DIR/shared/.env" ]; then
    if [ -f "$RELEASE_DIR/config/.env.example" ]; then
      echo "Copying .env.example as starting .env..."
      cp "$RELEASE_DIR/config/.env.example" "$PROJECT_DIR/shared/.env"
    else
      touch "$PROJECT_DIR/shared/.env"
    fi
  fi

  if [ ! -f "$PROJECT_DIR/shared/secrets/postgres_password" ]; then
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 > "$PROJECT_DIR/shared/secrets/postgres_password"
  fi

  if [ ! -f "$PROJECT_DIR/shared/secrets/n8n_encryption_key" ]; then
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 > "$PROJECT_DIR/shared/secrets/n8n_encryption_key"
  fi

  if [ ! -f "$PROJECT_DIR/shared/secrets/strapi_db_password" ]; then
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 > "$PROJECT_DIR/shared/secrets/strapi_db_password"
  fi

  if [ ! -f "$PROJECT_DIR/shared/secrets/redis_password" ]; then
    touch "$PROJECT_DIR/shared/secrets/redis_password"
  fi

  if [ ! -f "$PROJECT_DIR/shared/secrets/traefik_usersfile" ]; then
    touch "$PROJECT_DIR/shared/secrets/traefik_usersfile"
  fi
fi

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
if [ -f "$RELEASE_DIR/docker-compose.ghcr.yml" ]; then
  cp "$RELEASE_DIR/docker-compose.ghcr.yml" "$RELEASE_DIR/docker-compose.yml"
  echo "Using GHCR artifact compose file."
elif [ -f "$RELEASE_DIR/docker-compose.hostinger.prod.yml" ]; then
  cp "$RELEASE_DIR/docker-compose.hostinger.prod.yml" "$RELEASE_DIR/docker-compose.yml"
  echo "Using legacy hostinger prod compose file."
fi

# Ensure Docker networks exist (always, even on re-deploy — prune can remove them)
echo "Ensuring Docker networks exist..."
for net in proxy internal; do
  docker network create "$net" 2>/dev/null || true
done

# Create Docker volumes on first deploy
if [ "$IS_FIRST" = "true" ]; then
  echo "First deploy — creating Docker volumes..."
  for vol in traefik_data n8n_data postgres_data redis_data cms_uploads ollama_data; do
    docker volume create "$vol" 2>/dev/null || true
  done
fi

# ---------------------------------------------------------------------------
# Step 3.5: Pre-pull cleanup (free disk space for images)
# ---------------------------------------------------------------------------
echo ">>> Step 3.5: Pre-pull disk check and cleanup..."
DISK_FREE_MB=$(df -BM / | tail -1 | awk '{print $4}' | tr -d 'M')
echo "Disk free: ${DISK_FREE_MB}MB"
if [ "$DISK_FREE_MB" -lt 2048 ]; then
  echo "Low disk space — running Docker cleanup..."
  docker system prune -f --volumes 2>/dev/null || true
  docker image prune -a -f --filter "until=72h" 2>/dev/null || true
  DISK_FREE_MB=$(df -BM / | tail -1 | awk '{print $4}' | tr -d 'M')
  echo "Disk free after cleanup: ${DISK_FREE_MB}MB"
  if [ "$DISK_FREE_MB" -lt 1024 ]; then
    echo "::error::Insufficient disk space: ${DISK_FREE_MB}MB (need 1024MB minimum)"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Step 4: Pull images
# ---------------------------------------------------------------------------
echo ">>> Step 4: Pulling Docker images..."
cd "$RELEASE_DIR"

# Source .env for any additional compose variables (DOMAIN_NAME, N8N_VERSION, etc.)
if [ -f .env ]; then set -a; source .env; set +a; fi

export GITHUB_REPOSITORY_OWNER="$GH_OWNER"
export GHCR_IMAGE_CMS GHCR_IMAGE_ADMIN GHCR_IMAGE_KIOSK

echo "$GH_TOKEN" | docker login ghcr.io -u "$GH_ACTOR" --password-stdin
echo "GHCR login complete. Pulling images (this may take several minutes)..."

# Pull WITHOUT --quiet so progress is visible through SSH
# CMS image is ~500MB and VPS bandwidth may be limited (can take 15-20 min)
# Use generous timeout to avoid killing a legitimate slow pull
timeout 1500 docker compose pull 2>&1 || {
  PULL_EXIT=$?
  if [ "$PULL_EXIT" -eq 124 ]; then
    echo "::error::docker compose pull timed out after 25 minutes"
  else
    echo "::warning::docker compose pull failed (exit $PULL_EXIT), retrying individual images..."
  fi
  # Retry individual GHCR images (public images are usually cached)
  for img in "$GHCR_IMAGE_CMS" "$GHCR_IMAGE_ADMIN" "$GHCR_IMAGE_KIOSK"; do
    echo "Pulling $img ..."
    timeout 1200 docker pull "$img" 2>&1 || echo "::warning::Failed to pull $img"
  done
}
echo "Image pull complete."

# ---------------------------------------------------------------------------
# Step 5a: Stop previous services (free ports + shared volumes)
# ---------------------------------------------------------------------------
echo ">>> Step 5a: Stopping previous services..."

# Stop services from current symlink if it exists (normal re-deploy)
if [ -L "$PROJECT_DIR/current" ] && [ -d "$PROJECT_DIR/current" ]; then
  echo "Stopping services from previous release..."
  cd "$PROJECT_DIR/current"
  docker compose down --remove-orphans --timeout 30 2>/dev/null || true
fi

# Stop services from any OTHER release directory (handles failed deploys with no symlink)
for OLD_RELEASE in $(ls -1d "$PROJECT_DIR/releases"/*/ 2>/dev/null); do
  OLD_RELEASE="${OLD_RELEASE%/}"
  if [ "$OLD_RELEASE" = "$RELEASE_DIR" ]; then continue; fi
  if [ -f "$OLD_RELEASE/docker-compose.yml" ] || [ -f "$OLD_RELEASE/docker-compose.hostinger.prod.yml" ]; then
    echo "Stopping orphaned services from: $OLD_RELEASE"
    cd "$OLD_RELEASE" && docker compose down --remove-orphans --timeout 30 2>/dev/null || true
  fi
done

# Stop legacy services (manual deploys at /root/project, etc.)
# Always check for legacy containers, not just on first deploy,
# because manual workaround deploys may exist outside /opt/resto
for LEGACY_DIR in /root/project /root/resto-bot /home/deploy/project; do
  if [ -d "$LEGACY_DIR" ] 2>/dev/null; then
    echo "Stopping legacy services from $LEGACY_DIR..."
    cd "$LEGACY_DIR" 2>/dev/null && {
      if [ -f "docker-compose.hostinger.prod.yml" ]; then
        docker compose -f docker-compose.hostinger.prod.yml down --remove-orphans --timeout 30 2>/dev/null || true
      fi
      docker compose down --remove-orphans --timeout 30 2>/dev/null || true
    } || echo "Cannot access $LEGACY_DIR (permission denied — may need manual cleanup)"
  fi
done

# Stop ANY remaining containers that use ports we need (80, 443, 5678, 5432, 6379, 1337, 8080)
# This catches containers from any project name, manual runs, etc.
echo "Checking for conflicting containers on critical ports..."
for port in 80 443 5678 5432 6379 1337 8080; do
  CONFLICT=$(docker ps -q --filter "publish=$port" 2>/dev/null)
  if [ -n "$CONFLICT" ]; then
    echo "Stopping container(s) on port $port: $CONFLICT"
    docker stop $CONFLICT 2>/dev/null || true
    docker rm $CONFLICT 2>/dev/null || true
  fi
done

# Also stop any containers with "project-" prefix (legacy naming convention)
LEGACY_CONTAINERS=$(docker ps -q --filter "name=project-" 2>/dev/null)
if [ -n "$LEGACY_CONTAINERS" ]; then
  echo "Stopping legacy containers by name prefix..."
  docker stop $LEGACY_CONTAINERS 2>/dev/null || true
  docker rm $LEGACY_CONTAINERS 2>/dev/null || true
fi

# Stop any remaining staging containers (missed cleanup)
STAGING_CONTAINERS=$(docker ps -q --filter "name=resto-staging" 2>/dev/null)
if [ -n "$STAGING_CONTAINERS" ]; then
  echo "Stopping leftover staging containers..."
  docker stop $STAGING_CONTAINERS 2>/dev/null || true
  docker rm $STAGING_CONTAINERS 2>/dev/null || true
fi

echo "Waiting for ports to free up..."
sleep 5

# Verify critical ports are free
for port in 80 443 5678 5432 6379; do
  if docker ps -q --filter "publish=$port" 2>/dev/null | grep -q .; then
    echo "::warning::Port $port is still occupied after cleanup"
  fi
done

# ---------------------------------------------------------------------------
# Step 5b: Migrations (primary only)
# ---------------------------------------------------------------------------
cd "$RELEASE_DIR"
if [ "$ROLE" = "primary" ]; then
  echo ">>> Step 5b: Running migrations (primary node)..."
  docker compose up -d postgres redis
  echo "Waiting for PostgreSQL..."
  PG_READY=false
  for i in $(seq 1 30); do
    if docker compose exec -T postgres pg_isready -U n8n -d n8n >/dev/null 2>&1; then
      echo "PostgreSQL ready"
      PG_READY=true
      break
    fi
    sleep 2
  done

  if [ "$PG_READY" = "false" ]; then
    echo "::error::PostgreSQL failed to become ready! Dumping logs:"
    docker compose logs postgres --tail=100
    exit 1
  fi

  docker compose up db-migrate 2>&1 || true
  MIGRATE_EXIT=$(docker compose ps db-migrate --format '{{.ExitCode}}' 2>/dev/null || echo "0")

  if [ "$MIGRATE_EXIT" != "0" ] && [ "$MIGRATE_EXIT" != "" ]; then
    echo "::warning::Migration exited with code $MIGRATE_EXIT (non-blocking)"
    docker compose logs db-migrate --tail=20
  fi
  echo "Migrations complete"
else
  echo ">>> Step 5b: Skipping migrations (replica node)"
fi

# ---------------------------------------------------------------------------
# Step 6: Start services + symlink cutover
# ---------------------------------------------------------------------------
echo ">>> Step 6: Starting services and activating release..."
cd "$RELEASE_DIR"
# Remove db-migrate container from Step 5b so docker compose up recreates it fresh.
# If it exited non-zero, cached exit code would block services with
# depends_on: { condition: service_completed_successfully }
docker compose rm -f db-migrate 2>/dev/null || true
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
  # Exit codes: 0=healthy, 1=warning, 2=critical
  # Tolerate warnings (e.g. disk 76%) — only fail on critical
  set +e
  bash "$RELEASE_DIR/scripts/deep-health-check.sh"
  HC_EXIT=$?
  set -e
  if [ "$HC_EXIT" -ge 2 ]; then
    echo "::error::Deep health check CRITICAL (exit $HC_EXIT)"
    exit 1
  elif [ "$HC_EXIT" -eq 1 ]; then
    echo "::warning::Deep health check returned warnings (non-blocking)"
  fi
else
  echo "::warning::deep-health-check.sh not found — skipping"
fi

echo "============================================="
echo "✅ Deploy complete — Role: $ROLE"
echo "============================================="
