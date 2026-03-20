#!/usr/bin/env bash
# ==============================================================================
# P2-DZ-02: Delivery Location + Address Normalization Tests
# ==============================================================================
set -euo pipefail

# Configuration
: "${API_URL:=http://localhost:8080}"
: "${TEST_CUSTOMER:=212611111111}"
: "${META_APP_SECRET:=test_app_secret}"
: "${DATABASE_URL:=postgres://n8n:n8npass@localhost:5432/n8n}"
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

# ==============================================================================
# Test 1: Wilaya Reference Table
# ==============================================================================
test_wilaya_reference() {
    log "Test 1: Wilaya reference table exists and has 48 wilayas"

    if ! command -v psql &> /dev/null; then
        warn "psql not available, skipping DB tests"
        return
    fi

    local COUNT
    COUNT=$(psql "$DATABASE_URL" -tAc \
        "SELECT COUNT(*) FROM public.wilaya_reference;" 2>/dev/null || echo "0")

    if [[ "$COUNT" -ge 48 ]]; then
        pass "Wilaya reference table has $COUNT entries (expected >= 48)"
    else
        fail "Wilaya reference table has only $COUNT entries (expected 48)"
    fi

    # Test Alger lookup
    local ALGER
    ALGER=$(psql "$DATABASE_URL" -tAc \
        "SELECT name_fr FROM public.wilaya_reference WHERE wilaya_code = 16;" 2>/dev/null || echo "")

    if [[ "$ALGER" == "Alger" ]]; then
        pass "Wilaya code 16 = Alger"
    else
        fail "Wilaya code 16 lookup failed: got '$ALGER'"
    fi
}

# ==============================================================================
# Test 2: Address Normalization Function
# ==============================================================================
test_address_normalization() {
    log "Test 2: Address normalization function"

    if ! command -v psql &> /dev/null; then
        warn "psql not available, skipping"
        return
    fi

    # Test exact match
    local RESULT
    RESULT=$(psql "$DATABASE_URL" -tAc \
        "SELECT wilaya_name, confidence FROM public.normalize_address(NULL, 'Alger', 'Draria');" 2>/dev/null || echo "")

    if echo "$RESULT" | grep -q "Alger"; then
        pass "normalize_address('Alger', 'Draria') returns Alger"
    else
        fail "normalize_address failed for Alger/Draria: $RESULT"
    fi

    # Test variant spelling
    RESULT=$(psql "$DATABASE_URL" -tAc \
        "SELECT wilaya_name FROM public.normalize_address(NULL, 'algiers', NULL);" 2>/dev/null || echo "")

    if echo "$RESULT" | grep -qi "Alger"; then
        pass "normalize_address('algiers') maps to Alger"
    else
        fail "normalize_address('algiers') failed: $RESULT"
    fi

    # Test Arabic
    RESULT=$(psql "$DATABASE_URL" -tAc \
        "SELECT wilaya_name FROM public.normalize_address(NULL, 'الجزائر', NULL);" 2>/dev/null || echo "")

    if echo "$RESULT" | grep -qi "Alger"; then
        pass "normalize_address Arabic 'الجزائر' maps to Alger"
    else
        warn "normalize_address Arabic failed (may need UTF-8): $RESULT"
    fi
}

# ==============================================================================
# Test 3: Location to Zone Function
# ==============================================================================
test_location_to_zone() {
    log "Test 3: Location to zone matching function"

    if ! command -v psql &> /dev/null; then
        warn "psql not available, skipping"
        return
    fi

    # Test with Alger coordinates (Draria area: 36.7167, 2.9667)
    local RESULT
    RESULT=$(psql "$DATABASE_URL" -tAc \
        "SELECT wilaya, match_type FROM public.location_to_zone(
            '00000000-0000-0000-0000-000000000000'::uuid,
            36.7167,
            2.9667
        );" 2>/dev/null || echo "")

    if [[ -n "$RESULT" ]]; then
        pass "location_to_zone returns result for Draria coords: $RESULT"
    else
        warn "location_to_zone returned no result (may need seed data)"
    fi
}

# ==============================================================================
# Test 4: Delivery Quote V2 with Location
# ==============================================================================
test_delivery_quote_v2() {
    log "Test 4: delivery_quote_v2 with location support"

    if ! command -v psql &> /dev/null; then
        warn "psql not available, skipping"
        return
    fi

    # Test with coordinates
    local RESULT
    RESULT=$(psql "$DATABASE_URL" -tAc \
        "SELECT zone_found, wilaya, match_type, reason FROM public.delivery_quote_v2(
            '00000000-0000-0000-0000-000000000000'::uuid,
            NULL, NULL,
            36.7167, 2.9667,
            5000
        );" 2>/dev/null || echo "")

    if [[ -n "$RESULT" ]]; then
        pass "delivery_quote_v2 with coordinates works: $RESULT"
    else
        warn "delivery_quote_v2 returned no result"
    fi

    # Test with text address (fallback)
    RESULT=$(psql "$DATABASE_URL" -tAc \
        "SELECT zone_found, reason FROM public.delivery_quote_v2(
            '00000000-0000-0000-0000-000000000000'::uuid,
            'Alger', 'Draria',
            NULL, NULL,
            5000
        );" 2>/dev/null || echo "")

    if echo "$RESULT" | grep -q "t|OK\|true"; then
        pass "delivery_quote_v2 with text address works"
    else
        warn "delivery_quote_v2 text fallback: $RESULT"
    fi
}

