-- Migration: P0-SEC-02 - Meta Webhook Replay Guard
-- Consolidated into db/bootstrap.sql (webhook_replay_guard)
-- This file is idempotent and safe to re-run.

CREATE TABLE IF NOT EXISTS webhook_replay_guard (
  id             bigserial PRIMARY KEY,
  message_hash   varchar(64) NOT NULL,
  message_id     varchar(255),
  channel        varchar(20) NOT NULL DEFAULT 'whatsapp',
  received_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_replay_guard_hash_channel UNIQUE (message_hash, channel)
);

CREATE INDEX IF NOT EXISTS idx_replay_guard_received_at ON webhook_replay_guard (received_at);
CREATE INDEX IF NOT EXISTS idx_replay_guard_message_id ON webhook_replay_guard (message_id) WHERE message_id IS NOT NULL;
