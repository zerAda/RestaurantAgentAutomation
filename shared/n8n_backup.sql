--
-- PostgreSQL database dump
--

\restrict DphdstAIGhQLg6w4wixA1356NlhfK7dHfvn9aKfu5dehHgeX0C5M2JwfVBxSdcF

-- Dumped from database version 15.16
-- Dumped by pg_dump version 15.16

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: ops; Type: SCHEMA; Schema: -; Owner: n8n
--

CREATE SCHEMA ops;


ALTER SCHEMA ops OWNER TO n8n;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: security_event_type_enum; Type: TYPE; Schema: public; Owner: n8n
--

CREATE TYPE public.security_event_type_enum AS ENUM (
    'AUDIO_URL_BLOCKED',
    'AUTH_DENY',
    'RETENTION_RUN',
    'CONTRACT_VALIDATION_FAILED',
    'SLO_BREACH',
    'ADDRESS_AMBIGUOUS',
    'DELIVERY_DISABLED',
    'DELIVERY_MIN_ORDER',
    'DELIVERY_QUOTE_OK',
    'DELIVERY_SLOT_RESERVED',
    'DELIVERY_ZONE_INACTIVE',
    'DELIVERY_ZONE_NOT_FOUND',
    'SLOT_FULL',
    'LEGACY_TOKEN_ATTEMPT',
    'TOKEN_ROTATED',
    'SIGNATURE_INVALID',
    'SIGNATURE_MISSING',
    'REPLAY_DETECTED',
    'FRAUD_SIGNAL',
    'PAYMENT_FAILED',
    'FRAUD_CHECKOUT',
    'PAYMENT_INITIATED',
    'PAYMENT_COMPLETED'
);


ALTER TYPE public.security_event_type_enum OWNER TO n8n;

--
-- Name: create_index_if_cols_exist(text, text, text, text[]); Type: FUNCTION; Schema: ops; Owner: n8n
--

CREATE FUNCTION ops.create_index_if_cols_exist(p_index_name text, p_table_name text, p_index_ddl text, p_required_cols text[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_schema TEXT := split_part(p_table_name, '.', 1);
  v_table  TEXT := split_part(p_table_name, '.', 2);
  v_missing INT;
BEGIN
  IF to_regclass(p_table_name) IS NULL THEN
    RETURN;
  END IF;

  SELECT count(*) INTO v_missing
  FROM unnest(p_required_cols) col
  WHERE NOT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = v_schema
      AND c.table_name   = v_table
      AND c.column_name  = col
  );

  IF v_missing > 0 THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = v_schema
      AND indexname  = p_index_name
  ) THEN
    RETURN;
  END IF;

  EXECUTE p_index_ddl;
END;
$$;


ALTER FUNCTION ops.create_index_if_cols_exist(p_index_name text, p_table_name text, p_index_ddl text, p_required_cols text[]) OWNER TO n8n;

--
-- Name: purge_outbound_sent_batch(timestamp with time zone, integer, boolean); Type: FUNCTION; Schema: ops; Owner: n8n
--

CREATE FUNCTION ops.purge_outbound_sent_batch(p_cutoff_ts timestamp with time zone, p_batch_size integer, p_dry_run boolean DEFAULT false) RETURNS TABLE(deleted_count bigint)
    LANGUAGE plpgsql
    AS $_$
DECLARE
  v_sql TEXT;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size <= 0 THEN
    RAISE EXCEPTION 'batch_size must be > 0';
  END IF;

  IF to_regclass('public.outbound_messages') IS NULL THEN
    deleted_count := 0;
    RETURN NEXT;
    RETURN;
  END IF;

  IF p_dry_run THEN
    v_sql := 'SELECT count(*)::bigint AS deleted_count
              FROM public.outbound_messages
              WHERE status = ''SENT'' AND sent_at IS NOT NULL AND sent_at < $1';
    RETURN QUERY EXECUTE v_sql USING p_cutoff_ts;
    RETURN;
  END IF;

  v_sql := $q$
    WITH victim AS (
      SELECT ctid
      FROM public.outbound_messages
      WHERE status = 'SENT'
        AND sent_at IS NOT NULL
        AND sent_at < $1
      ORDER BY sent_at ASC
      LIMIT $2
    )
    DELETE FROM public.outbound_messages t
    USING victim v
    WHERE t.ctid = v.ctid
    RETURNING 1
  $q$;

  EXECUTE v_sql USING p_cutoff_ts, p_batch_size;
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN NEXT;
END;
$_$;


ALTER FUNCTION ops.purge_outbound_sent_batch(p_cutoff_ts timestamp with time zone, p_batch_size integer, p_dry_run boolean) OWNER TO n8n;

--
-- Name: purge_table_batch(text, timestamp with time zone, integer, boolean); Type: FUNCTION; Schema: ops; Owner: n8n
--

CREATE FUNCTION ops.purge_table_batch(p_table_name text, p_cutoff_ts timestamp with time zone, p_batch_size integer, p_dry_run boolean DEFAULT false) RETURNS TABLE(deleted_count bigint, time_column text)
    LANGUAGE plpgsql
    AS $_$
DECLARE
  v_schema   TEXT := split_part(p_table_name, '.', 1);
  v_table    TEXT := split_part(p_table_name, '.', 2);
  v_time_col TEXT;
  v_sql      TEXT;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size <= 0 THEN
    RAISE EXCEPTION 'batch_size must be > 0';
  END IF;

  IF to_regclass(p_table_name) IS NULL THEN
    -- Table absent: nothing to purge
    deleted_count := 0;
    time_column := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT c.column_name
    INTO v_time_col
  FROM information_schema.columns c
  WHERE c.table_schema = v_schema
    AND c.table_name   = v_table
    AND c.column_name IN ('received_at','created_at','sent_at','updated_at','inserted_at')
    AND c.data_type IN ('timestamp with time zone','timestamp without time zone')
  ORDER BY CASE c.column_name
    WHEN 'received_at' THEN 1
    WHEN 'created_at'  THEN 2
    WHEN 'sent_at'     THEN 3
    WHEN 'updated_at'  THEN 4
    WHEN 'inserted_at' THEN 5
    ELSE 99
  END
  LIMIT 1;

  IF v_time_col IS NULL THEN
    RAISE EXCEPTION 'No supported time column found for %', p_table_name;
  END IF;

  IF p_dry_run THEN
    v_sql := format(
      'SELECT count(*)::bigint AS deleted_count, %L::text AS time_column FROM %s WHERE %I < $1',
      v_time_col,
      p_table_name,
      v_time_col
    );
    RETURN QUERY EXECUTE v_sql USING p_cutoff_ts;
    RETURN;
  END IF;

  -- Delete a bounded chunk using CTID selection ordered by time column (index-friendly)
  v_sql := format($f$
    WITH victim AS (
      SELECT ctid
      FROM %s
      WHERE %I < $1
      ORDER BY %I ASC
      LIMIT $2
    )
    DELETE FROM %s t
    USING victim v
    WHERE t.ctid = v.ctid
    RETURNING 1
  $f$,
    p_table_name, v_time_col, v_time_col, p_table_name
  );

  EXECUTE v_sql USING p_cutoff_ts, p_batch_size;
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  time_column := v_time_col;
  RETURN NEXT;
END;
$_$;


ALTER FUNCTION ops.purge_table_batch(p_table_name text, p_cutoff_ts timestamp with time zone, p_batch_size integer, p_dry_run boolean) OWNER TO n8n;

