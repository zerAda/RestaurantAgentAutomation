-- =========================
-- P0 Security Patches - 2026-01-23
-- AGENT 02: Disable Legacy Shared Token Migration
-- =========================
-- Safe: idempotent, additive only, no breaking changes

BEGIN;

-- ========================================
-- 1. Enhance api_clients for migration tracking
-- ========================================
DO $$
BEGIN
  -- Add migration tracking column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'api_clients' AND column_name = 'legacy_migrated_at'
  ) THEN
    ALTER TABLE api_clients ADD COLUMN legacy_migrated_at timestamptz NULL;
    RAISE NOTICE 'Added legacy_migrated_at column to api_clients';
  END IF;

  -- Add token rotation tracking
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'api_clients' AND column_name = 'token_rotated_at'
  ) THEN
    ALTER TABLE api_clients ADD COLUMN token_rotated_at timestamptz NULL;
    RAISE NOTICE 'Added token_rotated_at column to api_clients';
  END IF;

  -- Add last_used_at for audit
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'api_clients' AND column_name = 'last_used_at'
  ) THEN
    ALTER TABLE api_clients ADD COLUMN last_used_at timestamptz NULL;
    RAISE NOTICE 'Added last_used_at column to api_clients';
  END IF;
END$$;

-- ========================================
-- 2. Create token_usage_log for audit trail
-- ========================================
CREATE TABLE IF NOT EXISTS token_usage_log (
  id              bigserial PRIMARY KEY,
  client_id       uuid REFERENCES api_clients(client_id) ON DELETE SET NULL,
  token_hash      text NOT NULL,
  endpoint        text NOT NULL,
  ip_address      text,
  user_agent      text,
  success         boolean NOT NULL DEFAULT true,
  failure_reason  text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Index for recent lookups
CREATE INDEX IF NOT EXISTS idx_token_usage_log_client_time 
  ON token_usage_log(client_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_token_usage_log_hash_time 
  ON token_usage_log(token_hash, created_at DESC);

-- ========================================
-- 3. Register security event types for token tracking
-- ========================================
-- Add enum values for token-related events (safe outside subtransaction)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'security_event_type_enum') THEN
    BEGIN EXECUTE 'ALTER TYPE security_event_type_enum ADD VALUE IF NOT EXISTS ''LEGACY_TOKEN_ATTEMPT'''; EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN EXECUTE 'ALTER TYPE security_event_type_enum ADD VALUE IF NOT EXISTS ''TOKEN_ROTATED'''; EXCEPTION WHEN duplicate_object THEN NULL; END;
  END IF;
END$$;

-- ========================================
-- 4. Function to log token usage
-- ========================================
CREATE OR REPLACE FUNCTION log_token_usage(
  p_client_id uuid,
  p_token_hash text,
  p_endpoint text,
  p_ip text DEFAULT NULL,
  p_ua text DEFAULT NULL,
  p_success boolean DEFAULT true,
  p_failure_reason text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO token_usage_log (client_id, token_hash, endpoint, ip_address, user_agent, success, failure_reason)
  VALUES (p_client_id, p_token_hash, p_endpoint, p_ip, p_ua, p_success, p_failure_reason);
  
  -- Update last_used_at on client
  IF p_client_id IS NOT NULL AND p_success THEN
    UPDATE api_clients SET last_used_at = now() WHERE client_id = p_client_id;
  END IF;
END;
$$;

-- ========================================
-- 5. Mark existing clients as migrated
-- ========================================
UPDATE api_clients 
SET legacy_migrated_at = now() 
WHERE legacy_migrated_at IS NULL 
  AND is_active = true;

-- ========================================
-- 6. Retention for token_usage_log (keep 90 days)
-- ========================================
-- Note: Add to W8_OPS retention job:
-- DELETE FROM token_usage_log WHERE created_at < now() - interval '90 days';

COMMIT;

-- ========================================
-- ROLLBACK INSTRUCTIONS
-- ========================================
-- To rollback, run:
-- ALTER TABLE api_clients DROP COLUMN IF EXISTS legacy_migrated_at;
-- ALTER TABLE api_clients DROP COLUMN IF EXISTS token_rotated_at;
-- ALTER TABLE api_clients DROP COLUMN IF EXISTS last_used_at;
-- DROP TABLE IF EXISTS token_usage_log;
-- DROP FUNCTION IF EXISTS log_token_usage;
