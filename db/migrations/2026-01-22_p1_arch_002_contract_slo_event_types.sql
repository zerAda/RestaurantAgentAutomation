-- Migration: P1-ARCH-002 - Contract SLO Event Types
-- Consolidated into db/bootstrap.sql (daily_metrics, latency_samples, ops tables)
-- This file is idempotent and safe to re-run.

CREATE TABLE IF NOT EXISTS daily_metrics (
  id             serial PRIMARY KEY,
  metric_date    date NOT NULL DEFAULT CURRENT_DATE,
  metric_name    text NOT NULL,
  metric_value   numeric NOT NULL DEFAULT 0,
  metadata       jsonb DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (metric_date, metric_name)
);

CREATE TABLE IF NOT EXISTS latency_samples (
  id             serial PRIMARY KEY,
  sample_time    timestamptz NOT NULL DEFAULT now(),
  operation      text NOT NULL,
  latency_ms     numeric NOT NULL,
  metadata       jsonb DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS ops_kv (
  key        text PRIMARY KEY,
  value      text,
  updated_at timestamptz DEFAULT now()
);
