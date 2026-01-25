-- =========================
-- P0-SUP-01: Admin WhatsApp Audit Log
-- 2026-01-23
-- =========================
-- Safe: idempotent, additive only

BEGIN;

-- ========================================
-- 1. Admin WhatsApp Audit Log Table
-- ========================================
CREATE TABLE IF NOT EXISTS admin_wa_audit_log (
  id              bigserial PRIMARY KEY,
  tenant_id       uuid NULL,
  restaurant_id   uuid NULL,
  actor_phone     text NOT NULL,
  actor_role      text NOT NULL DEFAULT 'admin',
  action          text NOT NULL,
  target_type     text,           -- 'ticket', 'order', 'customer', 'zone', etc.
  target_id       text,           -- ticket_id, order_id, etc.
  command_raw     text,           -- original command text (sanitized)
  metadata_json   jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip_address      text,
  success         boolean NOT NULL DEFAULT true,
  error_message   text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_tenant_time 
  ON admin_wa_audit_log(tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_actor_time 
  ON admin_wa_audit_log(actor_phone, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_action_time 
  ON admin_wa_audit_log(action, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_target 
  ON admin_wa_audit_log(target_type, target_id)
  WHERE target_type IS NOT NULL;

-- ========================================
-- 2. Enum-like constraint for actions
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'admin_wa_audit_action_check'
  ) THEN
    ALTER TABLE admin_wa_audit_log ADD CONSTRAINT admin_wa_audit_action_check
      CHECK (action IN (
        'take',           -- Assign ticket to self
        'reply',          -- Send reply to customer
        'close',          -- Close ticket
        'assign',         -- Assign to another agent
        'escalate',       -- Escalate ticket
        'note',           -- Add internal note
        'status_change',  -- Change ticket status
        'reopen',         -- Reopen closed ticket
        'merge',          -- Merge tickets
        'tag',            -- Add/remove tags
        'priority',       -- Change priority
        'zone_create',    -- Create delivery zone
        'zone_update',    -- Update delivery zone
        'zone_delete',    -- Delete delivery zone
        'order_status',   -- Change order status
        'order_cancel',   -- Cancel order
        'refund',         -- Process refund
        'block_user',     -- Block customer
        'unblock_user',   -- Unblock customer
        'other'           -- Catch-all for future actions
      ));
    RAISE NOTICE 'Added action constraint to admin_wa_audit_log';
  END IF;
END$$;

-- ========================================
-- 3. Helper function to insert audit log
-- ========================================
CREATE OR REPLACE FUNCTION insert_admin_wa_audit(
  p_tenant_id uuid,
  p_restaurant_id uuid,
  p_actor_phone text,
  p_actor_role text,
  p_action text,
  p_target_type text DEFAULT NULL,
  p_target_id text DEFAULT NULL,
  p_command_raw text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_ip text DEFAULT NULL,
  p_success boolean DEFAULT true,
  p_error text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_id bigint;
BEGIN
  INSERT INTO admin_wa_audit_log (
    tenant_id, restaurant_id, actor_phone, actor_role, action,
    target_type, target_id, command_raw, metadata_json, ip_address,
    success, error_message
  ) VALUES (
    p_tenant_id, p_restaurant_id, p_actor_phone, COALESCE(p_actor_role, 'admin'), p_action,
    p_target_type, p_target_id, p_command_raw, COALESCE(p_metadata, '{}'::jsonb), p_ip,
    p_success, p_error
  ) RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$$;

-- ========================================
-- 4. View for recent audit activity
-- ========================================
CREATE OR REPLACE VIEW v_admin_wa_audit_recent AS
SELECT 
  a.id,
  a.actor_phone,
  a.actor_role,
  a.action,
  a.target_type,
  a.target_id,
  a.success,
  a.created_at,
  r.name AS restaurant_name
FROM admin_wa_audit_log a
LEFT JOIN restaurants r ON a.restaurant_id = r.restaurant_id
WHERE a.created_at > now() - interval '24 hours'
ORDER BY a.created_at DESC;

-- ========================================
-- 5. Retention note
-- ========================================
-- Add to W8_OPS retention job:
-- DELETE FROM admin_wa_audit_log WHERE created_at < now() - interval '90 days';

COMMENT ON TABLE admin_wa_audit_log IS 'Audit trail for all Admin WhatsApp console actions (W14). Retention: 90 days.';

COMMIT;

-- ========================================
-- ROLLBACK INSTRUCTIONS
-- ========================================
-- DROP VIEW IF EXISTS v_admin_wa_audit_recent;
-- DROP FUNCTION IF EXISTS insert_admin_wa_audit;
-- DROP TABLE IF EXISTS admin_wa_audit_log;
