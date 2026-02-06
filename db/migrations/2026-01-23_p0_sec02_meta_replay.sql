-- =============================================================================
-- Migration: P0-SEC-02 - Meta Webhook Signature Validation + Anti-Replay
-- Date: 2026-01-23
-- Ticket: P0-SEC-02
-- 
-- Purpose:
-- 1. Store message hashes for replay detection
-- 2. Add new security event types for signature validation
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. Anti-replay table for webhook message deduplication
-- =============================================================================
CREATE TABLE IF NOT EXISTS webhook_replay_guard (
    id              BIGSERIAL PRIMARY KEY,
    message_hash    VARCHAR(64) NOT NULL,  -- SHA256 hex of payload
    message_id      VARCHAR(255),          -- Meta message ID if available
    channel         VARCHAR(20) NOT NULL DEFAULT 'whatsapp',
    received_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Composite unique to prevent exact duplicates
    CONSTRAINT uq_replay_guard_hash_channel UNIQUE (message_hash, channel)
);

-- Index for fast lookup and cleanup
CREATE INDEX IF NOT EXISTS idx_replay_guard_received_at 
    ON webhook_replay_guard(received_at);

CREATE INDEX IF NOT EXISTS idx_replay_guard_message_id 
    ON webhook_replay_guard(message_id) 
    WHERE message_id IS NOT NULL;

-- =============================================================================
-- 2. Add new security event types
-- =============================================================================
DO $$
BEGIN
    -- Add signature-related event types
    INSERT INTO ops.security_event_types (code, description)
    VALUES
        ('WA_SIGNATURE_INVALID', 'WhatsApp webhook signature validation failed'),
        ('WA_SIGNATURE_MISSING', 'WhatsApp webhook missing X-Hub-Signature-256 header'),
        ('WA_REPLAY_DETECTED', 'Duplicate webhook message detected (replay attack)'),
        ('WA_REPLAY_BLOCKED', 'Replay attack blocked'),
        ('LEGACY_TOKEN_BLOCKED', 'Legacy shared token usage blocked'),
        ('LEGACY_TOKEN_USED', 'Legacy shared token used (deprecated)')
    ON CONFLICT (code) DO UPDATE SET
        description = EXCLUDED.description;
EXCEPTION
    WHEN undefined_table THEN
        -- ops.security_event_types might not exist in all environments
        RAISE NOTICE 'Table ops.security_event_types not found, skipping event type registration';
END $$;

-- =============================================================================
-- 3. Cleanup job helper: Remove old replay guard entries
-- =============================================================================
CREATE OR REPLACE FUNCTION cleanup_replay_guard(
    retention_minutes INT DEFAULT 10
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM webhook_replay_guard
    WHERE received_at < NOW() - (retention_minutes || ' minutes')::INTERVAL;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

COMMENT ON FUNCTION cleanup_replay_guard IS 
    'Removes replay guard entries older than retention_minutes (default 10)';

-- =============================================================================
-- 4. Helper function to check and record message for replay
-- =============================================================================
CREATE OR REPLACE FUNCTION check_replay_guard(
    p_message_hash VARCHAR(64),
    p_channel VARCHAR(20) DEFAULT 'whatsapp',
    p_message_id VARCHAR(255) DEFAULT NULL
)
RETURNS TABLE(is_replay BOOLEAN, first_seen_at TIMESTAMPTZ)
LANGUAGE plpgsql
AS $$
DECLARE
    existing_record RECORD;
BEGIN
    -- Try to find existing entry
    SELECT received_at INTO existing_record
    FROM webhook_replay_guard
    WHERE message_hash = p_message_hash AND channel = p_channel;
    
    IF FOUND THEN
        -- It's a replay
        RETURN QUERY SELECT TRUE, existing_record.received_at;
    ELSE
        -- New message - insert and return not-replay
        INSERT INTO webhook_replay_guard (message_hash, message_id, channel)
        VALUES (p_message_hash, p_message_id, p_channel)
        ON CONFLICT (message_hash, channel) DO NOTHING;
        
        RETURN QUERY SELECT FALSE, NOW();
    END IF;
END;
$$;

COMMENT ON FUNCTION check_replay_guard IS 
    'Returns TRUE if message was already seen (replay), FALSE if new. Automatically records new messages.';

-- =============================================================================
-- 5. Grant permissions
-- =============================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n') THEN
    EXECUTE 'GRANT SELECT, INSERT, DELETE ON webhook_replay_guard TO n8n';
    EXECUTE 'GRANT USAGE, SELECT ON SEQUENCE webhook_replay_guard_id_seq TO n8n';
    EXECUTE 'GRANT EXECUTE ON FUNCTION cleanup_replay_guard TO n8n';
    EXECUTE 'GRANT EXECUTE ON FUNCTION check_replay_guard TO n8n';
  END IF;
END $$;

COMMIT;

-- =============================================================================
-- ROLLBACK INSTRUCTIONS:
-- DROP FUNCTION IF EXISTS check_replay_guard;
-- DROP FUNCTION IF EXISTS cleanup_replay_guard;
-- DROP TABLE IF EXISTS webhook_replay_guard;
-- =============================================================================
