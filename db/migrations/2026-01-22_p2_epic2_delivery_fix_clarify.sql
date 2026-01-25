-- EPIC2 Delivery - Fix clarification requests to work before order creation
-- Idempotent / additive.

BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='address_clarification_requests'
  ) THEN
    -- Allow creating clarification requests before an order exists
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='address_clarification_requests' AND column_name='order_id'
    ) THEN
      ALTER TABLE public.address_clarification_requests ALTER COLUMN order_id DROP NOT NULL;
    END IF;

    ALTER TABLE public.address_clarification_requests
      ADD COLUMN IF NOT EXISTS conversation_key text NULL;

    CREATE INDEX IF NOT EXISTS idx_address_clarify_conversation
      ON public.address_clarification_requests (conversation_key)
      WHERE conversation_key IS NOT NULL;
  END IF;
END
$$;

COMMIT;