--
-- Name: build_wa_order_status_payload(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.build_wa_order_status_payload(p_order_id uuid, p_customer_status text, p_status_link text DEFAULT NULL::text, p_locale text DEFAULT 'fr'::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  o RECORD;
  txt text;
  loc text;
BEGIN
  SELECT order_id, tenant_id, restaurant_id, channel, user_id, delivery_eta_min, delivery_eta_max
    INTO o
  FROM public.orders
  WHERE order_id = p_order_id;

  IF o.order_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  loc := public.normalize_locale(
    COALESCE(
      (SELECT locale FROM public.customer_preferences WHERE tenant_id=o.tenant_id AND phone=o.user_id),
      p_locale,
      'fr'
    )
  );

  txt := public.wa_order_status_text(loc, p_customer_status, p_order_id, o.delivery_eta_min, o.delivery_eta_max, p_status_link);

  RETURN jsonb_build_object(
    'channel','whatsapp',
    'to', o.user_id,
    'restaurantId', o.restaurant_id,
    'text', txt,
    'buttons', '[]'::jsonb
  );
END $$;


ALTER FUNCTION public.build_wa_order_status_payload(p_order_id uuid, p_customer_status text, p_status_link text, p_locale text) OWNER TO n8n;

--
-- Name: create_order(text); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.create_order(p_conversation_key text) RETURNS TABLE(order_id uuid, total_cents integer, summary text, delivery_fee_cents integer, total_payable_cents integer, delivery_eta_min integer, delivery_eta_max integer)
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


ALTER FUNCTION public.create_order(p_conversation_key text) OWNER TO n8n;

--
-- Name: delivery_quote(uuid, text, text, integer, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.delivery_quote(p_restaurant_id uuid, p_wilaya text, p_commune text, p_total_cents integer, p_at timestamp with time zone DEFAULT now()) RETURNS TABLE(zone_found boolean, zone_active boolean, fee_base_cents integer, surcharge_cents integer, free_threshold_cents integer, min_order_cents integer, eta_min integer, eta_max integer, final_fee_cents integer, reason text)
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


ALTER FUNCTION public.delivery_quote(p_restaurant_id uuid, p_wilaya text, p_commune text, p_total_cents integer, p_at timestamp with time zone) OWNER TO n8n;

--
-- Name: enqueue_wa_order_status(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.enqueue_wa_order_status(p_order_id uuid, p_customer_status text, p_status_link text DEFAULT NULL::text, p_locale text DEFAULT 'fr'::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  o RECORD;
  v_dedupe text;
  v_payload jsonb;
BEGIN
  IF p_customer_status IS NULL THEN
    RETURN;
  END IF;

  SELECT tenant_id, restaurant_id, channel, user_id
    INTO o
  FROM public.orders
  WHERE order_id = p_order_id;

  IF o.tenant_id IS NULL THEN
    RETURN;
  END IF;

  IF lower(COALESCE(o.channel,'')) <> 'whatsapp' THEN
    RETURN;
  END IF;

  v_dedupe := 'order_status:' || p_order_id::text || ':' || upper(p_customer_status);
  v_payload := public.build_wa_order_status_payload(p_order_id, upper(p_customer_status), p_status_link, p_locale);

  INSERT INTO public.outbound_messages(
    dedupe_key, tenant_id, restaurant_id, conversation_key, channel, user_id, order_id,
    template, payload_json, status, next_retry_at
  ) VALUES (
    v_dedupe, o.tenant_id, o.restaurant_id, NULL, 'whatsapp', o.user_id, p_order_id,
    'WA_ORDER_STATUS_' || upper(p_customer_status), v_payload, 'PENDING', now()
  ) ON CONFLICT (dedupe_key) DO NOTHING;
END $$;


ALTER FUNCTION public.enqueue_wa_order_status(p_order_id uuid, p_customer_status text, p_status_link text, p_locale text) OWNER TO n8n;

--
-- Name: faq_entries_tsv_update(); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.faq_entries_tsv_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.search_tsv :=
    setweight(to_tsvector('simple', coalesce(NEW.question,'')), 'A') ||
    setweight(to_tsvector('simple', array_to_string(coalesce(NEW.tags,'{}'::text[]),' ')), 'B') ||
    setweight(to_tsvector('simple', coalesce(NEW.answer,'')), 'C');
  NEW.updated_at := now();
  RETURN NEW;
END $$;


ALTER FUNCTION public.faq_entries_tsv_update() OWNER TO n8n;

--
-- Name: increment_workflow_version(); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.increment_workflow_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
			BEGIN
				IF NEW."versionCounter" IS NOT DISTINCT FROM OLD."versionCounter" THEN
					NEW."versionCounter" = OLD."versionCounter" + 1;
				END IF;
				RETURN NEW;
			END;
			$$;


ALTER FUNCTION public.increment_workflow_version() OWNER TO n8n;

--
-- Name: insert_admin_wa_audit(uuid, uuid, text, text, text, text, text, text, jsonb, text, boolean, text); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.insert_admin_wa_audit(p_tenant_id uuid, p_restaurant_id uuid, p_actor_phone text, p_actor_role text, p_action text, p_target_type text DEFAULT NULL::text, p_target_id text DEFAULT NULL::text, p_command_raw text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb, p_ip text DEFAULT NULL::text, p_success boolean DEFAULT true, p_error text DEFAULT NULL::text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_id bigint;
BEGIN
  INSERT INTO admin_wa_audit_log (
    tenant_id, restaurant_id, actor_phone, actor_role, action,
    target_type, target_id, command_raw, metadata_json, ip_address,
    success, error_message
  ) VALUES (
    p_tenant_id, p_restaurant_id, p_actor_phone, COALESCE(p_actor_role, 'admin'), p_action,
    p_target_type, p_target_id, p_command_raw, COALESCE(p_metadata, '{}'::jsonb), p_ip,
    p_success, p_error
  ) RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$$;


ALTER FUNCTION public.insert_admin_wa_audit(p_tenant_id uuid, p_restaurant_id uuid, p_actor_phone text, p_actor_role text, p_action text, p_target_type text, p_target_id text, p_command_raw text, p_metadata jsonb, p_ip text, p_success boolean, p_error text) OWNER TO n8n;

--
-- Name: list_delivery_slots(uuid, integer); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.list_delivery_slots(p_restaurant_id uuid, p_day_of_week integer) RETURNS TABLE(slot_id uuid, day_of_week integer, start_time time without time zone, end_time time without time zone, capacity integer, reserved integer, available integer)
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


ALTER FUNCTION public.list_delivery_slots(p_restaurant_id uuid, p_day_of_week integer) OWNER TO n8n;

--
-- Name: map_order_status_to_customer(text, text); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.map_order_status_to_customer(p_internal_status text, p_service_mode text) RETURNS text
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF p_internal_status IS NULL THEN
    RETURN NULL;
  END IF;

  CASE upper(p_internal_status)
    WHEN 'ACCEPTED' THEN RETURN 'CONFIRMED';
    WHEN 'IN_PROGRESS' THEN RETURN 'PREPARING';
    WHEN 'READY' THEN RETURN 'READY';
    WHEN 'OUT_FOR_DELIVERY' THEN RETURN 'OUT_FOR_DELIVERY';
    WHEN 'DONE' THEN RETURN 'DELIVERED';
    WHEN 'DELIVERED' THEN RETURN 'DELIVERED';
    WHEN 'CANCELLED' THEN RETURN 'CANCELLED';
    ELSE RETURN NULL; -- e.g. NEW
  END CASE;
END $$;


ALTER FUNCTION public.map_order_status_to_customer(p_internal_status text, p_service_mode text) OWNER TO n8n;

--
-- Name: normalize_locale(text); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.normalize_locale(p_locale text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
  loc text := lower(trim(coalesce(p_locale,'')));
BEGIN
  IF loc LIKE 'ar%' THEN RETURN 'ar'; END IF;
  IF loc IN ('fr','fr-fr','fr_fr','français','francais') THEN RETURN 'fr'; END IF;
  IF loc IN ('ar','ar-dz','ar_dz','arabic','عربية','العربية') THEN RETURN 'ar'; END IF;
  RETURN 'fr';
END $$;


ALTER FUNCTION public.normalize_locale(p_locale text) OWNER TO n8n;

--
-- Name: reserve_delivery_slot(uuid, uuid); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.reserve_delivery_slot(p_order_id uuid, p_slot_id uuid) RETURNS TABLE(ok boolean, reason text, capacity integer, reserved integer, available integer)
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


ALTER FUNCTION public.reserve_delivery_slot(p_order_id uuid, p_slot_id uuid) OWNER TO n8n;

--
-- Name: trg_orders_init_tracking(); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.trg_orders_init_tracking() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.last_notified_status IS NULL THEN NEW.last_notified_status := NULL; END IF;
  IF NEW.last_notified_at IS NULL THEN NEW.last_notified_at := NULL; END IF;
  RETURN NEW;
END $$;


ALTER FUNCTION public.trg_orders_init_tracking() OWNER TO n8n;

--
-- Name: trg_orders_status_tracking(); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.trg_orders_status_tracking() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_customer text;
  v_window interval := interval '30 seconds';
  v_next timestamptz;
BEGIN
  IF TG_OP <> 'UPDATE' OR NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  v_customer := public.map_order_status_to_customer(NEW.status, NEW.service_mode);

  INSERT INTO public.order_status_history(order_id, internal_status, customer_status)
  VALUES (NEW.order_id, NEW.status, v_customer);

  IF v_customer IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.last_notified_status IS NOT NULL AND NEW.last_notified_status = v_customer THEN
    RETURN NEW;
  END IF;

  IF NEW.last_notified_at IS NOT NULL AND NEW.last_notified_at > now() - v_window THEN
    v_next := NEW.last_notified_at + v_window;
  ELSE
    v_next := now();
  END IF;

  PERFORM public.enqueue_wa_order_status(NEW.order_id, v_customer, NULL, 'fr');

  NEW.last_notified_status := v_customer;
  NEW.last_notified_at := now();

  UPDATE public.outbound_messages
     SET next_retry_at = GREATEST(next_retry_at, v_next),
         updated_at = now()
   WHERE order_id = NEW.order_id
     AND dedupe_key = ('order_status:' || NEW.order_id::text || ':' || upper(v_customer));

  RETURN NEW;
END $$;


ALTER FUNCTION public.trg_orders_status_tracking() OWNER TO n8n;

--
-- Name: wa_order_status_text(text, text, uuid, integer, integer, text); Type: FUNCTION; Schema: public; Owner: n8n
--

CREATE FUNCTION public.wa_order_status_text(p_locale text, p_customer_status text, p_order_id uuid, p_eta_min integer, p_eta_max integer, p_status_link text DEFAULT NULL::text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  loc text := public.normalize_locale(p_locale);
  eta_txt text := '';
  link_txt text := '';
  k text := 'WA_ORDER_STATUS_' || upper(coalesce(p_customer_status,''));
  tmpl text;
  out_txt text;
  order_short text := left(p_order_id::text,8);
BEGIN
  IF p_eta_min IS NOT NULL OR p_eta_max IS NOT NULL THEN
    eta_txt := E'\nETA: ' || COALESCE(p_eta_min::text,'') ||
      CASE WHEN p_eta_max IS NOT NULL THEN '-'||p_eta_max::text ELSE '' END || ' min';
  END IF;

  IF p_status_link IS NOT NULL AND length(trim(p_status_link)) > 0 THEN
    link_txt := E'\nSuivi: ' || trim(p_status_link);
  END IF;

  SELECT content INTO tmpl
  FROM public.message_templates
  WHERE tenant_id = '_GLOBAL' AND key = k AND locale = loc
  LIMIT 1;

  IF tmpl IS NOT NULL THEN
    out_txt := replace(replace(tmpl, '{{order_id}}', order_short), '{{eta}}', eta_txt);
    RETURN out_txt || link_txt;
  END IF;

  -- Legacy fallback (exact behavior EPIC3)
  IF loc LIKE 'ar%' THEN
    CASE p_customer_status
      WHEN 'CONFIRMED' THEN RETURN '✅ تم تأكيد طلبك #'||order_short||eta_txt;
      WHEN 'PREPARING' THEN RETURN '👨‍🍳 يتم تحضير طلبك #'||order_short||eta_txt;
      WHEN 'READY' THEN RETURN '📦 طلبك جاهز #'||order_short||eta_txt;
      WHEN 'OUT_FOR_DELIVERY' THEN RETURN '🛵 طلبك في الطريق للتوصيل #'||order_short||eta_txt;
      WHEN 'DELIVERED' THEN RETURN '🎉 تم تسليم/إنهاء الطلب #'||order_short;
      WHEN 'CANCELLED' THEN RETURN '❌ تم إلغاء الطلب #'||order_short;
      ELSE RETURN 'ℹ️ تحديث الطلب #'||order_short||eta_txt;
    END CASE;
  END IF;

  CASE p_customer_status
    WHEN 'CONFIRMED' THEN RETURN '✅ Commande confirmée #'||order_short||eta_txt||link_txt;
    WHEN 'PREPARING' THEN RETURN '👨‍🍳 Votre commande est en préparation #'||order_short||eta_txt||link_txt;
    WHEN 'READY' THEN RETURN '📦 Votre commande est prête #'||order_short||eta_txt||link_txt;
    WHEN 'OUT_FOR_DELIVERY' THEN RETURN '🛵 Votre commande est en livraison #'||order_short||eta_txt||link_txt;
    WHEN 'DELIVERED' THEN RETURN '🎉 Commande livrée #'||order_short||link_txt;
    WHEN 'CANCELLED' THEN RETURN '❌ Commande annulée #'||order_short||link_txt;
    ELSE RETURN 'ℹ️ Mise à jour commande #'||order_short||eta_txt||link_txt;
  END CASE;
END $$;


ALTER FUNCTION public.wa_order_status_text(p_locale text, p_customer_status text, p_order_id uuid, p_eta_min integer, p_eta_max integer, p_status_link text) OWNER TO n8n;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: retention_runs; Type: TABLE; Schema: ops; Owner: n8n
--

CREATE TABLE ops.retention_runs (
    run_id bigint NOT NULL,
    run_started_at timestamp with time zone DEFAULT now() NOT NULL,
    run_finished_at timestamp with time zone,
    dry_run boolean DEFAULT false NOT NULL,
    table_name text NOT NULL,
    cutoff_ts timestamp with time zone NOT NULL,
    batch_size integer NOT NULL,
    deleted_rows bigint DEFAULT 0 NOT NULL,
    details_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'STARTED'::text NOT NULL
);


ALTER TABLE ops.retention_runs OWNER TO n8n;

--
-- Name: retention_runs_run_id_seq; Type: SEQUENCE; Schema: ops; Owner: n8n
--

CREATE SEQUENCE ops.retention_runs_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE ops.retention_runs_run_id_seq OWNER TO n8n;

--
-- Name: retention_runs_run_id_seq; Type: SEQUENCE OWNED BY; Schema: ops; Owner: n8n
--

ALTER SEQUENCE ops.retention_runs_run_id_seq OWNED BY ops.retention_runs.run_id;


--
-- Name: security_event_types; Type: TABLE; Schema: ops; Owner: n8n
--

CREATE TABLE ops.security_event_types (
    code text NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE ops.security_event_types OWNER TO n8n;

--
-- Name: address_clarification_requests; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.address_clarification_requests (
    id bigint NOT NULL,
    order_id uuid NOT NULL,
    missing_fields jsonb DEFAULT '[]'::jsonb NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'OPEN'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT address_clarification_requests_attempts_check CHECK ((attempts >= 0)),
    CONSTRAINT address_clarification_requests_status_check CHECK ((status = ANY (ARRAY['OPEN'::text, 'RESOLVED'::text, 'HANDOFF'::text, 'CANCELLED'::text])))
);


ALTER TABLE public.address_clarification_requests OWNER TO n8n;

--
-- Name: address_clarification_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.address_clarification_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.address_clarification_requests_id_seq OWNER TO n8n;

--
-- Name: address_clarification_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.address_clarification_requests_id_seq OWNED BY public.address_clarification_requests.id;


--
-- Name: admin_audit_log; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.admin_audit_log (
    id bigint NOT NULL,
    tenant_id uuid,
    restaurant_id uuid,
    actor_client_id uuid,
    actor_name text,
    action text NOT NULL,
    object_type text,
    object_id text,
    request_id text,
    ip text,
    user_agent text,
    payload_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.admin_audit_log OWNER TO n8n;

--
-- Name: admin_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.admin_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.admin_audit_log_id_seq OWNER TO n8n;

--
-- Name: admin_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.admin_audit_log_id_seq OWNED BY public.admin_audit_log.id;


--
-- Name: admin_phone_allowlist; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.admin_phone_allowlist (
    id integer NOT NULL,
    phone_number text NOT NULL,
    role text DEFAULT 'admin'::text NOT NULL,
    label text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.admin_phone_allowlist OWNER TO n8n;

--
-- Name: admin_phone_allowlist_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.admin_phone_allowlist_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.admin_phone_allowlist_id_seq OWNER TO n8n;

--
-- Name: admin_phone_allowlist_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.admin_phone_allowlist_id_seq OWNED BY public.admin_phone_allowlist.id;


--
-- Name: admin_wa_audit_log; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.admin_wa_audit_log (
    id bigint NOT NULL,
    tenant_id uuid,
    restaurant_id uuid,
    actor_phone text NOT NULL,
    actor_role text DEFAULT 'admin'::text NOT NULL,
    action text NOT NULL,
    target_type text,
    target_id text,
    command_raw text,
    metadata_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    ip_address text,
    success boolean DEFAULT true NOT NULL,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT admin_wa_audit_action_check CHECK ((action = ANY (ARRAY['take'::text, 'reply'::text, 'close'::text, 'assign'::text, 'escalate'::text, 'note'::text, 'status_change'::text, 'reopen'::text, 'merge'::text, 'tag'::text, 'priority'::text, 'zone_create'::text, 'zone_update'::text, 'zone_delete'::text, 'order_status'::text, 'order_cancel'::text, 'refund'::text, 'block_user'::text, 'unblock_user'::text, 'other'::text])))
);


ALTER TABLE public.admin_wa_audit_log OWNER TO n8n;

--
-- Name: TABLE admin_wa_audit_log; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON TABLE public.admin_wa_audit_log IS 'Audit trail for all Admin WhatsApp console actions (W14). Retention: 90 days.';


--
-- Name: admin_wa_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.admin_wa_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.admin_wa_audit_log_id_seq OWNER TO n8n;

--
-- Name: admin_wa_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.admin_wa_audit_log_id_seq OWNED BY public.admin_wa_audit_log.id;


--
-- Name: annotation_tag_entity; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.annotation_tag_entity (
    id character varying(16) NOT NULL,
    name character varying(24) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.annotation_tag_entity OWNER TO n8n;

--
-- Name: api_clients; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.api_clients (
    client_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_name text NOT NULL,
    token_hash text NOT NULL,
    tenant_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    scopes jsonb DEFAULT '[]'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.api_clients OWNER TO n8n;

--
-- Name: auth_identity; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.auth_identity (
    "userId" uuid,
    "providerId" character varying(64) NOT NULL,
    "providerType" character varying(32) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.auth_identity OWNER TO n8n;

--
-- Name: auth_provider_sync_history; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.auth_provider_sync_history (
    id integer NOT NULL,
    "providerType" character varying(32) NOT NULL,
    "runMode" text NOT NULL,
    status text NOT NULL,
    "startedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "endedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    scanned integer NOT NULL,
    created integer NOT NULL,
    updated integer NOT NULL,
    disabled integer NOT NULL,
    error text
);


ALTER TABLE public.auth_provider_sync_history OWNER TO n8n;

--
-- Name: auth_provider_sync_history_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.auth_provider_sync_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_provider_sync_history_id_seq OWNER TO n8n;

--
-- Name: auth_provider_sync_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.auth_provider_sync_history_id_seq OWNED BY public.auth_provider_sync_history.id;


--
-- Name: binary_data; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.binary_data (
    "fileId" uuid NOT NULL,
    "sourceType" character varying(50) NOT NULL,
    "sourceId" character varying(255) NOT NULL,
    data bytea NOT NULL,
    "mimeType" character varying(255),
    "fileName" character varying(255),
    "fileSize" integer NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_binary_data_sourceType" CHECK ((("sourceType")::text = ANY ((ARRAY['execution'::character varying, 'chat_message_attachment'::character varying])::text[])))
);


ALTER TABLE public.binary_data OWNER TO n8n;

--
-- Name: COLUMN binary_data."sourceType"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.binary_data."sourceType" IS 'Source the file belongs to, e.g. ''execution''';


--
-- Name: COLUMN binary_data."sourceId"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.binary_data."sourceId" IS 'ID of the source, e.g. execution ID';


--
-- Name: COLUMN binary_data.data; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.binary_data.data IS 'Raw, not base64 encoded';


--
-- Name: COLUMN binary_data."fileSize"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.binary_data."fileSize" IS 'In bytes';


--
-- Name: carts; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.carts (
    conversation_key text NOT NULL,
    cart_json jsonb DEFAULT '{"items": []}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.carts OWNER TO n8n;

--
-- Name: chat_hub_agents; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.chat_hub_agents (
    id uuid NOT NULL,
    name character varying(256) NOT NULL,
    description character varying(512),
    "systemPrompt" text NOT NULL,
    "ownerId" uuid NOT NULL,
    "credentialId" character varying(36),
    provider character varying(16) NOT NULL,
    model character varying(64) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    tools json DEFAULT '[]'::json NOT NULL,
    icon json
);


ALTER TABLE public.chat_hub_agents OWNER TO n8n;

--
-- Name: COLUMN chat_hub_agents.provider; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_agents.provider IS 'ChatHubProvider enum: "openai", "anthropic", "google", "n8n"';


--
-- Name: COLUMN chat_hub_agents.model; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_agents.model IS 'Model name used at the respective Model node, ie. "gpt-4"';


--
-- Name: COLUMN chat_hub_agents.tools; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_agents.tools IS 'Tools available to the agent as JSON node definitions';


--
-- Name: chat_hub_messages; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.chat_hub_messages (
    id uuid NOT NULL,
    "sessionId" uuid NOT NULL,
    "previousMessageId" uuid,
    "revisionOfMessageId" uuid,
    "retryOfMessageId" uuid,
    type character varying(16) NOT NULL,
    name character varying(128) NOT NULL,
    content text NOT NULL,
    provider character varying(16),
    model character varying(64),
    "workflowId" character varying(36),
    "executionId" integer,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "agentId" uuid,
    status character varying(16) DEFAULT 'success'::character varying NOT NULL,
    attachments json
);


ALTER TABLE public.chat_hub_messages OWNER TO n8n;

--
-- Name: COLUMN chat_hub_messages.type; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_messages.type IS 'ChatHubMessageType enum: "human", "ai", "system", "tool", "generic"';


--
-- Name: COLUMN chat_hub_messages.provider; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_messages.provider IS 'ChatHubProvider enum: "openai", "anthropic", "google", "n8n"';


--
-- Name: COLUMN chat_hub_messages.model; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_messages.model IS 'Model name used at the respective Model node, ie. "gpt-4"';


--
-- Name: COLUMN chat_hub_messages."agentId"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_messages."agentId" IS 'ID of the custom agent (if provider is "custom-agent")';


--
-- Name: COLUMN chat_hub_messages.status; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_messages.status IS 'ChatHubMessageStatus enum, eg. "success", "error", "running", "cancelled"';


--
-- Name: COLUMN chat_hub_messages.attachments; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_messages.attachments IS 'File attachments for the message (if any), stored as JSON. Files are stored as base64-encoded data URLs.';


--
-- Name: chat_hub_sessions; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.chat_hub_sessions (
    id uuid NOT NULL,
    title character varying(256) NOT NULL,
    "ownerId" uuid NOT NULL,
    "lastMessageAt" timestamp(3) with time zone NOT NULL,
    "credentialId" character varying(36),
    provider character varying(16),
    model character varying(64),
    "workflowId" character varying(36),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "agentId" uuid,
    "agentName" character varying(128),
    tools json DEFAULT '[]'::json NOT NULL
);


ALTER TABLE public.chat_hub_sessions OWNER TO n8n;

--
-- Name: COLUMN chat_hub_sessions.provider; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_sessions.provider IS 'ChatHubProvider enum: "openai", "anthropic", "google", "n8n"';


--
-- Name: COLUMN chat_hub_sessions.model; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_sessions.model IS 'Model name used at the respective Model node, ie. "gpt-4"';


--
-- Name: COLUMN chat_hub_sessions."agentId"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_sessions."agentId" IS 'ID of the custom agent (if provider is "custom-agent")';


--
-- Name: COLUMN chat_hub_sessions."agentName"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_sessions."agentName" IS 'Cached name of the custom agent (if provider is "custom-agent")';


--
-- Name: COLUMN chat_hub_sessions.tools; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.chat_hub_sessions.tools IS 'Tools available to the agent as JSON node definitions';


--
-- Name: conversation_quarantine; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.conversation_quarantine (
    id bigint NOT NULL,
    conversation_key text NOT NULL,
    reason text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.conversation_quarantine OWNER TO n8n;

--
-- Name: conversation_quarantine_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.conversation_quarantine_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.conversation_quarantine_id_seq OWNER TO n8n;

--
-- Name: conversation_quarantine_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.conversation_quarantine_id_seq OWNED BY public.conversation_quarantine.id;


--
-- Name: conversation_state; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.conversation_state (
    conversation_key text NOT NULL,
    tenant_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    channel text NOT NULL,
    user_id text NOT NULL,
    state_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT conversation_state_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'messenger'::text])))
);


ALTER TABLE public.conversation_state OWNER TO n8n;

--
-- Name: credentials_entity; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.credentials_entity (
    name character varying(128) NOT NULL,
    data text NOT NULL,
    type character varying(128) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    id character varying(36) NOT NULL,
    "isManaged" boolean DEFAULT false NOT NULL,
    "isGlobal" boolean DEFAULT false NOT NULL,
    "isResolvable" boolean DEFAULT false NOT NULL,
    "resolvableAllowFallback" boolean DEFAULT false NOT NULL,
    "resolverId" character varying(16)
);


ALTER TABLE public.credentials_entity OWNER TO n8n;

--
-- Name: customer_preferences; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.customer_preferences (
    tenant_id text NOT NULL,
    phone text NOT NULL,
    locale text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_customer_preferences_locale CHECK ((lower(locale) = ANY (ARRAY['fr'::text, 'ar'::text])))
);


ALTER TABLE public.customer_preferences OWNER TO n8n;

--
-- Name: daily_metrics; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.daily_metrics (
    id integer NOT NULL,
    metric_date date DEFAULT CURRENT_DATE NOT NULL,
    metric_name text NOT NULL,
    metric_value numeric DEFAULT 0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.daily_metrics OWNER TO n8n;

--
-- Name: daily_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.daily_metrics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.daily_metrics_id_seq OWNER TO n8n;

--
-- Name: daily_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.daily_metrics_id_seq OWNED BY public.daily_metrics.id;


--
-- Name: darija_patterns; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.darija_patterns (
    id integer NOT NULL,
    pattern text NOT NULL,
    intent text NOT NULL,
    confidence numeric DEFAULT 0.8 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.darija_patterns OWNER TO n8n;

--
-- Name: darija_patterns_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.darija_patterns_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.darija_patterns_id_seq OWNER TO n8n;

--
-- Name: darija_patterns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.darija_patterns_id_seq OWNED BY public.darija_patterns.id;


--
-- Name: data_table; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.data_table (
    id character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    "projectId" character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.data_table OWNER TO n8n;

--
-- Name: data_table_column; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.data_table_column (
    id character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    type character varying(32) NOT NULL,
    index integer NOT NULL,
    "dataTableId" character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.data_table_column OWNER TO n8n;

--
-- Name: COLUMN data_table_column.type; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.data_table_column.type IS 'Expected: string, number, boolean, or date (not enforced as a constraint)';


--
-- Name: COLUMN data_table_column.index; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.data_table_column.index IS 'Column order, starting from 0 (0 = first column)';


--
-- Name: delivery_fee_rules; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.delivery_fee_rules (
    rule_id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    name text NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    surcharge_cents integer DEFAULT 0 NOT NULL,
    free_delivery_threshold_cents integer,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT delivery_fee_rules_free_delivery_threshold_cents_check CHECK (((free_delivery_threshold_cents IS NULL) OR (free_delivery_threshold_cents >= 0))),
    CONSTRAINT delivery_fee_rules_surcharge_cents_check CHECK ((surcharge_cents >= 0))
);


ALTER TABLE public.delivery_fee_rules OWNER TO n8n;

--
-- Name: delivery_slot_reservations; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.delivery_slot_reservations (
    id bigint NOT NULL,
    order_id uuid NOT NULL,
    slot_id uuid NOT NULL,
    reserved_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.delivery_slot_reservations OWNER TO n8n;

--
-- Name: delivery_slot_reservations_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.delivery_slot_reservations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.delivery_slot_reservations_id_seq OWNER TO n8n;

--
-- Name: delivery_slot_reservations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.delivery_slot_reservations_id_seq OWNED BY public.delivery_slot_reservations.id;


--
-- Name: delivery_time_slots; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.delivery_time_slots (
    slot_id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    day_of_week smallint NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    capacity integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT delivery_time_slots_capacity_check CHECK ((capacity >= 0)),
    CONSTRAINT delivery_time_slots_day_of_week_check CHECK (((day_of_week >= 0) AND (day_of_week <= 6)))
);


ALTER TABLE public.delivery_time_slots OWNER TO n8n;

--
-- Name: delivery_zones; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.delivery_zones (
    zone_id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    wilaya text NOT NULL,
    commune text NOT NULL,
    fee_base_cents integer NOT NULL,
    min_order_cents integer DEFAULT 0 NOT NULL,
    eta_min integer DEFAULT 45 NOT NULL,
    eta_max integer DEFAULT 60 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT delivery_zones_check CHECK ((eta_max >= eta_min)),
    CONSTRAINT delivery_zones_eta_min_check CHECK ((eta_min >= 0)),
    CONSTRAINT delivery_zones_fee_base_cents_check CHECK ((fee_base_cents >= 0)),
    CONSTRAINT delivery_zones_min_order_cents_check CHECK ((min_order_cents >= 0))
);


ALTER TABLE public.delivery_zones OWNER TO n8n;

--
-- Name: dynamic_credential_entry; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.dynamic_credential_entry (
    credential_id character varying(16) NOT NULL,
    subject_id character varying(16) NOT NULL,
    resolver_id character varying(16) NOT NULL,
    data text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.dynamic_credential_entry OWNER TO n8n;

--
-- Name: dynamic_credential_resolver; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.dynamic_credential_resolver (
    id character varying(16) NOT NULL,
    name character varying(128) NOT NULL,
    type character varying(128) NOT NULL,
    config text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.dynamic_credential_resolver OWNER TO n8n;

--
-- Name: COLUMN dynamic_credential_resolver.config; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.dynamic_credential_resolver.config IS 'Encrypted resolver configuration (JSON encrypted as string)';


--
-- Name: event_destinations; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.event_destinations (
    id uuid NOT NULL,
    destination jsonb NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.event_destinations OWNER TO n8n;

--
-- Name: execution_annotation_tags; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.execution_annotation_tags (
    "annotationId" integer NOT NULL,
    "tagId" character varying(24) NOT NULL
);


ALTER TABLE public.execution_annotation_tags OWNER TO n8n;

--
-- Name: execution_annotations; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.execution_annotations (
    id integer NOT NULL,
    "executionId" integer NOT NULL,
    vote character varying(6),
    note text,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.execution_annotations OWNER TO n8n;

--
-- Name: execution_annotations_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.execution_annotations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.execution_annotations_id_seq OWNER TO n8n;

--
-- Name: execution_annotations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.execution_annotations_id_seq OWNED BY public.execution_annotations.id;


--
-- Name: execution_data; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.execution_data (
    "executionId" integer NOT NULL,
    "workflowData" json NOT NULL,
    data text NOT NULL,
    "workflowVersionId" character varying(36)
);


ALTER TABLE public.execution_data OWNER TO n8n;

--
-- Name: execution_entity; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.execution_entity (
    id integer NOT NULL,
    finished boolean NOT NULL,
    mode character varying NOT NULL,
    "retryOf" character varying,
    "retrySuccessId" character varying,
    "startedAt" timestamp(3) with time zone,
    "stoppedAt" timestamp(3) with time zone,
    "waitTill" timestamp(3) with time zone,
    status character varying NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "deletedAt" timestamp(3) with time zone,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.execution_entity OWNER TO n8n;

--
-- Name: execution_entity_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.execution_entity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.execution_entity_id_seq OWNER TO n8n;

--
-- Name: execution_entity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.execution_entity_id_seq OWNED BY public.execution_entity.id;


--
-- Name: execution_metadata; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.execution_metadata (
    id integer NOT NULL,
    "executionId" integer NOT NULL,
    key character varying(255) NOT NULL,
    value text NOT NULL
);


ALTER TABLE public.execution_metadata OWNER TO n8n;

--
-- Name: execution_metadata_temp_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.execution_metadata_temp_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.execution_metadata_temp_id_seq OWNER TO n8n;

--
-- Name: execution_metadata_temp_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.execution_metadata_temp_id_seq OWNED BY public.execution_metadata.id;


--
-- Name: faq_entries; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.faq_entries (
    faq_id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    locale text NOT NULL,
    question text NOT NULL,
    answer text NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    search_tsv tsvector,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT faq_entries_locale_check CHECK ((lower(locale) = ANY (ARRAY['fr'::text, 'ar'::text])))
);


ALTER TABLE public.faq_entries OWNER TO n8n;

--
-- Name: faq_entries_faq_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.faq_entries_faq_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.faq_entries_faq_id_seq OWNER TO n8n;

--
-- Name: faq_entries_faq_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.faq_entries_faq_id_seq OWNED BY public.faq_entries.faq_id;


--
-- Name: feedback_jobs; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.feedback_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    channel text NOT NULL,
    user_id text NOT NULL,
    restaurant_id uuid NOT NULL,
    order_id uuid,
    message_text text NOT NULL,
    scheduled_at timestamp with time zone NOT NULL,
    sent_at timestamp with time zone,
    status text DEFAULT 'PENDING'::text NOT NULL,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT feedback_jobs_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'messenger'::text]))),
    CONSTRAINT feedback_jobs_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'SENT'::text])))
);


ALTER TABLE public.feedback_jobs OWNER TO n8n;

--
-- Name: folder; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.folder (
    id character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    "parentFolderId" character varying(36),
    "projectId" character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.folder OWNER TO n8n;

--
-- Name: folder_tag; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.folder_tag (
    "folderId" character varying(36) NOT NULL,
    "tagId" character varying(36) NOT NULL
);


ALTER TABLE public.folder_tag OWNER TO n8n;

--
-- Name: fraud_signals; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.fraud_signals (
    id bigint NOT NULL,
    tenant_id uuid,
    conversation_key text,
    signal_type text NOT NULL,
    score numeric DEFAULT 0,
    details jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.fraud_signals OWNER TO n8n;

--
-- Name: fraud_signals_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.fraud_signals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.fraud_signals_id_seq OWNER TO n8n;

--
-- Name: fraud_signals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.fraud_signals_id_seq OWNED BY public.fraud_signals.id;


--
-- Name: idempotency_keys; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.idempotency_keys (
    conversation_key text NOT NULL,
    msg_id text NOT NULL,
    channel text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT idempotency_keys_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'messenger'::text])))
);


ALTER TABLE public.idempotency_keys OWNER TO n8n;

--
-- Name: inbound_messages; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.inbound_messages (
    id bigint NOT NULL,
    conversation_key text NOT NULL,
    msg_id text NOT NULL,
    channel text NOT NULL,
    message_type text NOT NULL,
    text_hash text,
    meta_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT inbound_messages_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'messenger'::text])))
)
WITH (autovacuum_vacuum_scale_factor='0.02', autovacuum_analyze_scale_factor='0.02');


ALTER TABLE public.inbound_messages OWNER TO n8n;

--
-- Name: inbound_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.inbound_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.inbound_messages_id_seq OWNER TO n8n;

--
-- Name: inbound_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.inbound_messages_id_seq OWNED BY public.inbound_messages.id;


--
-- Name: insights_by_period; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.insights_by_period (
    id integer NOT NULL,
    "metaId" integer NOT NULL,
    type integer NOT NULL,
    value bigint NOT NULL,
    "periodUnit" integer NOT NULL,
    "periodStart" timestamp(0) with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.insights_by_period OWNER TO n8n;

--
-- Name: COLUMN insights_by_period.type; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.insights_by_period.type IS '0: time_saved_minutes, 1: runtime_milliseconds, 2: success, 3: failure';


--
-- Name: COLUMN insights_by_period."periodUnit"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.insights_by_period."periodUnit" IS '0: hour, 1: day, 2: week';


--
-- Name: insights_by_period_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

ALTER TABLE public.insights_by_period ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.insights_by_period_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: insights_metadata; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.insights_metadata (
    "metaId" integer NOT NULL,
    "workflowId" character varying(36),
    "projectId" character varying(36),
    "workflowName" character varying(128) NOT NULL,
    "projectName" character varying(255) NOT NULL
);


ALTER TABLE public.insights_metadata OWNER TO n8n;

--
-- Name: insights_metadata_metaId_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

ALTER TABLE public.insights_metadata ALTER COLUMN "metaId" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."insights_metadata_metaId_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: insights_raw; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.insights_raw (
    id integer NOT NULL,
    "metaId" integer NOT NULL,
    type integer NOT NULL,
    value bigint NOT NULL,
    "timestamp" timestamp(0) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.insights_raw OWNER TO n8n;

--
-- Name: COLUMN insights_raw.type; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.insights_raw.type IS '0: time_saved_minutes, 1: runtime_milliseconds, 2: success, 3: failure';


--
-- Name: insights_raw_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

ALTER TABLE public.insights_raw ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.insights_raw_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: installed_nodes; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.installed_nodes (
    name character varying(200) NOT NULL,
    type character varying(200) NOT NULL,
    "latestVersion" integer DEFAULT 1 NOT NULL,
    package character varying(241) NOT NULL
);


ALTER TABLE public.installed_nodes OWNER TO n8n;

--
-- Name: installed_packages; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.installed_packages (
    "packageName" character varying(214) NOT NULL,
    "installedVersion" character varying(50) NOT NULL,
    "authorName" character varying(70),
    "authorEmail" character varying(70),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.installed_packages OWNER TO n8n;

--
-- Name: invalid_auth_token; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.invalid_auth_token (
    token character varying(512) NOT NULL,
    "expiresAt" timestamp(3) with time zone NOT NULL
);


ALTER TABLE public.invalid_auth_token OWNER TO n8n;

--
-- Name: latency_samples; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.latency_samples (
    id integer NOT NULL,
    sample_time timestamp with time zone DEFAULT now() NOT NULL,
    operation text NOT NULL,
    latency_ms numeric NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb
);


ALTER TABLE public.latency_samples OWNER TO n8n;

--
-- Name: latency_samples_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.latency_samples_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.latency_samples_id_seq OWNER TO n8n;

--
-- Name: latency_samples_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.latency_samples_id_seq OWNED BY public.latency_samples.id;


--
-- Name: menu_item_options; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.menu_item_options (
    restaurant_id uuid NOT NULL,
    item_code text NOT NULL,
    option_code text NOT NULL,
    label text NOT NULL,
    kind text NOT NULL,
    price_delta_cents integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT menu_item_options_kind_check CHECK ((kind = ANY (ARRAY['extra'::text, 'remove'::text, 'note'::text])))
);


ALTER TABLE public.menu_item_options OWNER TO n8n;

--
-- Name: menu_items; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.menu_items (
    restaurant_id uuid NOT NULL,
    item_code text NOT NULL,
    label text NOT NULL,
    category text DEFAULT 'Autres'::text NOT NULL,
    price_cents integer NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT menu_items_price_cents_check CHECK ((price_cents >= 0))
);


ALTER TABLE public.menu_items OWNER TO n8n;

--
-- Name: message_templates; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.message_templates (
    tenant_id text DEFAULT '_GLOBAL'::text NOT NULL,
    key text NOT NULL,
    locale text NOT NULL,
    content text NOT NULL,
    variables jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_message_templates_variables_array CHECK ((jsonb_typeof(variables) = 'array'::text))
);


ALTER TABLE public.message_templates OWNER TO n8n;

--
-- Name: migrations; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.migrations (
    id integer NOT NULL,
    "timestamp" bigint NOT NULL,
    name character varying NOT NULL
);


ALTER TABLE public.migrations OWNER TO n8n;

--
-- Name: migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.migrations_id_seq OWNER TO n8n;

--
-- Name: migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.migrations_id_seq OWNED BY public.migrations.id;


--
-- Name: oauth_access_tokens; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.oauth_access_tokens (
    token character varying NOT NULL,
    "clientId" character varying NOT NULL,
    "userId" uuid NOT NULL
);


ALTER TABLE public.oauth_access_tokens OWNER TO n8n;

--
-- Name: oauth_authorization_codes; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.oauth_authorization_codes (
    code character varying(255) NOT NULL,
    "clientId" character varying NOT NULL,
    "userId" uuid NOT NULL,
    "redirectUri" character varying NOT NULL,
    "codeChallenge" character varying NOT NULL,
    "codeChallengeMethod" character varying(255) NOT NULL,
    "expiresAt" bigint NOT NULL,
    state character varying,
    used boolean DEFAULT false NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.oauth_authorization_codes OWNER TO n8n;

--
-- Name: COLUMN oauth_authorization_codes."expiresAt"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.oauth_authorization_codes."expiresAt" IS 'Unix timestamp in milliseconds';


--
-- Name: oauth_clients; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.oauth_clients (
    id character varying NOT NULL,
    name character varying(255) NOT NULL,
    "redirectUris" json NOT NULL,
    "grantTypes" json NOT NULL,
    "clientSecret" character varying(255),
    "clientSecretExpiresAt" bigint,
    "tokenEndpointAuthMethod" character varying(255) DEFAULT 'none'::character varying NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.oauth_clients OWNER TO n8n;

--
-- Name: COLUMN oauth_clients."tokenEndpointAuthMethod"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.oauth_clients."tokenEndpointAuthMethod" IS 'Possible values: none, client_secret_basic or client_secret_post';


--
-- Name: oauth_refresh_tokens; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.oauth_refresh_tokens (
    token character varying(255) NOT NULL,
    "clientId" character varying NOT NULL,
    "userId" uuid NOT NULL,
    "expiresAt" bigint NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.oauth_refresh_tokens OWNER TO n8n;

--
-- Name: COLUMN oauth_refresh_tokens."expiresAt"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.oauth_refresh_tokens."expiresAt" IS 'Unix timestamp in milliseconds';


--
-- Name: oauth_user_consents; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.oauth_user_consents (
    id integer NOT NULL,
    "userId" uuid NOT NULL,
    "clientId" character varying NOT NULL,
    "grantedAt" bigint NOT NULL
);


ALTER TABLE public.oauth_user_consents OWNER TO n8n;

--
-- Name: COLUMN oauth_user_consents."grantedAt"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.oauth_user_consents."grantedAt" IS 'Unix timestamp in milliseconds';


--
-- Name: oauth_user_consents_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

ALTER TABLE public.oauth_user_consents ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.oauth_user_consents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ops_kv; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.ops_kv (
    key text NOT NULL,
    value_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.ops_kv OWNER TO n8n;

--
-- Name: order_items; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.order_items (
    id bigint NOT NULL,
    order_id uuid NOT NULL,
    item_code text NOT NULL,
    label text NOT NULL,
    qty integer NOT NULL,
    unit_price_cents integer NOT NULL,
    options_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    line_total_cents integer NOT NULL,
    CONSTRAINT order_items_line_total_cents_check CHECK ((line_total_cents >= 0)),
    CONSTRAINT order_items_qty_check CHECK (((qty >= 1) AND (qty <= 20))),
    CONSTRAINT order_items_unit_price_cents_check CHECK ((unit_price_cents >= 0))
);


ALTER TABLE public.order_items OWNER TO n8n;

--
-- Name: order_items_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.order_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.order_items_id_seq OWNER TO n8n;

--
-- Name: order_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.order_items_id_seq OWNED BY public.order_items.id;


--
-- Name: order_status_history; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.order_status_history (
    id bigint NOT NULL,
    order_id uuid NOT NULL,
    internal_status text NOT NULL,
    customer_status text,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.order_status_history OWNER TO n8n;

--
-- Name: order_status_history_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.order_status_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.order_status_history_id_seq OWNER TO n8n;

--
-- Name: order_status_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.order_status_history_id_seq OWNED BY public.order_status_history.id;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.orders (
    order_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    channel text NOT NULL,
    user_id text NOT NULL,
    service_mode text NOT NULL,
    status text DEFAULT 'NEW'::text NOT NULL,
    total_cents integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_notified_status text,
    last_notified_at timestamp with time zone,
    delivery_address_json jsonb,
    delivery_wilaya text,
    delivery_commune text,
    delivery_phone text,
    delivery_fee_cents integer,
    delivery_eta_min integer,
    delivery_eta_max integer,
    delivery_slot_id uuid,
    delivery_slot_start timestamp with time zone,
    delivery_slot_end timestamp with time zone,
    CONSTRAINT chk_orders_status_valid CHECK ((status = ANY (ARRAY['NEW'::text, 'ACCEPTED'::text, 'IN_PROGRESS'::text, 'READY'::text, 'OUT_FOR_DELIVERY'::text, 'DONE'::text, 'DELIVERED'::text, 'CANCELLED'::text]))),
    CONSTRAINT orders_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'messenger'::text]))),
    CONSTRAINT orders_delivery_eta_max_check CHECK (((delivery_eta_max IS NULL) OR (delivery_eta_max >= 0))),
    CONSTRAINT orders_delivery_eta_min_check CHECK (((delivery_eta_min IS NULL) OR (delivery_eta_min >= 0))),
    CONSTRAINT orders_delivery_fee_cents_check CHECK (((delivery_fee_cents IS NULL) OR (delivery_fee_cents >= 0))),
    CONSTRAINT orders_service_mode_check CHECK ((service_mode = ANY (ARRAY['sur_place'::text, 'a_emporter'::text, 'livraison'::text]))),
    CONSTRAINT orders_status_check CHECK ((status = ANY (ARRAY['NEW'::text, 'ACCEPTED'::text, 'IN_PROGRESS'::text, 'READY'::text, 'DONE'::text, 'CANCELLED'::text]))),
    CONSTRAINT orders_total_cents_check CHECK ((total_cents >= 0))
);


ALTER TABLE public.orders OWNER TO n8n;

--
-- Name: outbound_messages; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.outbound_messages (
    outbound_id uuid DEFAULT gen_random_uuid() NOT NULL,
    dedupe_key text NOT NULL,
    tenant_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    conversation_key text,
    channel text NOT NULL,
    user_id text NOT NULL,
    order_id uuid,
    template text DEFAULT 'reply'::text NOT NULL,
    payload_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    next_retry_at timestamp with time zone DEFAULT now() NOT NULL,
    provider_message_id text,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sent_at timestamp with time zone,
    CONSTRAINT outbound_messages_attempts_check CHECK ((attempts >= 0)),
    CONSTRAINT outbound_messages_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'messenger'::text]))),
    CONSTRAINT outbound_messages_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'RETRY'::text, 'SENT'::text, 'DLQ'::text])))
)
WITH (autovacuum_vacuum_scale_factor='0.05', autovacuum_analyze_scale_factor='0.05');


ALTER TABLE public.outbound_messages OWNER TO n8n;

--
-- Name: payment_transactions; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.payment_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid,
    tenant_id uuid,
    amount_cents integer NOT NULL,
    currency text DEFAULT 'DZD'::text NOT NULL,
    provider text DEFAULT 'ccp'::text NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    provider_ref text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.payment_transactions OWNER TO n8n;

--
-- Name: processed_data; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.processed_data (
    "workflowId" character varying(36) NOT NULL,
    context character varying(255) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    value text NOT NULL
);


ALTER TABLE public.processed_data OWNER TO n8n;

--
-- Name: project; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.project (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    icon json,
    description character varying(512),
    "creatorId" uuid
);


ALTER TABLE public.project OWNER TO n8n;

--
-- Name: COLUMN project."creatorId"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.project."creatorId" IS 'ID of the user who created the project';


--
-- Name: project_relation; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.project_relation (
    "projectId" character varying(36) NOT NULL,
    "userId" uuid NOT NULL,
    role character varying NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.project_relation OWNER TO n8n;

--
-- Name: restaurant_users; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.restaurant_users (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    channel text NOT NULL,
    user_id text NOT NULL,
    role text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT restaurant_users_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'messenger'::text]))),
    CONSTRAINT restaurant_users_role_check CHECK ((role = ANY (ARRAY['customer'::text, 'owner'::text, 'admin'::text, 'kitchen'::text])))
);


