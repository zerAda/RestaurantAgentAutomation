#!/bin/sh
# =============================================================================
# n8n Worker Entrypoint
# =============================================================================
# n8n worker does NOT support N8N_ENCRYPTION_KEY_FILE natively.
# This entrypoint reads the encryption key from the Docker secret file
# and exports it as an environment variable before starting the worker.
#
# Usage: Mounted as entrypoint in docker-compose for n8n-worker service.
# =============================================================================
set -e

SECRET_FILE="/run/secrets/n8n_encryption_key"

if [ ! -f "$SECRET_FILE" ]; then
  echo "FATAL: $SECRET_FILE not found. Cannot start n8n worker without encryption key."
  exit 1
fi

export N8N_ENCRYPTION_KEY
N8N_ENCRYPTION_KEY=$(cat "$SECRET_FILE")

if [ -z "$N8N_ENCRYPTION_KEY" ]; then
  echo "FATAL: $SECRET_FILE is empty. Cannot start n8n worker without encryption key."
  exit 1
fi

echo "n8n-worker: Encryption key loaded from secret file."

# Hand off to the standard n8n entrypoint
exec tini -- /docker-entrypoint.sh worker
