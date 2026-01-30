-- =============================================================================
-- P2-02: Admin WA Commands + Audit Trail
-- Migration: Phone allowlist, STATUS/FLAGS/DLQ commands support
-- =============================================================================

BEGIN;

-- 1. Admin phone allowlist table
CREATE TABLE IF NOT EXISTS public.admin_phone_allowlist (
  id serial PRIMARY KEY,
  tenant_id uuid,
  restaurant_id uuid,
  phone_number text NOT NULL,
  display_name text,
  role text NOT NULL DEFAULT 'admin' CHECK (role IN ('admin','owner','super_admin')),
  permissions jsonb NOT NULL DEFAULT '["status","flags","dlq:list","help"]'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by text,
  UNIQUE (phone_number)
);

CREATE INDEX IF NOT EXISTS idx_admin_phone_allowlist_phone
  ON public.admin_phone_allowlist(phone_number) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_admin_phone_allowlist_tenant
  ON public.admin_phone_allowlist(tenant_id, restaurant_id) WHERE is_active = true;

COMMENT ON TABLE public.admin_phone_allowlist IS 'P2-02: WhatsApp phone numbers allowed to use admin commands';

-- 2. Function to check if phone is admin
CREATE OR REPLACE FUNCTION public.is_admin_phone(p_phone text)
RETURNS TABLE (
  is_admin boolean,
  role text,
  permissions jsonb,
  display_name text
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    true AS is_admin,
    a.role,
    a.permissions,
    a.display_name
  FROM public.admin_phone_allowlist a
  WHERE a.phone_number = p_phone
    AND a.is_active = true
  LIMIT 1;

  -- If no rows returned, return false
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::text, NULL::jsonb, NULL::text;
  END IF;
END;
$$;

-- 3. Extend admin_wa_audit_log with new action types
DO $$
BEGIN
  -- Add new action types to enum if they don't exist
  ALTER TABLE public.admin_wa_audit_log
    DROP CONSTRAINT IF EXISTS chk_admin_wa_audit_action;

  ALTER TABLE public.admin_wa_audit_log
    ADD CONSTRAINT chk_admin_wa_audit_action
    CHECK (action IN (
      -- Existing actions
      'help', 'tickets', 'take', 'close', 'reply',
      'template_get', 'template_set', 'template_vars',
      'zone_list', 'zone_create', 'zone_update', 'zone_delete',
      -- New P2-02 actions
      'status', 'flags', 'flags_set', 'flags_unset',
      'dlq_list', 'dlq_show', 'dlq_replay', 'dlq_drop',
      'unknown', 'unauthorized'
    ));
EXCEPTION WHEN others THEN
  -- Constraint might not exist yet
  NULL;
END $$;

-- 4. System flags table for feature toggles
CREATE TABLE IF NOT EXISTS public.system_flags (
  flag_key text PRIMARY KEY,
  flag_value text NOT NULL,
  description text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by text
);

-- Seed default flags
INSERT INTO public.system_flags (flag_key, flag_value, description)
VALUES
  ('MAINTENANCE_MODE', 'false', 'When true, all inbound processing is paused'),
  ('DLQ_REPLAY_ENABLED', 'true', 'Allow DLQ replay via admin commands'),
  ('OUTBOUND_ENABLED', 'true', 'Enable outbound message sending'),
  ('LLM_ENABLED', 'false', 'Enable LLM fallback for intent detection'),
  ('RATE_LIMIT_MULTIPLIER', '1.0', 'Multiplier for rate limits (0.5 = stricter, 2.0 = relaxed)'),
  ('DEBUG_MODE', 'false', 'Enable verbose debug logging')
ON CONFLICT (flag_key) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_system_flags_key ON public.system_flags(flag_key);

-- 5. Function to get system status
CREATE OR REPLACE FUNCTION public.get_system_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'timestamp', now()::text,
    'database', jsonb_build_object(
      'connected', true,
      'version', version()
    ),
    'counts', jsonb_build_object(
      'pending_outbound', (SELECT COUNT(*) FROM outbound_messages WHERE status = 'PENDING'),
      'dlq_messages', (SELECT COUNT(*) FROM outbound_messages WHERE status = 'DLQ'),
      'active_tickets', (SELECT COUNT(*) FROM support_tickets WHERE status IN ('OPEN','ASSIGNED')),
      'conversations_24h', (SELECT COUNT(DISTINCT conversation_key) FROM conversation_state WHERE updated_at > now() - interval '24 hours')
    ),
    'flags', (SELECT jsonb_object_agg(flag_key, flag_value) FROM system_flags)
  ) INTO result;

  RETURN result;