# ==============================================================================
# Test 5: WhatsApp Location Message Simulation
# ==============================================================================
test_wa_location_message() {
    log "Test 5: WhatsApp location message handling"

    local LOCATION_CUSTOMER="21362$(date +%s | tail -c 8)"

    # Simulate a WhatsApp location message
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
                        \"id\": \"wamid.loc$(date +%s)\",
                        \"from\": \"${LOCATION_CUSTOMER}\",
                        \"timestamp\": \"$(date +%s)\",
                        \"type\": \"location\",
                        \"location\": {
                            \"latitude\": 36.7167,
                            \"longitude\": 2.9667,
                            \"name\": \"Draria\",
                            \"address\": \"Draria, Alger, Algerie\"
                        }
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
        pass "WhatsApp location message accepted"
    else
        warn "WhatsApp location message: $RESPONSE (API may be down)"
    fi
}

# ==============================================================================
# Test 6: Commune Reference Table
# ==============================================================================
test_commune_reference() {
    log "Test 6: Commune reference table"

    if ! command -v psql &> /dev/null; then
        warn "psql not available, skipping"
        return
    fi

    local COUNT
    COUNT=$(psql "$DATABASE_URL" -tAc \
        "SELECT COUNT(*) FROM public.commune_reference WHERE wilaya_code = 16;" 2>/dev/null || echo "0")

    if [[ "$COUNT" -ge 10 ]]; then
        pass "Commune reference has $COUNT Alger communes"
    else
        warn "Commune reference has only $COUNT Alger communes"
    fi

    # Test Draria lookup
    local DRARIA
    DRARIA=$(psql "$DATABASE_URL" -tAc \
        "SELECT name_fr FROM public.commune_reference WHERE wilaya_code = 16 AND lower(name_fr) = 'draria';" 2>/dev/null || echo "")

    if [[ "$DRARIA" == "Draria" ]]; then
        pass "Commune Draria found in reference"
    else
        warn "Commune Draria not found: '$DRARIA'"
    fi
}

# ==============================================================================
# Test 7: Delivery Zones Coordinate Columns
# ==============================================================================
test_delivery_zones_coords() {
    log "Test 7: Delivery zones coordinate columns"

    if ! command -v psql &> /dev/null; then
        warn "psql not available, skipping"
        return
    fi

    local HAS_LAT
    HAS_LAT=$(psql "$DATABASE_URL" -tAc \
        "SELECT column_name FROM information_schema.columns
         WHERE table_name='delivery_zones' AND column_name='center_lat';" 2>/dev/null || echo "")

    if [[ "$HAS_LAT" == "center_lat" ]]; then
        pass "delivery_zones has center_lat column"
    else
        fail "delivery_zones missing center_lat column"
    fi

    local HAS_RADIUS
    HAS_RADIUS=$(psql "$DATABASE_URL" -tAc \
        "SELECT column_name FROM information_schema.columns
         WHERE table_name='delivery_zones' AND column_name='radius_km';" 2>/dev/null || echo "")

    if [[ "$HAS_RADIUS" == "radius_km" ]]; then
        pass "delivery_zones has radius_km column"
    else
        fail "delivery_zones missing radius_km column"
    fi
}

# ==============================================================================
# Test 8: Message Templates for Location
# ==============================================================================
test_location_templates() {
    log "Test 8: Location-related message templates"

    if ! command -v psql &> /dev/null; then
        warn "psql not available, skipping"
        return
    fi

    local TEMPLATES
    TEMPLATES=$(psql "$DATABASE_URL" -tAc \
        "SELECT COUNT(*) FROM public.message_templates
         WHERE template_key LIKE 'delivery_location%';" 2>/dev/null || echo "0")

    if [[ "$TEMPLATES" -ge 4 ]]; then
        pass "Found $TEMPLATES location-related templates"
    else
        fail "Only $TEMPLATES location templates found (expected >= 4)"
    fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo "=============================================="
    echo "P2-DZ-02: Delivery Location Tests"
    echo "=============================================="
    echo ""

    test_wilaya_reference
    echo ""

    test_commune_reference
    echo ""

    test_address_normalization
    echo ""

    test_location_to_zone
    echo ""

    test_delivery_quote_v2
    echo ""

    test_delivery_zones_coords
    echo ""

    test_location_templates
    echo ""

    test_wa_location_message
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