ALTER TABLE public.restaurant_users OWNER TO n8n;

--
-- Name: restaurant_users_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.restaurant_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.restaurant_users_id_seq OWNER TO n8n;

--
-- Name: restaurant_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.restaurant_users_id_seq OWNED BY public.restaurant_users.id;


--
-- Name: restaurants; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.restaurants (
    restaurant_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    timezone text DEFAULT 'Africa/Algiers'::text NOT NULL,
    currency text DEFAULT 'EUR'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.restaurants OWNER TO n8n;

--
-- Name: role; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.role (
    slug character varying(128) NOT NULL,
    "displayName" text,
    description text,
    "roleType" text,
    "systemRole" boolean DEFAULT false NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.role OWNER TO n8n;

--
-- Name: COLUMN role.slug; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.role.slug IS 'Unique identifier of the role for example: "global:owner"';


--
-- Name: COLUMN role."displayName"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.role."displayName" IS 'Name used to display in the UI';


--
-- Name: COLUMN role.description; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.role.description IS 'Text describing the scope in more detail of users';


--
-- Name: COLUMN role."roleType"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.role."roleType" IS 'Type of the role, e.g., global, project, or workflow';


--
-- Name: COLUMN role."systemRole"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.role."systemRole" IS 'Indicates if the role is managed by the system and cannot be edited';


--
-- Name: role_scope; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.role_scope (
    "roleSlug" character varying(128) NOT NULL,
    "scopeSlug" character varying(128) NOT NULL
);


ALTER TABLE public.role_scope OWNER TO n8n;

--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.schema_migrations (
    id integer NOT NULL,
    filename text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL,
    checksum text
);


ALTER TABLE public.schema_migrations OWNER TO n8n;

--
-- Name: schema_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.schema_migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.schema_migrations_id_seq OWNER TO n8n;

--
-- Name: schema_migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.schema_migrations_id_seq OWNED BY public.schema_migrations.id;


--
-- Name: scope; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.scope (
    slug character varying(128) NOT NULL,
    "displayName" text,
    description text
);


ALTER TABLE public.scope OWNER TO n8n;

--
-- Name: COLUMN scope.slug; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.scope.slug IS 'Unique identifier of the scope for example: "project:create"';


--
-- Name: COLUMN scope."displayName"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.scope."displayName" IS 'Name used to display in the UI';


--
-- Name: COLUMN scope.description; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.scope.description IS 'Text describing the scope in more detail of users';


--
-- Name: security_events; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.security_events (
    id bigint NOT NULL,
    tenant_id uuid,
    restaurant_id uuid,
    conversation_key text,
    channel text,
    user_id text,
    event_type public.security_event_type_enum NOT NULL,
    severity text DEFAULT 'MEDIUM'::text NOT NULL,
    payload_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT security_events_severity_check CHECK ((severity = ANY (ARRAY['LOW'::text, 'MEDIUM'::text, 'HIGH'::text, 'CRITICAL'::text])))
)
WITH (autovacuum_vacuum_scale_factor='0.02', autovacuum_analyze_scale_factor='0.02');


ALTER TABLE public.security_events OWNER TO n8n;

--
-- Name: security_events_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.security_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.security_events_id_seq OWNER TO n8n;

--
-- Name: security_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.security_events_id_seq OWNED BY public.security_events.id;


--
-- Name: settings; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.settings (
    key character varying(255) NOT NULL,
    value text NOT NULL,
    "loadOnStartup" boolean DEFAULT false NOT NULL
);


ALTER TABLE public.settings OWNER TO n8n;

--
-- Name: shared_credentials; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.shared_credentials (
    "credentialsId" character varying(36) NOT NULL,
    "projectId" character varying(36) NOT NULL,
    role text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.shared_credentials OWNER TO n8n;

--
-- Name: shared_workflow; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.shared_workflow (
    "workflowId" character varying(36) NOT NULL,
    "projectId" character varying(36) NOT NULL,
    role text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.shared_workflow OWNER TO n8n;

--
-- Name: support_assignments; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.support_assignments (
    id bigint NOT NULL,
    ticket_id bigint NOT NULL,
    admin_user_id text NOT NULL,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    released_at timestamp with time zone
);


ALTER TABLE public.support_assignments OWNER TO n8n;

--
-- Name: support_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.support_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.support_assignments_id_seq OWNER TO n8n;

--
-- Name: support_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.support_assignments_id_seq OWNED BY public.support_assignments.id;


--
-- Name: support_ticket_messages; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.support_ticket_messages (
    id bigint NOT NULL,
    ticket_id bigint NOT NULL,
    direction text NOT NULL,
    from_user_id text,
    to_user_id text,
    body_text text NOT NULL,
    meta_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT support_ticket_messages_direction_check CHECK ((direction = ANY (ARRAY['INBOUND'::text, 'OUTBOUND'::text, 'INTERNAL'::text])))
);


ALTER TABLE public.support_ticket_messages OWNER TO n8n;

--
-- Name: support_ticket_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.support_ticket_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.support_ticket_messages_id_seq OWNER TO n8n;

--
-- Name: support_ticket_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.support_ticket_messages_id_seq OWNED BY public.support_ticket_messages.id;


--
-- Name: support_tickets; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.support_tickets (
    ticket_id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    channel text NOT NULL,
    conversation_key text NOT NULL,
    customer_user_id text NOT NULL,
    status text DEFAULT 'OPEN'::text NOT NULL,
    priority text DEFAULT 'NORMAL'::text NOT NULL,
    reason_code text DEFAULT 'HELP'::text NOT NULL,
    subject text,
    context_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_at timestamp with time zone,
    CONSTRAINT support_tickets_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'instagram'::text, 'messenger'::text]))),
    CONSTRAINT support_tickets_priority_check CHECK ((priority = ANY (ARRAY['LOW'::text, 'NORMAL'::text, 'HIGH'::text]))),
    CONSTRAINT support_tickets_reason_code_check CHECK ((reason_code = ANY (ARRAY['HELP'::text, 'DELIVERY_AMBIGUOUS'::text, 'PAYMENT_ISSUE'::text, 'FAQ_FALLBACK'::text, 'OTHER'::text]))),
    CONSTRAINT support_tickets_status_check CHECK ((status = ANY (ARRAY['OPEN'::text, 'ASSIGNED'::text, 'CLOSED'::text])))
);


