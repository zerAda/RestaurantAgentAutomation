/*
FIX: create_order and delivery_quote functions
Bugs fixed:
1. create_order: "order_id" in subqueries conflicts with RETURNS TABLE(order_id uuid, ...)
2. delivery_quote: NULL cast issues in RETURN QUERY

The fix qualifies all column references with table aliases and casts NULLs properly.
*/

BEGIN;

-- Fix delivery_quote NULL casting issue
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
    RETURN QUERY SELECT false,false,0,0,NULL::int,0,0,0,0,'DELIVERY_ZONE_NOT_FOUND';
    RETURN;
  END IF;

  SELECT * INTO z
  FROM public.delivery_zones dz
  WHERE dz.restaurant_id = p_restaurant_id
    AND lower(dz.wilaya) = lower(COALESCE(p_wilaya,''))
    AND lower(dz.commune) = lower(COALESCE(p_commune,''))
  LIMIT 1;

  IF z.zone_id IS NULL THEN
    RETURN QUERY SELECT false,false,0,0,NULL::int,0,0,0,0,'DELIVERY_ZONE_NOT_FOUND';
    RETURN;
  END IF;

  IF NOT z.is_active THEN
    RETURN QUERY SELECT true,false,z.fee_base_cents,0,NULL::int,z.min_order_cents,z.eta_min,z.eta_max,z.fee_base_cents,'DELIVERY_ZONE_INACTIVE';
    RETURN;
  END IF;

  IF COALESCE(p_total_cents,0) < COALESCE(z.min_order_cents,0) THEN
    RETURN QUERY SELECT true,true,z.fee_base_cents,0,NULL::int,z.min_order_cents,z.eta_min,z.eta_max,z.fee_base_cents,'DELIVERY_MIN_ORDER';
    RETURN;
  END IF;

  -- local time in restaurant timezone (default Africa/Algiers)
  t_local := (p_at AT TIME ZONE COALESCE((SELECT rest.timezone FROM public.restaurants rest WHERE rest.restaurant_id=p_restaurant_id),'Africa/Algiers'))::time;

  -- choose the matching rule with the highest surcharge (simple rule system)
  FOR r IN
    SELECT *
    FROM public.delivery_fee_rules dfr
    WHERE dfr.restaurant_id=p_restaurant_id
      AND dfr.is_active=true
    ORDER BY dfr.surcharge_cents DESC
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

