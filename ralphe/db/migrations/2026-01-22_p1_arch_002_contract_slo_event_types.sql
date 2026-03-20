-- Migration: P1-ARCH-002 - Contract SLO Event Types
-- Guard migration: compatible with bootstrap.sql (source of truth)
-- Creates tables/indexes only if they don't already exist.

-- daily_metrics (bootstrap uses: metric_key, metric_value bigint, channel, updated_at)
CREATE TABLE IF NOT EXISTS daily_metrics (
  id           serial PRIMARY KEY,
  metric_date  date NOT NULL DEFAULT CURRENT_DATE,
  metric_key   text NOT NULL,
  metric_value bigint NOT NULL DEFAULT 0,
  channel      text,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (metric_date, metric_key, channel)
);

CREATE INDEX IF NOT EXISTS idx_daily_metrics_date ON daily_metrics(metric_date);
CREATE INDEX IF NOT EXISTS idx_daily_metrics_key  ON daily_metrics(metric_key, metric_date);

-- latency_samples (bootstrap uses: sample_date, workflow, channel, latency_ms int, created_at)
CREATE TABLE IF NOT EXISTS latency_samples (
  id          bigserial PRIMARY KEY,
  sample_date date NOT NULL DEFAULT CURRENT_DATE,
  workflow    text NOT NULL,
  channel     text,
  latency_ms  int NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_latency_samples_date     ON latency_samples(sample_date);
CREATE INDEX IF NOT EXISTS idx_latency_samples_workflow  ON latency_samples(workflow, sample_date);

-- ops_kv (bootstrap uses: value_json jsonb)
CREATE TABLE IF NOT EXISTS ops_kv (
  key        text PRIMARY KEY,
  value_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_kv_updated_at_idx ON ops_kv(updated_at);

-- ops schema + security_event_types
CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS ops.security_event_types (
  code        text PRIMARY KEY,
  description text NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
