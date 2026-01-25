/*
EPIC 2 — Livraison (P2)
- DEL-001: delivery zones + quote + storage in orders
- DEL-002: address clarification requests
- DEL-003: delivery time slots + reservations

Idempotent (safe to replay).
*/

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS ops;

-- =========================
-- 1) Event types (ops.security_event_types + enum extension)
-- =========================

-- Ensure reference table exists (created in P1 migration but safe here)
CREATE TABLE IF NOT EXISTS ops.security_event_types (
  code        TEXT PRIMARY KEY,
  description TEXT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO ops.security_event_types(code, description) VALUES
  ('DELIVERY_ZONE_NOT_FOUND', 'Delivery: zone not found for wilaya/commune'),
  ('DELIVERY_ZONE_INACTIVE', 'Delivery: zone inactive'),
  ('DELIVERY_MIN_ORDER', 'Delivery: minimum order not reached'),
  ('DELIVERY_QUOTE_OK', 'Delivery: quote computed successfully'),
  ('DELIVERY_DISABLED', 'Delivery: feature disabled'),
  ('ADDRESS_AMBIGUOUS', 'Delivery: address missing/ambiguous, clarification requested'),
  ('SLOT_FULL', 'Delivery: selected time slot at capacity'),
  ('DELIVERY_SLOT_RESERVED', 'Delivery: time slot reserved for order')
ON CONFLICT (code) DO NOTHING;

-- Ensure enum exists and contains seeded values
DO $$
DECLARE
  r RECORD;
  v_vals TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'security_event_type_enum') THEN
    SELECT string_agg(quote_literal(code), ', ' ORDER BY code)
      INTO v_vals
    FROM ops.security_event_types;

    IF v_vals IS NULL THEN
      v_vals := quote_literal('RETENTION_RUN');
    END IF;

    EXECUTE format('CREATE TYPE security_event_type_enum AS ENUM (%s)', v_vals);
  END IF;

  FOR r IN SELECT code FROM ops.security_event_types ORDER BY code LOOP
    BEGIN
      EXECUTE format('ALTER TYPE security_event_type_enum ADD VALUE %L', r.code);
    EXCEPTION WHEN duplicate_object THEN
      NULL;
    END;
  END LOOP;
END $$;

-- =========================
-- 2) Orders: add delivery columns (nullable, backward compatible)
-- =========================

ALTER TABLE IF EXISTS public.orders
  ADD COLUMN IF NOT EXISTS delivery_address_json jsonb NULL,
  ADD COLUMN IF NOT EXISTS delivery_wilaya text NULL,
  ADD COLUMN IF NOT EXISTS delivery_commune text NULL,
  ADD COLUMN IF NOT EXISTS delivery_phone text NULL,
  ADD COLUMN IF NOT EXISTS delivery_fee_cents int NULL CHECK (delivery_fee_cents IS NULL OR delivery_fee_cents >= 0),
  ADD COLUMN IF NOT EXISTS delivery_eta_min int NULL CHECK (delivery_eta_min IS NULL OR delivery_eta_min >= 0),
  ADD COLUMN IF NOT EXISTS delivery_eta_max int NULL CHECK (delivery_eta_max IS NULL OR delivery_eta_max >= 0),
  ADD COLUMN IF NOT EXISTS delivery_slot_id uuid NULL,
  ADD COLUMN IF NOT EXISTS delivery_slot_start timestamptz NULL,
  ADD COLUMN IF NOT EXISTS delivery_slot_end timestamptz NULL;

-- Basic lookup index (case-insensitive)
CREATE INDEX IF NOT EXISTS idx_orders_delivery_zone
  ON public.orders (restaurant_id, lower(delivery_wilaya), lower(delivery_commune));

-- =========================
-- 3) Delivery zones + fee rules
-- =========================

