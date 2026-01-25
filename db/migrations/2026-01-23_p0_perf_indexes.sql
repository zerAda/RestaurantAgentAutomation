-- =========================
-- P0-PERF-01: Performance Optimization Indexes
-- 2026-01-23
-- =========================
-- Safe: idempotent, additive only
-- Note: Using CONCURRENTLY for online index creation (no locks)

-- ========================================
-- 1. Quarantine lookup optimization
-- Query: Check if conversation is quarantined
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname='public' AND indexname='idx_quarantine_conv_active_exp'
  ) THEN
    CREATE INDEX idx_quarantine_conv_active_exp
      ON conversation_quarantine (conversation_key, active, expires_at);
    RAISE NOTICE 'Created idx_quarantine_conv_active_exp';
  END IF;
END$$;

-- ========================================
-- 2. Outbox due picking optimization
-- Query: SELECT ... WHERE status IN ('PENDING','RETRY') ORDER BY next_retry_at
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname='public' AND indexname='idx_outbox_status_due'
  ) THEN
    CREATE INDEX idx_outbox_status_due
      ON outbound_messages (status, next_retry_at, created_at);
    RAISE NOTICE 'Created idx_outbox_status_due';
  END IF;
END$$;

-- ========================================
-- 3. Security events time queries
-- Query: SELECT ... WHERE created_at > now() - interval '1 hour'
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname='public' AND indexname='idx_security_events_time'
  ) THEN
    CREATE INDEX idx_security_events_time
      ON security_events (created_at DESC);
    RAISE NOTICE 'Created idx_security_events_time';
  END IF;
END$$;

-- ========================================
-- 4. Security events by type
-- Query: SELECT ... WHERE event_type = 'AUTH_DENY'
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname='public' AND indexname='idx_security_events_type_time'
  ) THEN
    CREATE INDEX idx_security_events_type_time
      ON security_events (event_type, created_at DESC);
    RAISE NOTICE 'Created idx_security_events_type_time';
  END IF;
END$$;

-- ========================================
-- 5. Support tickets ops console
-- Query: SELECT ... WHERE status = 'OPEN' ORDER BY created_at
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname='public' AND indexname='idx_support_tickets_status_time'
  ) THEN
    -- Check if table exists first
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'support_tickets') THEN
      CREATE INDEX idx_support_tickets_status_time
        ON support_tickets (tenant_id, restaurant_id, status, created_at DESC);
      RAISE NOTICE 'Created idx_support_tickets_status_time';
    ELSE
      RAISE NOTICE 'support_tickets table does not exist, skipping index';
    END IF;
  END IF;
END$$;

-- ========================================
-- 6. Inbound messages rate limit window
-- Query: SELECT COUNT(*) WHERE conversation_key = X AND received_at > now() - 30s
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname='public' AND indexname='idx_inbound_conv_time'
  ) THEN
    CREATE INDEX idx_inbound_conv_time
      ON inbound_messages (conversation_key, received_at DESC);
    RAISE NOTICE 'Created idx_inbound_conv_time';
  END IF;
END$$;

-- ========================================
-- 7. Orders by status (kitchen display)
-- Query: SELECT ... WHERE status IN ('NEW','ACCEPTED','IN_PROGRESS')
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname='public' AND indexname='idx_orders_status_time'
  ) THEN
    CREATE INDEX idx_orders_status_time
      ON orders (restaurant_id, status, created_at DESC);
    RAISE NOTICE 'Created idx_orders_status_time';
  END IF;
END$$;

-- ========================================
-- 8. Workflow errors recent
-- Query: SELECT ... WHERE created_at > now() - interval '1 hour'
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname='public' AND indexname='idx_workflow_errors_time'
  ) THEN
    CREATE INDEX idx_workflow_errors_time
      ON workflow_errors (created_at DESC);
    RAISE NOTICE 'Created idx_workflow_errors_time';
  END IF;
END$$;

-- ========================================
-- MAINTENANCE RECOMMENDATIONS
-- ========================================
-- Run during low-traffic windows (e.g., 2-5 AM local time):
-- 
-- VACUUM (ANALYZE) inbound_messages;
-- VACUUM (ANALYZE) outbound_messages;
-- VACUUM (ANALYZE) security_events;
-- VACUUM (ANALYZE) conversation_quarantine;
-- VACUUM (ANALYZE) workflow_errors;
-- 
-- Consider adding to W8_OPS as a scheduled maintenance task.

-- ========================================
-- ROLLBACK INSTRUCTIONS
-- ========================================
-- DROP INDEX IF EXISTS idx_quarantine_conv_active_exp;
-- DROP INDEX IF EXISTS idx_outbox_status_due;
-- DROP INDEX IF EXISTS idx_security_events_time;
-- DROP INDEX IF EXISTS idx_security_events_type_time;
-- DROP INDEX IF EXISTS idx_support_tickets_status_time;
-- DROP INDEX IF EXISTS idx_inbound_conv_time;
-- DROP INDEX IF EXISTS idx_orders_status_time;
-- DROP INDEX IF EXISTS idx_workflow_errors_time;
