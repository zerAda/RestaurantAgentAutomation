#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Environment Sync Check =="

ENV_EXAMPLE="config/.env.example"

if [[ ! -f "$ENV_EXAMPLE" ]]; then
  echo "ERROR: $ENV_EXAMPLE not found"
  exit 1
fi

# Extract expected variable names (lines starting with VAR_NAME=)
EXPECTED=$(grep -E '^[A-Z_][A-Z0-9_]*=' "$ENV_EXAMPLE" | cut -d= -f1 | sort)

# Read actual vars from stdin or file argument
if [[ $# -gt 0 && -f "$1" ]]; then
  ACTUAL=$(grep -E '^[A-Z_][A-Z0-9_]*=' "$1" | cut -d= -f1 | sort)
else
  echo "Usage: $0 <production-.env-file>"
  echo "  Or pipe production env var names via stdin"
  exit 1
fi

# Compare
MISSING=$(comm -23 <(echo "$EXPECTED") <(echo "$ACTUAL"))
EXTRA=$(comm -13 <(echo "$EXPECTED") <(echo "$ACTUAL"))

echo ""
echo "Expected vars: $(echo "$EXPECTED" | wc -l)"
echo "Actual vars:   $(echo "$ACTUAL" | wc -l)"

EXIT_CODE=0

if [[ -n "$MISSING" ]]; then
  echo ""
  echo "MISSING (in .env.example but not in production):"
  echo "$MISSING" | while read -r var; do
    echo "  - $var"
  done

  # Check required vars
  REQUIRED="DOMAIN_NAME WEBHOOK_SHARED_TOKEN META_APP_SECRET POSTGRES_USER POSTGRES_PASSWORD"
  for req in $REQUIRED; do
    if echo "$MISSING" | grep -q "^${req}$"; then
      echo "CRITICAL: Required var $req is missing in production!"
      EXIT_CODE=1
    fi
  done
fi

if [[ -n "$EXTRA" ]]; then
  echo ""
  echo "EXTRA (in production but not in .env.example):"
  echo "$EXTRA" | while read -r var; do
    echo "  + $var"
  done
fi

if [[ -z "$MISSING" && -z "$EXTRA" ]]; then
  echo ""
  echo "Environment is in sync!"
fi

exit $EXIT_CODE
