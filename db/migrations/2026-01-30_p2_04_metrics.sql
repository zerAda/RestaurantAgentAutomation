-- =============================================================================
-- P2-04: Minimal Metrics + Stats
-- Migration: Daily counters for inbound/outbound/errors + latency tracking
-- =============================================================================

BEGIN;

-- 1. Daily metrics table (PostgreSQL fallback when Redis unavailable)
CREATE TABLE IF NOT EXISTS public.daily_metrics (
  id serial PRIMARY KEY,
  metric_date date NOT NULL DEFAULT CURRENT_DATE,
  metric_key text NOT NULL,
  metric_value bigint NOT NULL DEFAULT 0,
  channel text,  -- 'whatsapp', 'instagram', 'messenger', or NULL for global
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (metric_date, metric_key, channel)
);

CREATE INDEX IF NOT EXISTS idx_daily_metrics_date ON public.daily_metrics(metric_date);
CREATE INDEX IF NOT EXISTS idx_daily_metrics_key ON public.daily_metrics(metric_key, metric_date);

COMMENT ON TABLE public.daily_metrics IS 'P2-04: Daily aggregated metrics (Redis fallback)';

-- 2. Latency samples table (for percentile calculations)
CREATE TABLE IF NOT EXISTS public.latency_samples (
  id bigserial PRIMARY KEY,
  sample_date date NOT NULL DEFAULT CURRENT_DATE,
  workflow text NOT NULL,  -- 'W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7'
  channel text,
  latency_ms int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_latency_samples_date ON public.latency_samples(sample_date);
CREATE INDEX IF NOT EXISTS idx_latency_samples_workflow ON public.latency_samples(workflow, sample_date);

-- Partition by date (keep only 7 days by default)
-- For simplicity, we'll use a cleanup job instead of partitioning

COMMENT ON TABLE public.latency_samples IS 'P2-04: Latency samples for percentile calculations';

-- 3. Function to increment a metric counter
CREATE OR REPLACE FUNCTION public.increment_metric(
  p_key text,
  p_channel text DEFAULT NULL,
  p_increment bigint DEFAULT 1,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_new_value bigint;
BEGIN
  INSERT INTO public.daily_metrics (metric_date, metric_key, channel, metric_value)
  VALUES (p_date, p_key, p_channel, p_increment)
  ON CONFLICT (metric_date, metric_key, channel)
  DO UPDATE SET
    metric_value = daily_metrics.metric_value + p_increment,
    updated_at = now()
  RETURNING metric_value INTO v_new_value;

  RETURN v_new_value;
END;
$$;

-- 4. Function to record latency sample
CREATE OR REPLACE FUNCTION public.record_latency(
  p_workflow text,
  p_channel text,
  p_latency_ms int,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.latency_samples (sample_date, workflow, channel, latency_ms)
  VALUES (p_date, p_workflow, p_channel, p_latency_ms);
END;
$$;

-- 5. Function to get daily stats summary
CREATE OR REPLACE FUNCTION public.get_daily_stats(p_date date DEFAULT CURRENT_DATE)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'date', p_date::text,
    'timestamp', now()::text,
    'counters', (
      SELECT COALESCE(jsonb_object_agg(
        CASE WHEN channel IS NULL THEN metric_key ELSE metric_key || ':' || channel END,
        metric_value
      ), '{}'::jsonb)
      FROM public.daily_metrics
      WHERE metric_date = p_date
    ),
    'inbound', jsonb_build_object(
      'total', COALESCE((SELECT SUM(metric_value) FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'inbound'), 0),
      'whatsapp', COALESCE((SELECT metric_value FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'inbound' AND channel = 'whatsapp'), 0),
      'instagram', COALESCE((SELECT metric_value FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'inbound' AND channel = 'instagram'), 0),
      'messenger', COALESCE((SELECT metric_value FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'inbound' AND channel = 'messenger'), 0)
    ),
    'outbound', jsonb_build_object(
      'total', COALESCE((SELECT SUM(metric_value) FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'outbound'), 0),
      'whatsapp', COALESCE((SELECT metric_value FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'outbound' AND channel = 'whatsapp'), 0),
      'instagram', COALESCE((SELECT metric_value FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'outbound' AND channel = 'instagram'), 0),
      'messenger', COALESCE((SELECT metric_value FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'outbound' AND channel = 'messenger'), 0)
    ),
    'errors', jsonb_build_object(
      'total', COALESCE((SELECT SUM(metric_value) FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'errors'), 0),
      'auth', COALESCE((SELECT metric_value FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'errors' AND channel = 'auth'), 0),
      'validation', COALESCE((SELECT metric_value FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'errors' AND channel = 'validation'), 0),
      'outbound', COALESCE((SELECT metric_value FROM public.daily_metrics WHERE metric_date = p_date AND metric_key = 'errors' AND channel = 'outbound'), 0)
    ),
    'latency', (
      SELECT jsonb_build_object(
        'samples', COUNT(*),
        'avg_ms', ROUND(AVG(latency_ms)),
        'p50_ms', PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY latency_ms),
        'p95_ms', PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_ms),
        'p99_ms', PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY latency_ms),
        'max_ms', MAX(latency_ms)
      )
      FROM public.latency_samples
      WHERE sample_date = p_date
    )
  ) INTO result;

  RETURN result;
END;
$$;

-- 6. Function to get stats for last N days
CREATE OR REPLACE FUNCTION public.get_stats_range(p_days int DEFAULT 7)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  result jsonb;
  day_stats jsonb;
  d date;
BEGIN
  result := '[]'::jsonb;

  FOR d IN SELECT generate_series(CURRENT_DATE - (p_days - 1), CURRENT_DATE, '1 day'::interval)::date
  LOOP
    day_stats := get_daily_stats(d);
    result := result || jsonb_build_array(day_stats);
  END LOOP;

  RETURN result;
END;
$$;

-- 7. Cleanup function for old latency samples (keep 7 days)
CREATE OR REPLACE FUNCTION public.cleanup_old_metrics(p_retention_days int DEFAULT 7)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  v_deleted int;
BEGIN
  DELETE FROM public.latency_samples
  WHERE sample_date < CURRENT_DATE - p_retention_days;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  -- Also cleanup old daily_metrics (keep 30 days)
  DELETE FROM public.daily_metrics
  WHERE metric_date < CURRENT_DATE - 30;

  RETURN v_deleted;
END;
$$;

-- 8. Redis key schema documentation (for reference in workflows)
COMMENT ON FUNCTION public.increment_metric IS 'P2-04: Increment metric counter. Redis keys: ralphe:metrics:{key}:{channel}:{YYYY-MM-DD}';

-- 9. Seed initial metrics for today (optional, for testing)
-- INSERT INTO public.daily_metrics (metric_date, metric_key, channel, metric_value) VALUES
--   (CURRENT_DATE, 'inbound', 'whatsapp', 0),
--   (CURRENT_DATE, 'inbound', 'instagram', 0),
--   (CURRENT_DATE, 'inbound', 'messenger', 0),
--   (CURRENT_DATE, 'outbound', 'whatsapp', 0),
--   (CURRENT_DATE, 'outbound', 'instagram', 0),
--   (CURRENT_DATE, 'outbound', 'messenger', 0),
--   (CURRENT_DATE, 'errors', NULL, 0)
-- ON CONFLICT DO NOTHING;

COMMIT;
