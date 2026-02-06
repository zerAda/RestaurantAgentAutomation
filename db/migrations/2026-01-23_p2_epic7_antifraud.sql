-- EPIC 7 (P2) Anti-fraude / Anti-abus (2026-01-23)
-- Scope:
--  - Fraud rules engine (light): fraud_rules table + evaluation funcs
--  - Quarantine policies + auto-release (W8_OPS will call release_expired_quarantines)
--  - Security events: SPAM_DETECTED, BOT_SUSPECTED, QUARANTINE_*, FRAUD_CONFIRMATION_REQUIRED

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =========================
-- 1) Extend security event types (enum seeded via ops.security_event_types)
-- =========================
CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS ops.security_event_types (
  code        TEXT PRIMARY KEY,
  description TEXT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO ops.security_event_types(code, description) VALUES
  ('SPAM_DETECTED', 'Inbound spam/flood detected'),
  ('BOT_SUSPECTED', 'Inbound bot/payload suspected'),
  ('QUARANTINE_APPLIED', 'Conversation quarantined'),
  ('QUARANTINE_RELEASED', 'Conversation quarantine released'),
  ('FRAUD_CONFIRMATION_REQUIRED', 'Checkout requires explicit confirmation')
ON CONFLICT (code) DO NOTHING;

-- Ensure enum exists and contains values (compatible with previous migration)
DO $$
DECLARE
  r RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'security_event_type_enum') THEN
    -- if the P1 migration wasn't applied, create a minimal enum then extend
    EXECUTE 'CREATE TYPE security_event_type_enum AS ENUM (\'AUTH_DENY\')';
  END IF;

  FOR r IN SELECT code FROM ops.security_event_types ORDER BY code LOOP
    BEGIN
      EXECUTE format('ALTER TYPE security_event_type_enum ADD VALUE %L', r.code);
    EXCEPTION WHEN duplicate_object THEN
      NULL;
    END;
  END LOOP;
END $$;

-- Convert column if needed
DO $$
DECLARE
  v_udt_name TEXT;
BEGIN
  IF to_regclass('public.security_events') IS NULL THEN
    RETURN;
  END IF;

  SELECT udt_name INTO v_udt_name
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='security_events' AND column_name='event_type';

  IF v_udt_name IS NOT NULL AND v_udt_name <> 'security_event_type_enum' THEN
    ALTER TABLE public.security_events
      ALTER COLUMN event_type TYPE security_event_type_enum
      USING event_type::text::security_event_type_enum;
  END IF;
END $$;

-- =========================
-- 2) conversation_quarantine policies (non-breaking)
-- =========================
ALTER TABLE public.conversation_quarantine
  ADD COLUMN IF NOT EXISTS release_policy text NOT NULL DEFAULT 'AUTO_RELEASE' CHECK (release_policy IN ('AUTO_RELEASE','CONFIRMATION','MANUAL')),
  ADD COLUMN IF NOT EXISTS released_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS released_reason text NULL,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_quarantine_active_expires
  ON public.conversation_quarantine (active, expires_at);

CREATE INDEX IF NOT EXISTS idx_quarantine_conv_active
  ON public.conversation_quarantine (conversation_key, active);

-- =========================
-- 3) Fraud rules table
-- =========================
CREATE TABLE IF NOT EXISTS public.fraud_rules (
  rule_id      bigserial PRIMARY KEY,
  rule_key     text NOT NULL UNIQUE,
  scope        text NOT NULL CHECK (scope IN ('INBOUND','CHECKOUT')),
  action       text NOT NULL CHECK (action IN ('ALLOW','THROTTLE','REQUIRE_CONFIRMATION','QUARANTINE')),
  score        int  NOT NULL DEFAULT 0,
  params_json  jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fraud_rules_scope_active
  ON public.fraud_rules (scope, is_active);

-- Seed baseline rules (idempotent)
INSERT INTO public.fraud_rules(rule_key, scope, action, score, params_json) VALUES
  -- Inbound (mainly for auditing; enforcement is in workflows)
  ('IN_FLOOD_30S', 'INBOUND', 'QUARANTINE', 80, '{"limit_30s":6,"quarantine_minutes":10}'::jsonb),
  ('IN_LONG_TEXT', 'INBOUND', 'THROTTLE', 20, '{"max_len":1200}'::jsonb),

  -- Checkout
  ('CO_HIGH_ORDER_TOTAL', 'CHECKOUT', 'REQUIRE_CONFIRMATION', 70, '{"threshold_cents":30000,"confirm_ttl_minutes":10}'::jsonb),
  ('CO_REPEAT_CANCELLED_7D', 'CHECKOUT', 'QUARANTINE', 90, '{"cancel_limit":3,"window_days":7,"quarantine_minutes":30}'::jsonb)
ON CONFLICT (rule_key) DO NOTHING;

-- =========================
-- 4) Helpers: compute cart total (same pricing logic as create_order)
-- =========================
CREATE OR REPLACE FUNCTION public.compute_cart_total(p_conversation_key text)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  v_restaurant uuid;
  v_cart jsonb;
  v_total int := 0;
