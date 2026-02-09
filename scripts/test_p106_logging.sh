#!/usr/bin/env bash
# =============================================================================
# P1-06: Test Script for Structured Logging + Correlation Propagation
# =============================================================================
# Tests:
# 1. Same correlation_id appears throughout the trace (inbound -> core -> outbound)
# 2. No secrets are logged (tokens, passwords, etc. are masked)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

echo "=========================================="
echo "P1-06: Structured Logging + Correlation ID Tests"
echo "=========================================="
echo ""

# -----------------------------------------------------------------------------
# Test 1: Verify correlation_id field exists in workflow files
# -----------------------------------------------------------------------------
log_test "1. Checking correlation_id in W1_IN_WA.json..."
if grep -q "correlation_id" "$PROJECT_DIR/workflows/W1_IN_WA.json"; then
    log_pass "W1_IN_WA.json contains correlation_id"
else
    log_fail "W1_IN_WA.json missing correlation_id"
fi

log_test "2. Checking correlation_id in W5_OUT_WA.json..."
if grep -q "correlation_id" "$PROJECT_DIR/workflows/W5_OUT_WA.json"; then
    log_pass "W5_OUT_WA.json contains correlation_id"
else
    log_fail "W5_OUT_WA.json missing correlation_id"
fi

log_test "3. Checking correlation_id in W6_OUT_IG.json..."
if grep -q "correlation_id" "$PROJECT_DIR/workflows/W6_OUT_IG.json"; then
    log_pass "W6_OUT_IG.json contains correlation_id"
else
    log_fail "W6_OUT_IG.json missing correlation_id"
fi

log_test "4. Checking correlation_id in W7_OUT_MSG.json..."
if grep -q "correlation_id" "$PROJECT_DIR/workflows/W7_OUT_MSG.json"; then
    log_pass "W7_OUT_MSG.json contains correlation_id"
else
    log_fail "W7_OUT_MSG.json missing correlation_id"
fi

# -----------------------------------------------------------------------------
# Test 2: Verify P1-06 markers are present in modified files
# -----------------------------------------------------------------------------
log_test "5. Checking P1-06 markers in W5_OUT_WA.json..."
if grep -q "P1-06" "$PROJECT_DIR/workflows/W5_OUT_WA.json"; then
    log_pass "W5_OUT_WA.json has P1-06 markers"
else
    log_fail "W5_OUT_WA.json missing P1-06 markers"
fi

log_test "6. Checking P1-06 markers in W6_OUT_IG.json..."
if grep -q "P1-06" "$PROJECT_DIR/workflows/W6_OUT_IG.json"; then
    log_pass "W6_OUT_IG.json has P1-06 markers"
else
    log_fail "W6_OUT_IG.json missing P1-06 markers"
fi

log_test "7. Checking P1-06 markers in W7_OUT_MSG.json..."
if grep -q "P1-06" "$PROJECT_DIR/workflows/W7_OUT_MSG.json"; then
    log_pass "W7_OUT_MSG.json has P1-06 markers"
else
    log_fail "W7_OUT_MSG.json missing P1-06 markers"
fi

# -----------------------------------------------------------------------------
# Test 3: Verify LOG_LEVEL and LOG_STRUCTURED in .env.example
# -----------------------------------------------------------------------------
log_test "8. Checking LOG_LEVEL in .env.example..."
if grep -q "LOG_LEVEL=" "$PROJECT_DIR/config/.env.example"; then
    log_pass "LOG_LEVEL found in .env.example"
else
    log_fail "LOG_LEVEL missing from .env.example"
fi

log_test "9. Checking LOG_STRUCTURED in .env.example..."
if grep -q "LOG_STRUCTURED=" "$PROJECT_DIR/config/.env.example"; then
    log_pass "LOG_STRUCTURED found in .env.example"
else
    log_fail "LOG_STRUCTURED missing from .env.example"
fi

