-- Migration: P1 - DB Indexes & Retention
-- Consolidated into db/bootstrap.sql (SECTION 7: Performance Indexes)
-- This file is idempotent and safe to re-run.

-- Performance indexes (already in bootstrap.sql SECTION 7)
CREATE INDEX IF NOT EXISTS idx_inbound_messages_created
  ON inbound_messages (created_at);
CREATE INDEX IF NOT EXISTS idx_outbound_messages_status
  ON outbound_messages (status);
CREATE INDEX IF NOT EXISTS idx_outbound_messages_created
  ON outbound_messages (created_at);
CREATE INDEX IF NOT EXISTS idx_security_events_created
  ON security_events (created_at);
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_status
  ON orders (restaurant_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_created
  ON orders (created_at);

-- Retention-supporting ops schema
CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS ops.retention_runs (
  id           serial PRIMARY KEY,
  table_name   text NOT NULL,
  rows_deleted bigint NOT NULL DEFAULT 0,
  started_at   timestamptz NOT NULL DEFAULT now(),
  finished_at  timestamptz,
  dry_run      boolean NOT NULL DEFAULT false
);