ALTER TABLE public.support_tickets OWNER TO n8n;

--
-- Name: support_tickets_ticket_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.support_tickets_ticket_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.support_tickets_ticket_id_seq OWNER TO n8n;

--
-- Name: support_tickets_ticket_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.support_tickets_ticket_id_seq OWNED BY public.support_tickets.ticket_id;


--
-- Name: tag_entity; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.tag_entity (
    name character varying(24) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    id character varying(36) NOT NULL
);


ALTER TABLE public.tag_entity OWNER TO n8n;

--
-- Name: tenants; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.tenants (
    tenant_id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tenants OWNER TO n8n;

--
-- Name: test_case_execution; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.test_case_execution (
    id character varying(36) NOT NULL,
    "testRunId" character varying(36) NOT NULL,
    "executionId" integer,
    status character varying NOT NULL,
    "runAt" timestamp(3) with time zone,
    "completedAt" timestamp(3) with time zone,
    "errorCode" character varying,
    "errorDetails" json,
    metrics json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    inputs json,
    outputs json
);


ALTER TABLE public.test_case_execution OWNER TO n8n;

--
-- Name: test_run; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.test_run (
    id character varying(36) NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    status character varying NOT NULL,
    "errorCode" character varying,
    "errorDetails" json,
    "runAt" timestamp(3) with time zone,
    "completedAt" timestamp(3) with time zone,
    metrics json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.test_run OWNER TO n8n;

--
-- Name: user; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public."user" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying(255),
    "firstName" character varying(32),
    "lastName" character varying(32),
    password character varying(255),
    "personalizationAnswers" json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    settings json,
    disabled boolean DEFAULT false NOT NULL,
    "mfaEnabled" boolean DEFAULT false NOT NULL,
    "mfaSecret" text,
    "mfaRecoveryCodes" text,
    "lastActiveAt" date,
    "roleSlug" character varying(128) DEFAULT 'global:member'::character varying NOT NULL,
    role character varying(255)
);


ALTER TABLE public."user" OWNER TO n8n;

--
-- Name: user_api_keys; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.user_api_keys (
    id character varying(36) NOT NULL,
    "userId" uuid NOT NULL,
    label character varying(100) NOT NULL,
    "apiKey" character varying NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    scopes json,
    audience character varying DEFAULT 'public-api'::character varying NOT NULL
);


ALTER TABLE public.user_api_keys OWNER TO n8n;

--
-- Name: v_admin_wa_audit_recent; Type: VIEW; Schema: public; Owner: n8n
--

CREATE VIEW public.v_admin_wa_audit_recent AS
 SELECT a.id,
    a.actor_phone,
    a.actor_role,
    a.action,
    a.target_type,
    a.target_id,
    a.success,
    a.created_at,
    r.name AS restaurant_name
   FROM (public.admin_wa_audit_log a
     LEFT JOIN public.restaurants r ON ((a.restaurant_id = r.restaurant_id)))
  WHERE (a.created_at > (now() - '24:00:00'::interval))
  ORDER BY a.created_at DESC;


ALTER TABLE public.v_admin_wa_audit_recent OWNER TO n8n;

--
-- Name: variables; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.variables (
    key character varying(50) NOT NULL,
    type character varying(50) DEFAULT 'string'::character varying NOT NULL,
    value character varying(255),
    id character varying(36) NOT NULL,
    "projectId" character varying(36)
);


ALTER TABLE public.variables OWNER TO n8n;

--
-- Name: voice_interactions; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.voice_interactions (
    id bigint NOT NULL,
    conversation_key text NOT NULL,
    audio_url text NOT NULL,
    transcript text,
    confidence numeric,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.voice_interactions OWNER TO n8n;

--
-- Name: voice_interactions_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.voice_interactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.voice_interactions_id_seq OWNER TO n8n;

--
-- Name: voice_interactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.voice_interactions_id_seq OWNED BY public.voice_interactions.id;


--
-- Name: webhook_entity; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.webhook_entity (
    "webhookPath" character varying NOT NULL,
    method character varying NOT NULL,
    node character varying NOT NULL,
    "webhookId" character varying,
    "pathLength" integer,
    "workflowId" character varying(36) NOT NULL
);


ALTER TABLE public.webhook_entity OWNER TO n8n;

--
-- Name: webhook_replay_guard; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.webhook_replay_guard (
    id bigint NOT NULL,
    payload_hash text NOT NULL,
    channel text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:05:00'::interval) NOT NULL
);


ALTER TABLE public.webhook_replay_guard OWNER TO n8n;

--
-- Name: webhook_replay_guard_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.webhook_replay_guard_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.webhook_replay_guard_id_seq OWNER TO n8n;

--
-- Name: webhook_replay_guard_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.webhook_replay_guard_id_seq OWNED BY public.webhook_replay_guard.id;


--
-- Name: workflow_dependency; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.workflow_dependency (
    id integer NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "workflowVersionId" integer NOT NULL,
    "dependencyType" character varying(32) NOT NULL,
    "dependencyKey" character varying(255) NOT NULL,
    "dependencyInfo" json,
    "indexVersionId" smallint DEFAULT 1 NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.workflow_dependency OWNER TO n8n;

--
-- Name: COLUMN workflow_dependency."workflowVersionId"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.workflow_dependency."workflowVersionId" IS 'Version of the workflow';


--
-- Name: COLUMN workflow_dependency."dependencyType"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.workflow_dependency."dependencyType" IS 'Type of dependency: "credential", "nodeType", "webhookPath", or "workflowCall"';


--
-- Name: COLUMN workflow_dependency."dependencyKey"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.workflow_dependency."dependencyKey" IS 'ID or name of the dependency';


--
-- Name: COLUMN workflow_dependency."dependencyInfo"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.workflow_dependency."dependencyInfo" IS 'Additional info about the dependency, interpreted based on type';


--
-- Name: COLUMN workflow_dependency."indexVersionId"; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.workflow_dependency."indexVersionId" IS 'Version of the index structure';


--
-- Name: workflow_dependency_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

ALTER TABLE public.workflow_dependency ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.workflow_dependency_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: workflow_entity; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.workflow_entity (
    name character varying(128) NOT NULL,
    active boolean DEFAULT false NOT NULL,
    nodes json NOT NULL,
    connections json NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    settings json,
    "staticData" json,
    "pinData" json,
    "versionId" character(36) DEFAULT gen_random_uuid() NOT NULL,
    "triggerCount" integer DEFAULT 0 NOT NULL,
    id character varying(36) NOT NULL,
    meta json,
    "parentFolderId" character varying(36) DEFAULT NULL::character varying,
    "isArchived" boolean DEFAULT false NOT NULL,
    "versionCounter" integer DEFAULT 1 NOT NULL,
    description text,
    "activeVersionId" character varying(36)
);


ALTER TABLE public.workflow_entity OWNER TO n8n;

--
-- Name: workflow_errors; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.workflow_errors (
    id bigint NOT NULL,
    workflow_name text,
    node_name text,
    error_message text,
    stack text,
    execution_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
)
WITH (autovacuum_vacuum_scale_factor='0.05', autovacuum_analyze_scale_factor='0.05');


ALTER TABLE public.workflow_errors OWNER TO n8n;

--
-- Name: workflow_errors_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

CREATE SEQUENCE public.workflow_errors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.workflow_errors_id_seq OWNER TO n8n;

--
-- Name: workflow_errors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n
--

ALTER SEQUENCE public.workflow_errors_id_seq OWNED BY public.workflow_errors.id;


--
-- Name: workflow_history; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.workflow_history (
    "versionId" character varying(36) NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    authors character varying(255) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    nodes json NOT NULL,
    connections json NOT NULL,
    name character varying(128),
    autosaved boolean DEFAULT false NOT NULL,
    description text
);


ALTER TABLE public.workflow_history OWNER TO n8n;

--
-- Name: workflow_publish_history; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.workflow_publish_history (
    id integer NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "versionId" character varying(36) NOT NULL,
    event character varying(36) NOT NULL,
    "userId" uuid,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CHK_workflow_publish_history_event" CHECK (((event)::text = ANY ((ARRAY['activated'::character varying, 'deactivated'::character varying])::text[])))
);


ALTER TABLE public.workflow_publish_history OWNER TO n8n;

--
-- Name: COLUMN workflow_publish_history.event; Type: COMMENT; Schema: public; Owner: n8n
--

COMMENT ON COLUMN public.workflow_publish_history.event IS 'Type of history record: activated (workflow is now active), deactivated (workflow is now inactive)';


--
-- Name: workflow_publish_history_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n
--

ALTER TABLE public.workflow_publish_history ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.workflow_publish_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: workflow_statistics; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.workflow_statistics (
    count integer DEFAULT 0,
    "latestEvent" timestamp(3) with time zone,
    name character varying(128) NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "rootCount" integer DEFAULT 0
);


ALTER TABLE public.workflow_statistics OWNER TO n8n;

--
-- Name: workflows_tags; Type: TABLE; Schema: public; Owner: n8n
--

CREATE TABLE public.workflows_tags (
    "workflowId" character varying(36) NOT NULL,
    "tagId" character varying(36) NOT NULL
);


ALTER TABLE public.workflows_tags OWNER TO n8n;

--
-- Name: retention_runs run_id; Type: DEFAULT; Schema: ops; Owner: n8n
--

ALTER TABLE ONLY ops.retention_runs ALTER COLUMN run_id SET DEFAULT nextval('ops.retention_runs_run_id_seq'::regclass);


--
-- Name: address_clarification_requests id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.address_clarification_requests ALTER COLUMN id SET DEFAULT nextval('public.address_clarification_requests_id_seq'::regclass);


--
-- Name: admin_audit_log id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.admin_audit_log ALTER COLUMN id SET DEFAULT nextval('public.admin_audit_log_id_seq'::regclass);


--
-- Name: admin_phone_allowlist id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.admin_phone_allowlist ALTER COLUMN id SET DEFAULT nextval('public.admin_phone_allowlist_id_seq'::regclass);


--
-- Name: admin_wa_audit_log id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.admin_wa_audit_log ALTER COLUMN id SET DEFAULT nextval('public.admin_wa_audit_log_id_seq'::regclass);


--
-- Name: auth_provider_sync_history id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.auth_provider_sync_history ALTER COLUMN id SET DEFAULT nextval('public.auth_provider_sync_history_id_seq'::regclass);


--
-- Name: conversation_quarantine id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.conversation_quarantine ALTER COLUMN id SET DEFAULT nextval('public.conversation_quarantine_id_seq'::regclass);


--
-- Name: daily_metrics id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.daily_metrics ALTER COLUMN id SET DEFAULT nextval('public.daily_metrics_id_seq'::regclass);


--
-- Name: darija_patterns id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.darija_patterns ALTER COLUMN id SET DEFAULT nextval('public.darija_patterns_id_seq'::regclass);


--
-- Name: delivery_slot_reservations id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.delivery_slot_reservations ALTER COLUMN id SET DEFAULT nextval('public.delivery_slot_reservations_id_seq'::regclass);


--
-- Name: execution_annotations id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.execution_annotations ALTER COLUMN id SET DEFAULT nextval('public.execution_annotations_id_seq'::regclass);


--
-- Name: execution_entity id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.execution_entity ALTER COLUMN id SET DEFAULT nextval('public.execution_entity_id_seq'::regclass);


--
-- Name: execution_metadata id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.execution_metadata ALTER COLUMN id SET DEFAULT nextval('public.execution_metadata_temp_id_seq'::regclass);


--
-- Name: faq_entries faq_id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.faq_entries ALTER COLUMN faq_id SET DEFAULT nextval('public.faq_entries_faq_id_seq'::regclass);


--
-- Name: fraud_signals id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.fraud_signals ALTER COLUMN id SET DEFAULT nextval('public.fraud_signals_id_seq'::regclass);


--
-- Name: inbound_messages id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.inbound_messages ALTER COLUMN id SET DEFAULT nextval('public.inbound_messages_id_seq'::regclass);


--
-- Name: latency_samples id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.latency_samples ALTER COLUMN id SET DEFAULT nextval('public.latency_samples_id_seq'::regclass);


--
-- Name: migrations id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.migrations ALTER COLUMN id SET DEFAULT nextval('public.migrations_id_seq'::regclass);


--
-- Name: order_items id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.order_items ALTER COLUMN id SET DEFAULT nextval('public.order_items_id_seq'::regclass);


--
-- Name: order_status_history id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.order_status_history ALTER COLUMN id SET DEFAULT nextval('public.order_status_history_id_seq'::regclass);


--
-- Name: restaurant_users id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.restaurant_users ALTER COLUMN id SET DEFAULT nextval('public.restaurant_users_id_seq'::regclass);


--
-- Name: schema_migrations id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.schema_migrations ALTER COLUMN id SET DEFAULT nextval('public.schema_migrations_id_seq'::regclass);


--
-- Name: security_events id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.security_events ALTER COLUMN id SET DEFAULT nextval('public.security_events_id_seq'::regclass);


--
-- Name: support_assignments id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.support_assignments ALTER COLUMN id SET DEFAULT nextval('public.support_assignments_id_seq'::regclass);


--
-- Name: support_ticket_messages id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.support_ticket_messages ALTER COLUMN id SET DEFAULT nextval('public.support_ticket_messages_id_seq'::regclass);


--
-- Name: support_tickets ticket_id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.support_tickets ALTER COLUMN ticket_id SET DEFAULT nextval('public.support_tickets_ticket_id_seq'::regclass);


--
-- Name: voice_interactions id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.voice_interactions ALTER COLUMN id SET DEFAULT nextval('public.voice_interactions_id_seq'::regclass);


--
-- Name: webhook_replay_guard id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.webhook_replay_guard ALTER COLUMN id SET DEFAULT nextval('public.webhook_replay_guard_id_seq'::regclass);


--
-- Name: workflow_errors id; Type: DEFAULT; Schema: public; Owner: n8n
--

ALTER TABLE ONLY public.workflow_errors ALTER COLUMN id SET DEFAULT nextval('public.workflow_errors_id_seq'::regclass);


--
-- Data for Name: retention_runs; Type: TABLE DATA; Schema: ops; Owner: n8n
--

COPY ops.retention_runs (run_id, run_started_at, run_finished_at, dry_run, table_name, cutoff_ts, batch_size, deleted_rows, details_json, status) FROM stdin;
\.


--
-- Data for Name: security_event_types; Type: TABLE DATA; Schema: ops; Owner: n8n
--

COPY ops.security_event_types (code, description, created_at) FROM stdin;
AUTH_DENY	Auth token invalid / access denied	2026-01-27 02:30:16.118322+00
AUDIO_URL_BLOCKED	Voice URL rejected by security gate	2026-01-27 02:30:16.118322+00
RETENTION_RUN	Retention purge job execution log	2026-01-27 02:30:16.118322+00
CONTRACT_VALIDATION_FAILED	Inbound payload rejected by JSON Schema validation	2026-01-27 08:04:16.659668+00
SLO_BREACH	SLO threshold breached (queue/outbox)	2026-01-27 08:04:16.659668+00
DELIVERY_ZONE_NOT_FOUND	Delivery: zone not found for wilaya/commune	2026-01-27 08:04:37.546357+00
DELIVERY_ZONE_INACTIVE	Delivery: zone inactive	2026-01-27 08:04:37.546357+00
DELIVERY_MIN_ORDER	Delivery: minimum order not reached	2026-01-27 08:04:37.546357+00
DELIVERY_QUOTE_OK	Delivery: quote computed successfully	2026-01-27 08:04:37.546357+00
DELIVERY_DISABLED	Delivery: feature disabled	2026-01-27 08:04:37.546357+00
ADDRESS_AMBIGUOUS	Delivery: address missing/ambiguous, clarification requested	2026-01-27 08:04:37.546357+00
SLOT_FULL	Delivery: selected time slot at capacity	2026-01-27 08:04:37.546357+00
DELIVERY_SLOT_RESERVED	Delivery: time slot reserved for order	2026-01-27 08:04:37.546357+00
\.


--
-- Data for Name: address_clarification_requests; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.address_clarification_requests (id, order_id, missing_fields, attempts, status, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: admin_audit_log; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.admin_audit_log (id, tenant_id, restaurant_id, actor_client_id, actor_name, action, object_type, object_id, request_id, ip, user_agent, payload_json, created_at) FROM stdin;
\.


--
-- Data for Name: admin_phone_allowlist; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.admin_phone_allowlist (id, phone_number, role, label, active, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: admin_wa_audit_log; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.admin_wa_audit_log (id, tenant_id, restaurant_id, actor_phone, actor_role, action, target_type, target_id, command_raw, metadata_json, ip_address, success, error_message, created_at) FROM stdin;
\.


--
-- Data for Name: annotation_tag_entity; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.annotation_tag_entity (id, name, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: api_clients; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.api_clients (client_id, client_name, token_hash, tenant_id, restaurant_id, scopes, is_active, last_used_at, created_at) FROM stdin;
9add7b80-e517-492e-942d-77bb5935f5aa	test_inbound_client	057a080348f8718bf30fce2c3af94a73230cee2feeaa8e726b626349e00fcbe2	00000000-0000-0000-0000-000000000001	00000000-0000-0000-0000-000000000000	["inbound:write"]	t	\N	2026-01-27 13:56:23.963066+00
2bb2193f-dd77-46f4-a718-a979e20bc0b5	test_admin_client	e211d8dc92775d53e4be89b8f2b0481a4bf64016e50e74113a33ea897d0e05ea	00000000-0000-0000-0000-000000000001	00000000-0000-0000-0000-000000000000	["admin:read", "admin:write"]	t	\N	2026-01-27 13:56:23.974191+00
d5e03588-899b-41a0-82bd-0f013eee81ff	test_customer_client	ad48ebfe6e69a50bfeed149de3ec5a925eb0b1ebf1c154771910e1fb19e09a80	00000000-0000-0000-0000-000000000001	00000000-0000-0000-0000-000000000000	["delivery:quote"]	t	\N	2026-01-27 13:56:23.974928+00
\.


--
-- Data for Name: auth_identity; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.auth_identity ("userId", "providerId", "providerType", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: auth_provider_sync_history; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.auth_provider_sync_history (id, "providerType", "runMode", status, "startedAt", "endedAt", scanned, created, updated, disabled, error) FROM stdin;
\.


--
-- Data for Name: binary_data; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.binary_data ("fileId", "sourceType", "sourceId", data, "mimeType", "fileName", "fileSize", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: carts; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.carts (conversation_key, cart_json, created_at, updated_at) FROM stdin;
test-conv-002	{"items": []}	2026-01-27 08:21:47.499724+00	2026-01-27 08:23:55.164545+00
\.


--
-- Data for Name: chat_hub_agents; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.chat_hub_agents (id, name, description, "systemPrompt", "ownerId", "credentialId", provider, model, "createdAt", "updatedAt", tools, icon) FROM stdin;
\.


--
-- Data for Name: chat_hub_messages; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.chat_hub_messages (id, "sessionId", "previousMessageId", "revisionOfMessageId", "retryOfMessageId", type, name, content, provider, model, "workflowId", "executionId", "createdAt", "updatedAt", "agentId", status, attachments) FROM stdin;
\.


--
-- Data for Name: chat_hub_sessions; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.chat_hub_sessions (id, title, "ownerId", "lastMessageAt", "credentialId", provider, model, "workflowId", "createdAt", "updatedAt", "agentId", "agentName", tools) FROM stdin;
\.


--
-- Data for Name: conversation_quarantine; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.conversation_quarantine (id, conversation_key, reason, active, expires_at, created_at) FROM stdin;
\.


--
-- Data for Name: conversation_state; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.conversation_state (conversation_key, tenant_id, restaurant_id, channel, user_id, state_json, created_at, updated_at) FROM stdin;
test-conv-002	00000000-0000-0000-0000-000000000001	00000000-0000-0000-0000-000000000000	whatsapp	+212600000002	{"stage": "PLACED", "serviceMode": "a_emporter", "last_order_id": "544be146-5f3d-4c5c-a950-9b4bd22a5e41"}	2026-01-27 08:21:22.299905+00	2026-01-27 08:23:55.164545+00
\.


--
-- Data for Name: credentials_entity; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.credentials_entity (name, data, type, "createdAt", "updatedAt", id, "isManaged", "isGlobal", "isResolvable", "resolvableAllowFallback", "resolverId") FROM stdin;
\.


--
-- Data for Name: customer_preferences; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.customer_preferences (tenant_id, phone, locale, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: daily_metrics; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.daily_metrics (id, metric_date, metric_name, metric_value, metadata, created_at) FROM stdin;
\.


--
-- Data for Name: darija_patterns; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.darija_patterns (id, pattern, intent, confidence, active, created_at) FROM stdin;
\.


--
-- Data for Name: data_table; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.data_table (id, name, "projectId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: data_table_column; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.data_table_column (id, name, type, index, "dataTableId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: delivery_fee_rules; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.delivery_fee_rules (rule_id, restaurant_id, name, start_time, end_time, surcharge_cents, free_delivery_threshold_cents, is_active, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: delivery_slot_reservations; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.delivery_slot_reservations (id, order_id, slot_id, reserved_at) FROM stdin;
\.


--
-- Data for Name: delivery_time_slots; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.delivery_time_slots (slot_id, restaurant_id, day_of_week, start_time, end_time, capacity, is_active, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: delivery_zones; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.delivery_zones (zone_id, restaurant_id, wilaya, commune, fee_base_cents, min_order_cents, eta_min, eta_max, is_active, created_at, updated_at) FROM stdin;
3e558a90-e10f-409f-a7d8-1b28de20d138	00000000-0000-0000-0000-000000000000	Alger	Hussein Dey	350	2000	30	45	t	2026-01-27 08:27:01.148217+00	2026-01-27 08:27:01.148217+00
\.


--
-- Data for Name: dynamic_credential_entry; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.dynamic_credential_entry (credential_id, subject_id, resolver_id, data, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: dynamic_credential_resolver; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.dynamic_credential_resolver (id, name, type, config, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: event_destinations; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.event_destinations (id, destination, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: execution_annotation_tags; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.execution_annotation_tags ("annotationId", "tagId") FROM stdin;
\.


--
-- Data for Name: execution_annotations; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.execution_annotations (id, "executionId", vote, note, "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: execution_data; Type: TABLE DATA; Schema: public; Owner: n8n
--

COPY public.execution_data ("executionId", "workflowData", data, "workflowVersionId") FROM stdin;
542	{"id":"2yjSMmSZgmFtRnqn","name":"W18 - Media Fetch Worker (Graph API + DLQ)","active":true,"createdAt":"2026-02-22T20:56:05.016Z","updatedAt":"2026-02-22T20:56:05.016Z","nodes":[{"parameters":{"notice":"","rule":{"interval":[{"field":"seconds","secondsInterval":15}]}},"id":"media-worker-trigger","name":"CRON - Every 15s","type":"n8n-nodes-base.scheduleTrigger","typeVersion":1,"position":[-2400,0]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-config","name":"B0 - Config","type":"n8n-nodes-base.code","typeVersion":2,"position":[-2150,0]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.skip}}","operation":"isFalse"}]},"options":{}},"id":"media-enabled-check","name":"B0 - Enabled?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-1900,0]},{"parameters":{"operation":"pop","list":"ralphe:media:pending","tail":true,"propertyName":"propertyName","options":{}},"id":"media-rpop","name":"B1 - RPOP Media Request","type":"n8n-nodes-base.redis","typeVersion":1,"position":[-1650,-100],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-parse-msg","name":"B1 - Parse Request","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1400,-100]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.empty || $json.invalid}}","operation":"isTrue"}]},"options":{}},"id":"media-check-empty","name":"B1 - Empty/Invalid?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-1150,-100]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.notReady}}","operation":"isTrue"}]},"options":{}},"id":"media-check-ready","name":"B1 - Not Ready?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-900,-200]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-prepare-requeue","name":"B1 - Prepare Requeue","type":"n8n-nodes-base.code","typeVersion":2,"position":[-650,-300]},{"parameters":{"operation":"push","list":"ralphe:media:pending","messageData":"={{$json.requeue}}","tail":true},"id":"media-requeue","name":"B1 - LPUSH Requeue","type":"n8n-nodes-base.redis","typeVersion":1,"position":[-400,-300],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-fetch","name":"B2 - Fetch Media URL","type":"n8n-nodes-base.code","typeVersion":2,"position":[-650,-100]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.fetched}}","operation":"isTrue"}]},"options":{}},"id":"media-fetch-ok","name":"B2 - Fetch OK?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-400,-100]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-prepare-update","name":"B3 - Prepare Update","type":"n8n-nodes-base.code","typeVersion":2,"position":[-150,-200]},{"parameters":{"operation":"set","key":"={{$json.updateKey}}","value":"={{$json.updatePayload}}","keyType":"automatic","expire":true,"ttl":"={{$json.ttl}}"},"id":"media-store-url","name":"B3 - Store Resolved URL","type":"n8n-nodes-base.redis","typeVersion":1,"position":[100,-200],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-handle-fail","name":"B2 - Handle Failure","type":"n8n-nodes-base.code","typeVersion":2,"position":[-150,0]},{"parameters":{"conditions":{"string":[{"value1":"={{$json.action}}","value2":"retry"}]},"options":{}},"id":"media-retry-or-dlq","name":"B2 - Retry or DLQ?","type":"n8n-nodes-base.if","typeVersion":2,"position":[100,0]},{"parameters":{"operation":"push","list":"ralphe:media:pending","messageData":"={{$json.retryReq}}","tail":true},"id":"media-push-retry","name":"B3 - LPUSH Retry","type":"n8n-nodes-base.redis","typeVersion":1,"position":[350,-100],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"operation":"push","list":"ralphe:media:dlq","messageData":"={{$json.dlqEntry}}","tail":false},"id":"media-push-dlq","name":"B3 - Push to DLQ","type":"n8n-nodes-base.redis","typeVersion":1,"position":[350,100],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.is401}}","operation":"isTrue"}]},"options":{}},"id":"media-is-401","name":"B3 - Is 401 Auth Error?","type":"n8n-nodes-base.if","typeVersion":2,"position":[600,100]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-prepare-alert","name":"B4 - Prepare Admin Alert","type":"n8n-nodes-base.code","typeVersion":2,"position":[850,0]},{"parameters":{"operation":"push","list":"ralphe:alerts:critical","messageData":"={{JSON.stringify($json.alertPayload)}}","tail":false},"id":"media-push-alert","name":"B4 - Push Alert","type":"n8n-nodes-base.redis","typeVersion":1,"position":[1100,0],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-success","name":"END - Success","type":"n8n-nodes-base.code","typeVersion":2,"position":[350,-200]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-retry","name":"END - Retry Scheduled","type":"n8n-nodes-base.code","typeVersion":2,"position":[600,-100]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-dlq","name":"END - DLQ","type":"n8n-nodes-base.code","typeVersion":2,"position":[850,200]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-dlq-alert","name":"END - DLQ + Alert","type":"n8n-nodes-base.code","typeVersion":2,"position":[1350,0]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-idle","name":"END - Idle","type":"n8n-nodes-base.code","typeVersion":2,"position":[-900,100]}],"connections":{"CRON - Every 15s":{"main":[[{"node":"B0 - Config","type":"main","index":0}]]},"B0 - Config":{"main":[[{"node":"B0 - Enabled?","type":"main","index":0}]]},"B0 - Enabled?":{"main":[[{"node":"B1 - RPOP Media Request","type":"main","index":0}],[{"node":"END - Idle","type":"main","index":0}]]},"B1 - RPOP Media Request":{"main":[[{"node":"B1 - Parse Request","type":"main","index":0}]]},"B1 - Parse Request":{"main":[[{"node":"B1 - Empty/Invalid?","type":"main","index":0}]]},"B1 - Empty/Invalid?":{"main":[[{"node":"END - Idle","type":"main","index":0}],[{"node":"B1 - Not Ready?","type":"main","index":0}]]},"B1 - Not Ready?":{"main":[[{"node":"B1 - Prepare Requeue","type":"main","index":0}],[{"node":"B2 - Fetch Media URL","type":"main","index":0}]]},"B1 - Prepare Requeue":{"main":[[{"node":"B1 - LPUSH Requeue","type":"main","index":0}]]},"B1 - LPUSH Requeue":{"main":[[{"node":"END - Idle","type":"main","index":0}]]},"B2 - Fetch Media URL":{"main":[[{"node":"B2 - Fetch OK?","type":"main","index":0}]]},"B2 - Fetch OK?":{"main":[[{"node":"B3 - Prepare Update","type":"main","index":0}],[{"node":"B2 - Handle Failure","type":"main","index":0}]]},"B3 - Prepare Update":{"main":[[{"node":"B3 - Store Resolved URL","type":"main","index":0}]]},"B3 - Store Resolved URL":{"main":[[{"node":"END - Success","type":"main","index":0}]]},"B2 - Handle Failure":{"main":[[{"node":"B2 - Retry or DLQ?","type":"main","index":0}]]},"B2 - Retry or DLQ?":{"main":[[{"node":"B3 - LPUSH Retry","type":"main","index":0}],[{"node":"B3 - Push to DLQ","type":"main","index":0}]]},"B3 - LPUSH Retry":{"main":[[{"node":"END - Retry Scheduled","type":"main","index":0}]]},"B3 - Push to DLQ":{"main":[[{"node":"B3 - Is 401 Auth Error?","type":"main","index":0}]]},"B3 - Is 401 Auth Error?":{"main":[[{"node":"B4 - Prepare Admin Alert","type":"main","index":0}],[{"node":"END - DLQ","type":"main","index":0}]]},"B4 - Prepare Admin Alert":{"main":[[{"node":"B4 - Push Alert","type":"main","index":0}]]},"B4 - Push Alert":{"main":[[{"node":"END - DLQ + Alert","type":"main","index":0}]]}},"settings":{"executionTimeout":300,"saveExecutionProgress":true,"saveManualExecutions":true},"staticData":{"node:CRON - Every 15s":{"recurrenceRules":[]}},"pinData":null}	[{"resultData":"1"},{"error":"2","runData":"3"},{"message":"4","stack":"5"},{},"Failed to run workflow due to missing execution data","Error: Failed to run workflow due to missing execution data\\n    at Queue.onFailed (/usr/local/lib/node_modules/n8n/node_modules/bull/lib/job.js:516:18)\\n    at Queue.emit (node:events:518:28)\\n    at Object.module.exports.emitSafe (/usr/local/lib/node_modules/n8n/node_modules/bull/lib/utils.js:50:20)\\n    at EventEmitter.messageHandler (/usr/local/lib/node_modules/n8n/node_modules/bull/lib/queue.js:476:15)\\n    at EventEmitter.emit (node:events:518:28)\\n    at DataHandler.handleSubscriberReply (/usr/local/lib/node_modules/n8n/node_modules/ioredis/built/DataHandler.js:80:32)\\n    at DataHandler.returnReply (/usr/local/lib/node_modules/n8n/node_modules/ioredis/built/DataHandler.js:47:18)\\n    at JavascriptRedisParser.returnReply (/usr/local/lib/node_modules/n8n/node_modules/ioredis/built/DataHandler.js:21:22)\\n    at JavascriptRedisParser.execute (/usr/local/lib/node_modules/n8n/node_modules/redis-parser/lib/parser.js:544:14)\\n    at Socket.<anonymous> (/usr/local/lib/node_modules/n8n/node_modules/ioredis/built/DataHandler.js:25:20)"]	\N
306	{"id":"2yjSMmSZgmFtRnqn","name":"W18 - Media Fetch Worker (Graph API + DLQ)","nodes":[{"parameters":{"notice":"","rule":{"interval":[{"field":"seconds","secondsInterval":15}]}},"id":"media-worker-trigger","name":"CRON - Every 15s","type":"n8n-nodes-base.scheduleTrigger","typeVersion":1,"position":[-2400,0]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-config","name":"B0 - Config","type":"n8n-nodes-base.code","typeVersion":2,"position":[-2150,0]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.skip}}","operation":"isFalse"}]},"options":{}},"id":"media-enabled-check","name":"B0 - Enabled?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-1900,0]},{"parameters":{"operation":"pop","list":"ralphe:media:pending","tail":true,"propertyName":"propertyName","options":{}},"id":"media-rpop","name":"B1 - RPOP Media Request","type":"n8n-nodes-base.redis","typeVersion":1,"position":[-1650,-100],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-parse-msg","name":"B1 - Parse Request","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1400,-100]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.empty || $json.invalid}}","operation":"isTrue"}]},"options":{}},"id":"media-check-empty","name":"B1 - Empty/Invalid?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-1150,-100]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.notReady}}","operation":"isTrue"}]},"options":{}},"id":"media-check-ready","name":"B1 - Not Ready?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-900,-200]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-prepare-requeue","name":"B1 - Prepare Requeue","type":"n8n-nodes-base.code","typeVersion":2,"position":[-650,-300]},{"parameters":{"operation":"push","list":"ralphe:media:pending","messageData":"={{$json.requeue}}","tail":true},"id":"media-requeue","name":"B1 - LPUSH Requeue","type":"n8n-nodes-base.redis","typeVersion":1,"position":[-400,-300],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-fetch","name":"B2 - Fetch Media URL","type":"n8n-nodes-base.code","typeVersion":2,"position":[-650,-100]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.fetched}}","operation":"isTrue"}]},"options":{}},"id":"media-fetch-ok","name":"B2 - Fetch OK?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-400,-100]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-prepare-update","name":"B3 - Prepare Update","type":"n8n-nodes-base.code","typeVersion":2,"position":[-150,-200]},{"parameters":{"operation":"set","key":"={{$json.updateKey}}","value":"={{$json.updatePayload}}","keyType":"automatic","expire":true,"ttl":"={{$json.ttl}}"},"id":"media-store-url","name":"B3 - Store Resolved URL","type":"n8n-nodes-base.redis","typeVersion":1,"position":[100,-200],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-handle-fail","name":"B2 - Handle Failure","type":"n8n-nodes-base.code","typeVersion":2,"position":[-150,0]},{"parameters":{"conditions":{"string":[{"value1":"={{$json.action}}","value2":"retry"}]},"options":{}},"id":"media-retry-or-dlq","name":"B2 - Retry or DLQ?","type":"n8n-nodes-base.if","typeVersion":2,"position":[100,0]},{"parameters":{"operation":"push","list":"ralphe:media:pending","messageData":"={{$json.retryReq}}","tail":true},"id":"media-push-retry","name":"B3 - LPUSH Retry","type":"n8n-nodes-base.redis","typeVersion":1,"position":[350,-100],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"operation":"push","list":"ralphe:media:dlq","messageData":"={{$json.dlqEntry}}","tail":false},"id":"media-push-dlq","name":"B3 - Push to DLQ","type":"n8n-nodes-base.redis","typeVersion":1,"position":[350,100],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.is401}}","operation":"isTrue"}]},"options":{}},"id":"media-is-401","name":"B3 - Is 401 Auth Error?","type":"n8n-nodes-base.if","typeVersion":2,"position":[600,100]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-prepare-alert","name":"B4 - Prepare Admin Alert","type":"n8n-nodes-base.code","typeVersion":2,"position":[850,0]},{"parameters":{"operation":"push","list":"ralphe:alerts:critical","messageData":"={{JSON.stringify($json.alertPayload)}}","tail":false},"id":"media-push-alert","name":"B4 - Push Alert","type":"n8n-nodes-base.redis","typeVersion":1,"position":[1100,0],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-success","name":"END - Success","type":"n8n-nodes-base.code","typeVersion":2,"position":[350,-200]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-retry","name":"END - Retry Scheduled","type":"n8n-nodes-base.code","typeVersion":2,"position":[600,-100]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-dlq","name":"END - DLQ","type":"n8n-nodes-base.code","typeVersion":2,"position":[850,200]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-dlq-alert","name":"END - DLQ + Alert","type":"n8n-nodes-base.code","typeVersion":2,"position":[1350,0]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-idle","name":"END - Idle","type":"n8n-nodes-base.code","typeVersion":2,"position":[-900,100]}],"connections":{"CRON - Every 15s":{"main":[[{"node":"B0 - Config","type":"main","index":0}]]},"B0 - Config":{"main":[[{"node":"B0 - Enabled?","type":"main","index":0}]]},"B0 - Enabled?":{"main":[[{"node":"B1 - RPOP Media Request","type":"main","index":0}],[{"node":"END - Idle","type":"main","index":0}]]},"B1 - RPOP Media Request":{"main":[[{"node":"B1 - Parse Request","type":"main","index":0}]]},"B1 - Parse Request":{"main":[[{"node":"B1 - Empty/Invalid?","type":"main","index":0}]]},"B1 - Empty/Invalid?":{"main":[[{"node":"END - Idle","type":"main","index":0}],[{"node":"B1 - Not Ready?","type":"main","index":0}]]},"B1 - Not Ready?":{"main":[[{"node":"B1 - Prepare Requeue","type":"main","index":0}],[{"node":"B2 - Fetch Media URL","type":"main","index":0}]]},"B1 - Prepare Requeue":{"main":[[{"node":"B1 - LPUSH Requeue","type":"main","index":0}]]},"B1 - LPUSH Requeue":{"main":[[{"node":"END - Idle","type":"main","index":0}]]},"B2 - Fetch Media URL":{"main":[[{"node":"B2 - Fetch OK?","type":"main","index":0}]]},"B2 - Fetch OK?":{"main":[[{"node":"B3 - Prepare Update","type":"main","index":0}],[{"node":"B2 - Handle Failure","type":"main","index":0}]]},"B3 - Prepare Update":{"main":[[{"node":"B3 - Store Resolved URL","type":"main","index":0}]]},"B3 - Store Resolved URL":{"main":[[{"node":"END - Success","type":"main","index":0}]]},"B2 - Handle Failure":{"main":[[{"node":"B2 - Retry or DLQ?","type":"main","index":0}]]},"B2 - Retry or DLQ?":{"main":[[{"node":"B3 - LPUSH Retry","type":"main","index":0}],[{"node":"B3 - Push to DLQ","type":"main","index":0}]]},"B3 - LPUSH Retry":{"main":[[{"node":"END - Retry Scheduled","type":"main","index":0}]]},"B3 - Push to DLQ":{"main":[[{"node":"B3 - Is 401 Auth Error?","type":"main","index":0}]]},"B3 - Is 401 Auth Error?":{"main":[[{"node":"B4 - Prepare Admin Alert","type":"main","index":0}],[{"node":"END - DLQ","type":"main","index":0}]]},"B4 - Prepare Admin Alert":{"main":[[{"node":"B4 - Push Alert","type":"main","index":0}]]},"B4 - Push Alert":{"main":[[{"node":"END - DLQ + Alert","type":"main","index":0}]]}},"settings":{"executionTimeout":300,"saveExecutionProgress":true,"saveManualExecutions":true}}	[{"startData":"1","resultData":"2","executionData":"3"},{},{"runData":"4","lastNodeExecuted":"5","error":"6"},{"contextData":"7","metadata":"8","nodeExecutionStack":"9","waitingExecution":"10","waitingExecutionSource":"11"},{"CRON - Every 15s":"12","B0 - Config":"13"},"B0 - Config",{"level":"14","tags":"15","extra":"16","message":"17","stack":"18"},{},{},["19"],{},{},["20"],["21"],"error",{},{"parameterName":"22"},"Could not get parameter","Error: Could not get parameter\\n    at ExecuteContext._getNodeParameter (/usr/local/lib/node_modules/n8n/node_modules/n8n-core/dist/execution-engine/node-execution-context/node-execution-context.js:195:19)\\n    at ExecuteContext.getNodeParameter (/usr/local/lib/node_modules/n8n/node_modules/n8n-core/dist/execution-engine/node-execution-context/execute-context.js:39:93)\\n    at getSandbox (/usr/local/lib/node_modules/n8n/node_modules/n8n-nodes-base/dist/nodes/Code/Code.node.js:110:31)\\n    at ExecuteContext.execute (/usr/local/lib/node_modules/n8n/node_modules/n8n-nodes-base/dist/nodes/Code/Code.node.js:129:29)\\n    at WorkflowExecute.runNode (/usr/local/lib/node_modules/n8n/node_modules/n8n-core/dist/execution-engine/workflow-execute.js:627:42)\\n    at /usr/local/lib/node_modules/n8n/node_modules/n8n-core/dist/execution-engine/workflow-execute.js:878:62\\n    at processTicksAndRejections (node:internal/process/task_queues:95:5)\\n    at /usr/local/lib/node_modules/n8n/node_modules/n8n-core/dist/execution-engine/workflow-execute.js:1211:20",{"node":"23","data":"24","source":"25"},{"hints":"26","startTime":1771799730111,"executionTime":0,"source":"27","executionStatus":"28","data":"29"},{"hints":"30","startTime":1771799730125,"executionTime":2,"source":"31","executionStatus":"14","error":"32"},"jsCode",{"parameters":"33","id":"34","name":"5","type":"35","typeVersion":2,"position":"36"},{"main":"37"},{"main":"31"},[],[],"success",{"main":"38"},[],["39"],{"level":"14","tags":"15","extra":"16","message":"17","stack":"18"},{"mode":"40","language":"41"},"media-config","n8n-nodes-base.code",[-2150,0],["42"],["43"],{"previousNode":"44"},"runOnceForAllItems","javascript",["45"],["46"],"CRON - Every 15s",{"json":"47","pairedItem":"48"},{"json":"47","pairedItem":"49"},{"timestamp":"50","Readable date":"51","Readable time":"52","Day of week":"53","Year":"54","Month":"55","Day of month":"56","Hour":"57","Minute":"58","Second":"59","Timezone":"60"},{"item":0},{"item":0},"2026-02-22T23:35:30.009+01:00","February 22nd 2026, 11:35:30 pm","11:35:30 pm","Sunday","2026","February","22","23","35","30","Europe/Paris (UTC+01:00)"]	\N
307	{"connections":{"Poll Orders":{"main":[[{"node":"Get Pending Orders","type":"main","index":0}]]},"Get Pending Orders":{"main":[[{"node":"Format Dashboard Data","type":"main","index":0}]]},"Format Dashboard Data":{"main":[[{"node":"Has New Orders?","type":"main","index":0}]]},"Has New Orders?":{"main":[[{"node":"Push to Admin Dashboard","type":"main","index":0}],[]]}},"nodes":[{"parameters":{"notice":"","rule":{"interval":[{"field":"seconds","secondsInterval":10}]}},"name":"Poll Orders","type":"n8n-nodes-base.scheduleTrigger","typeVersion":1,"position":[100,300],"id":"991af380-947a-425d-9877-ab63d7dfb5c9"},{"parameters":{"authentication":"password","resource":"entry","operation":"getAll","contentType":"","returnAll":false,"limit":50,"options":{}},"name":"Get Pending Orders","type":"n8n-nodes-base.strapi","typeVersion":1,"position":[300,300],"id":"0d7652a7-1a4f-4204-9eeb-7f6eca16848d"},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"const orders = $input.all().map(i => i.json);\\nconst newOrders = orders.filter(o => !$node['Redis Check'].json[o.id]);\\n\\n// Format for dashboard\\nconst formatted = newOrders.map(o => ({\\n  id: o.id,\\n  table: o.table_id || 'Livraison',\\n  items: o.items?.length || 0,\\n  total: o.total,\\n  time: new Date(o.createdAt).toLocaleTimeString('fr-FR'),\\n  urgent: (Date.now() - new Date(o.createdAt).getTime()) > 120000\\n}));\\n\\nreturn {\\n  json: {\\n    new_orders: formatted,\\n    count: formatted.length,\\n    has_urgent: formatted.some(o => o.urgent)\\n  }\\n};","notice":""},"name":"Format Dashboard Data","type":"n8n-nodes-base.code","typeVersion":1,"position":[500,300],"id":"cc96a42b-1229-441d-a61d-0950c779d555"},{"parameters":{"conditions":{"number":[{"value1":"={{ $json.count }}","operation":"larger","value2":0}]},"combineOperation":"all"},"name":"Has New Orders?","type":"n8n-nodes-base.if","typeVersion":1,"position":[700,300],"id":"66499ea1-c11d-4c8e-9105-a8a0c5cffb70"},{"parameters":{"curlImport":"","method":"POST","url":"={{ $env.ADMIN_WEBHOOK_URL || 'http://inventory-cms:1337/api/admin-notifications' }}","authentication":"none","provideSslCertificates":false,"sendQuery":false,"sendHeaders":false,"sendBody":true,"contentType":"json","specifyBody":"keypair","bodyParameters":{"parameters":[{"name":"type","value":"new_orders"},{"name":"orders","value":"={{ $json.new_orders }}"},{"name":"count","value":"={{ $json.count }}"},{"name":"play_sound","value":"={{ true }}"},{"name":"urgent","value":"={{ $json.has_urgent }}"}]},"options":{},"infoMessage":""},"name":"Push to Admin Dashboard","type":"n8n-nodes-base.httpRequest","typeVersion":3,"position":[900,200],"id":"06849b20-aa06-46a1-9b87-a762a3fe5115"}],"name":"W_ADMIN_LIVE_MONITOR","settings":null,"id":"VtddVi20Tn9zNqyc"}	[{"startData":"1","resultData":"2","executionData":"3"},{},{"runData":"4"},{"contextData":"5","metadata":"6","nodeExecutionStack":"7","waitingExecution":"8","waitingExecutionSource":"9"},{},{},{},["10"],{},{},{"node":"11","data":"12","source":null},{"parameters":"13","name":"14","type":"15","typeVersion":1,"position":"16","id":"17"},{"main":"18"},{"notice":"19","rule":"20"},"Poll Orders","n8n-nodes-base.scheduleTrigger",[100,300],"991af380-947a-425d-9877-ab63d7dfb5c9",["21"],"",{"interval":"22"},["23"],["24"],{"json":"25"},{"field":"26","secondsInterval":10},{"timestamp":"27","Readable date":"28","Readable time":"29","Day of week":"30","Year":"31","Month":"32","Day of month":"33","Hour":"34","Minute":"35","Second":"36","Timezone":"37"},"seconds","2026-02-22T23:35:40.002+01:00","February 22nd 2026, 11:35:40 pm","11:35:40 pm","Sunday","2026","February","22","23","35","40","Europe/Paris (UTC+01:00)"]	\N
308	{"id":"2yjSMmSZgmFtRnqn","name":"W18 - Media Fetch Worker (Graph API + DLQ)","active":true,"createdAt":"2026-02-22T20:56:05.016Z","updatedAt":"2026-02-22T20:56:05.016Z","nodes":[{"parameters":{"notice":"","rule":{"interval":[{"field":"seconds","secondsInterval":15}]}},"id":"media-worker-trigger","name":"CRON - Every 15s","type":"n8n-nodes-base.scheduleTrigger","typeVersion":1,"position":[-2400,0]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-config","name":"B0 - Config","type":"n8n-nodes-base.code","typeVersion":2,"position":[-2150,0]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.skip}}","operation":"isFalse"}]},"options":{}},"id":"media-enabled-check","name":"B0 - Enabled?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-1900,0]},{"parameters":{"operation":"pop","list":"ralphe:media:pending","tail":true,"propertyName":"propertyName","options":{}},"id":"media-rpop","name":"B1 - RPOP Media Request","type":"n8n-nodes-base.redis","typeVersion":1,"position":[-1650,-100],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-parse-msg","name":"B1 - Parse Request","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1400,-100]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.empty || $json.invalid}}","operation":"isTrue"}]},"options":{}},"id":"media-check-empty","name":"B1 - Empty/Invalid?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-1150,-100]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.notReady}}","operation":"isTrue"}]},"options":{}},"id":"media-check-ready","name":"B1 - Not Ready?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-900,-200]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-prepare-requeue","name":"B1 - Prepare Requeue","type":"n8n-nodes-base.code","typeVersion":2,"position":[-650,-300]},{"parameters":{"operation":"push","list":"ralphe:media:pending","messageData":"={{$json.requeue}}","tail":true},"id":"media-requeue","name":"B1 - LPUSH Requeue","type":"n8n-nodes-base.redis","typeVersion":1,"position":[-400,-300],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-fetch","name":"B2 - Fetch Media URL","type":"n8n-nodes-base.code","typeVersion":2,"position":[-650,-100]},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.fetched}}","operation":"isTrue"}]},"options":{}},"id":"media-fetch-ok","name":"B2 - Fetch OK?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-400,-100]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-prepare-update","name":"B3 - Prepare Update","type":"n8n-nodes-base.code","typeVersion":2,"position":[-150,-200]},{"parameters":{"operation":"set","key":"={{$json.updateKey}}","value":"={{$json.updatePayload}}","keyType":"automatic","expire":true,"ttl":"={{$json.ttl}}"},"id":"media-store-url","name":"B3 - Store Resolved URL","type":"n8n-nodes-base.redis","typeVersion":1,"position":[100,-200],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-handle-fail","name":"B2 - Handle Failure","type":"n8n-nodes-base.code","typeVersion":2,"position":[-150,0]},{"parameters":{"conditions":{"string":[{"value1":"={{$json.action}}","value2":"retry"}]},"options":{}},"id":"media-retry-or-dlq","name":"B2 - Retry or DLQ?","type":"n8n-nodes-base.if","typeVersion":2,"position":[100,0]},{"parameters":{"operation":"push","list":"ralphe:media:pending","messageData":"={{$json.retryReq}}","tail":true},"id":"media-push-retry","name":"B3 - LPUSH Retry","type":"n8n-nodes-base.redis","typeVersion":1,"position":[350,-100],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"operation":"push","list":"ralphe:media:dlq","messageData":"={{$json.dlqEntry}}","tail":false},"id":"media-push-dlq","name":"B3 - Push to DLQ","type":"n8n-nodes-base.redis","typeVersion":1,"position":[350,100],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"conditions":{"boolean":[{"value1":"={{$json.is401}}","operation":"isTrue"}]},"options":{}},"id":"media-is-401","name":"B3 - Is 401 Auth Error?","type":"n8n-nodes-base.if","typeVersion":2,"position":[600,100]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"media-prepare-alert","name":"B4 - Prepare Admin Alert","type":"n8n-nodes-base.code","typeVersion":2,"position":[850,0]},{"parameters":{"operation":"push","list":"ralphe:alerts:critical","messageData":"={{JSON.stringify($json.alertPayload)}}","tail":false},"id":"media-push-alert","name":"B4 - Push Alert","type":"n8n-nodes-base.redis","typeVersion":1,"position":[1100,0],"credentials":{"redis":{"id":"REDIS_CREDENTIAL_ID","name":"Redis"}},"continueOnFail":true},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-success","name":"END - Success","type":"n8n-nodes-base.code","typeVersion":2,"position":[350,-200]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-retry","name":"END - Retry Scheduled","type":"n8n-nodes-base.code","typeVersion":2,"position":[600,-100]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-dlq","name":"END - DLQ","type":"n8n-nodes-base.code","typeVersion":2,"position":[850,200]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-dlq-alert","name":"END - DLQ + Alert","type":"n8n-nodes-base.code","typeVersion":2,"position":[1350,0]},{"parameters":{"mode":"runOnceForAllItems","language":"javascript"},"id":"end-idle","name":"END - Idle","type":"n8n-nodes-base.code","typeVersion":2,"position":[-900,100]}],"connections":{"CRON - Every 15s":{"main":[[{"node":"B0 - Config","type":"main","index":0}]]},"B0 - Config":{"main":[[{"node":"B0 - Enabled?","type":"main","index":0}]]},"B0 - Enabled?":{"main":[[{"node":"B1 - RPOP Media Request","type":"main","index":0}],[{"node":"END - Idle","type":"main","index":0}]]},"B1 - RPOP Media Request":{"main":[[{"node":"B1 - Parse Request","type":"main","index":0}]]},"B1 - Parse Request":{"main":[[{"node":"B1 - Empty/Invalid?","type":"main","index":0}]]},"B1 - Empty/Invalid?":{"main":[[{"node":"END - Idle","type":"main","index":0}],[{"node":"B1 - Not Ready?","type":"main","index":0}]]},"B1 - Not Ready?":{"main":[[{"node":"B1 - Prepare Requeue","type":"main","index":0}],[{"node":"B2 - Fetch Media URL","type":"main","index":0}]]},"B1 - Prepare Requeue":{"main":[[{"node":"B1 - LPUSH Requeue","type":"main","index":0}]]},"B1 - LPUSH Requeue":{"main":[[{"node":"END - Idle","type":"main","index":0}]]},"B2 - Fetch Media URL":{"main":[[{"node":"B2 - Fetch OK?","type":"main","index":0}]]},"B2 - Fetch OK?":{"main":[[{"node":"B3 - Prepare Update","type":"main","index":0}],[{"node":"B2 - Handle Failure","type":"main","index":0}]]},"B3 - Prepare Update":{"main":[[{"node":"B3 - Store Resolved URL","type":"main","index":0}]]},"B3 - Store Resolved URL":{"main":[[{"node":"END - Success","type":"main","index":0}]]},"B2 - Handle Failure":{"main":[[{"node":"B2 - Retry or DLQ?","type":"main","index":0}]]},"B2 - Retry or DLQ?":{"main":[[{"node":"B3 - LPUSH Retry","type":"main","index":0}],[{"node":"B3 - Push to DLQ","type":"main","index":0}]]},"B3 - LPUSH Retry":{"main":[[{"node":"END - Retry Scheduled","type":"main","index":0}]]},"B3 - Push to DLQ":{"main":[[{"node":"B3 - Is 401 Auth Error?","type":"main","index":0}]]},"B3 - Is 401 Auth Error?":{"main":[[{"node":"B4 - Prepare Admin Alert","type":"main","index":0}],[{"node":"END - DLQ","type":"main","index":0}]]},"B4 - Prepare Admin Alert":{"main":[[{"node":"B4 - Push Alert","type":"main","index":0}]]},"B4 - Push Alert":{"main":[[{"node":"END - DLQ + Alert","type":"main","index":0}]]}},"settings":{"executionTimeout":300,"saveExecutionProgress":true,"saveManualExecutions":true},"staticData":null,"pinData":null}	[{"resultData":"1"},{"error":"2","runData":"3"},{"message":"4","stack":"5"},{},"Missing process handler for job type __default__","Error: Missing process handler for job type __default__\\n    at Queue.onFailed (/usr/local/lib/node_modules/n8n/node_modules/bull/lib/job.js:516:18)\\n    at Queue.emit (node:events:530:35)\\n    at Object.module.exports.emitSafe (/usr/local/lib/node_modules/n8n/node_modules/bull/lib/utils.js:50:20)\\n    at EventEmitter.messageHandler (/usr/local/lib/node_modules/n8n/node_modules/bull/lib/queue.js:476:15)\\n    at EventEmitter.emit (node:events:518:28)\\n    at DataHandler.handleSubscriberReply (/usr/local/lib/node_modules/n8n/node_modules/ioredis/built/DataHandler.js:80:32)\\n    at DataHandler.returnReply (/usr/local/lib/node_modules/n8n/node_modules/ioredis/built/DataHandler.js:47:18)\\n    at JavascriptRedisParser.returnReply (/usr/local/lib/node_modules/n8n/node_modules/ioredis/built/DataHandler.js:21:22)\\n    at JavascriptRedisParser.execute (/usr/local/lib/node_modules/n8n/node_modules/redis-parser/lib/parser.js:544:14)\\n    at Socket.<anonymous> (/usr/local/lib/node_modules/n8n/node_modules/ioredis/built/DataHandler.js:25:20)"]	\N
\.


