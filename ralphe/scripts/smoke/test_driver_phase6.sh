#!/usr/bin/env bash
# =============================================================================
# RESTO BOT - Phase 6 Diamond Driver WhatsApp Smoke Tests
# =============================================================================
# Tests all driver delivery webhook endpoints
# Usage: ./scripts/smoke/test_driver_phase6.sh [--verbose]
# =============================================================================
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
: "${API_URL:=http://localhost:8080}"
: "${STRAPI_URL:=http://localhost:1337}"
: "${STRAPI_API_TOKEN:=}"

PASSED=0
FAILED=0
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v) VERBOSE=true; shift ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# ─── Helpers ─────────────────────────────────────────────────────────────────

pass() { PASSED=$((PASSED + 1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { FAILED=$((FAILED + 1)); echo -e "  ${RED}✗${NC} $1"; }

test_webhook() {
    local name="$1"
    local path="$2"
    local payload="${3:-{}}"

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${API_URL}${path}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        --max-time 10 2>/dev/null || echo "000")

    if [[ "$status" =~ ^(200|201|204|404)$ ]]; then
        pass "${name} (HTTP ${status})"
    else
        fail "${name} (HTTP ${status})"
    fi
}

test_strapi_collection() {
    local name="$1"
    local endpoint="$2"

    if [[ -z "$STRAPI_API_TOKEN" ]]; then
        echo -e "  ${YELLOW}⊘${NC} ${name} (skipped — no STRAPI_API_TOKEN)"
        return
    fi

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -X GET "${STRAPI_URL}${endpoint}" \
        -H "Authorization: Bearer ${STRAPI_API_TOKEN}" \
        --max-time 10 2>/dev/null || echo "000")

    if [[ "$status" =~ ^(200|201)$ ]]; then
        pass "${name} (HTTP ${status})"
    else
        fail "${name} (HTTP ${status})"
    fi
}

# ─── Test Suite ──────────────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE} Phase 6 — Diamond Driver WhatsApp Smoke Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

DRIVER_PHONE="+213555000001"
DRIVER_PAYLOAD="{\"from\":\"${DRIVER_PHONE}\",\"phone\":\"${DRIVER_PHONE}\"}"
OTP_PAYLOAD="{\"from\":\"${DRIVER_PHONE}\",\"text\":\"1234\"}"
CLAIM_PAYLOAD="{\"from\":\"${DRIVER_PHONE}\",\"button_id\":\"CLAIM_1\"}"
IGNORE_PAYLOAD="{\"from\":\"${DRIVER_PHONE}\",\"button_id\":\"IGNORE_1\"}"

# ── Section 1: Webhook endpoints ──
echo -e "${YELLOW}Section 1: Driver Webhook Endpoints${NC}"

test_webhook "Onboarding webhook" \
    "/webhook/strapi/driver-created" \
    "{\"entry\":{\"id\":999,\"phone_number\":\"${DRIVER_PHONE}\",\"first_name\":\"Test\",\"last_name\":\"Driver\",\"is_active\":true}}"

test_webhook "Router webhook" \
    "/webhook/driver/menu" \
    "${DRIVER_PAYLOAD}"

test_webhook "Available list webhook" \
    "/webhook/driver/available" \
    "${DRIVER_PAYLOAD}"

test_webhook "Action: claim webhook" \
    "/webhook/driver/action" \
    "${CLAIM_PAYLOAD}"

test_webhook "Action: ignore webhook" \
    "/webhook/driver/action" \
    "${IGNORE_PAYLOAD}"

test_webhook "OTP verify webhook" \
    "/webhook/driver/otp-verify" \
    "${OTP_PAYLOAD}"

test_webhook "History webhook" \
    "/webhook/driver/history" \
    "${DRIVER_PAYLOAD}"

echo ""

# ── Section 2: Strapi collections ──
echo -e "${YELLOW}Section 2: Strapi Collections${NC}"

test_strapi_collection "Driver collection accessible" \
    "/api/drivers?pagination[limit]=1"

test_strapi_collection "Driver-order-ignore collection accessible" \
    "/api/driver-order-ignores?pagination[limit]=1"

test_strapi_collection "Order delivery fields accessible" \
    "/api/orders?filters[delivery_status][\$eq]=READY_FOR_DELIVERY&pagination[limit]=1"

echo ""

# ── Section 3: Workflow JSON validation ──
echo -e "${YELLOW}Section 3: Workflow JSON Validation${NC}"

WORKFLOWS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/workflows"

for wf in W_DRIVER_ONBOARDING W_DRIVER_ROUTER W_DRIVER_AVAILABLE_LIST W_DRIVER_ACTIONS W_DRIVER_OTP_VERIFY W_DRIVER_HISTORY; do
    FILE="${WORKFLOWS_DIR}/${wf}.json"
    if [[ -f "$FILE" ]]; then
        if python3 -c "import json; json.load(open('${FILE}'))" 2>/dev/null; then
            pass "${wf}.json is valid JSON"
        else
            fail "${wf}.json has invalid JSON"
        fi
    else
        fail "${wf}.json not found"
    fi
done

echo ""

# ── Summary ──
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed: ${PASSED}${NC}  |  ${RED}Failed: ${FAILED}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

[[ $FAILED -eq 0 ]] && exit 0 || exit 1
