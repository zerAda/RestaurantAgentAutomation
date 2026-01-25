#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# GO/NO-GO VALIDATION SCRIPT
# Vérifie tous les critères de production readiness
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
WARN=0
TOTAL=0

check() {
    local name="$1"
    local result="$2"  # 0=pass, 1=fail, 2=warn
    ((TOTAL++))
    
    case $result in
        0) echo -e "${GREEN}✅${NC} $name"; ((PASS++)) ;;
        1) echo -e "${RED}❌${NC} $name"; ((FAIL++)) ;;
        2) echo -e "${YELLOW}⚠️${NC} $name"; ((WARN++)) ;;
    esac
}

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  GO/NO-GO VALIDATION - Production Readiness        ║"
echo "║  Date: $(date +%Y-%m-%d)                                   ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# ==========================================================
# SECTION 1: SECURITY (V1-V3 from audit)
# ==========================================================
echo -e "${BLUE}═══ SECTION 1: SECURITY ═══${NC}"

# V1: Gateway patch applied
if grep -q "query_token_blocked\|block_query_token" "$PROJECT_ROOT/infra/gateway/nginx.conf" 2>/dev/null; then
    check "V1: Gateway query token protection ACTIVE" 0
else
    check "V1: Gateway query token protection NOT ACTIVE (nginx.conf not patched)" 1
fi

# V1: Rate limiting in nginx
if grep -q "limit_req_zone" "$PROJECT_ROOT/infra/gateway/nginx.conf" 2>/dev/null; then
    check "V1: Gateway rate limiting configured" 0
else
    check "V1: Gateway rate limiting NOT configured" 2
fi

# V2: Signature validation code exists
if [ -f "$PROJECT_ROOT/agents/wave1_critical/snippets/signature_validation_node.js" ]; then
    check "V2: Signature validation code EXISTS" 0
    check "V2: Signature validation APPLIED to workflows (manual check required)" 2
else
    check "V2: Signature validation code MISSING" 1
fi

# V2: Signature config in .env
if grep -q "SIGNATURE_VALIDATION_MODE" "$PROJECT_ROOT/config/.env.example" 2>/dev/null; then
    check "V2: SIGNATURE_VALIDATION_MODE configured" 0
else
    check "V2: SIGNATURE_VALIDATION_MODE not configured" 1
fi

# V3: Legacy token disabled
if grep -q "LEGACY_SHARED_TOKEN_ENABLED=false" "$PROJECT_ROOT/config/.env.example" 2>/dev/null; then
    check "V3: LEGACY_SHARED_TOKEN_ENABLED=false" 0
else
    check "V3: Legacy token not explicitly disabled" 1
fi

# V3: WEBHOOK_SHARED_TOKEN empty
if grep -q "^WEBHOOK_SHARED_TOKEN=$" "$PROJECT_ROOT/config/.env.example" 2>/dev/null || \
   grep -q 'WEBHOOK_SHARED_TOKEN=""' "$PROJECT_ROOT/config/.env.example" 2>/dev/null; then
    check "V3: WEBHOOK_SHARED_TOKEN is empty" 0
else
    check "V3: WEBHOOK_SHARED_TOKEN may still have a value (check manually)" 2
fi

echo ""

# ==========================================================
# SECTION 2: AUDIT & COMPLIANCE (V4)
# ==========================================================
echo -e "${BLUE}═══ SECTION 2: AUDIT & COMPLIANCE ═══${NC}"

# V4: Audit table migration exists
if ls "$PROJECT_ROOT/db/migrations/"*"admin_wa_audit"* 1>/dev/null 2>&1; then
    check "V4: admin_wa_audit_log migration EXISTS" 0
else
    check "V4: admin_wa_audit_log migration MISSING" 1
fi

# V4: Audit enabled flag
if grep -q "ADMIN_WA_AUDIT_ENABLED=true" "$PROJECT_ROOT/config/.env.example" 2>/dev/null; then
    check "V4: ADMIN_WA_AUDIT_ENABLED=true" 0
else
    check "V4: ADMIN_WA_AUDIT_ENABLED not set to true" 1
fi

# V4: W14 exists
if [ -f "$PROJECT_ROOT/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" ]; then
    check "V4: W14 Admin WA Console workflow EXISTS" 0
else
    check "V4: W14 Admin WA Console workflow MISSING" 1
fi

check "V4: Audit nodes CONNECTED in W14 (manual verification required)" 2

echo ""

# ==========================================================
# SECTION 3: LOCALIZATION (V5)
# ==========================================================
echo -e "${BLUE}═══ SECTION 3: LOCALIZATION ═══${NC}"

# V5: L10N enabled
if grep -q "L10N_ENABLED=true" "$PROJECT_ROOT/config/.env.example" 2>/dev/null; then
    check "V5: L10N_ENABLED=true" 0
else
    check "V5: L10N_ENABLED not set to true (CRITICAL for Algeria)" 1
fi

# V5: Sticky AR
if grep -q "L10N_STICKY_AR_ENABLED=true" "$PROJECT_ROOT/config/.env.example" 2>/dev/null; then
    check "V5: L10N_STICKY_AR_ENABLED=true" 0
else
    check "V5: L10N_STICKY_AR_ENABLED not set" 2
fi

# V5: Templates FR exist
if ls "$PROJECT_ROOT/templates/whatsapp/"*".fr.json" 1>/dev/null 2>&1; then
    check "V5: French templates exist" 0