BEGIN
  SELECT restaurant_id INTO v_restaurant
  FROM public.conversation_state
  WHERE conversation_key = p_conversation_key;

  IF v_restaurant IS NULL THEN
    RETURN 0;
  END IF;

  SELECT cart_json INTO v_cart
  FROM public.carts
  WHERE conversation_key = p_conversation_key;

  v_cart := COALESCE(v_cart, '{"items":[]}'::jsonb);

  WITH lines AS (
    SELECT
      (elem->>'item')::text AS item_code,
      GREATEST(1, LEAST(20, COALESCE((elem->>'qty')::int, 1))) AS qty,
      COALESCE(elem->'options','[]'::jsonb) AS options_json
    FROM jsonb_array_elements(COALESCE(v_cart->'items','[]'::jsonb)) elem
  ),
  priced AS (
    SELECT
      l.item_code,
      l.qty,
      mi.price_cents AS base_cents,
      COALESCE((
        SELECT SUM(mo.price_delta_cents)
        FROM jsonb_array_elements_text(l.options_json) oc(option_code)
        JOIN public.menu_item_options mo
          ON mo.restaurant_id = v_restaurant
         AND mo.option_code = oc.option_code
      ),0) AS opt_cents
    FROM lines l
    JOIN public.menu_items mi
      ON mi.restaurant_id = v_restaurant
     AND mi.item_code = l.item_code
     AND mi.active = true
  )
  SELECT COALESCE(SUM((base_cents + opt_cents) * qty),0)::int
    INTO v_total
  FROM priced;

  RETURN COALESCE(v_total,0);
END;
$$;