CREATE TABLE IF NOT EXISTS public.delivery_zones (
  zone_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id    uuid NOT NULL REFERENCES public.restaurants(restaurant_id) ON DELETE CASCADE,
  wilaya           text NOT NULL,
  commune          text NOT NULL,
  fee_base_cents   int NOT NULL CHECK (fee_base_cents >= 0),
  min_order_cents  int NOT NULL DEFAULT 0 CHECK (min_order_cents >= 0),
  eta_min          int NOT NULL DEFAULT 45 CHECK (eta_min >= 0),
  eta_max          int NOT NULL DEFAULT 60 CHECK (eta_max >= eta_min),
  is_active        boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- Unique lookup per restaurant (case-insensitive)
CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_zones_rest_wilaya_commune
  ON public.delivery_zones (restaurant_id, lower(wilaya), lower(commune));

CREATE INDEX IF NOT EXISTS idx_delivery_zones_active
  ON public.delivery_zones (restaurant_id, is_active);

CREATE TABLE IF NOT EXISTS public.delivery_fee_rules (
  rule_id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id                  uuid NOT NULL REFERENCES public.restaurants(restaurant_id) ON DELETE CASCADE,
  name                           text NOT NULL,
  start_time                     time NOT NULL,
  end_time                       time NOT NULL,
  surcharge_cents                int NOT NULL DEFAULT 0 CHECK (surcharge_cents >= 0),
  free_delivery_threshold_cents  int NULL CHECK (free_delivery_threshold_cents IS NULL OR free_delivery_threshold_cents >= 0),
  is_active                      boolean NOT NULL DEFAULT true,
  created_at                     timestamptz NOT NULL DEFAULT now(),
  updated_at                     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_delivery_fee_rules_active
  ON public.delivery_fee_rules (restaurant_id, is_active);

-- =========================
-- 4) Address clarification requests (DEL-002)
-- =========================

CREATE TABLE IF NOT EXISTS public.address_clarification_requests (
  id            bigserial PRIMARY KEY,
  order_id      uuid NOT NULL REFERENCES public.orders(order_id) ON DELETE CASCADE,
  missing_fields jsonb NOT NULL DEFAULT '[]'::jsonb,
  attempts      int NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  status        text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','RESOLVED','HANDOFF','CANCELLED')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE(order_id)
);

CREATE INDEX IF NOT EXISTS idx_address_clarify_status
  ON public.address_clarification_requests (status, created_at DESC);

-- =========================
-- 5) Delivery time slots + reservations (DEL-003)
-- =========================

CREATE TABLE IF NOT EXISTS public.delivery_time_slots (
  slot_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(restaurant_id) ON DELETE CASCADE,
  day_of_week  smallint NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time   time NOT NULL,
  end_time     time NOT NULL,
  capacity     int NOT NULL DEFAULT 0 CHECK (capacity >= 0),
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_slots_def
  ON public.delivery_time_slots (restaurant_id, day_of_week, start_time, end_time);

CREATE INDEX IF NOT EXISTS idx_delivery_slots_active
  ON public.delivery_time_slots (restaurant_id, day_of_week, is_active);

CREATE TABLE IF NOT EXISTS public.delivery_slot_reservations (
  id          bigserial PRIMARY KEY,
  order_id    uuid NOT NULL REFERENCES public.orders(order_id) ON DELETE CASCADE,
  slot_id     uuid NOT NULL REFERENCES public.delivery_time_slots(slot_id) ON DELETE CASCADE,
  reserved_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(order_id)
);

CREATE INDEX IF NOT EXISTS idx_slot_reservations_slot
  ON public.delivery_slot_reservations (slot_id, reserved_at DESC);

-- orders.delivery_slot_id FK (guarded)
DO $$
BEGIN
  IF to_regclass('public.orders') IS NULL THEN
    RETURN;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_orders_delivery_slot'
  ) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT fk_orders_delivery_slot
      FOREIGN KEY (delivery_slot_id)
      REFERENCES public.delivery_time_slots(slot_id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- =========================
-- 6) Helper functions
-- =========================

-- Delivery quote
CREATE OR REPLACE FUNCTION public.delivery_quote(
  p_restaurant_id uuid,
  p_wilaya text,
  p_commune text,
  p_total_cents int,
  p_at timestamptz DEFAULT now()
)
RETURNS TABLE(
  zone_found boolean,
  zone_active boolean,
  fee_base_cents int,
  surcharge_cents int,
  free_threshold_cents int,
  min_order_cents int,
  eta_min int,
  eta_max int,
  final_fee_cents int,
  reason text
)
LANGUAGE plpgsql
AS $$
DECLARE
  z RECORD;
  r RECORD;
  t_local time;
  v_surcharge int := 0;
  v_free int := NULL;