END;
$$;

-- 6. Function to get DLQ messages
CREATE OR REPLACE FUNCTION public.get_dlq_messages(p_limit int DEFAULT 20, p_offset int DEFAULT 0)
RETURNS TABLE (
  outbound_id bigint,
  channel text,
  user_id text,
  restaurant_id uuid,
  status text,
  attempts int,
  last_error text,
  created_at timestamptz,
  correlation_id text
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    o.outbound_id,
    o.channel,
    o.user_id,
    o.restaurant_id,
    o.status,
    o.attempts,
    o.last_error,
    o.created_at,
    o.correlation_id
  FROM public.outbound_messages o
  WHERE o.status = 'DLQ'
  ORDER BY o.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

-- 7. Function to replay DLQ message
CREATE OR REPLACE FUNCTION public.replay_dlq_message(p_outbound_id bigint, p_actor text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_msg record;
  v_result jsonb;
BEGIN
  -- Get the DLQ message
  SELECT * INTO v_msg
  FROM public.outbound_messages
  WHERE outbound_id = p_outbound_id AND status = 'DLQ';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Message not found or not in DLQ');
  END IF;

  -- Update status to RETRY
  UPDATE public.outbound_messages
  SET
    status = 'RETRY',
    attempts = 0,
    last_error = 'Replayed by ' || p_actor,
    updated_at = now()
  WHERE outbound_id = p_outbound_id;

  -- Log the replay action
  PERFORM insert_admin_wa_audit(
    NULL, v_msg.restaurant_id, p_actor, 'admin',
    'dlq_replay', 'outbound_message', p_outbound_id::text,
    '!dlq replay ' || p_outbound_id::text,
    jsonb_build_object('channel', v_msg.channel, 'user_id', v_msg.user_id),
    NULL, true, NULL
  );

  RETURN jsonb_build_object(
    'success', true,
    'outbound_id', p_outbound_id,
    'new_status', 'RETRY',
    'message', 'Message queued for retry'
  );
END;
$$;

-- 8. Function to drop DLQ message
CREATE OR REPLACE FUNCTION public.drop_dlq_message(p_outbound_id bigint, p_actor text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_msg record;
BEGIN
  -- Get the DLQ message
  SELECT * INTO v_msg
  FROM public.outbound_messages
  WHERE outbound_id = p_outbound_id AND status = 'DLQ';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Message not found or not in DLQ');
  END IF;

  -- Update status to DROPPED (permanent)
  UPDATE public.outbound_messages
  SET
    status = 'DROPPED',
    last_error = 'Dropped by ' || p_actor,
    updated_at = now()
  WHERE outbound_id = p_outbound_id;

  -- Log the drop action
  PERFORM insert_admin_wa_audit(
    NULL, v_msg.restaurant_id, p_actor, 'admin',
    'dlq_drop', 'outbound_message', p_outbound_id::text,
    '!dlq drop ' || p_outbound_id::text,
    jsonb_build_object('channel', v_msg.channel, 'user_id', v_msg.user_id),
    NULL, true, NULL
  );

  RETURN jsonb_build_object(
    'success', true,
    'outbound_id', p_outbound_id,
    'new_status', 'DROPPED',
    'message', 'Message permanently dropped'
  );
END;
$$;

-- 9. Add DROPPED status to outbound_messages if not exists
DO $$
BEGIN
  ALTER TABLE public.outbound_messages
    DROP CONSTRAINT IF EXISTS chk_outbound_messages_status;

  ALTER TABLE public.outbound_messages
    ADD CONSTRAINT chk_outbound_messages_status
    CHECK (status IN ('PENDING', 'RETRY', 'SENT', 'DLQ', 'DROPPED'));
EXCEPTION WHEN others THEN
  NULL;
END $$;

-- 10. View for recent DLQ messages
CREATE OR REPLACE VIEW public.v_dlq_recent AS
SELECT
  outbound_id,
  channel,
  user_id,
  restaurant_id,
  attempts,
  last_error,
  created_at,
  correlation_id,
  EXTRACT(EPOCH FROM (now() - created_at)) / 3600 AS age_hours
FROM public.outbound_messages
WHERE status = 'DLQ'
ORDER BY created_at DESC
LIMIT 100;

COMMENT ON VIEW public.v_dlq_recent IS 'P2-02: Recent DLQ messages for admin monitoring';

COMMIT;
