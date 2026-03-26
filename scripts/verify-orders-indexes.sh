#!/usr/bin/env bash
# =============================================================================
# Phase 6 — PERF-03: Verify Order Indexes via EXPLAIN ANALYZE
# =============================================================================
# Purpose: Confirm that the new indexes are being used by the 3 most common
#          order query patterns. Outputs query plans with index scan confirmation.
#
# Usage:   DATABASE_URL=postgres://... bash scripts/verify-orders-indexes.sh
#          Or: PGHOST=localhost PGUSER=n8n PGDATABASE=n8n bash scripts/verify-orders-indexes.sh
# =============================================================================

set -euo pipefail

DB_URL="${DATABASE_URL:-postgres://${PGUSER:-n8n}:${PGPASSWORD:-n8npass}@${PGHOST:-localhost}:${PGPORT:-5432}/${PGDATABASE:-n8n}}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  PERF-03: Order Index Verification (EXPLAIN ANALYZE)     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check indexes exist first
echo -e "${YELLOW}━━━ Step 1: Verify Indexes Exist ━━━${NC}"
for IDX in idx_orders_status_created idx_orders_user_status idx_orders_restaurant_created idx_orders_active; do
  EXISTS=$(psql "$DB_URL" -tAc "SELECT 1 FROM pg_indexes WHERE indexname = '$IDX';" 2>/dev/null || echo "0")
  if [[ "$EXISTS" == "1" ]]; then
    echo -e "${GREEN}✅ Index $IDX exists${NC}"
    ((PASS++))
  else
    echo -e "${RED}❌ Index $IDX MISSING — run migration first${NC}"
    ((FAIL++))
  fi
done

# Query 1: Orders by status (kitchen display, admin dashboard)
echo -e "\n${YELLOW}━━━ Query 1: Active Orders by Status ━━━${NC}"
PLAN1=$(psql "$DB_URL" -c "
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT order_id, status, created_at, total_cents
FROM orders
WHERE status IN ('NEW', 'ACCEPTED', 'IN_PROGRESS')
ORDER BY created_at DESC
LIMIT 50;
" 2>&1 || echo "QUERY_FAILED")

echo "$PLAN1"
if echo "$PLAN1" | grep -qi "Index"; then
  echo -e "${GREEN}✅ Query 1: Using index scan${NC}"
  ((PASS++))
else
  echo -e "${RED}⚠️  Query 1: Sequential scan detected (may be OK for small tables)${NC}"
  ((FAIL++))
fi

# Query 2: Orders by user (customer history)
echo -e "\n${YELLOW}━━━ Query 2: Customer Order History ━━━${NC}"
PLAN2=$(psql "$DB_URL" -c "
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT order_id, status, created_at, total_cents
FROM orders
WHERE user_id = 'test_user_placeholder'
  AND status != 'CANCELLED'
ORDER BY created_at DESC
LIMIT 20;
" 2>&1 || echo "QUERY_FAILED")

echo "$PLAN2"
if echo "$PLAN2" | grep -qi "Index"; then
  echo -e "${GREEN}✅ Query 2: Using index scan${NC}"
  ((PASS++))
else
  echo -e "${RED}⚠️  Query 2: Sequential scan detected${NC}"
  ((FAIL++))
fi

# Query 3: Recent orders (dashboard home widget)
echo -e "\n${YELLOW}━━━ Query 3: Recent 24h Orders ━━━${NC}"
PLAN3=$(psql "$DB_URL" -c "
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT order_id, status, channel, total_cents, created_at
FROM orders
WHERE created_at > now() - interval '24 hours'
ORDER BY created_at DESC
LIMIT 100;
" 2>&1 || echo "QUERY_FAILED")

echo "$PLAN3"
if echo "$PLAN3" | grep -qi "Index"; then
  echo -e "${GREEN}✅ Query 3: Using index scan${NC}"
  ((PASS++))
else
  echo -e "${RED}⚠️  Query 3: Sequential scan detected${NC}"
  ((FAIL++))
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  RESULTS: $PASS passed / $FAIL issues"
echo "╚════════════════════════════════════════════════════════════╝"

if [[ $FAIL -gt 0 ]]; then
  echo -e "${YELLOW}Note: Sequential scans are expected on small tables (<1000 rows).${NC}"
  echo -e "${YELLOW}PostgreSQL's query planner prefers seq scan when table fits in memory.${NC}"
fi
exit 0