BEGIN
  IF p_restaurant_id IS NULL THEN
    RETURN QUERY SELECT false,false,0,0,NULL,0,0,0,0,'DELIVERY_ZONE_NOT_FOUND';
    RETURN;
  END IF;

  SELECT * INTO z
  FROM public.delivery_zones
  WHERE restaurant_id = p_restaurant_id
    AND lower(wilaya) = lower(COALESCE(p_wilaya,''))
    AND lower(commune) = lower(COALESCE(p_commune,''))
  LIMIT 1;

  IF z.zone_id IS NULL THEN
    RETURN QUERY SELECT false,false,0,0,NULL,0,0,0,0,'DELIVERY_ZONE_NOT_FOUND';
    RETURN;
  END IF;

  IF NOT z.is_active THEN
    RETURN QUERY SELECT true,false,z.fee_base_cents,0,NULL,z.min_order_cents,z.eta_min,z.eta_max,z.fee_base_cents,'DELIVERY_ZONE_INACTIVE';
    RETURN;
  END IF;

  IF COALESCE(p_total_cents,0) < COALESCE(z.min_order_cents,0) THEN
    RETURN QUERY SELECT true,true,z.fee_base_cents,0,NULL,z.min_order_cents,z.eta_min,z.eta_max,z.fee_base_cents,'DELIVERY_MIN_ORDER';
    RETURN;
  END IF;

  -- local time in restaurant timezone (default Africa/Algiers)
  t_local := (p_at AT TIME ZONE COALESCE((SELECT timezone FROM public.restaurants WHERE restaurant_id=p_restaurant_id),'Africa/Algiers'))::time;

  -- choose the matching rule with the highest surcharge (simple rule system)
  FOR r IN
    SELECT *
    FROM public.delivery_fee_rules
    WHERE restaurant_id=p_restaurant_id
      AND is_active=true
    ORDER BY surcharge_cents DESC
  LOOP
    IF r.start_time <= r.end_time THEN
      IF t_local >= r.start_time AND t_local < r.end_time THEN
        v_surcharge := COALESCE(r.surcharge_cents,0);
        v_free := r.free_delivery_threshold_cents;
        EXIT;
      END IF;
    ELSE
      -- crosses midnight
      IF t_local >= r.start_time OR t_local < r.end_time THEN
        v_surcharge := COALESCE(r.surcharge_cents,0);
        v_free := r.free_delivery_threshold_cents;
        EXIT;
      END IF;
    END IF;
  END LOOP;

  IF v_free IS NOT NULL AND COALESCE(p_total_cents,0) >= v_free THEN
    RETURN QUERY SELECT true,true,z.fee_base_cents,v_surcharge,v_free,z.min_order_cents,z.eta_min,z.eta_max,0,'OK';
  ELSE
    RETURN QUERY SELECT true,true,z.fee_base_cents,v_surcharge,v_free,z.min_order_cents,z.eta_min,z.eta_max,(z.fee_base_cents + v_surcharge),'OK';
  END IF;
END;
$$;

-- List available slots for a given day_of_week
CREATE OR REPLACE FUNCTION public.list_delivery_slots(
  p_restaurant_id uuid,
  p_day_of_week int
)
RETURNS TABLE(
  slot_id uuid,
  day_of_week int,
  start_time time,
  end_time time,
  capacity int,
  reserved int,
  available int
)
LANGUAGE sql
AS $$
  WITH slots AS (
    SELECT s.slot_id, s.day_of_week::int AS day_of_week, s.start_time, s.end_time, s.capacity
    FROM public.delivery_time_slots s
    WHERE s.restaurant_id = p_restaurant_id
      AND s.is_active = true
      AND s.day_of_week = p_day_of_week
  ), res AS (
    SELECT r.slot_id, COUNT(*)::int AS reserved
    FROM public.delivery_slot_reservations r
    JOIN public.orders o ON o.order_id = r.order_id
    WHERE o.restaurant_id = p_restaurant_id
      AND o.status <> 'CANCELLED'
    GROUP BY r.slot_id
  )
  SELECT s.slot_id, s.day_of_week, s.start_time, s.end_time, s.capacity,
         COALESCE(res.reserved,0) AS reserved,
         GREATEST(0, s.capacity - COALESCE(res.reserved,0)) AS available
  FROM slots s
  LEFT JOIN res ON res.slot_id = s.slot_id
  ORDER BY s.start_time;
$$;

