-- Migration: P2 - EPIC3 Order Tracking
-- Consolidated into db/bootstrap.sql (order_status_history)
-- This file is idempotent and safe to re-run.

CREATE TABLE IF NOT EXISTS order_status_history (
  id              bigserial PRIMARY KEY,
  order_id        uuid NOT NULL,
  old_status      text,
  new_status      text NOT NULL,
  changed_by      text DEFAULT 'system',
  metadata        jsonb DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_osh_order ON order_status_history (order_id);
CREATE INDEX IF NOT EXISTS idx_osh_created ON order_status_history (created_at);
