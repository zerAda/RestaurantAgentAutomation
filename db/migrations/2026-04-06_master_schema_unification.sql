-- =============================================================================
-- Phase X: Final Execution — Master Schema Unification (SaaS Hardening)
-- =============================================================================
-- Purpose: Unifies the Postgres bootstrap.sql schema with the Strapi Control Plane schema.
-- 
-- Fixes the following "split-brain" discrepancies:
-- 1. Renames `user_id` to `customer_userId` (platform-specific ID)
-- 2. Adds `customer_phone` (human-readable phone)
-- 3. Adds `total_amount` (numeric) matching Strapi, copies data from `total_cents`
-- 4. Adds `items_summary` (jsonb) for dashboard snapshots
-- 5. Adds `review_prompted` (boolean) for feedback tracking
-- 6. Backfills/modifies `status` to Strapi's lowercase enums (pending, confirmed)
-- 7. Drops legacy `service_mode` and replaces it with `order_type`
-- 8. Injects Strapi's managed fields (`source`, `payment_method`) with defaults
-- 9. Forces Strapi's schema control over the `orders` table.
-- =============================================================================

BEGIN;

-- 1. Rename existing identifier column if it exists as user_id
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'user_id') THEN
        ALTER TABLE orders RENAME COLUMN user_id TO "customer_userId";
    END IF;
END $$;

-- 2. Ensure Strapi required columns are present so we can backfill
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_phone TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS total_amount DECIMAL;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS items_summary JSONB;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS metadata JSONB;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS review_prompted BOOLEAN DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_type TEXT DEFAULT 'dine_in';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'kiosk';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'cash';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS id SERIAL UNIQUE; -- Support Strapi internal ID relations

-- 3. Drop the old conflicting Postgres constraints so we can mutate data
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_service_mode_check;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_payment_mode_check;

-- 4. Data Migration: Migrate total_cents -> total_amount (divided by 100)
-- Strapi expects a standard decimal (1500.00) instead of integer cents (150000)
UPDATE orders 
SET total_amount = COALESCE(total_cents, 0) / 100.0 
WHERE total_amount IS NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'total_cents');

-- 5. Data Migration: Map legacy service_mode -> order_type
UPDATE orders
SET order_type = 
  CASE 
    WHEN service_mode = 'sur_place' THEN 'dine_in'
    WHEN service_mode = 'a_emporter' THEN 'takeaway'
    WHEN service_mode = 'livraison' THEN 'delivery'
    ELSE 'dine_in'
  END
WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'service_mode');

-- 6. Data Migration: Map legacy uppercase statuses to Strapi lowercase Enums
UPDATE orders
SET status = 
  CASE 
    WHEN status IN ('NEW', 'A_CONFIRMER') THEN 'pending'
    WHEN status IN ('ACCEPTED', 'CONFIRMED') THEN 'confirmed'
    WHEN status IN ('IN_PROGRESS', 'A_PREPARER', 'EN_PREPARATION') THEN 'preparing'
    WHEN status IN ('READY') THEN 'ready'
    WHEN status IN ('DONE', 'DELIVERED') THEN 'delivered'
    WHEN status IN ('CANCELLED', 'REJETE') THEN 'cancelled'
    ELSE lower(trim(status))
  END;

-- 7. Apply new Strapi-aligned CHECK constraints
ALTER TABLE orders ADD CONSTRAINT chk_orders_status CHECK (
  status IN ('pending', 'confirmed', 'preparing', 'ready', 'delivered', 'cancelled')
);

ALTER TABLE orders ADD CONSTRAINT chk_orders_type CHECK (
  order_type IN ('dine_in', 'takeaway', 'delivery')
);

ALTER TABLE orders ADD CONSTRAINT chk_orders_source CHECK (
  source IN ('kiosk', 'whatsapp', 'instagram', 'messenger', 'tiktok', 'voice', 'web')
);

-- 8. Drop legacy overlapping columns to finalize the unification
ALTER TABLE orders DROP COLUMN IF EXISTS total_cents;
ALTER TABLE orders DROP COLUMN IF EXISTS service_mode;
ALTER TABLE orders DROP COLUMN IF EXISTS payment_mode;

COMMIT;
