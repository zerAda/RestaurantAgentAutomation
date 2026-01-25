/*
P1-DB-002 — DB PERF + RETENTION

Scope:
- Add/adjust indexes for high-churn tables: inbound_messages, security_events, outbound_messages, workflow_errors (if present)
- Add retention primitives (audit table + batch purge helper)

Design principles:
- Idempotent (replay-safe)
- No functional regression (no column removal, no schema-breaking changes)
- Safe purge: delete in bounded chunks, index-friendly, no long-running locks.

Notes on CREATE INDEX CONCURRENTLY:
- Not used here because migration runners typically wrap in a transaction and Postgres forbids CONCURRENTLY inside a txn.
- If you run migrations with "transaction: false" for this file, you may change CREATE INDEX -> CREATE INDEX CONCURRENTLY.
*/

CREATE SCHEMA IF NOT EXISTS ops;

-- Audit table for retention runs
CREATE TABLE IF NOT EXISTS ops.retention_runs (
  run_id            BIGSERIAL PRIMARY KEY,
  run_started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  run_finished_at   TIMESTAMPTZ NULL,
  dry_run           BOOLEAN NOT NULL DEFAULT false,
  table_name        TEXT NOT NULL,
  cutoff_ts         TIMESTAMPTZ NOT NULL,
  batch_size        INTEGER NOT NULL,
  deleted_rows      BIGINT NOT NULL DEFAULT 0,
  details_json      JSONB NOT NULL DEFAULT '{}'::jsonb,
  status            TEXT NOT NULL DEFAULT 'STARTED' -- STARTED|DONE|FAILED
);

CREATE INDEX IF NOT EXISTS idx_retention_runs_started_at
  ON ops.retention_runs (run_started_at DESC);