-- =========================
-- 5) Quarantine apply + auto-release
-- =========================
CREATE OR REPLACE FUNCTION public.apply_quarantine(
  p_conversation_key text,
  p_reason text,
  p_expires_at timestamptz,
  p_release_policy text DEFAULT 'AUTO_RELEASE'
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_id bigint;
  v_tenant uuid;
  v_restaurant uuid;
  v_channel text;
  v_user text;
BEGIN
  SELECT tenant_id, restaurant_id, channel, user_id
    INTO v_tenant, v_restaurant, v_channel, v_user
  FROM public.conversation_state
  WHERE conversation_key = p_conversation_key;

  INSERT INTO public.conversation_quarantine(conversation_key, reason, active, expires_at, release_policy, updated_at)
  VALUES (p_conversation_key, p_reason, true, p_expires_at, p_release_policy, now())
  RETURNING id INTO v_id;

  INSERT INTO public.security_events(tenant_id, restaurant_id, conversation_key, channel, user_id, event_type, severity, payload_json)
  VALUES (v_tenant, v_restaurant, p_conversation_key, v_channel, v_user, 'QUARANTINE_APPLIED', 'MEDIUM', jsonb_build_object('reason',p_reason,'expires_at',p_expires_at,'policy',p_release_policy));

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_expired_quarantines(p_limit int DEFAULT 50)
RETURNS TABLE(
  quarantine_id bigint,
  conversation_key text,
  tenant_id uuid,
  restaurant_id uuid,
  channel text,
  user_id text,
  reason text,
  expires_at timestamptz
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT q.id
    FROM public.conversation_quarantine q
    WHERE q.active = true
      AND q.expires_at IS NOT NULL
      AND q.expires_at <= now()
      AND q.release_policy = 'AUTO_RELEASE'
    ORDER BY q.expires_at ASC
    LIMIT GREATEST(1, p_limit)
    FOR UPDATE SKIP LOCKED
  ), upd AS (
    UPDATE public.conversation_quarantine q
       SET active=false,
           released_at=now(),
           released_reason='AUTO_RELEASE',
           updated_at=now()
     WHERE q.id IN (SELECT id FROM due)
     RETURNING q.*
  )
  SELECT
    u.id,
    u.conversation_key,
    cs.tenant_id,
    cs.restaurant_id,
    cs.channel,
    cs.user_id,
    u.reason,
    u.expires_at
  FROM upd u
  JOIN public.conversation_state cs ON cs.conversation_key=u.conversation_key;

  -- Log security events for released quarantines
  INSERT INTO public.security_events(tenant_id, restaurant_id, conversation_key, channel, user_id, event_type, severity, payload_json)
  SELECT
    cs.tenant_id, cs.restaurant_id, u.conversation_key, cs.channel, cs.user_id,
    'QUARANTINE_RELEASED', 'LOW', jsonb_build_object('reason',u.reason,'expires_at',u.expires_at)
  FROM public.conversation_quarantine u
  JOIN public.conversation_state cs ON cs.conversation_key=u.conversation_key
  WHERE u.released_at IS NOT NULL AND u.released_reason='AUTO_RELEASE'
    AND u.updated_at > (now() - interval '2 minutes');

END;
$$;

-- =========================
-- 6) Checkout fraud evaluation + confirmation flow
-- =========================
CREATE OR REPLACE FUNCTION public.fraud_eval_checkout(p_conversation_key text)
RETURNS TABLE(
  action text,
  score int,
  total_cents int,
  reason text,
  confirm_ttl_minutes int,
  quarantine_minutes int
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_total int := 0;
  v_user text;
  v_thr int := 30000;
  v_ttl int := 10;
  v_cancel_limit int := 3;
  v_window_days int := 7;
  v_quar int := 30;
  v_cancel_cnt int := 0;
BEGIN
  -- Compute cart total
  v_total := public.compute_cart_total(p_conversation_key);

  SELECT user_id INTO v_user
  FROM public.conversation_state
  WHERE conversation_key=p_conversation_key;

  -- Load rule params (if active)
  SELECT
    COALESCE((params_json->>'threshold_cents')::int, v_thr),
    COALESCE((params_json->>'confirm_ttl_minutes')::int, v_ttl)
  INTO v_thr, v_ttl
  FROM public.fraud_rules
  WHERE scope='CHECKOUT' AND rule_key='CO_HIGH_ORDER_TOTAL' AND is_active=true
  LIMIT 1;

  SELECT
    COALESCE((params_json->>'cancel_limit')::int, v_cancel_limit),
    COALESCE((params_json->>'window_days')::int, v_window_days),
    COALESCE((params_json->>'quarantine_minutes')::int, v_quar)
  INTO v_cancel_limit, v_window_days, v_quar
  FROM public.fraud_rules
  WHERE scope='CHECKOUT' AND rule_key='CO_REPEAT_CANCELLED_7D' AND is_active=true
  LIMIT 1;

  IF v_user IS NOT NULL THEN
    SELECT COUNT(*)::int INTO v_cancel_cnt
    FROM public.orders
    WHERE user_id=v_user
      AND status='CANCELLED'
      AND created_at >= (now() - make_interval(days => v_window_days));
  END IF;

  -- Rule precedence: quarantine > confirm > allow
  IF v_cancel_cnt >= v_cancel_limit THEN
    RETURN QUERY SELECT 'QUARANTINE', 90, v_total, 'REPEAT_CANCELLED', v_ttl, v_quar;
    RETURN;
  END IF;

  IF v_total >= v_thr THEN
    RETURN QUERY SELECT 'REQUIRE_CONFIRMATION', 70, v_total, 'HIGH_ORDER_TOTAL', v_ttl, 0;
    RETURN;
  END IF;

  RETURN QUERY SELECT 'ALLOW', 0, v_total, 'OK', 0, 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.fraud_request_confirmation(p_conversation_key text, p_total_cents int, p_ttl_minutes int DEFAULT 10)
RETURNS TABLE(code text, expires_at timestamptz)
LANGUAGE plpgsql
AS $$
DECLARE
  v_code text;
  v_exp timestamptz;
  v_state jsonb;
  v_tenant uuid;
  v_restaurant uuid;
  v_channel text;
  v_user text;
BEGIN
  v_code := lpad((floor(random()*10000))::int::text, 4, '0');
  v_exp := now() + make_interval(mins => GREATEST(1,p_ttl_minutes));

  SELECT tenant_id, restaurant_id, channel, user_id, COALESCE(state_json,'{}'::jsonb)
    INTO v_tenant, v_restaurant, v_channel, v_user, v_state
  FROM public.conversation_state
  WHERE conversation_key = p_conversation_key
  FOR UPDATE;

  v_state := jsonb_set(v_state, '{fraud}', jsonb_build_object(
    'pending', true,
    'code', v_code,
    'expires_at', to_char(v_exp,'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'total_cents', p_total_cents
  ), true);

  UPDATE public.conversation_state
     SET state_json = v_state,
         updated_at = now()
   WHERE conversation_key = p_conversation_key;

  INSERT INTO public.security_events(tenant_id, restaurant_id, conversation_key, channel, user_id, event_type, severity, payload_json)
  VALUES (v_tenant, v_restaurant, p_conversation_key, v_channel, v_user, 'FRAUD_CONFIRMATION_REQUIRED', 'MEDIUM', jsonb_build_object('total_cents',p_total_cents,'expires_at',v_exp));

  RETURN QUERY SELECT v_code, v_exp;
END;
$$;

CREATE OR REPLACE FUNCTION public.fraud_confirm(p_conversation_key text, p_code text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_state jsonb;
  v_fraud jsonb;
  v_code text;
  v_exp_text text;
  v_exp timestamptz;
BEGIN
  SELECT COALESCE(state_json,'{}'::jsonb) INTO v_state
  FROM public.conversation_state
  WHERE conversation_key=p_conversation_key
  FOR UPDATE;

  v_fraud := COALESCE(v_state->'fraud','{}'::jsonb);
  v_code := COALESCE(v_fraud->>'code','');
  v_exp_text := COALESCE(v_fraud->>'expires_at','');

  IF v_code = '' THEN
    RETURN false;
  END IF;

  BEGIN
    v_exp := NULLIF(v_exp_text,'')::timestamptz;
  EXCEPTION WHEN others THEN
    v_exp := NULL;
  END;

  IF v_exp IS NOT NULL AND v_exp < now() THEN
    -- Expired: clear pending
    v_state := v_state - 'fraud';
    UPDATE public.conversation_state SET state_json=v_state, updated_at=now() WHERE conversation_key=p_conversation_key;
    RETURN false;
  END IF;

  IF trim(p_code) = v_code THEN
    -- Confirmed: clear fraud pending
    v_state := v_state - 'fraud';
    UPDATE public.conversation_state SET state_json=v_state, updated_at=now() WHERE conversation_key=p_conversation_key;
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- =========================
-- 7) Message templates (FR/AR)
-- =========================
INSERT INTO public.message_templates(template_key, locale, content, variables, tenant_id)
VALUES
  ('FRAUD_CONFIRM_REQUIRED','fr','⚠️ Montant élevé détecté. Pour confirmer, réponds : CONFIRM {{code}} (valable {{minutes}} min).','["code","minutes"]'::jsonb,'_GLOBAL'),
  ('FRAUD_CONFIRM_REQUIRED','ar','⚠️ تم اكتشاف مبلغ مرتفع. للتأكيد أرسل: CONFIRM {{code}} (صالحة لمدة {{minutes}} دقيقة).','["code","minutes"]'::jsonb,'_GLOBAL'),
  ('FRAUD_CONFIRM_INVALID','fr','❌ Code incorrect ou expiré. Réessaie : CONFIRM {{code}} ou relance la commande.','["code"]'::jsonb,'_GLOBAL'),
  ('FRAUD_CONFIRM_INVALID','ar','❌ الرمز غير صحيح أو منتهي. أعد المحاولة: CONFIRM {{code}} أو أعد تأكيد الطلب.','["code"]'::jsonb,'_GLOBAL'),
  ('FRAUD_THROTTLED','fr','⏳ Trop de requêtes. Merci de ralentir et réessayer.','[]'::jsonb,'_GLOBAL'),
  ('FRAUD_THROTTLED','ar','⏳ طلبات كثيرة. من فضلك تمهّل ثم أعد المحاولة.','[]'::jsonb,'_GLOBAL'),
  ('FRAUD_QUARANTINED','fr','🔒 Activité suspecte détectée. Ton accès est temporairement limité, réessaye plus tard.','[]'::jsonb,'_GLOBAL'),
  ('FRAUD_QUARANTINED','ar','🔒 تم رصد نشاط مشبوه. تم تقييد الوصول مؤقتًا، أعد المحاولة لاحقًا.','[]'::jsonb,'_GLOBAL'),
  ('FRAUD_RELEASED','fr','✅ Accès rétabli. Tu peux reprendre.','[]'::jsonb,'_GLOBAL'),
  ('FRAUD_RELEASED','ar','✅ تم رفع التقييد. يمكنك المتابعة.','[]'::jsonb,'_GLOBAL')
ON CONFLICT DO NOTHING;

COMMIT;
