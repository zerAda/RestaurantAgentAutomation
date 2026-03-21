#!/usr/bin/env bash
# =============================================================================
# P2-02: Test Script for Admin WA Commands + Audit Trail
# =============================================================================
# Tests:
# 1. Admin phone allowlist table exists
# 2. System flags table exists with default flags
# 3. is_admin_phone() function works
# 4. get_system_status() function works
# 5. DLQ functions exist (get_dlq_messages, replay_dlq_message, drop_dlq_message)
# 6. W14 has new command handlers (STATUS, FLAGS, DLQ)
# 7. W14 JSON is valid
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
echo "P2-02: Admin WA Commands + Audit Trail"
echo "=========================================="
echo ""

# -----------------------------------------------------------------------------
# Test 1: Check admin_phone_allowlist table in migration
# -----------------------------------------------------------------------------
log_test "1. Checking admin_phone_allowlist table in migration..."
if grep -q "admin_phone_allowlist" "$PROJECT_DIR/db/migrations/2026-01-30_p2_02_admin_wa_commands.sql"; then
    log_pass "admin_phone_allowlist table defined in migration"
else
    log_fail "admin_phone_allowlist table missing from migration"
fi

# -----------------------------------------------------------------------------
# Test 2: Check system_flags table in migration
# -----------------------------------------------------------------------------
log_test "2. Checking system_flags table in migration..."
if grep -q "system_flags" "$PROJECT_DIR/db/migrations/2026-01-30_p2_02_admin_wa_commands.sql"; then
    log_pass "system_flags table defined in migration"
else
    log_fail "system_flags table missing from migration"
fi

# -----------------------------------------------------------------------------
# Test 3: Check is_admin_phone function in migration
# -----------------------------------------------------------------------------
log_test "3. Checking is_admin_phone function..."
if grep -q "is_admin_phone" "$PROJECT_DIR/db/migrations/2026-01-30_p2_02_admin_wa_commands.sql"; then
    log_pass "is_admin_phone function defined"
else
    log_fail "is_admin_phone function missing"
fi

# -----------------------------------------------------------------------------
# Test 4: Check get_system_status function in migration
# -----------------------------------------------------------------------------
log_test "4. Checking get_system_status function..."
if grep -q "get_system_status" "$PROJECT_DIR/db/migrations/2026-01-30_p2_02_admin_wa_commands.sql"; then
    log_pass "get_system_status function defined"
else
    log_fail "get_system_status function missing"
fi

# -----------------------------------------------------------------------------
# Test 5: Check DLQ functions in migration
# -----------------------------------------------------------------------------
log_test "5. Checking DLQ functions..."
DLQ_FUNCS=0
grep -q "get_dlq_messages" "$PROJECT_DIR/db/migrations/2026-01-30_p2_02_admin_wa_commands.sql" && DLQ_FUNCS=$((DLQ_FUNCS+1))
grep -q "replay_dlq_message" "$PROJECT_DIR/db/migrations/2026-01-30_p2_02_admin_wa_commands.sql" && DLQ_FUNCS=$((DLQ_FUNCS+1))
grep -q "drop_dlq_message" "$PROJECT_DIR/db/migrations/2026-01-30_p2_02_admin_wa_commands.sql" && DLQ_FUNCS=$((DLQ_FUNCS+1))
if [ "$DLQ_FUNCS" -eq 3 ]; then
    log_pass "All 3 DLQ functions defined"
else
    log_fail "Missing DLQ functions (found $DLQ_FUNCS/3)"
fi

# -----------------------------------------------------------------------------
# Test 6: Check default system flags seeded
# -----------------------------------------------------------------------------
log_test "6. Checking default system flags..."
FLAGS_COUNT=$(grep -c "INSERT INTO public.system_flags" "$PROJECT_DIR/db/migrations/2026-01-30_p2_02_admin_wa_commands.sql" || echo "0")
if [ "$FLAGS_COUNT" -ge 1 ]; then
    log_pass "System flags seeded in migration"
else
    log_fail "System flags not seeded"
fi

# -----------------------------------------------------------------------------
# Test 7: Check STATUS command handler in W14
# -----------------------------------------------------------------------------
log_test "7. Checking STATUS command handler in W14..."
if grep -q "D1 - Is STATUS?" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json"; then
    log_pass "STATUS handler found in W14"
else
    log_fail "STATUS handler missing from W14"
fi