-- Batch purge helper (generic)
-- Tries time columns in order: received_at, created_at, sent_at, updated_at, inserted_at
CREATE OR REPLACE FUNCTION ops.purge_table_batch(
  p_table_name TEXT,
  p_cutoff_ts  TIMESTAMPTZ,
  p_batch_size INTEGER,
  p_dry_run    BOOLEAN DEFAULT false
)
RETURNS TABLE(deleted_count BIGINT, time_column TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_schema   TEXT := split_part(p_table_name, '.', 1);
  v_table    TEXT := split_part(p_table_name, '.', 2);
  v_time_col TEXT;
  v_sql      TEXT;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size <= 0 THEN
    RAISE EXCEPTION 'batch_size must be > 0';
  END IF;

  IF to_regclass(p_table_name) IS NULL THEN
    -- Table absent: nothing to purge
    deleted_count := 0;
    time_column := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT c.column_name
    INTO v_time_col
  FROM information_schema.columns c
  WHERE c.table_schema = v_schema
    AND c.table_name   = v_table
    AND c.column_name IN ('received_at','created_at','sent_at','updated_at','inserted_at')
    AND c.data_type IN ('timestamp with time zone','timestamp without time zone')
  ORDER BY CASE c.column_name
    WHEN 'received_at' THEN 1
    WHEN 'created_at'  THEN 2
    WHEN 'sent_at'     THEN 3
    WHEN 'updated_at'  THEN 4
    WHEN 'inserted_at' THEN 5
    ELSE 99
  END
  LIMIT 1;

  IF v_time_col IS NULL THEN
    RAISE EXCEPTION 'No supported time column found for %', p_table_name;
  END IF;

  IF p_dry_run THEN
    v_sql := format(
      'SELECT count(*)::bigint AS deleted_count, %L::text AS time_column FROM %s WHERE %I < $1',
      v_time_col,
      p_table_name,
      v_time_col
    );
    RETURN QUERY EXECUTE v_sql USING p_cutoff_ts;
    RETURN;
  END IF;

  -- Delete a bounded chunk using CTID selection ordered by time column (index-friendly)
  v_sql := format($f$
    WITH victim AS (
      SELECT ctid
      FROM %s
      WHERE %I < $1
      ORDER BY %I ASC
      LIMIT $2
    )
    DELETE FROM %s t
    USING victim v
    WHERE t.ctid = v.ctid
    RETURNING 1
  $f$,
    p_table_name, v_time_col, v_time_col, p_table_name
  );

  EXECUTE v_sql USING p_cutoff_ts, p_batch_size;
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  time_column := v_time_col;
  RETURN NEXT;
END;
$$;

-- Specialized helper: outbound_messages SENT purge (uses sent_at + status filter)
CREATE OR REPLACE FUNCTION ops.purge_outbound_sent_batch(
  p_cutoff_ts  TIMESTAMPTZ,
  p_batch_size INTEGER,
  p_dry_run    BOOLEAN DEFAULT false
)
RETURNS TABLE(deleted_count BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_sql TEXT;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size <= 0 THEN
    RAISE EXCEPTION 'batch_size must be > 0';
  END IF;

  IF to_regclass('public.outbound_messages') IS NULL THEN
    deleted_count := 0;
    RETURN NEXT;
    RETURN;
  END IF;

  IF p_dry_run THEN
    v_sql := 'SELECT count(*)::bigint AS deleted_count
              FROM public.outbound_messages
              WHERE status = ''SENT'' AND sent_at IS NOT NULL AND sent_at < $1';
    RETURN QUERY EXECUTE v_sql USING p_cutoff_ts;
    RETURN;
  END IF;

  v_sql := $q$
    WITH victim AS (
      SELECT ctid
      FROM public.outbound_messages
      WHERE status = 'SENT'
        AND sent_at IS NOT NULL
        AND sent_at < $1
      ORDER BY sent_at ASC
      LIMIT $2
    )
    DELETE FROM public.outbound_messages t
    USING victim v
    WHERE t.ctid = v.ctid
    RETURNING 1
  $q$;

  EXECUTE v_sql USING p_cutoff_ts, p_batch_size;
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN NEXT;
END;
$$;

-- Helper: create index only if table + required columns exist and index not already present
CREATE OR REPLACE FUNCTION ops.create_index_if_cols_exist(
  p_index_name TEXT,
  p_table_name TEXT,
  p_index_ddl  TEXT,
  p_required_cols TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_schema TEXT := split_part(p_table_name, '.', 1);
  v_table  TEXT := split_part(p_table_name, '.', 2);
  v_missing INT;
BEGIN
  IF to_regclass(p_table_name) IS NULL THEN
    RETURN;
  END IF;

  SELECT count(*) INTO v_missing
  FROM unnest(p_required_cols) col
  WHERE NOT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = v_schema
      AND c.table_name   = v_table
      AND c.column_name  = col
  );

  IF v_missing > 0 THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = v_schema
      AND indexname  = p_index_name
  ) THEN
    RETURN;
  END IF;

  EXECUTE p_index_ddl;
END;
$$;

-- =========================
-- Indexes
-- =========================

-- inbound_messages: purge + window queries
-- Existing: idx_inbound_messages_window(conversation_key, received_at desc)
SELECT ops.create_index_if_cols_exist(
  'idx_inbound_messages_received_at',
  'public.inbound_messages',
  'CREATE INDEX idx_inbound_messages_received_at ON public.inbound_messages (received_at DESC)',
  ARRAY['received_at']
);

-- security_events: filter by tenant/event_type and date
SELECT ops.create_index_if_cols_exist(
  'idx_security_events_tenant_created_at',
  'public.security_events',
  'CREATE INDEX idx_security_events_tenant_created_at ON public.security_events (tenant_id, created_at DESC)',
  ARRAY['tenant_id','created_at']
);

SELECT ops.create_index_if_cols_exist(
  'idx_security_events_event_type_created_at',
  'public.security_events',
  'CREATE INDEX idx_security_events_event_type_created_at ON public.security_events (event_type, created_at DESC)',
  ARRAY['event_type','created_at']
);

-- outbound_messages: speed up purge of SENT rows (and analytics on sent_at)
SELECT ops.create_index_if_cols_exist(
  'idx_outbound_messages_sent_at',
  'public.outbound_messages',
  'CREATE INDEX idx_outbound_messages_sent_at ON public.outbound_messages (sent_at DESC) WHERE sent_at IS NOT NULL',
  ARRAY['sent_at']
);

-- workflow_errors: purge + investigations
SELECT ops.create_index_if_cols_exist(
  'idx_workflow_errors_created_at',
  'public.workflow_errors',
  'CREATE INDEX idx_workflow_errors_created_at ON public.workflow_errors (created_at DESC)',
  ARRAY['created_at']
);

SELECT ops.create_index_if_cols_exist(
  'idx_workflow_errors_workflow_name_created_at',
  'public.workflow_errors',
  'CREATE INDEX idx_workflow_errors_workflow_name_created_at ON public.workflow_errors (workflow_name, created_at DESC)',
  ARRAY['workflow_name','created_at']
);

-- =========================
-- Autovacuum hints (table-level, safe)
-- =========================
DO $$
BEGIN
  IF to_regclass('public.inbound_messages') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.inbound_messages SET (autovacuum_vacuum_scale_factor = 0.02, autovacuum_analyze_scale_factor = 0.02)';
  END IF;
  IF to_regclass('public.security_events') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.security_events SET (autovacuum_vacuum_scale_factor = 0.02, autovacuum_analyze_scale_factor = 0.02)';
  END IF;
  IF to_regclass('public.outbound_messages') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.outbound_messages SET (autovacuum_vacuum_scale_factor = 0.05, autovacuum_analyze_scale_factor = 0.05)';
  END IF;
  IF to_regclass('public.workflow_errors') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.workflow_errors SET (autovacuum_vacuum_scale_factor = 0.05, autovacuum_analyze_scale_factor = 0.05)';
  END IF;
END $$;
