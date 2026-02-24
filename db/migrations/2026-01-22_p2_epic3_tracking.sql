-- Migration: P2 - EPIC3 Order Tracking
-- Guard migration: compatible with bootstrap.sql (source of truth)
-- Bootstrap uses: internal_status, customer_status, note (not old_status/new_status/changed_by/metadata)

CREATE TABLE IF NOT EXISTS order_status_history (
  id              bigserial PRIMARY KEY,
  order_id        uuid NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
  internal_status text NOT NULL,
  customer_status text NULL,
  note            text NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_status_history_order_time
  ON order_status_history(order_id, created_at ASC);
