-- =============================================================================
-- P2-DZ-01: COD Flow + No-Show Scoring + Admin Controls (Algeria)
-- =============================================================================
-- Adds payment tracking to orders and functions for no-show management
-- =============================================================================

-- 1. Add payment columns to orders table
-- =============================================================================
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS payment_mode TEXT DEFAULT 'COD'
    CHECK (payment_mode IN ('COD', 'DEPOSIT_COD', 'CIB', 'EDAHABIA', 'FREE', 'PREPAID'));

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'PENDING'
    CHECK (payment_status IN ('PENDING', 'DEPOSIT_REQUESTED', 'DEPOSIT_PAID', 'CONFIRMED', 'COLLECTED', 'COMPLETED', 'FAILED', 'REFUNDED', 'CANCELLED', 'NO_SHOW'));

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS payment_intent_id UUID NULL;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS delivery_address TEXT NULL;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS delivery_notes TEXT NULL;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS customer_phone TEXT NULL;

-- Add indexes for payment queries
CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON orders(payment_status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_payment_mode ON orders(payment_mode);
CREATE INDEX IF NOT EXISTS idx_orders_user_status ON orders(user_id, status, created_at DESC);

-- 2. Ensure customer_payment_profiles table exists with all needed columns
-- =============================================================================
CREATE TABLE IF NOT EXISTS customer_payment_profiles (
  id                  BIGSERIAL PRIMARY KEY,
  user_id             TEXT NOT NULL UNIQUE,
  tenant_id           UUID NOT NULL,
  total_orders        INTEGER NOT NULL DEFAULT 0,
  completed_orders    INTEGER NOT NULL DEFAULT 0,
  cancelled_orders    INTEGER NOT NULL DEFAULT 0,
  no_show_count       INTEGER NOT NULL DEFAULT 0,
  trust_score         INTEGER NOT NULL DEFAULT 50 CHECK (trust_score BETWEEN 0 AND 100),
  requires_deposit    BOOLEAN NOT NULL DEFAULT false,
  soft_blacklisted    BOOLEAN NOT NULL DEFAULT false,
  blacklist_reason    TEXT NULL,
  blacklist_until     TIMESTAMPTZ NULL,
  last_order_at       TIMESTAMPTZ NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cpp_tenant ON customer_payment_profiles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_cpp_trust ON customer_payment_profiles(trust_score);
CREATE INDEX IF NOT EXISTS idx_cpp_blacklist ON customer_payment_profiles(soft_blacklisted) WHERE soft_blacklisted = true;

-- 3. Function: Get or create customer payment profile
-- =============================================================================
CREATE OR REPLACE FUNCTION get_customer_profile(
  p_user_id TEXT,
  p_tenant_id UUID
)
RETURNS customer_payment_profiles
LANGUAGE plpgsql
AS $$
DECLARE
  v_profile customer_payment_profiles;
BEGIN
  SELECT * INTO v_profile
  FROM customer_payment_profiles
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    INSERT INTO customer_payment_profiles (user_id, tenant_id)
    VALUES (p_user_id, p_tenant_id)
    RETURNING * INTO v_profile;
  END IF;

  RETURN v_profile;
END;
$$;

-- 4. Function: Mark order as NO_SHOW and update customer score
-- =============================================================================
CREATE OR REPLACE FUNCTION mark_order_noshow(
  p_order_id UUID,
  p_admin_user_id TEXT DEFAULT NULL
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  new_trust_score INTEGER,
  new_no_show_count INTEGER,
  blacklisted BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_order orders;
  v_profile customer_payment_profiles;
  v_new_score INTEGER;
  v_blacklisted BOOLEAN := false;
BEGIN
  -- Get order
  SELECT * INTO v_order FROM orders WHERE order_id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Order not found'::TEXT, 0, 0, false;
    RETURN;
  END IF;

  -- Check if already marked
  IF v_order.payment_status = 'NO_SHOW' THEN
    RETURN QUERY SELECT false, 'Order already marked as no-show'::TEXT, 0, 0, false;
    RETURN;
  END IF;

  -- Check valid status (only NEW, ACCEPTED, IN_PROGRESS, READY can be no-show)
  IF v_order.status NOT IN ('NEW', 'ACCEPTED', 'IN_PROGRESS', 'READY') THEN
    RETURN QUERY SELECT false, 'Invalid order status for no-show'::TEXT, 0, 0, false;
    RETURN;
  END IF;

  -- Update order
  UPDATE orders SET
    status = 'CANCELLED',
    payment_status = 'NO_SHOW',
    updated_at = now()
  WHERE order_id = p_order_id;

  -- Get or create customer profile
  SELECT * INTO v_profile
  FROM customer_payment_profiles
  WHERE user_id = v_order.user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO customer_payment_profiles (user_id, tenant_id, no_show_count, trust_score)
    VALUES (v_order.user_id, v_order.tenant_id, 1, 30) -- -20 from default 50
    RETURNING * INTO v_profile;
    v_new_score := 30;
  ELSE
    -- Update no-show count and decrease trust score by 20
    v_new_score := GREATEST(0, v_profile.trust_score - 20);

    UPDATE customer_payment_profiles SET
      no_show_count = no_show_count + 1,
      trust_score = v_new_score,
      -- Auto-blacklist after 2+ no-shows
      soft_blacklisted = CASE WHEN (no_show_count + 1) >= 2 THEN true ELSE soft_blacklisted END,
      blacklist_reason = CASE WHEN (no_show_count + 1) >= 2 THEN 'AUTO_NOSHOW_LIMIT' ELSE blacklist_reason END,
      blacklist_until = CASE WHEN (no_show_count + 1) >= 2 THEN now() + interval '30 days' ELSE blacklist_until END,
      requires_deposit = true, -- Always require deposit after no-show
      updated_at = now()
    WHERE user_id = v_order.user_id
    RETURNING * INTO v_profile;
  END IF;

  v_blacklisted := v_profile.soft_blacklisted;

  -- Log security event
  INSERT INTO security_events (tenant_id, restaurant_id, conversation_key, channel, user_id, event_type, severity, payload_json)
  VALUES (
    v_order.tenant_id,
    v_order.restaurant_id,
    NULL,
    v_order.channel,
    v_order.user_id,
    'ORDER_NO_SHOW',
    'MEDIUM',
    jsonb_build_object(
      'order_id', p_order_id,
      'total_cents', v_order.total_cents,
      'admin_user_id', p_admin_user_id,
      'new_trust_score', v_new_score,
      'new_no_show_count', v_profile.no_show_count,
      'blacklisted', v_blacklisted
    )
  );

  RETURN QUERY SELECT
    true,
    'Order marked as no-show'::TEXT,
    v_profile.trust_score,
    v_profile.no_show_count,
    v_blacklisted;
END;
$$;

-- 5. Function: Mark order as DELIVERED and update customer score
-- =============================================================================
CREATE OR REPLACE FUNCTION mark_order_delivered(
  p_order_id UUID,
  p_admin_user_id TEXT DEFAULT NULL
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  new_trust_score INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_order orders;
  v_profile customer_payment_profiles;
  v_new_score INTEGER;
BEGIN
  -- Get order
  SELECT * INTO v_order FROM orders WHERE order_id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Order not found'::TEXT, 0;
    RETURN;
  END IF;

  -- Check valid status
  IF v_order.status NOT IN ('NEW', 'ACCEPTED', 'IN_PROGRESS', 'READY') THEN
    RETURN QUERY SELECT false, 'Order already completed or cancelled'::TEXT, 0;
    RETURN;
  END IF;

  -- Update order
  UPDATE orders SET
    status = 'DONE',
    payment_status = 'COLLECTED',
    updated_at = now()
  WHERE order_id = p_order_id;

  -- Get or create customer profile and increase trust
  SELECT * INTO v_profile
  FROM customer_payment_profiles
  WHERE user_id = v_order.user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO customer_payment_profiles (user_id, tenant_id, completed_orders, trust_score)
    VALUES (v_order.user_id, v_order.tenant_id, 1, 55) -- +5 from default 50
    RETURNING * INTO v_profile;
    v_new_score := 55;
  ELSE
    v_new_score := LEAST(100, v_profile.trust_score + 5);

    UPDATE customer_payment_profiles SET
      completed_orders = completed_orders + 1,
      trust_score = v_new_score,
      last_order_at = now(),
      -- Auto-lift blacklist if score recovers above 70 and no recent no-shows
      soft_blacklisted = CASE
        WHEN soft_blacklisted AND v_new_score >= 70 AND blacklist_until < now() THEN false
        ELSE soft_blacklisted
      END,
      -- Remove deposit requirement if trusted
      requires_deposit = CASE
        WHEN (completed_orders + 1) >= 3 AND v_new_score >= 70 THEN false
        ELSE requires_deposit
      END,
      updated_at = now()
    WHERE user_id = v_order.user_id
    RETURNING * INTO v_profile;
  END IF;

  -- Log security event
  INSERT INTO security_events (tenant_id, restaurant_id, conversation_key, channel, user_id, event_type, severity, payload_json)
  VALUES (
    v_order.tenant_id,
    v_order.restaurant_id,
    NULL,
    v_order.channel,
    v_order.user_id,
    'ORDER_DELIVERED',
    'LOW',
    jsonb_build_object(
      'order_id', p_order_id,
      'total_cents', v_order.total_cents,
      'admin_user_id', p_admin_user_id,
      'new_trust_score', v_new_score,
      'completed_orders', v_profile.completed_orders
    )
  );

  RETURN QUERY SELECT true, 'Order marked as delivered'::TEXT, v_profile.trust_score;
END;
$$;

-- 6. Function: Get customer risk profile for admin
-- =============================================================================
CREATE OR REPLACE FUNCTION get_customer_risk_profile(
  p_user_id TEXT
)
RETURNS TABLE(
  user_id TEXT,
  trust_score INTEGER,
  total_orders INTEGER,
  completed_orders INTEGER,
  cancelled_orders INTEGER,
  no_show_count INTEGER,
  requires_deposit BOOLEAN,
  soft_blacklisted BOOLEAN,
  blacklist_reason TEXT,
  blacklist_until TIMESTAMPTZ,
  risk_level TEXT,
  last_order_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_profile customer_payment_profiles;
  v_risk TEXT;
BEGIN
  SELECT * INTO v_profile
  FROM customer_payment_profiles cpp
  WHERE cpp.user_id = p_user_id;

  IF NOT FOUND THEN
    -- New customer, no history
    RETURN QUERY SELECT
      p_user_id,
      50::INTEGER,
      0::INTEGER,
      0::INTEGER,
      0::INTEGER,
      0::INTEGER,
      false,
      false,
      NULL::TEXT,
      NULL::TIMESTAMPTZ,
      'NEW'::TEXT,
      NULL::TIMESTAMPTZ;
    RETURN;
  END IF;

  -- Calculate risk level
  IF v_profile.soft_blacklisted THEN
    v_risk := 'BLACKLISTED';
  ELSIF v_profile.trust_score < 30 THEN
    v_risk := 'HIGH';
  ELSIF v_profile.trust_score < 50 THEN
    v_risk := 'MEDIUM';
  ELSIF v_profile.trust_score < 70 THEN
    v_risk := 'LOW';
  ELSE
    v_risk := 'TRUSTED';
  END IF;

  RETURN QUERY SELECT
    v_profile.user_id,
    v_profile.trust_score,
    v_profile.total_orders,
    v_profile.completed_orders,
    v_profile.cancelled_orders,
    v_profile.no_show_count,
    v_profile.requires_deposit,
    v_profile.soft_blacklisted,
    v_profile.blacklist_reason,
    v_profile.blacklist_until,
    v_risk,
    v_profile.last_order_at;
END;
$$;

-- 7. Function: Blacklist customer manually
-- =============================================================================
CREATE OR REPLACE FUNCTION blacklist_customer(
  p_user_id TEXT,
  p_tenant_id UUID,
  p_reason TEXT,
  p_duration_days INTEGER DEFAULT 30,
  p_admin_user_id TEXT DEFAULT NULL
)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_profile customer_payment_profiles;
BEGIN
  -- Get or create profile
  SELECT * INTO v_profile
  FROM customer_payment_profiles
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO customer_payment_profiles (
      user_id, tenant_id, soft_blacklisted, blacklist_reason, blacklist_until, trust_score
    )
    VALUES (
      p_user_id, p_tenant_id, true, p_reason, now() + (p_duration_days || ' days')::interval, 0
    );
  ELSE
    UPDATE customer_payment_profiles SET
      soft_blacklisted = true,
      blacklist_reason = p_reason,
      blacklist_until = now() + (p_duration_days || ' days')::interval,
      trust_score = 0,
      updated_at = now()
    WHERE user_id = p_user_id;
  END IF;

  -- Log security event
  INSERT INTO security_events (tenant_id, restaurant_id, channel, user_id, event_type, severity, payload_json)
  VALUES (
    p_tenant_id, NULL, 'whatsapp', p_user_id, 'CUSTOMER_BLACKLISTED', 'HIGH',
    jsonb_build_object('reason', p_reason, 'duration_days', p_duration_days, 'admin_user_id', p_admin_user_id)
  );

  RETURN QUERY SELECT true, 'Customer blacklisted for ' || p_duration_days || ' days';
END;
$$;

-- 8. Function: Unblacklist customer
-- =============================================================================
CREATE OR REPLACE FUNCTION unblacklist_customer(
  p_user_id TEXT,
  p_admin_user_id TEXT DEFAULT NULL
)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE customer_payment_profiles SET
    soft_blacklisted = false,
    blacklist_reason = NULL,
    blacklist_until = NULL,
    trust_score = GREATEST(30, trust_score), -- Restore minimum 30
    updated_at = now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Customer not found';
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'Customer unblacklisted';
END;
$$;

-- 9. Function: Get recent orders for admin
-- =============================================================================
CREATE OR REPLACE FUNCTION get_recent_orders(
  p_restaurant_id UUID,
  p_limit INTEGER DEFAULT 20,
  p_status TEXT DEFAULT NULL
)
RETURNS TABLE(
  order_id UUID,
  user_id TEXT,
  status TEXT,
  payment_mode TEXT,
  payment_status TEXT,
  total_cents INTEGER,
  service_mode TEXT,
  channel TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
AS $$
  SELECT
    o.order_id,
    o.user_id,
    o.status,
    COALESCE(o.payment_mode, 'COD') as payment_mode,
    COALESCE(o.payment_status, 'PENDING') as payment_status,
    o.total_cents,
    o.service_mode,
    o.channel,
    o.created_at
  FROM orders o
  WHERE o.restaurant_id = p_restaurant_id
    AND (p_status IS NULL OR o.status = p_status)
  ORDER BY o.created_at DESC
  LIMIT p_limit;
$$;

-- 10. Function: Get order details for admin
-- =============================================================================
CREATE OR REPLACE FUNCTION get_order_details(
  p_order_id UUID
)
RETURNS TABLE(
  order_id UUID,
  user_id TEXT,
  status TEXT,
  payment_mode TEXT,
  payment_status TEXT,
  total_cents INTEGER,
  service_mode TEXT,
  channel TEXT,
  delivery_address TEXT,
  customer_phone TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  items_json JSONB,
  customer_trust_score INTEGER,
  customer_no_show_count INTEGER
)
LANGUAGE sql
AS $$
  SELECT
    o.order_id,
    o.user_id,
    o.status,
    COALESCE(o.payment_mode, 'COD'),
    COALESCE(o.payment_status, 'PENDING'),
    o.total_cents,
    o.service_mode,
    o.channel,
    o.delivery_address,
    o.customer_phone,
    o.created_at,
    o.updated_at,
    COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'item_code', oi.item_code,
        'label', oi.label,
        'qty', oi.qty,
        'unit_price', oi.unit_price_cents,
        'line_total', oi.line_total_cents
      ))
      FROM order_items oi WHERE oi.order_id = o.order_id),
      '[]'::jsonb
    ),
    COALESCE(cpp.trust_score, 50),
    COALESCE(cpp.no_show_count, 0)
  FROM orders o
  LEFT JOIN customer_payment_profiles cpp ON cpp.user_id = o.user_id
  WHERE o.order_id = p_order_id;
$$;

-- 11. Message templates for COD confirmation
-- =============================================================================
INSERT INTO message_templates (template_key, locale, content, variables, version, is_active)
VALUES
  ('COD_CONFIRMATION_REQUEST', 'fr',
   '💳 *Récapitulatif commande*\n\n{{items_summary}}\n\n*Total: {{total}} DA*\nMode: Paiement à la livraison (COD)\n\n✅ Confirmez en répondant *OUI*\n❌ Annuler: *NON*',
   '["items_summary", "total"]', 1, true),
  ('COD_CONFIRMATION_REQUEST', 'ar',
   '💳 *ملخص الطلب*\n\n{{items_summary}}\n\n*المجموع: {{total}} دج*\nالدفع: عند التوصيل\n\n✅ للتأكيد أرسل *نعم*\n❌ للإلغاء: *لا*',
   '["items_summary", "total"]', 1, true),
  ('COD_CONFIRMED', 'fr',
   '✅ *Commande confirmée!*\n\nN° {{order_id}}\nTotal: {{total}} DA (à payer à la livraison)\n\nMerci pour votre confiance! 🙏',
   '["order_id", "total"]', 1, true),
  ('COD_CONFIRMED', 'ar',
   '✅ *تم تأكيد الطلب!*\n\nرقم: {{order_id}}\nالمجموع: {{total}} دج (الدفع عند التوصيل)\n\nشكراً لثقتكم! 🙏',
   '["order_id", "total"]', 1, true),
  ('DEPOSIT_REQUIRED', 'fr',
   '⚠️ *Acompte requis*\n\nVotre historique nécessite un acompte de *{{deposit}} DA* ({{percentage}}%)\n\n💳 Envoyez l''acompte via:\n- CCP/BaridiMob: {{ccp_number}}\n\nDélai: {{timeout}} min\nPuis répondez *PAYE* avec capture',
   '["deposit", "percentage", "ccp_number", "timeout"]', 1, true),
  ('DEPOSIT_REQUIRED', 'ar',
   '⚠️ *مطلوب تسبيق*\n\nنظراً لسجلكم، يرجى دفع تسبيق *{{deposit}} دج* ({{percentage}}%)\n\n💳 أرسل التسبيق عبر:\n- CCP/BaridiMob: {{ccp_number}}\n\nالمهلة: {{timeout}} دقيقة\nثم أرسل *دفعت* مع صورة',
   '["deposit", "percentage", "ccp_number", "timeout"]', 1, true),
  ('HIGH_RISK_WARNING', 'fr',
   '⚠️ *Vérification requise*\n\nPour valider votre commande de {{total}} DA:\n1. Confirmez votre numéro: {{phone}}\n2. Confirmez l''adresse de livraison\n\nRépondez *CONFIRMER* pour continuer.',
   '["total", "phone"]', 1, true),
  ('HIGH_RISK_WARNING', 'ar',
   '⚠️ *التحقق مطلوب*\n\nلتأكيد طلبكم بقيمة {{total}} دج:\n1. أكد رقمك: {{phone}}\n2. أكد عنوان التوصيل\n\nأرسل *تأكيد* للمتابعة.',
   '["total", "phone"]', 1, true)
ON CONFLICT (template_key, locale) DO UPDATE SET
  content = EXCLUDED.content,
  variables = EXCLUDED.variables,
  version = message_templates.version + 1,
  updated_at = now();

-- 12. Event types for order management
-- =============================================================================
DO $$
BEGIN
  -- Add new event types if security_events uses an enum
  -- If it's just text, this is not needed
  NULL;
END $$;

COMMENT ON FUNCTION mark_order_noshow IS 'P2-DZ-01: Mark order as no-show, decrease customer trust score by 20, auto-blacklist after 2 no-shows';
COMMENT ON FUNCTION mark_order_delivered IS 'P2-DZ-01: Mark order as delivered, increase customer trust score by 5';
COMMENT ON FUNCTION get_customer_risk_profile IS 'P2-DZ-01: Get customer risk profile for admin console';
COMMENT ON FUNCTION blacklist_customer IS 'P2-DZ-01: Manually blacklist a customer';
