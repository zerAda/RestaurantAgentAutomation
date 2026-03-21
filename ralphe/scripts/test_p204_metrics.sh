#!/usr/bin/env bash
# =============================================================================
# P2-04: Test Script for Minimal Metrics + Stats
# =============================================================================
# Tests:
# 1. daily_metrics table exists
# 2. latency_samples table exists
# 3. increment_metric function exists
# 4. record_latency function exists
# 5. get_daily_stats function exists
# 6. get_stats_range function exists
# 7. cleanup_old_metrics function exists
# 8. W14 has STATS command handler
# 9. W14 JSON is valid
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
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

echo "=========================================="
echo "P2-04: Minimal Metrics + Stats Tests"
echo "=========================================="
echo ""

MIGRATION_FILE="$PROJECT_DIR/db/migrations/2026-01-30_p2_04_metrics.sql"

# -----------------------------------------------------------------------------
# Test 1: Check daily_metrics table in migration
# -----------------------------------------------------------------------------
log_test "1. Checking daily_metrics table in migration..."
if grep -q "daily_metrics" "$MIGRATION_FILE"; then
    log_pass "daily_metrics table defined in migration"
else
    log_fail "daily_metrics table missing from migration"
fi

# -----------------------------------------------------------------------------
# Test 2: Check latency_samples table in migration
# -----------------------------------------------------------------------------
log_test "2. Checking latency_samples table in migration..."
if grep -q "latency_samples" "$MIGRATION_FILE"; then
    log_pass "latency_samples table defined in migration"
else
    log_fail "latency_samples table missing from migration"
fi

# -----------------------------------------------------------------------------
# Test 3: Check increment_metric function in migration
# -----------------------------------------------------------------------------
log_test "3. Checking increment_metric function..."
if grep -q "increment_metric" "$MIGRATION_FILE"; then
    log_pass "increment_metric function defined"
else
    log_fail "increment_metric function missing"
fi

# -----------------------------------------------------------------------------
# Test 4: Check record_latency function in migration
# -----------------------------------------------------------------------------
log_test "4. Checking record_latency function..."
if grep -q "record_latency" "$MIGRATION_FILE"; then
    log_pass "record_latency function defined"
else
    log_fail "record_latency function missing"
fi

# -----------------------------------------------------------------------------
# Test 5: Check get_daily_stats function in migration
# -----------------------------------------------------------------------------
log_test "5. Checking get_daily_stats function..."
if grep -q "get_daily_stats" "$MIGRATION_FILE"; then
    log_pass "get_daily_stats function defined"
else
    log_fail "get_daily_stats function missing"
fi

# -----------------------------------------------------------------------------
# Test 6: Check get_stats_range function in migration
# -----------------------------------------------------------------------------
log_test "6. Checking get_stats_range function..."
if grep -q "get_stats_range" "$MIGRATION_FILE"; then
    log_pass "get_stats_range function defined"
else
    log_fail "get_stats_range function missing"
fi

# -----------------------------------------------------------------------------
# Test 7: Check cleanup_old_metrics function in migration
# -----------------------------------------------------------------------------
log_test "7. Checking cleanup_old_metrics function..."
if grep -q "cleanup_old_metrics" "$MIGRATION_FILE"; then
    log_pass "cleanup_old_metrics function defined"
else
    log_fail "cleanup_old_metrics function missing"
fi

# -----------------------------------------------------------------------------
# Test 8: Check STATS command handler in W14
# -----------------------------------------------------------------------------
log_test "8. Checking STATS command handler in W14..."
if grep -q "D8 - Is STATS?" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json"; then
    log_pass "STATS handler found in W14"
else
    log_fail "STATS handler missing from W14"
fi

# -----------------------------------------------------------------------------
# Test 9: Check A5 Parse Intent handles STATS
# -----------------------------------------------------------------------------
log_test "9. Checking A5 Parse Intent handles STATS..."
if grep -q "'stats'" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json"; then
    log_pass "A5 Parse Intent handles stats command"
else
    log_fail "A5 Parse Intent does not handle stats command"
fi

# -----------------------------------------------------------------------------
# Test 10: Validate W14.json syntax
# -----------------------------------------------------------------------------
log_test "10. Validating W14_ADMIN_WA_SUPPORT_CONSOLE.json syntax..."
W14_FILE="$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json"
if node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$W14_FILE" 2>/dev/null; then
    log_pass "W14 JSON is valid"
else
    log_fail "W14 JSON has invalid syntax"
fi

# -----------------------------------------------------------------------------
# Test 11: Check metric_key column in daily_metrics
# -----------------------------------------------------------------------------
log_test "11. Checking metric_key column in daily_metrics..."
if grep -q "metric_key text" "$MIGRATION_FILE"; then
    log_pass "metric_key column defined"
else
    log_fail "metric_key column missing"
fi

# -----------------------------------------------------------------------------
# Test 12: Check PERCENTILE_CONT in get_daily_stats
# -----------------------------------------------------------------------------
log_test "12. Checking percentile calculations in get_daily_stats..."
if grep -q "PERCENTILE_CONT" "$MIGRATION_FILE"; then
    log_pass "Percentile calculations present"
else
    log_fail "Percentile calculations missing"
fi

# -----------------------------------------------------------------------------
# Test 13: Check D8 chain nodes exist
# -----------------------------------------------------------------------------
log_test "13. Checking D8 chain nodes..."
D8_NODES=0
grep -q "D8 - Is STATS?" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && D8_NODES=$((D8_NODES+1))
grep -q "D8a - Get Stats" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && D8_NODES=$((D8_NODES+1))
grep -q "D8b - Format Stats" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && D8_NODES=$((D8_NODES+1))
if [ "$D8_NODES" -eq 3 ]; then
    log_pass "All 3 D8 nodes found in W14"
else
    log_fail "D8 nodes missing from W14 (found $D8_NODES/3)"
fi

# -----------------------------------------------------------------------------
# Test 14: Check inbound/outbound/errors metrics in get_daily_stats
# -----------------------------------------------------------------------------
log_test "14. Checking metrics categories in get_daily_stats..."
METRIC_CATS=0
grep -q "'inbound'" "$MIGRATION_FILE" && METRIC_CATS=$((METRIC_CATS+1))
grep -q "'outbound'" "$MIGRATION_FILE" && METRIC_CATS=$((METRIC_CATS+1))
grep -q "'errors'" "$MIGRATION_FILE" && METRIC_CATS=$((METRIC_CATS+1))
if [ "$METRIC_CATS" -eq 3 ]; then
    log_pass "All metric categories defined (inbound, outbound, errors)"
else
    log_fail "Metric categories missing (found $METRIC_CATS/3)"
fi

# -----------------------------------------------------------------------------
# Test 15: Check retention cleanup (7 days latency, 30 days metrics)
# -----------------------------------------------------------------------------
log_test "15. Checking retention cleanup logic..."
if grep -q "p_retention_days" "$MIGRATION_FILE" && grep -q "30" "$MIGRATION_FILE"; then
    log_pass "Retention cleanup logic present"
else
    log_fail "Retention cleanup logic missing"
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
    echo -e "${GREEN}All P2-04 Metrics tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the changes.${NC}"
    exit 1
fi
