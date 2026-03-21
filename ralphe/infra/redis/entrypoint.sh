#!/bin/sh
# Redis startup script with optional password support.
# Set REDIS_PASSWORD in .env to enable authentication.
# Leave empty (or unset) for backward-compatible no-auth mode.
set -e

ARGS="--appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru"

if [ -n "$REDIS_PASSWORD" ]; then
  echo "[redis-entrypoint] Starting Redis with password authentication"
  exec redis-server $ARGS --requirepass "$REDIS_PASSWORD"
else
  echo "[redis-entrypoint] Starting Redis without password (set REDIS_PASSWORD to enable auth)"
  exec redis-server $ARGS
fi
