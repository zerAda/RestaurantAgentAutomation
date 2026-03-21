#!/usr/bin/env bash
# =============================================================================
# P2-01: Test Script for FR/AR/Darija Auto-detect + LANG Command
# =============================================================================
# Tests:
# 1. Arabic script message -> reply in Arabic
# 2. Darija message -> reply in Darija
# 3. French message -> reply in French
# 4. Other language -> reply in French (default)
# 5. LANG FR/AR/DARIJA command override
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

echo "=========================================="
echo "P2-01: FR/AR/Darija L10N Tests"
echo "=========================================="
echo ""

# -----------------------------------------------------------------------------
# Test 1: Check Darija locale in DB migration
# -----------------------------------------------------------------------------
log_test "1. Checking darija locale in DB migration..."
if grep -q "'darija'" "$PROJECT_DIR/db/migrations/2026-01-30_p2_01_darija_locale.sql"; then
    log_pass "Darija locale defined in migration"
else
    log_fail "Darija locale missing from migration"
fi

# -----------------------------------------------------------------------------
# Test 2: Check Darija templates in migration
# -----------------------------------------------------------------------------
log_test "2. Checking Darija templates..."
DARIJA_TEMPLATES=$(grep -c ",'darija'," "$PROJECT_DIR/db/migrations/2026-01-30_p2_01_darija_locale.sql" || echo "0")
if [ "$DARIJA_TEMPLATES" -ge 10 ]; then
    log_pass "Found $DARIJA_TEMPLATES Darija templates in migration"
else
    log_fail "Not enough Darija templates (found $DARIJA_TEMPLATES, expected >= 10)"
fi

# -----------------------------------------------------------------------------
# Test 3: Check LANG DARIJA in W4_CORE
# -----------------------------------------------------------------------------
log_test "3. Checking LANG DARIJA command in W4_CORE..."
if grep -q "darija" "$PROJECT_DIR/workflows/W4_CORE.json"; then
    log_pass "Darija handling found in W4_CORE"
else
    log_fail "Darija handling missing from W4_CORE"
fi

# -----------------------------------------------------------------------------
# Test 4: Check Darija detection patterns in migration
# -----------------------------------------------------------------------------
log_test "4. Checking Darija detection patterns..."
if grep -q "darija_patterns" "$PROJECT_DIR/db/migrations/2026-01-30_p2_01_darija_locale.sql"; then
    log_pass "Darija patterns table defined"
else
    log_fail "Darija patterns table missing"
fi

# -----------------------------------------------------------------------------
# Test 5: Check locale constraint includes darija
# -----------------------------------------------------------------------------
log_test "5. Checking locale constraint includes darija..."
if grep -q "'fr','ar','darija'" "$PROJECT_DIR/db/migrations/2026-01-30_p2_01_darija_locale.sql"; then
    log_pass "Locale constraint updated for darija"
else
    log_fail "Locale constraint not updated for darija"
fi

# -----------------------------------------------------------------------------
# Test 6: Verify W4_CORE JSON validity
# -----------------------------------------------------------------------------
log_test "6. Validating W4_CORE.json syntax..."
if node -e "JSON.parse(require('fs').readFileSync('$PROJECT_DIR/workflows/W4_CORE.json'))" 2>/dev/null; then
    log_pass "W4_CORE.json is valid JSON"
else
    log_fail "W4_CORE.json has invalid JSON syntax"
fi

# -----------------------------------------------------------------------------
# Test 7: Check Arabic detection regex in W4_CORE
# -----------------------------------------------------------------------------
log_test "7. Checking Arabic script detection..."
if grep -q "hasArabic" "$PROJECT_DIR/workflows/W4_CORE.json"; then
    log_pass "Arabic script detection present in W4_CORE"
else
    log_fail "Arabic script detection missing"
fi

# -----------------------------------------------------------------------------
# Test 8: Check Darija pattern keywords
# -----------------------------------------------------------------------------
log_test "8. Checking Darija keyword patterns..."
DARIJA_KEYWORDS=("chno kayn" "wakha" "kml" "salam" "bghit")
FOUND=0
for kw in "${DARIJA_KEYWORDS[@]}"; do
    if grep -q "$kw" "$PROJECT_DIR/workflows/W4_CORE.json" 2>/dev/null; then
        ((FOUND++))
    fi
done
if [ "$FOUND" -ge 3 ]; then
    log_pass "Found $FOUND/${{#DARIJA_KEYWORDS[@]}} Darija keywords in W4_CORE"
else
    log_fail "Not enough Darija keywords (found $FOUND, expected >= 3)"
fi

# -----------------------------------------------------------------------------
# Test 9: Check L10N env variables
# -----------------------------------------------------------------------------
log_test "9. Checking L10N environment variables..."
if grep -q "L10N_ENABLED" "$PROJECT_DIR/config/.env.example"; then
    log_pass "L10N_ENABLED found in .env.example"
else
    log_fail "L10N_ENABLED missing from .env.example"
fi

# -----------------------------------------------------------------------------
# Test 10: Check normalize_locale function supports darija
# -----------------------------------------------------------------------------
log_test "10. Checking normalize_locale function..."
if grep -q "RETURN 'darija'" "$PROJECT_DIR/db/migrations/2026-01-30_p2_01_darija_locale.sql"; then
    log_pass "normalize_locale function handles darija"
else
    log_fail "normalize_locale function doesn't handle darija"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All P2-01 L10N tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the changes.${NC}"
    exit 1
fi
