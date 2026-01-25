-- P0-OPS-01 Alerting KV store for cooldown / last-alert state
-- Safe to run multiple times
CREATE TABLE IF NOT EXISTS ops_kv (
  key text PRIMARY KEY,
  value_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ops_kv_updated_at_idx ON ops_kv(updated_at);
