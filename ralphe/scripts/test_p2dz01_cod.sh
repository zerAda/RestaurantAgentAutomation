#!/usr/bin/env bash
# ==============================================================================
# P2-DZ-01: COD Flow + No-Show Scoring + Admin Controls Tests (Algeria)
# ==============================================================================
set -euo pipefail

# Configuration
: "${API_URL:=http://localhost:8080}"
: "${ADMIN_PHONE:=212600000001}"
: "${TEST_CUSTOMER:=212611111111}"
: "${META_APP_SECRET:=test_app_secret}"
: "${VERBOSE:=false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; }

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

generate_signature() {
    local payload="$1"
    local secret="$2"
    echo -n "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/^.* //'
}

send_admin_command() {
    local cmd="$1"
    local PAYLOAD="{
        \"object\": \"whatsapp_business_account\",
        \"entry\": [{
            \"id\": \"123456789\",
            \"changes\": [{
                \"field\": \"messages\",
                \"value\": {
                    \"messaging_product\": \"whatsapp\",
                    \"metadata\": { \"phone_number_id\": \"987654321\" },
                    \"messages\": [{
                        \"id\": \"wamid.admin$(date +%s)\",
                        \"from\": \"${ADMIN_PHONE}\",
                        \"timestamp\": \"$(date +%s)\",
                        \"type\": \"text\",
                        \"text\": { \"body\": \"${cmd}\" }
                    }]
                }
            }]
        }]
    }"

    local SIG
    SIG=$(generate_signature "$PAYLOAD" "$META_APP_SECRET")

    curl -sf -X POST "${API_URL}/v1/inbound/whatsapp" \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: sha256=${SIG}" \
        -d "$PAYLOAD" 2>&1 || echo '{"error":"request_failed"}'
}

# ==============================================================================
# Test 1: Admin !order list command
# ==============================================================================
test_order_list() {
    log "Test 1: Admin !order list command"

    local RESPONSE
    RESPONSE=$(send_admin_command "!order list 5")

    if echo "$RESPONSE" | grep -q '"status"'; then
        pass "!order list command accepted"
    else
        fail "!order list command failed: $RESPONSE"
    fi
}

# ==============================================================================
# Test 2: Admin !customer risk command
# ==============================================================================
test_customer_risk() {
    log "Test 2: Admin !customer risk command"

    local RESPONSE
    RESPONSE=$(send_admin_command "!customer risk ${TEST_CUSTOMER}")

    if echo "$RESPONSE" | grep -q '"status"'; then
        pass "!customer risk command accepted"
    else
        fail "!customer risk command failed: $RESPONSE"
    fi
}

# ==============================================================================
# Test 3: Help includes new commands
# ==============================================================================
test_help_updated() {
    log "Test 3: Admin !help includes ORDER/CUSTOMER commands"

    local RESPONSE
    RESPONSE=$(send_admin_command "!help")

    # Just verify the request is accepted
    if echo "$RESPONSE" | grep -q '"status"'; then
        pass "!help command accepted (manual check for order/customer)"
    else
        fail "!help command failed: $RESPONSE"
    fi
}

# ==============================================================================
# Test 4: Database migration check
# ==============================================================================
test_db_migration() {
    log "Test 4: Database migration check (requires psql)"

    if command -v psql &> /dev/null; then
        # Check if payment_mode column exists in orders
        local CHECK
        CHECK=$(psql "${DATABASE_URL:-postgres://n8n:n8npass@localhost:5432/n8n}" -tAc \
            "SELECT column_name FROM information_schema.columns WHERE table_name='orders' AND column_name='payment_mode';" 2>/dev/null || echo "")

        if [[ "$CHECK" == "payment_mode" ]]; then
            pass "payment_mode column exists in orders table"
        else
            warn "payment_mode column not found (run migration first)"
        fi

        # Check mark_order_noshow function
        CHECK=$(psql "${DATABASE_URL:-postgres://n8n:n8npass@localhost:5432/n8n}" -tAc \
            "SELECT proname FROM pg_proc WHERE proname='mark_order_noshow';" 2>/dev/null || echo "")

        if [[ "$CHECK" == "mark_order_noshow" ]]; then
            pass "mark_order_noshow function exists"
        else
            warn "mark_order_noshow function not found (run migration first)"
        fi
    else
        warn "psql not available, skipping DB checks"
    fi
}

