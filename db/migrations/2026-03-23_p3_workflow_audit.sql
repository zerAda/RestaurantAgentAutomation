-- Migration: P3 - Workflow Audit Trail
-- Creates ops.workflow_audit and ops.workflow_audit_archive tables.
-- The ops schema already exists (created by 2026-01-22_p1_db_indexes_retention.sql).

-- Primary audit table
CREATE TABLE IF NOT EXISTS ops.workflow_audit (
  id              bigserial PRIMARY KEY,
  workflow_name   text NOT NULL,
  workflow_id     text NOT NULL,
  execution_id    text NOT NULL,
  channel         text NOT NULL DEFAULT 'unknown',
  status          text NOT NULL CHECK (status IN ('started', 'completed', 'failed')),
  started_at      timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz NULL,
  duration_ms     integer NULL,
  tenant_id       text NULL,
  correlation_id  text NULL,
  error_message   text NULL,
  metadata_json   jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Indexes for dashboard queries (date range + workflow_name filter)
CREATE INDEX IF NOT EXISTS idx_wf_audit_started_at
  ON ops.workflow_audit (started_at DESC);

CREATE INDEX IF NOT EXISTS idx_wf_audit_workflow_name
  ON ops.workflow_audit (workflow_name, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_wf_audit_status
  ON ops.workflow_audit (status, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_wf_audit_execution_id
  ON ops.workflow_audit (execution_id);

-- Archive table: same schema + archived_at column
-- Rows older than 90 days are moved here by W_AUDIT_ARCHIVE workflow
CREATE TABLE IF NOT EXISTS ops.workflow_audit_archive (
  id              bigint NOT NULL,
  workflow_name   text NOT NULL,
  workflow_id     text NOT NULL,
  execution_id    text NOT NULL,
  channel         text NOT NULL DEFAULT 'unknown',
  status          text NOT NULL,
  started_at      timestamptz NOT NULL,
  completed_at    timestamptz NULL,
  duration_ms     integer NULL,
  tenant_id       text NULL,
  correlation_id  text NULL,
  error_message   text NULL,
  metadata_json   jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL,
  archived_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wf_audit_archive_started_at
  ON ops.workflow_audit_archive (started_at DESC);

CREATE INDEX IF NOT EXISTS idx_wf_audit_archive_workflow_name
  ON ops.workflow_audit_archive (workflow_name, started_at DESC);

-- Record migration applied
-- (db-migrate service handles this automatically via schema_migrations table)
