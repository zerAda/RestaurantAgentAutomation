-- Migration: P1 - DB Indexes & Retention
-- Guard migration: compatible with bootstrap.sql (source of truth)
-- Creates indexes/tables only if they don't already exist.

-- Performance indexes (safe to re-run with IF NOT EXISTS)
CREATE INDEX IF NOT EXISTS idx_inbound_messages_created
  ON inbound_messages (received_at);
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

-- ops.retention_runs (bootstrap uses: run_id, run_started_at, run_finished_at,
--   dry_run, table_name, cutoff_ts, batch_size, deleted_rows, details_json, status)
CREATE TABLE IF NOT EXISTS ops.retention_runs (
  run_id            bigserial PRIMARY KEY,
  run_started_at    timestamptz NOT NULL DEFAULT now(),
  run_finished_at   timestamptz NULL,
  dry_run           boolean NOT NULL DEFAULT false,
  table_name        text NOT NULL,
  cutoff_ts         timestamptz NOT NULL,
  batch_size        integer NOT NULL,
  deleted_rows      bigint NOT NULL DEFAULT 0,
  details_json      jsonb NOT NULL DEFAULT '{}'::jsonb,
  status            text NOT NULL DEFAULT 'STARTED'
);

CREATE INDEX IF NOT EXISTS idx_retention_runs_started_at
  ON ops.retention_runs (run_started_at DESC);
