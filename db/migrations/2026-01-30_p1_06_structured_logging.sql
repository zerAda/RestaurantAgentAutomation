-- =============================================================================
-- P1-06: Structured Logging + Correlation ID
-- Migration: Add correlation_id to logging tables for end-to-end tracing
-- =============================================================================

-- Add correlation_id column to security_events
ALTER TABLE security_events
ADD COLUMN IF NOT EXISTS correlation_id text;

CREATE INDEX IF NOT EXISTS idx_security_events_correlation_id
ON security_events(correlation_id)
WHERE correlation_id IS NOT NULL;

-- Add correlation_id column to workflow_errors
ALTER TABLE workflow_errors
ADD COLUMN IF NOT EXISTS correlation_id text;

CREATE INDEX IF NOT EXISTS idx_workflow_errors_correlation_id
ON workflow_errors(correlation_id)
WHERE correlation_id IS NOT NULL;

-- Add correlation_id column to outbound_messages
ALTER TABLE outbound_messages
ADD COLUMN IF NOT EXISTS correlation_id text;

CREATE INDEX IF NOT EXISTS idx_outbound_messages_correlation_id
ON outbound_messages(correlation_id)
WHERE correlation_id IS NOT NULL;

-- Add correlation_id column to inbound_messages
ALTER TABLE inbound_messages
ADD COLUMN IF NOT EXISTS correlation_id text;

CREATE INDEX IF NOT EXISTS idx_inbound_messages_correlation_id
ON inbound_messages(correlation_id)
WHERE correlation_id IS NOT NULL;

-- Create structured_logs table for centralized logging
CREATE TABLE IF NOT EXISTS structured_logs (
  id              bigserial PRIMARY KEY,
  correlation_id  text NOT NULL,
  tenant_id       uuid,
  restaurant_id   uuid,
  user_id         text,
  conversation_key text,
  channel         text CHECK (channel IS NULL OR channel IN ('whatsapp','instagram','messenger')),
  workflow_name   text,
  node_name       text,
  level           text NOT NULL CHECK (level IN ('DEBUG','INFO','WARN','ERROR')),
  event_type      text,
  message         text,
  context_json    jsonb DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Indexes for structured_logs
CREATE INDEX IF NOT EXISTS idx_structured_logs_correlation_id
ON structured_logs(correlation_id);

CREATE INDEX IF NOT EXISTS idx_structured_logs_created_at
ON structured_logs(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_structured_logs_level_created
ON structured_logs(level, created_at DESC)
WHERE level IN ('WARN','ERROR');

CREATE INDEX IF NOT EXISTS idx_structured_logs_tenant_created
ON structured_logs(tenant_id, created_at DESC)
WHERE tenant_id IS NOT NULL;

-- Function to log structured events (callable from workflows via SQL)
CREATE OR REPLACE FUNCTION log_structured(
  p_correlation_id text,
  p_level text,
  p_message text,
  p_event_type text DEFAULT NULL,
  p_tenant_id uuid DEFAULT NULL,
  p_restaurant_id uuid DEFAULT NULL,
  p_user_id text DEFAULT NULL,
  p_conversation_key text DEFAULT NULL,
  p_channel text DEFAULT NULL,
  p_workflow_name text DEFAULT NULL,
  p_node_name text DEFAULT NULL,
  p_context_json jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_id bigint;
BEGIN
  INSERT INTO structured_logs (
    correlation_id, level, message, event_type,
    tenant_id, restaurant_id, user_id, conversation_key, channel,
    workflow_name, node_name, context_json
  ) VALUES (
    p_correlation_id, p_level, p_message, p_event_type,
    p_tenant_id, p_restaurant_id, p_user_id, p_conversation_key, p_channel,
    p_workflow_name, p_node_name, p_context_json
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- View to trace full request flow by correlation_id
CREATE OR REPLACE VIEW v_request_trace AS
SELECT
  correlation_id,
  created_at,
  'structured_log' AS source,
  level,
  event_type,
  message,
  workflow_name,
  node_name,
  context_json
FROM structured_logs
UNION ALL
SELECT
  correlation_id,
  created_at,
  'security_event' AS source,
  severity AS level,
  event_type::text,
  NULL AS message,
  NULL AS workflow_name,
  NULL AS node_name,
  payload_json AS context_json
FROM security_events
WHERE correlation_id IS NOT NULL
UNION ALL
SELECT
  correlation_id,
  received_at,
  'inbound_message' AS source,
  'INFO' AS level,
  'INBOUND_RECEIVED' AS event_type,
  NULL AS message,
  NULL AS workflow_name,
  NULL AS node_name,
  meta_json AS context_json
FROM inbound_messages
WHERE correlation_id IS NOT NULL
UNION ALL
SELECT
  correlation_id,
  created_at,
  'outbound_message' AS source,
  CASE WHEN status = 'DLQ' THEN 'ERROR' WHEN status = 'RETRY' THEN 'WARN' ELSE 'INFO' END AS level,
  'OUTBOUND_' || status AS event_type,
  last_error AS message,
  NULL AS workflow_name,
  NULL AS node_name,
  payload_json AS context_json
FROM outbound_messages
WHERE correlation_id IS NOT NULL
ORDER BY created_at;

-- Comment for documentation
COMMENT ON TABLE structured_logs IS 'P1-06: Centralized structured logging table for end-to-end request tracing';
COMMENT ON FUNCTION log_structured IS 'P1-06: Helper function to insert structured log entries from workflows';
COMMENT ON VIEW v_request_trace IS 'P1-06: Unified view of all events for a given correlation_id';