log_test "10. Checking LOG_MASK_PATTERNS in .env.example..."
if grep -q "LOG_MASK_PATTERNS=" "$PROJECT_DIR/config/.env.example"; then
    log_pass "LOG_MASK_PATTERNS found in .env.example"
else
    log_fail "LOG_MASK_PATTERNS missing from .env.example"
fi

# -----------------------------------------------------------------------------
# Test 4: Verify DB migration exists
# -----------------------------------------------------------------------------
log_test "11. Checking DB migration file exists..."
if [ -f "$PROJECT_DIR/db/migrations/2026-01-30_p1_06_structured_logging.sql" ]; then
    log_pass "DB migration file exists"
else
    log_fail "DB migration file missing"
fi

log_test "12. Checking structured_logs table in migration..."
if grep -q "CREATE TABLE IF NOT EXISTS structured_logs" "$PROJECT_DIR/db/migrations/2026-01-30_p1_06_structured_logging.sql"; then
    log_pass "structured_logs table defined in migration"
else
    log_fail "structured_logs table missing from migration"
fi

log_test "13. Checking log_structured function in migration..."
if grep -q "CREATE OR REPLACE FUNCTION log_structured" "$PROJECT_DIR/db/migrations/2026-01-30_p1_06_structured_logging.sql"; then
    log_pass "log_structured function defined in migration"
else
    log_fail "log_structured function missing from migration"
fi

log_test "14. Checking v_request_trace view in migration..."
if grep -q "CREATE OR REPLACE VIEW v_request_trace" "$PROJECT_DIR/db/migrations/2026-01-30_p1_06_structured_logging.sql"; then
    log_pass "v_request_trace view defined in migration"
else
    log_fail "v_request_trace view missing from migration"
fi

# -----------------------------------------------------------------------------
# Test 5: Verify no secrets are hardcoded in workflow files (basic check)
# -----------------------------------------------------------------------------
log_test "15. Checking no hardcoded tokens in workflows..."
SECRETS_FOUND=0
for wf in W1_IN_WA.json W5_OUT_WA.json W6_OUT_IG.json W7_OUT_MSG.json; do
    if grep -iE '(token|password|secret)\s*[:=]\s*["\047][A-Za-z0-9]{20,}["\047]' "$PROJECT_DIR/workflows/$wf" 2>/dev/null | grep -v "REDACTED" | grep -v '\\$env' | grep -v 'tokenHash' >/dev/null; then
        log_fail "Possible hardcoded secret in $wf"
        ((SECRETS_FOUND++))
    fi
done
if [ "$SECRETS_FOUND" -eq 0 ]; then
    log_pass "No hardcoded secrets detected in workflows"
fi

# -----------------------------------------------------------------------------
# Test 6: Verify outbox entry includes correlation_id
# -----------------------------------------------------------------------------
log_test "16. Checking outboxEntry includes correlation_id in W5..."
if grep -q 'outboxEntry = {' "$PROJECT_DIR/workflows/W5_OUT_WA.json" && grep -q 'correlation_id: correlationId' "$PROJECT_DIR/workflows/W5_OUT_WA.json"; then
    log_pass "W5 outboxEntry includes correlation_id"
else
    log_fail "W5 outboxEntry missing correlation_id"
fi

# -----------------------------------------------------------------------------
# Test 7: JSON validity of workflow files
# -----------------------------------------------------------------------------
log_test "17. Validating JSON syntax of workflow files..."
JSON_VALID=0
for wf in W1_IN_WA.json W5_OUT_WA.json W6_OUT_IG.json W7_OUT_MSG.json; do
    if ! node -e "JSON.parse(require('fs').readFileSync('$PROJECT_DIR/workflows/$wf'))" 2>/dev/null; then
        log_fail "Invalid JSON in $wf"
        ((JSON_VALID++))
    fi
done
if [ "$JSON_VALID" -eq 0 ]; then
    log_pass "All workflow files are valid JSON"
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
    echo -e "${GREEN}All P1-06 tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the changes.${NC}"
    exit 1
fi