-- Must DROP first: return type may differ from bootstrap version
DROP FUNCTION IF EXISTS public.create_order(text);

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
  SELECT cs.tenant_id, cs.restaurant_id, cs.channel, cs.user_id,
         COALESCE(cs.state_json->>'stage','') AS stage,
         COALESCE(cs.state_json->>'last_order_id','') AS last_order_id,
         COALESCE(cs.state_json,'{}'::jsonb) AS state_json
    INTO v_tenant, v_restaurant, v_channel, v_user, v_stage, v_last_order, v_state
  FROM public.conversation_state cs
  WHERE cs.conversation_key = p_conversation_key
  FOR UPDATE;

  IF v_restaurant IS NULL THEN
    RAISE EXCEPTION 'Unknown conversation_key %', p_conversation_key;
  END IF;

  -- Idempotency: if already placed, return existing order
  IF v_stage = 'PLACED' AND v_last_order <> '' THEN
    RETURN QUERY
      SELECT
        v_last_order::uuid,
        COALESCE((SELECT o.total_cents FROM public.orders o WHERE o.order_id=v_last_order::uuid), 0),
        (SELECT string_agg(oi.label || ' x' || oi.qty, ', ')
           FROM public.order_items oi
          WHERE oi.order_id=v_last_order::uuid),
        (SELECT o.delivery_fee_cents FROM public.orders o WHERE o.order_id=v_last_order::uuid),
        (SELECT COALESCE(o.total_cents,0) + COALESCE(o.delivery_fee_cents,0) FROM public.orders o WHERE o.order_id=v_last_order::uuid),
        (SELECT o.delivery_eta_min FROM public.orders o WHERE o.order_id=v_last_order::uuid),
        (SELECT o.delivery_eta_max FROM public.orders o WHERE o.order_id=v_last_order::uuid);
    RETURN;
  END IF;

  SELECT COALESCE(
           (SELECT c.cart_json->>'serviceMode' FROM public.carts c WHERE c.conversation_key=p_conversation_key),
           (SELECT cs2.state_json->>'serviceMode' FROM public.conversation_state cs2 WHERE cs2.conversation_key=p_conversation_key),
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
    SELECT c.cart_json
    FROM public.carts c
    WHERE c.conversation_key = p_conversation_key
  ),
  lines AS (
    SELECT
      (elem->>'item')::text AS item_code,
      GREATEST(1, LEAST(20, COALESCE((elem->>'qty')::int, 1))) AS qty,
      COALESCE(elem->'options','[]'::jsonb) AS options_json
    FROM cart, LATERAL jsonb_array_elements(COALESCE(cart.cart_json->'items','[]'::jsonb)) elem
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
    priced.item_code,
    priced.label,
    priced.qty,
    (priced.base_cents + priced.opt_cents) AS unit_price_cents,
    priced.options_json,
    (priced.base_cents + priced.opt_cents) * priced.qty AS line_total_cents
  FROM priced;

  SELECT COALESCE(SUM(oi.line_total_cents),0)::int INTO v_items_total
  FROM public.order_items oi
  WHERE oi.order_id = v_order;

  UPDATE public.orders o
     SET total_cents = v_items_total,
         updated_at = now()
   WHERE o.order_id = v_order;

  -- If delivery, compute quote again at commit-time (zone active + min order)
  IF v_mode = 'livraison' THEN
    SELECT * INTO q
    FROM public.delivery_quote(v_restaurant, v_wilaya, v_commune, v_items_total, now());

    IF q.reason <> 'OK' THEN
      -- Fail fast to avoid inconsistent orders in delivery mode
      RAISE EXCEPTION '%', q.reason;
    END IF;

    v_fee := COALESCE(q.final_fee_cents,0);

    UPDATE public.orders o
       SET delivery_address_json = v_addr,
           delivery_wilaya = v_wilaya,
           delivery_commune = v_commune,
           delivery_phone = v_phone,
           delivery_fee_cents = v_fee,
           delivery_eta_min = q.eta_min,
           delivery_eta_max = q.eta_max,
           updated_at = now()
     WHERE o.order_id = v_order;
  END IF;

  -- Clear cart after placing order
  UPDATE public.carts c SET cart_json='{"items":[]}'::jsonb, updated_at=now()
   WHERE c.conversation_key = p_conversation_key;

  -- Persist durable state lock (PLACED)
  UPDATE public.conversation_state cs
     SET state_json = jsonb_set(
           jsonb_set(v_state, '{stage}', to_jsonb('PLACED'::text), true),
           '{last_order_id}', to_jsonb(v_order::text), true
         ),
         updated_at = now()
   WHERE cs.conversation_key = p_conversation_key;

  RETURN QUERY
    SELECT
      v_order,
      v_items_total,
      (SELECT string_agg(oi.label || ' x' || oi.qty, ', ')
         FROM public.order_items oi
        WHERE oi.order_id=v_order),
      (SELECT o.delivery_fee_cents FROM public.orders o WHERE o.order_id=v_order),
      (SELECT v_items_total + COALESCE(o.delivery_fee_cents,0) FROM public.orders o WHERE o.order_id=v_order),
      (SELECT o.delivery_eta_min FROM public.orders o WHERE o.order_id=v_order),
      (SELECT o.delivery_eta_max FROM public.orders o WHERE o.order_id=v_order);

END;
$$;

COMMIT;
