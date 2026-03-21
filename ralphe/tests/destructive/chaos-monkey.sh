#!/bin/bash
# =============================================================================
# Resto Bot - Chaos Monkey (Resilience Testing)
# =============================================================================
# Purpose: Simulates random service failures to verify auto-healing (Docker restart).
# WARNING: This script is destructive. Do NOT run in production.
# =============================================================================

# Safety Gate: Must set ENABLE_CHAOS=true
if [[ "${ENABLE_CHAOS:-false}" != "true" ]]; then
    echo "❌ Chaos Monkey is caged. Set ENABLE_CHAOS=true to release."
    exit 1
fi

SERVICES=("postgres" "redis" "n8n-main" "inventory-cms")
TARGET_SERVICE=${SERVICES[$RANDOM % ${#SERVICES[@]}]}

echo "🐒 Chaos Monkey is loose!"
echo "🎯 Target acquired: $TARGET_SERVICE"

# 1. Kill the service
echo "🔥 Stopping $TARGET_SERVICE..."
docker compose stop "$TARGET_SERVICE"

# 2. Wait 5 seconds
echo "⏳ Waiting for observer..."
sleep 5

# 3. Check stats
docker compose ps "$TARGET_SERVICE"

# 4. Verify auto-healing
CONTAINER_ID=$(docker compose ps -q "$TARGET_SERVICE")
if [ -n "$CONTAINER_ID" ]; then
    echo "💥 Crashing process in container $CONTAINER_ID..."
    docker exec "$CONTAINER_ID" kill 1
fi

sleep 10
echo "✅ Chaos run complete. Check 'docker compose ps' to verify recovery."