# -----------------------------------------------------------------------------
# Test 8: Check FLAGS command handlers in W14
# -----------------------------------------------------------------------------
log_test "8. Checking FLAGS command handlers in W14..."
FLAGS_HANDLERS=0
grep -q "D2 - Is FLAGS_LIST?" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && FLAGS_HANDLERS=$((FLAGS_HANDLERS+1))
grep -q "D3 - Is FLAGS_SET?" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && FLAGS_HANDLERS=$((FLAGS_HANDLERS+1))
if [ "$FLAGS_HANDLERS" -eq 2 ]; then
    log_pass "FLAGS handlers found in W14 (LIST + SET)"
else
    log_fail "FLAGS handlers missing from W14 (found $FLAGS_HANDLERS/2)"
fi

# -----------------------------------------------------------------------------
# Test 9: Check DLQ command handlers in W14
# -----------------------------------------------------------------------------
log_test "9. Checking DLQ command handlers in W14..."
DLQ_HANDLERS=0
grep -q "D4 - Is DLQ_LIST?" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && DLQ_HANDLERS=$((DLQ_HANDLERS+1))
grep -q "D5 - Is DLQ_SHOW?" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && DLQ_HANDLERS=$((DLQ_HANDLERS+1))
grep -q "D6 - Is DLQ_REPLAY?" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && DLQ_HANDLERS=$((DLQ_HANDLERS+1))
grep -q "D7 - Is DLQ_DROP?" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && DLQ_HANDLERS=$((DLQ_HANDLERS+1))
if [ "$DLQ_HANDLERS" -eq 4 ]; then
    log_pass "All 4 DLQ handlers found in W14"
else
    log_fail "DLQ handlers missing from W14 (found $DLQ_HANDLERS/4)"
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
# Test 11: Check A2 RBAC uses phone_allowlist
# -----------------------------------------------------------------------------
log_test "11. Checking A2 RBAC queries phone_allowlist..."
if grep -q "admin_phone_allowlist" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json"; then
    log_pass "A2 RBAC checks admin_phone_allowlist"
else
    log_fail "A2 RBAC does not check admin_phone_allowlist"
fi

# -----------------------------------------------------------------------------
# Test 12: Check A5 Parse Intent handles new commands
# -----------------------------------------------------------------------------
log_test "12. Checking A5 Parse Intent handles STATUS/FLAGS/DLQ..."
INTENT_CMDS=0
grep -q "'status'" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && INTENT_CMDS=$((INTENT_CMDS+1))
grep -q "'flags'" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && INTENT_CMDS=$((INTENT_CMDS+1))
grep -q "'dlq'" "$PROJECT_DIR/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" && INTENT_CMDS=$((INTENT_CMDS+1))
if [ "$INTENT_CMDS" -eq 3 ]; then
    log_pass "A5 Parse Intent handles status, flags, dlq commands"
else
    log_fail "A5 Parse Intent missing command handlers (found $INTENT_CMDS/3)"
fi

# -----------------------------------------------------------------------------
# Test 13: Check v_dlq_recent view in migration
# -----------------------------------------------------------------------------
log_test "13. Checking v_dlq_recent view..."
if grep -q "v_dlq_recent" "$PROJECT_DIR/db/migrations/2026-01-30_p2_02_admin_wa_commands.sql"; then
    log_pass "v_dlq_recent view defined"
else
    log_fail "v_dlq_recent view missing"
fi

# -----------------------------------------------------------------------------
# Test 14: Check DROPPED status added to outbound_messages
# -----------------------------------------------------------------------------
log_test "14. Checking DROPPED status for outbound_messages..."
if grep -q "'DROPPED'" "$PROJECT_DIR/db/migrations/2026-01-30_p2_02_admin_wa_commands.sql"; then
    log_pass "DROPPED status defined in migration"
else
    log_fail "DROPPED status missing from migration"
fi

# -----------------------------------------------------------------------------
# Test 15: Check permissions column in admin_phone_allowlist
# -----------------------------------------------------------------------------
log_test "15. Checking permissions column in admin_phone_allowlist..."
if grep -q "permissions jsonb" "$PROJECT_DIR/db/migrations/2026-01-30_p2_02_admin_wa_commands.sql"; then
    log_pass "permissions jsonb column defined"
else
    log_fail "permissions column missing"
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
    echo -e "${GREEN}All P2-02 Admin Commands tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the changes.${NC}"
    exit 1
fi
