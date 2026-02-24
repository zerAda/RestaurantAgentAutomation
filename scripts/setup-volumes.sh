#!/bin/bash
# =============================================================================
# Setup Docker Volumes
# =============================================================================
# Creates external Docker volumes required by docker-compose.hostinger.prod.yml.
# Idempotent: safe to run multiple times.
#
# Usage: bash scripts/setup-volumes.sh
# =============================================================================
set -euo pipefail

VOLUMES="traefik_data n8n_data postgres_data redis_data cms_uploads ollama_data"

echo "=== Docker Volume Setup ==="

for vol in $VOLUMES; do
  if docker volume inspect "$vol" > /dev/null 2>&1; then
    echo "  [OK] $vol (exists)"
  else
    docker volume create "$vol" > /dev/null
    echo "  [CREATED] $vol"
  fi
done

echo "=== All volumes ready ==="