else
    check "V5: French templates MISSING" 1
fi

# V5: Templates AR exist
if ls "$PROJECT_ROOT/templates/whatsapp/"*".ar.json" 1>/dev/null 2>&1; then
    check "V5: Arabic templates exist" 0
else
    check "V5: Arabic templates MISSING" 1
fi

echo ""

# ==========================================================
# SECTION 4: DATABASE
# ==========================================================
echo -e "${BLUE}═══ SECTION 4: DATABASE ═══${NC}"

# Migrations exist
MIGRATION_COUNT=$(ls "$PROJECT_ROOT/db/migrations/"*.sql 2>/dev/null | wc -l)
check "Migrations present: $MIGRATION_COUNT files" 0

# P0 migrations
if ls "$PROJECT_ROOT/db/migrations/"*"p0"* 1>/dev/null 2>&1; then
    check "P0 security migrations present" 0
else
    check "P0 security migrations not found" 2
fi

# Performance indexes
if ls "$PROJECT_ROOT/db/migrations/"*"perf"*"index"* 1>/dev/null 2>&1 || \
   ls "$PROJECT_ROOT/db/migrations/"*"indexes"* 1>/dev/null 2>&1; then
    check "Performance index migrations present" 0
else
    check "Performance index migrations not found" 2
fi

echo ""

# ==========================================================
# SECTION 5: INFRASTRUCTURE
# ==========================================================
echo -e "${BLUE}═══ SECTION 5: INFRASTRUCTURE ═══${NC}"

# Docker compose
if [ -f "$PROJECT_ROOT/docker/docker-compose.yml" ]; then
    check "docker-compose.yml exists" 0
else
    check "docker-compose.yml MISSING" 1
fi

# Production compose
if [ -f "$PROJECT_ROOT/docker-compose.hostinger.prod.yml" ]; then
    check "Production compose exists" 0
else
    check "Production compose MISSING" 1
fi

# Backup scripts
if [ -f "$PROJECT_ROOT/scripts/backup_postgres.sh" ]; then
    check "Backup script exists" 0
else
    check "Backup script MISSING" 1
fi

echo ""

# ==========================================================
# SECTION 6: TESTING
# ==========================================================
echo -e "${BLUE}═══ SECTION 6: TESTING ═══${NC}"

# Smoke tests
if [ -f "$PROJECT_ROOT/scripts/smoke.sh" ]; then
    check "Smoke test script exists" 0
else
    check "Smoke test script MISSING" 1
fi

# Security smoke tests
if [ -f "$PROJECT_ROOT/scripts/smoke_security.sh" ]; then
    check "Security smoke test script exists" 0
else
    check "Security smoke test script MISSING" 1
fi

# Test harness
if [ -f "$PROJECT_ROOT/scripts/test_harness.sh" ]; then
    check "Test harness exists" 0
else
    check "Test harness MISSING" 1
fi

# Integrity gate
if [ -f "$PROJECT_ROOT/scripts/integrity_gate.sh" ]; then
    check "Integrity gate exists" 0
else
    check "Integrity gate MISSING" 1
fi

echo ""

# ==========================================================
# SECTION 7: DOCUMENTATION
# ==========================================================
echo -e "${BLUE}═══ SECTION 7: DOCUMENTATION ═══${NC}"

# Key docs
DOCS=(
    "docs/ARCHITECTURE.md"
    "docs/BACKUP_RESTORE.md"
    "docs/RUNBOOKS.md"
    "docs/SLO.md"
    "docs/L10N.md"
    "docs/SUPPORT.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$PROJECT_ROOT/$doc" ]; then
        check "$doc exists" 0
    else
        check "$doc MISSING" 2
    fi
done

echo ""

# ==========================================================
# SUMMARY
# ==========================================================
echo "╔════════════════════════════════════════════════════╗"
echo "║  VALIDATION SUMMARY                                ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo -e "Total Checks:  $TOTAL"
echo -e "${GREEN}Passed:${NC}        $PASS"
echo -e "${RED}Failed:${NC}        $FAIL"
echo -e "${YELLOW}Warnings:${NC}      $WARN"
echo ""

# Calculate score
SCORE=$((PASS * 100 / TOTAL))

echo -e "Score: ${SCORE}%"
echo ""

# Decision
if [ $FAIL -eq 0 ]; then
    if [ $WARN -le 5 ]; then
        echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  VERDICT: GO                                       ║${NC}"
        echo -e "${GREEN}║  All critical checks passed                        ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
        EXIT_CODE=0
    else
        echo -e "${YELLOW}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  VERDICT: GO-WITH-CONDITIONS                       ║${NC}"
        echo -e "${YELLOW}║  Review warnings before production                 ║${NC}"
        echo -e "${YELLOW}╚════════════════════════════════════════════════════╝${NC}"
        EXIT_CODE=0
    fi
else
    echo -e "${RED}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  VERDICT: NO-GO                                    ║${NC}"
    echo -e "${RED}║  $FAIL critical check(s) failed                     ║${NC}"
    echo -e "${RED}║  Fix issues before production deployment           ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════╝${NC}"
    EXIT_CODE=1
fi

echo ""
echo "Manual verification still required for:"
echo "  1. Signature validation nodes in W1/W2/W3"
echo "  2. Audit nodes connected in W14"
echo "  3. Database migrations applied"
echo "  4. Production .env updated"
echo "  5. Nginx reloaded"
echo ""

exit $EXIT_CODE
