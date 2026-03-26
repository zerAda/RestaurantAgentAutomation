-- =============================================================================
-- Phase 6: Performance Tuning — Database Index Migration
-- =============================================================================
-- Purpose: Add composite indexes on the orders table to optimize the 3 most
--          common query patterns: status filtering, user history, and time range.
--
-- Verified against: db/bootstrap.sql (orders table schema)
-- Pattern: db/migrations/2026-01-22_p1_db_indexes_retention.sql
-- =============================================================================

-- PERF-01: Composite index for status + time range queries
-- Used by: Kitchen Display (active orders), Admin Dashboard (order list), API queries
-- Covers: WHERE status IN (...) ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_orders_status_created
  ON orders (status, created_at DESC);

-- PERF-02: Composite index for per-user order history
-- CRITICAL NOTE: orders table has NO customer_id column. The column is user_id (text).
-- Confirmed from db/bootstrap.sql line 253.
-- Used by: Customer history, driver earnings, repeat order detection
CREATE INDEX IF NOT EXISTS idx_orders_user_status
  ON orders (user_id, status);

-- PERF-10: Composite index for restaurant + status (dispatch, kitchen)
-- Used by: Hive Mind Dispatch, Kitchen Display per-restaurant filtering
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_created
  ON orders (restaurant_id, created_at DESC);

-- PERF-11: Index for delivery zone queries (driver assignment)
CREATE INDEX IF NOT EXISTS idx_orders_delivery_zone
  ON orders (delivery_zone_id)
  WHERE delivery_zone_id IS NOT NULL;

-- PERF-12: Partial index for active orders only (most common query pattern)
-- This dramatically speeds up "show me all active orders" which is the #1 query
CREATE INDEX IF NOT EXISTS idx_orders_active
  ON orders (created_at DESC)
  WHERE status IN ('NEW', 'ACCEPTED', 'IN_PROGRESS', 'READY');

-- PERF-13: Index on inbound_messages for conversation lookup
CREATE INDEX IF NOT EXISTS idx_inbound_messages_conversation
  ON inbound_messages (restaurant_id, channel, sender_id, created_at DESC);

-- PERF-14: Index on outbound_messages for delivery tracking
CREATE INDEX IF NOT EXISTS idx_outbound_messages_status
  ON outbound_messages (status, created_at DESC)
  WHERE status != 'SENT';
