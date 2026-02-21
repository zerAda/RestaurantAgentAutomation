#!/bin/bash
# scripts/ops/check_drift.sh
# Checks for configuration drift between local .env.example and remote shared .env
# Usage: ./check_drift.sh <ssh_user> <ssh_host> <remote_project_dir>

SSH_USER=$1
SSH_HOST=$2
REMOTE_DIR=$3

if [ -z "$SSH_USER" ] || [ -z "$SSH_HOST" ] || [ -z "$REMOTE_DIR" ]; then
  echo "Usage: $0 <user> <host> <remote_dir>"
  exit 1
fi

echo "=== Config drift detection ==="

# Extract variable names from local config/.env.example
if [ ! -f "config/.env.example" ]; then
  echo "::notice::No config/.env.example found - skipping drift check"
  exit 0
fi

LOCAL_VARS=$(grep -E '^[A-Z_][A-Z0-9_]*=' config/.env.example 2>/dev/null | cut -d= -f1 | sort)

if [ -z "$LOCAL_VARS" ]; then
  echo "::notice::config/.env.example is empty - skipping drift check"
  exit 0
fi

# Extract variable names from VPS shared .env
# We use single quotes for the remote command to prevent local expansion
VPS_VARS=$(ssh -o StrictHostKeyChecking=no "$SSH_USER@$SSH_HOST" \
  "grep -E '^[A-Z_][A-Z0-9_]*=' $REMOTE_DIR/shared/.env 2>/dev/null | cut -d= -f1 | sort" || echo "")

if [ -z "$VPS_VARS" ]; then
  echo "::warning::No shared .env found on VPS at $REMOTE_DIR/shared/.env - skipping drift check"
  exit 0
fi

# Find vars in .env.example that are missing from VPS .env
MISSING_VARS=""
for var in $LOCAL_VARS; do
  if ! echo "$VPS_VARS" | grep -qx "$var"; then
    MISSING_VARS="${MISSING_VARS}${var}\n"
  fi
done

if [ -n "$MISSING_VARS" ]; then
  echo "::warning::Config drift detected - variables in config/.env.example missing from VPS shared .env:"
  echo -e "$MISSING_VARS" | while read -r v; do
    if [ -n "$v" ]; then echo "::warning::  Missing var: $v"; fi
  done
else
  echo "No config drift detected - all .env.example vars present on VPS"
fi

exit 0
