-- Migration: 013_unified_identity_linking.sql
-- Description: Adds primary_phone to restaurant_users to link platform-specific IDs to a unified customer entity.

ALTER TABLE restaurant_users ADD COLUMN IF NOT EXISTS primary_phone text;

-- Create an index to quickly find all platform IDs for a given phone
CREATE INDEX IF NOT EXISTS idx_restaurant_users_primary_phone ON restaurant_users(primary_phone);

-- Helper function to link an identity
CREATE OR REPLACE FUNCTION link_customer_identity(
    p_restaurant_id uuid,
    p_channel text,
    p_user_id text,
    p_phone text
) RETURNS void AS $$
BEGIN
    INSERT INTO restaurant_users (restaurant_id, channel, user_id, role, primary_phone)
    VALUES (p_restaurant_id, p_channel, p_user_id, 'customer', p_phone)
    ON CONFLICT (restaurant_id, channel, user_id) 
    DO UPDATE SET primary_phone = EXCLUDED.primary_phone, updated_at = now();
END;
$$ LANGUAGE plpgsql;
