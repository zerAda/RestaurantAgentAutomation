#!/bin/bash
# =============================================================================
# scripts/ops/deploy_staging_to_node.sh
# =============================================================================
# Deployment logic for the staging environment on a single node.
# Encapsulates the operations that were previously an inline script in the CD pipeline.
#
# Usage (called via SSH from the GitHub Actions runner):
#   deploy_staging_to_node.sh \
#     --staging-dir <path> \
#     --project-dir <path> \
#     --deploy-sha <commit-sha> \
#     --github-owner <owner> \
#     --github-actor <actor> \
#     --github-token <token>
# =============================================================================

set -e

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --staging-dir)  STAGING_DIR="$2";  shift 2 ;;
    --project-dir)  PROJECT_DIR="$2";  shift 2 ;;
    --deploy-sha)   DEPLOY_SHA="$2";   shift 2 ;;
    --github-owner) GH_OWNER="$2";     shift 2 ;;
    --github-actor) GH_ACTOR="$2";     shift 2 ;;
    --github-token) GH_TOKEN="$2";     shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# Link shared .env and secrets into staging release
if [ -f "$PROJECT_DIR/shared/.env" ]; then
  ln -sf "$PROJECT_DIR/shared/.env" "$STAGING_DIR/.env"
fi

if [ -d "$PROJECT_DIR/shared/secrets" ] && [ "$(ls -A "$PROJECT_DIR/shared/secrets" 2>/dev/null)" ]; then
  ln -sf "$PROJECT_DIR/shared/secrets" "$STAGING_DIR/secrets"
fi

# Use production compose file (prefer GHCR, fallback to local build)
if [ -f "$STAGING_DIR/docker-compose.ghcr.yml" ]; then
  cp "$STAGING_DIR/docker-compose.ghcr.yml" "$STAGING_DIR/docker-compose.yml"
elif [ -f "$STAGING_DIR/docker-compose.hostinger.prod.yml" ]; then
  cp "$STAGING_DIR/docker-compose.hostinger.prod.yml" "$STAGING_DIR/docker-compose.yml"
fi

cd "$STAGING_DIR"

# Set image tags for GHCR (lowercase owner required by GHCR)
GH_OWNER_LC=$(echo "$GH_OWNER" | tr '[:upper:]' '[:lower:]')
export GITHUB_REPOSITORY_OWNER="$GH_OWNER_LC"
export GHCR_IMAGE_CMS="ghcr.io/$GH_OWNER_LC/resto-bot-cms:$DEPLOY_SHA"
export GHCR_IMAGE_ADMIN="ghcr.io/$GH_OWNER_LC/resto-bot-admin:$DEPLOY_SHA"
export GHCR_IMAGE_KIOSK="ghcr.io/$GH_OWNER_LC/resto-bot-kiosk:$DEPLOY_SHA"

# Login to GHCR on VPS
echo "$GH_TOKEN" | docker login ghcr.io -u "$GH_ACTOR" --password-stdin

# Source .env so scripts can access DOMAIN_NAME etc.
if [ -f .env ]; then set -a; source .env; set +a; fi

# Override external volumes so staging uses its own data (not production!)
cat > docker-compose.staging-override.yml <<'OVERRIDE'
networks:
  internal:
    name: resto_staging_internal

services:
  cms:
    labels:
      - "traefik.http.routers.cms.rule=Host(`staging-cms.${DOMAIN_NAME}`)"
  admin-dashboard:
    labels:
      - "traefik.http.routers.admin-dash.rule=Host(`staging-admin.${DOMAIN_NAME}`)"
  n8n-main:
    labels:
      - "traefik.http.routers.resto-console.rule=Host(`staging-n8n.${DOMAIN_NAME}`)"
  kiosk-app:
    labels:
      - "traefik.http.routers.kiosk.rule=Host(`staging-kiosk.${DOMAIN_NAME}`)"

volumes:
  traefik_data:
    external: false
  n8n_data:
    external: false
  postgres_data:
    external: false
  redis_data:
    external: false
  cms_uploads:
    external: false
  ollama_data:
    external: false
OVERRIDE

STAGING_COMPOSE="docker compose --project-name resto-staging -f docker-compose.yml -f docker-compose.staging-override.yml"

# Validate compose config before starting
$STAGING_COMPOSE config --quiet

# Pull images to verify they exist in registry
$STAGING_COMPOSE pull --quiet

# Start infrastructure services first (postgres, redis)
$STAGING_COMPOSE up -d postgres redis
echo "Waiting for postgres + redis healthy..."
for i in $(seq 1 30); do
  if $STAGING_COMPOSE exec -T postgres pg_isready -U n8n -d n8n >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# Run migrations (may fail on fresh staging DB — non-blocking)
$STAGING_COMPOSE up db-migrate 2>&1 || {
  echo "::warning::db-migrate failed in staging (non-blocking)"
}

# Remove db-migrate so cached exit code doesn't block depends_on
$STAGING_COMPOSE rm -f db-migrate 2>/dev/null || true

# Start remaining services WITHOUT traefik (port 80/443 conflict)
# and WITHOUT db-migrate (already ran above)
STAGING_SERVICES=$($STAGING_COMPOSE config --services 2>/dev/null | grep -Ev '^(traefik|db-migrate)$' | tr '\n' ' ')
$STAGING_COMPOSE up -d --remove-orphans $STAGING_SERVICES || {
  echo "::warning::Some staging services failed to start (non-blocking)"
}

echo "Staging services:"
$STAGING_COMPOSE ps

echo "=== Running Staging Image Cleanup ==="
docker image prune -a -f --filter "until=24h"

echo "=== Running Deep Health Check (Staging) ==="
COMPOSE_PROJECT_NAME=resto-staging bash scripts/deep-health-check.sh