-- Reserve a slot (capacity check) and update order.delivery_slot_id
CREATE OR REPLACE FUNCTION public.reserve_delivery_slot(
  p_order_id uuid,
  p_slot_id uuid
)
RETURNS TABLE(
  ok boolean,
  reason text,
  capacity int,
  reserved int,
  available int
)
LANGUAGE plpgsql
AS $$
DECLARE
  s RECORD;
  r_cnt int;
BEGIN
  IF p_order_id IS NULL OR p_slot_id IS NULL THEN
    RETURN QUERY SELECT false,'INVALID_INPUT',0,0,0;
    RETURN;
  END IF;

  SELECT * INTO s
  FROM public.delivery_time_slots
  WHERE slot_id = p_slot_id
  FOR UPDATE;

  IF s.slot_id IS NULL OR NOT s.is_active THEN
    RETURN QUERY SELECT false,'SLOT_NOT_FOUND',0,0,0;
    RETURN;
  END IF;

  SELECT COUNT(*)::int INTO r_cnt
  FROM public.delivery_slot_reservations r
  JOIN public.orders o ON o.order_id=r.order_id
  WHERE r.slot_id = p_slot_id
    AND o.status <> 'CANCELLED';

  IF r_cnt >= s.capacity THEN
    RETURN QUERY SELECT false,'SLOT_FULL',s.capacity,r_cnt,0;
    RETURN;
  END IF;

  INSERT INTO public.delivery_slot_reservations(order_id, slot_id)
  VALUES (p_order_id, p_slot_id)
  ON CONFLICT (order_id) DO UPDATE SET slot_id=EXCLUDED.slot_id, reserved_at=now();

  UPDATE public.orders
     SET delivery_slot_id = p_slot_id,
         updated_at = now()
   WHERE order_id = p_order_id;

  RETURN QUERY SELECT true,'OK',s.capacity,r_cnt+1,GREATEST(0, s.capacity - (r_cnt+1));
END;
$$;

-- =========================
-- 7) Update create_order to persist delivery info (from conversation_state.state_json)
-- =========================