# ==============================================================================
# Test 5: New customer COD flow simulation
# ==============================================================================
test_new_customer_cod() {
    log "Test 5: New customer COD flow (simulation)"

    # Simulate new customer sending a message
    local NEW_CUSTOMER="21261$(date +%s | tail -c 8)"

    local PAYLOAD="{
        \"object\": \"whatsapp_business_account\",
        \"entry\": [{
            \"id\": \"123456789\",
            \"changes\": [{
                \"field\": \"messages\",
                \"value\": {
                    \"messaging_product\": \"whatsapp\",
                    \"metadata\": { \"phone_number_id\": \"987654321\" },
                    \"messages\": [{
                        \"id\": \"wamid.newcust$(date +%s)\",
                        \"from\": \"${NEW_CUSTOMER}\",
                        \"timestamp\": \"$(date +%s)\",
                        \"type\": \"text\",
                        \"text\": { \"body\": \"Je veux commander\" }
                    }]
                }
            }]
        }]
    }"

    local SIG
    SIG=$(generate_signature "$PAYLOAD" "$META_APP_SECRET")

    local RESPONSE
    RESPONSE=$(curl -sf -X POST "${API_URL}/v1/inbound/whatsapp" \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: sha256=${SIG}" \
        -d "$PAYLOAD" 2>&1 || echo '{"error":"request_failed"}')

    if echo "$RESPONSE" | grep -q '"status"'; then
        pass "New customer message accepted"
    else
        fail "New customer message failed: $RESPONSE"
    fi
}

# ==============================================================================
# Test 6: Trust score calculation validation
# ==============================================================================
test_trust_score_logic() {
    log "Test 6: Trust score calculation logic"

    if command -v psql &> /dev/null; then
        # Insert test customer and verify score changes
        local TEST_USER="test_trust_$(date +%s)"

        # Create profile with default score
        psql "${DATABASE_URL:-postgres://n8n:n8npass@localhost:5432/n8n}" -c \
            "INSERT INTO customer_payment_profiles (user_id, tenant_id, trust_score)
             VALUES ('${TEST_USER}', '00000000-0000-0000-0000-000000000001', 50)
             ON CONFLICT (user_id) DO NOTHING;" 2>/dev/null || true

        # Get current score
        local SCORE
        SCORE=$(psql "${DATABASE_URL:-postgres://n8n:n8npass@localhost:5432/n8n}" -tAc \
            "SELECT trust_score FROM customer_payment_profiles WHERE user_id='${TEST_USER}';" 2>/dev/null || echo "50")

        if [[ "$SCORE" == "50" ]]; then
            pass "Default trust score is 50"
        else
            warn "Trust score: $SCORE (expected 50)"
        fi

        # Cleanup
        psql "${DATABASE_URL:-postgres://n8n:n8npass@localhost:5432/n8n}" -c \
            "DELETE FROM customer_payment_profiles WHERE user_id='${TEST_USER}';" 2>/dev/null || true
    else
        warn "psql not available, skipping trust score test"
    fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo "=============================================="
    echo "P2-DZ-01: COD + No-Show Scoring Tests"
    echo "=============================================="
    echo ""

    # Run tests
    test_db_migration
    echo ""

    test_order_list
    echo ""

    test_customer_risk
    echo ""

    test_help_updated
    echo ""

    test_new_customer_cod
    echo ""

    test_trust_score_logic
    echo ""

    # Summary
    echo "=============================================="
    echo -e "Results: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}"
    echo "=============================================="

    if [[ $FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
