-- Migration: Add 'tiktok' to channel enums
-- Created: 2026-02-03
-- Description: Updates check constraints on tables with 'channel' column to include 'tiktok'.

BEGIN;

-- 1. restaurant_users
ALTER TABLE restaurant_users DROP CONSTRAINT restaurant_users_channel_check;
ALTER TABLE restaurant_users ADD CONSTRAINT restaurant_users_channel_check 
  CHECK (channel IN ('whatsapp','instagram','messenger','tiktok'));

-- 2. conversation_state
ALTER TABLE conversation_state DROP CONSTRAINT conversation_state_channel_check;
ALTER TABLE conversation_state ADD CONSTRAINT conversation_state_channel_check 
  CHECK (channel IN ('whatsapp','instagram','messenger','tiktok'));

-- 3. orders
ALTER TABLE orders DROP CONSTRAINT orders_channel_check;
ALTER TABLE orders ADD CONSTRAINT orders_channel_check 
  CHECK (channel IN ('whatsapp','instagram','messenger','tiktok'));

-- 4. outbound_messages
ALTER TABLE outbound_messages DROP CONSTRAINT outbound_messages_channel_check;
ALTER TABLE outbound_messages ADD CONSTRAINT outbound_messages_channel_check 
  CHECK (channel IN ('whatsapp','instagram','messenger','tiktok'));

-- 5. inbound_messages
ALTER TABLE inbound_messages DROP CONSTRAINT inbound_messages_channel_check;
ALTER TABLE inbound_messages ADD CONSTRAINT inbound_messages_channel_check 
  CHECK (channel IN ('whatsapp','instagram','messenger','tiktok'));

-- 6. idempotency_keys
ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_channel_check;
ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_channel_check 
  CHECK (channel IN ('whatsapp','instagram','messenger','tiktok'));

-- 7. feedback_jobs
ALTER TABLE feedback_jobs DROP CONSTRAINT feedback_jobs_channel_check;
ALTER TABLE feedback_jobs ADD CONSTRAINT feedback_jobs_channel_check 
  CHECK (channel IN ('whatsapp','instagram','messenger','tiktok'));

COMMIT;