CREATE OR REPLACE FUNCTION public.create_order(p_conversation_key text)
RETURNS TABLE(
  order_id uuid,
  total_cents int,
  summary text,
  delivery_fee_cents int,
  total_payable_cents int,
  delivery_eta_min int,
  delivery_eta_max int
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_tenant uuid;
  v_restaurant uuid;
  v_channel text;
  v_user text;
  v_mode text;
  v_order uuid;
  v_stage text;
  v_last_order text;
  v_state jsonb;
  v_delivery jsonb;
  v_wilaya text;
  v_commune text;
  v_phone text;
  v_addr jsonb;
  v_items_total int := 0;
  q RECORD;
  v_fee int := 0;
BEGIN
  -- Lock state row to prevent concurrent double orders
  SELECT tenant_id, restaurant_id, channel, user_id,
         COALESCE(state_json->>'stage','') AS stage,
         COALESCE(state_json->>'last_order_id','') AS last_order_id,
         COALESCE(state_json,'{}'::jsonb) AS state_json
    INTO v_tenant, v_restaurant, v_channel, v_user, v_stage, v_last_order, v_state
  FROM public.conversation_state
  WHERE conversation_key = p_conversation_key
  FOR UPDATE;

  IF v_restaurant IS NULL THEN
    RAISE EXCEPTION 'Unknown conversation_key %', p_conversation_key;
  END IF;

  -- Idempotency: if already placed, return existing order
  IF v_stage = 'PLACED' AND v_last_order <> '' THEN
    RETURN QUERY
      SELECT
        v_last_order::uuid,
        COALESCE((SELECT total_cents FROM public.orders WHERE order_id=v_last_order::uuid), 0),
        (SELECT string_agg(label || ' x' || qty, ', ')
           FROM public.order_items
          WHERE order_id=v_last_order::uuid),
        (SELECT delivery_fee_cents FROM public.orders WHERE order_id=v_last_order::uuid),
        (SELECT COALESCE(total_cents,0) + COALESCE(delivery_fee_cents,0) FROM public.orders WHERE order_id=v_last_order::uuid),
        (SELECT delivery_eta_min FROM public.orders WHERE order_id=v_last_order::uuid),
        (SELECT delivery_eta_max FROM public.orders WHERE order_id=v_last_order::uuid);
    RETURN;
  END IF;

  SELECT COALESCE(
           (SELECT cart_json->>'serviceMode' FROM public.carts WHERE conversation_key=p_conversation_key),
           (SELECT state_json->>'serviceMode' FROM public.conversation_state WHERE conversation_key=p_conversation_key),
           'a_emporter'
         )
    INTO v_mode;

  -- Extract delivery info from state_json if needed
  v_delivery := COALESCE(v_state->'delivery','{}'::jsonb);
  v_addr := COALESCE(v_delivery->'address','{}'::jsonb);
  v_wilaya := NULLIF(COALESCE(v_addr->>'wilaya',''), '');
  v_commune := NULLIF(COALESCE(v_addr->>'commune',''), '');
  v_phone := NULLIF(COALESCE(v_addr->>'phone',''), '');

  IF v_mode = 'livraison' THEN
    IF v_wilaya IS NULL OR v_commune IS NULL THEN
      RAISE EXCEPTION 'DELIVERY_ADDRESS_MISSING';
    END IF;
  END IF;

  INSERT INTO public.orders (tenant_id, restaurant_id, channel, user_id, service_mode, status)
  VALUES (v_tenant, v_restaurant, v_channel, v_user, v_mode, 'NEW')
  RETURNING public.orders.order_id INTO v_order;

  -- Insert items
  WITH cart AS (
    SELECT cart_json
    FROM public.carts
    WHERE conversation_key = p_conversation_key
  ),
  lines AS (
    SELECT
      (elem->>'item')::text AS item_code,
      GREATEST(1, LEAST(20, COALESCE((elem->>'qty')::int, 1))) AS qty,
      COALESCE(elem->'options','[]'::jsonb) AS options_json
    FROM cart, LATERAL jsonb_array_elements(COALESCE(cart_json->'items','[]'::jsonb)) elem
  ),
  priced AS (
    SELECT
      l.item_code,
      l.qty,
      l.options_json,
      mi.label,
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
  INSERT INTO public.order_items(order_id, item_code, label, qty, unit_price_cents, options_json, line_total_cents)
  SELECT
    v_order,
    item_code,
    label,
    qty,
    (base_cents + opt_cents) AS unit_price_cents,
    options_json,
    (base_cents + opt_cents) * qty AS line_total_cents
  FROM priced;

  SELECT COALESCE(SUM(line_total_cents),0)::int INTO v_items_total
  FROM public.order_items
  WHERE order_id = v_order;

  UPDATE public.orders
     SET total_cents = v_items_total,
         updated_at = now()
   WHERE order_id = v_order;

  -- If delivery, compute quote again at commit-time (zone active + min order)
  IF v_mode = 'livraison' THEN
    SELECT * INTO q
    FROM public.delivery_quote(v_restaurant, v_wilaya, v_commune, v_items_total, now());

    IF q.reason <> 'OK' THEN
      -- Fail fast to avoid inconsistent orders in delivery mode
      RAISE EXCEPTION '%', q.reason;
    END IF;

    v_fee := COALESCE(q.final_fee_cents,0);

    UPDATE public.orders
       SET delivery_address_json = v_addr,
           delivery_wilaya = v_wilaya,
           delivery_commune = v_commune,
           delivery_phone = v_phone,
           delivery_fee_cents = v_fee,
           delivery_eta_min = q.eta_min,
           delivery_eta_max = q.eta_max,
           updated_at = now()
     WHERE order_id = v_order;
  END IF;

  -- Clear cart after placing order
  UPDATE public.carts SET cart_json='{"items":[]}'::jsonb, updated_at=now()
   WHERE conversation_key = p_conversation_key;

  -- Persist durable state lock (PLACED)
  UPDATE public.conversation_state
     SET state_json = jsonb_set(
           jsonb_set(v_state, '{stage}', to_jsonb('PLACED'::text), true),
           '{last_order_id}', to_jsonb(v_order::text), true
         ),
         updated_at = now()
   WHERE conversation_key = p_conversation_key;

  RETURN QUERY
    SELECT
      v_order,
      v_items_total,
      (SELECT string_agg(label || ' x' || qty, ', ')
         FROM public.order_items
        WHERE order_id=v_order),
      (SELECT delivery_fee_cents FROM public.orders WHERE order_id=v_order),
      (SELECT v_items_total + COALESCE(delivery_fee_cents,0) FROM public.orders WHERE order_id=v_order),
      (SELECT delivery_eta_min FROM public.orders WHERE order_id=v_order),
      (SELECT delivery_eta_max FROM public.orders WHERE order_id=v_order);

END;
$$;

COMMIT;
