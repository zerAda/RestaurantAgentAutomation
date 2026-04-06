#!/usr/bin/env bash
# ==============================================================================
# Registry Validity Test
# Validates workflow_registry.json and product_modules.json structure and
# cross-references with actual workflow files.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="$REPO_ROOT/config/workflow_registry.json"
MODULES="$REPO_ROOT/config/product_modules.json"
WORKFLOWS_DIR="$REPO_ROOT/workflows"

ERRORS=0

echo "=== Validating JSON syntax ==="

if ! python3 -c "import json; json.load(open('$REGISTRY'))" 2>/dev/null; then
  if ! node -e "JSON.parse(require('fs').readFileSync('$REGISTRY','utf8'))" 2>/dev/null; then
    echo "❌ workflow_registry.json has invalid JSON"
    ERRORS=$((ERRORS + 1))
  fi
fi
echo "✅ workflow_registry.json syntax OK"

if ! python3 -c "import json; json.load(open('$MODULES'))" 2>/dev/null; then
  if ! node -e "JSON.parse(require('fs').readFileSync('$MODULES','utf8'))" 2>/dev/null; then
    echo "❌ product_modules.json has invalid JSON"
    ERRORS=$((ERRORS + 1))
  fi
fi
echo "✅ product_modules.json syntax OK"

echo ""
echo "=== Cross-referencing registry with workflow files ==="

# Extract workflow file references from registry
REGISTRY_FILES=$(node -e "
const r = JSON.parse(require('fs').readFileSync('$REGISTRY','utf8'));
r.workflows.forEach(w => console.log(w.file));
")

for FILE in $REGISTRY_FILES; do
  if [ ! -f "$WORKFLOWS_DIR/$FILE" ]; then
    echo "❌ Registry references $FILE but file not found in workflows/"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
echo "=== Checking for unregistered workflows ==="

for WF_FILE in "$WORKFLOWS_DIR"/*.json; do
  BASENAME=$(basename "$WF_FILE")
  if ! echo "$REGISTRY_FILES" | grep -q "^${BASENAME}$"; then
    echo "⚠️  $BASENAME exists in workflows/ but not in registry"
  fi
done

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "❌ $ERRORS errors found"
  exit 1
fi
echo "✅ All registry checks passed"
