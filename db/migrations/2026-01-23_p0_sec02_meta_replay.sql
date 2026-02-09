-- Migration: P0-SEC-02 - Meta Webhook Replay Guard
-- Consolidated into db/bootstrap.sql (webhook_replay_guard)
-- This file is idempotent and safe to re-run.

CREATE TABLE IF NOT EXISTS webhook_replay_guard (
  id             bigserial PRIMARY KEY,
  payload_hash   text NOT NULL UNIQUE,
  channel        text NOT NULL,
  received_at    timestamptz NOT NULL DEFAULT now(),
  expires_at     timestamptz NOT NULL DEFAULT (now() + interval '5 minutes')
);

CREATE INDEX IF NOT EXISTS idx_wrg_hash ON webhook_replay_guard (payload_hash);
CREATE INDEX IF NOT EXISTS idx_wrg_expires ON webhook_replay_guard (expires_at);
