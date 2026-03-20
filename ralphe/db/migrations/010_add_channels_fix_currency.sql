-- Migration: Add missing channel types and fix currency
-- Date: 2026-03-04
-- Fixes: C-04, M-04, M-05
-- 1. Expand channel constraints to include tiktok, kiosk, voice
ALTER TABLE conversation_state DROP CONSTRAINT IF EXISTS conversation_state_channel_check;
ALTER TABLE conversation_state
ADD CONSTRAINT conversation_state_channel_check CHECK (
        channel IN (
            'whatsapp',
            'instagram',
            'messenger',
            'tiktok',
            'kiosk',
            'voice'
        )
    );
ALTER TABLE restaurant_users DROP CONSTRAINT IF EXISTS restaurant_users_channel_check;
ALTER TABLE restaurant_users
ADD CONSTRAINT restaurant_users_channel_check CHECK (
        channel IN (
            'whatsapp',
            'instagram',
            'messenger',
            'tiktok',
            'kiosk',
            'voice'
        )
    );
ALTER TABLE inbound_messages DROP CONSTRAINT IF EXISTS inbound_messages_channel_check;
ALTER TABLE inbound_messages
ADD CONSTRAINT inbound_messages_channel_check CHECK (
        channel IN (
            'whatsapp',
            'instagram',
            'messenger',
            'tiktok',
            'kiosk',
            'voice'
        )
    );
ALTER TABLE idempotency_keys DROP CONSTRAINT IF EXISTS idempotency_keys_channel_check;
ALTER TABLE idempotency_keys
ADD CONSTRAINT idempotency_keys_channel_check CHECK (
        channel IN (
            'whatsapp',
            'instagram',
            'messenger',
            'tiktok',
            'kiosk',
            'voice'
        )
    );
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_channel_check;
ALTER TABLE orders
ADD CONSTRAINT orders_channel_check CHECK (
        channel IN (
            'whatsapp',
            'instagram',
            'messenger',
            'tiktok',
            'kiosk',
            'voice'
        )
    );
ALTER TABLE feedback_jobs DROP CONSTRAINT IF EXISTS feedback_jobs_channel_check;
ALTER TABLE feedback_jobs
ADD CONSTRAINT feedback_jobs_channel_check CHECK (
        channel IN (
            'whatsapp',
            'instagram',
            'messenger',
            'tiktok',
            'kiosk',
            'voice'
        )
    );
-- 2. Fix default currency for Algerian market
ALTER TABLE restaurants
ALTER COLUMN currency
SET DEFAULT 'DZD';
-- 3. Add kiosk_order service mode
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_service_mode_check;
ALTER TABLE orders
ADD CONSTRAINT orders_service_mode_check CHECK (
        service_mode IN (
            'sur_place',
            'a_emporter',
            'livraison',
            'kiosk_sur_place',
            'kiosk_a_emporter'
        )
    );