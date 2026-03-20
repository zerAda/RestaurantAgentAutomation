#!/usr/bin/env bash
# ============================================================================
# OPS: Set W_ERROR_HANDLER as error workflow on ALL n8n workflows
# ============================================================================
# Run from VPS: bash /opt/resto/current/scripts/ops_set_error_workflow.sh
# Or locally if your IP is allowlisted.
#
# Prerequisites:
#   - N8N_API_KEY env var set, or edit the fallback below
#   - jq installed (apt-get install jq)
#   - curl installed
# ============================================================================

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
N8N_BASE="http://localhost:5678"  # Internal URL on VPS (no BasicAuth needed)
API_KEY="${N8N_API_KEY:-39a9c9dc8573353fda064f2dea61f7234532f79874f590afebd19ce3bc6bd8b35cbaf067db828556ca37cbd69f8c3002d0b2dcb7463cd7e7b3e314185b8134cdc5a5c3b355df769196ea0a09b47af742c76acbedd8c3270d2b7b7032c27cbf0d14ccb19795061166388f81d8d45bc4f909b336edfded99cc19ce11b60ec1a37b}"

HEADER="X-N8N-API-KEY: ${API_KEY}"
ERROR_WF_NAME="W_ERROR_HANDLER"

echo "═══════════════════════════════════════════════════════════"
echo "  OPS: Configure Error Workflow on ALL n8n Workflows"
echo "═══════════════════════════════════════════════════════════"

# ── Step 1: Find error handler workflow ID ──────────────────────────────────
echo ""
echo "[1/4] Searching for '${ERROR_WF_NAME}' workflow..."

ALL_WORKFLOWS=$(curl -s -H "${HEADER}" "${N8N_BASE}/api/v1/workflows?limit=200")

# Try to find by name (partial match)
ERROR_WF_ID=$(echo "$ALL_WORKFLOWS" | jq -r ".data[] | select(.name | test(\"${ERROR_WF_NAME}\"; \"i\")) | .id" | head -1)

if [ -z "$ERROR_WF_ID" ] || [ "$ERROR_WF_ID" = "null" ]; then
    echo "    ⚠️  W_ERROR_HANDLER not found in n8n. Importing from local file..."
    
    # Import the workflow
    WF_JSON=$(cat "$(dirname "$0")/../workflows/W_ERROR_HANDLER.json")
    IMPORT_RESULT=$(curl -s -X POST \
        -H "${HEADER}" \
        -H "Content-Type: application/json" \
        -d "${WF_JSON}" \
        "${N8N_BASE}/api/v1/workflows")
    
    ERROR_WF_ID=$(echo "$IMPORT_RESULT" | jq -r '.id')
    
    if [ -z "$ERROR_WF_ID" ] || [ "$ERROR_WF_ID" = "null" ]; then
        echo "    ❌ FAILED to import W_ERROR_HANDLER. Response:"
        echo "$IMPORT_RESULT" | jq .
        exit 1
    fi
    
    echo "    ✅ Imported W_ERROR_HANDLER → ID: ${ERROR_WF_ID}"
    
    # Activate the error handler workflow
    curl -s -X PATCH \
        -H "${HEADER}" \
        -H "Content-Type: application/json" \
        -d '{"active": true}' \
        "${N8N_BASE}/api/v1/workflows/${ERROR_WF_ID}" > /dev/null
    
    echo "    ✅ Activated W_ERROR_HANDLER"
else
    echo "    ✅ Found W_ERROR_HANDLER → ID: ${ERROR_WF_ID}"
fi

# ── Step 2: List all workflows ──────────────────────────────────────────────
echo ""
echo "[2/4] Listing all workflows..."

WORKFLOW_IDS=$(echo "$ALL_WORKFLOWS" | jq -r ".data[] | select(.id != \"${ERROR_WF_ID}\") | .id")
TOTAL=$(echo "$WORKFLOW_IDS" | wc -l)
echo "    Found ${TOTAL} workflows to update (excluding error handler itself)"

# ── Step 3: Update each workflow's settings ─────────────────────────────────
echo ""
echo "[3/4] Setting errorWorkflow=${ERROR_WF_ID} on all workflows..."

SUCCESS=0
FAILED=0
SKIPPED=0

for WF_ID in $WORKFLOW_IDS; do
    WF_NAME=$(echo "$ALL_WORKFLOWS" | jq -r ".data[] | select(.id == \"${WF_ID}\") | .name")
    
    # Check if already configured
    CURRENT_ERROR_WF=$(echo "$ALL_WORKFLOWS" | jq -r ".data[] | select(.id == \"${WF_ID}\") | .settings.errorWorkflow // empty")
    
    if [ "$CURRENT_ERROR_WF" = "$ERROR_WF_ID" ]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    # Update the workflow settings
    RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
        -H "${HEADER}" \
        -H "Content-Type: application/json" \
        -d "{\"settings\": {\"errorWorkflow\": \"${ERROR_WF_ID}\"}}" \
        "${N8N_BASE}/api/v1/workflows/${WF_ID}")
    
    if [ "$RESULT" = "200" ]; then
        SUCCESS=$((SUCCESS + 1))
        echo "    ✅ ${WF_NAME}"
    else
        FAILED=$((FAILED + 1))
        echo "    ❌ ${WF_NAME} (HTTP ${RESULT})"
    fi
    
    # Small delay to avoid overwhelming the API
    sleep 0.1
done

# ── Step 4: Summary ────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  RESULTS"
echo "═══════════════════════════════════════════════════════════"
echo "  Error Handler ID: ${ERROR_WF_ID}"
echo "  ✅ Updated:  ${SUCCESS}"
echo "  ⏭️  Skipped:  ${SKIPPED} (already configured)"
echo "  ❌ Failed:   ${FAILED}"
echo "  Total:       ${TOTAL}"
echo "═══════════════════════════════════════════════════════════"

if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "⚠️  Some workflows failed. Re-run to retry."
    exit 1
fi

echo ""
echo "🎉 Done! All workflows now use W_ERROR_HANDLER for error reporting."
