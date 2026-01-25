-- P0 production patches (2026-01-21)
-- Idempotent migration: API clients (multi-tenant), Outbox, create_order idempotency/PLACED lock.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- API clients
CREATE TABLE IF NOT EXISTS api_clients (
  client_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_name     text NOT NULL,
  token_hash      text NOT NULL UNIQUE, -- sha256 hex
  tenant_id       uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id   uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  scopes          jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_active       boolean NOT NULL DEFAULT true,
  last_used_at    timestamptz NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_clients_active_hash
  ON api_clients (is_active, token_hash);

-- Outbox
CREATE TABLE IF NOT EXISTS outbound_messages (
  outbound_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dedupe_key          text NOT NULL UNIQUE,
  tenant_id           uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id       uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  conversation_key    text NULL,
  channel             text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger')),
  user_id             text NOT NULL,
  order_id            uuid NULL REFERENCES orders(order_id) ON DELETE SET NULL,
  template            text NOT NULL DEFAULT 'reply',
  payload_json        jsonb NOT NULL DEFAULT '{}'::jsonb,
  status              text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','RETRY','SENT','DLQ')),
  attempts            int NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_retry_at       timestamptz NOT NULL DEFAULT now(),
  provider_message_id text NULL,
  last_error          text NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  sent_at             timestamptz NULL
);

CREATE INDEX IF NOT EXISTS idx_outbound_due
  ON outbound_messages (status, next_retry_at);

CREATE INDEX IF NOT EXISTS idx_outbound_rest_channel
  ON outbound_messages (restaurant_id, channel, created_at DESC);

-- Replace create_order with idempotent PLACED lock
CREATE OR REPLACE FUNCTION create_order(p_conversation_key text)
RETURNS TABLE(order_id uuid, total_cents int, summary text)
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
BEGIN
  -- Lock state row to prevent concurrent double orders
  SELECT tenant_id, restaurant_id, channel, user_id,
         COALESCE(state_json->>'stage','') AS stage,
         COALESCE(state_json->>'last_order_id','') AS last_order_id
    INTO v_tenant, v_restaurant, v_channel, v_user, v_stage, v_last_order
  FROM conversation_state
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
        COALESCE((SELECT total_cents FROM orders WHERE order_id=v_last_order::uuid), 0),
        (SELECT string_agg(label || ' x' || qty, ', ')
           FROM order_items
          WHERE order_id=v_last_order::uuid);
    RETURN;
  END IF;

  SELECT COALESCE(
           (SELECT cart_json->>'serviceMode' FROM carts WHERE conversation_key=p_conversation_key),
           (SELECT state_json->>'serviceMode' FROM conversation_state WHERE conversation_key=p_conversation_key),
           'a_emporter'
         )
    INTO v_mode;

  INSERT INTO orders (tenant_id, restaurant_id, channel, user_id, service_mode, status)
  VALUES (v_tenant, v_restaurant, v_channel, v_user, v_mode, 'NEW')
  RETURNING orders.order_id INTO v_order;

  -- Insert items
  WITH cart AS (
    SELECT cart_json
    FROM carts
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
        JOIN menu_item_options mo
          ON mo.restaurant_id = v_restaurant
         AND mo.option_code = oc.option_code
      ),0) AS opt_cents
    FROM lines l
    JOIN menu_items mi
      ON mi.restaurant_id = v_restaurant
     AND mi.item_code = l.item_code
     AND mi.active = true
  )
  INSERT INTO order_items(order_id, item_code, label, qty, unit_price_cents, options_json, line_total_cents)
  SELECT
    v_order,
    item_code,
    label,
    qty,
    (base_cents + opt_cents) AS unit_price_cents,
    options_json,
    (base_cents + opt_cents) * qty AS line_total_cents
  FROM priced;

  UPDATE orders
     SET total_cents = COALESCE((SELECT SUM(line_total_cents) FROM order_items WHERE order_id=v_order),0),
         updated_at = now()
   WHERE order_id = v_order;

  -- Clear cart after placing order
  UPDATE carts SET cart_json='{"items":[]}'::jsonb, updated_at=now()
   WHERE conversation_key = p_conversation_key;

  -- Persist durable state lock (PLACED)
  UPDATE conversation_state
     SET state_json = jsonb_set(
           jsonb_set(state_json, '{stage}', to_jsonb('PLACED'::text), true),
           '{last_order_id}', to_jsonb(v_order::text), true
         ),
         updated_at = now()
   WHERE conversation_key = p_conversation_key;

  RETURN QUERY
    SELECT
      v_order,
      (SELECT total_cents FROM orders WHERE order_id=v_order),
      (SELECT string_agg(label || ' x' || qty, ', ')
         FROM order_items
        WHERE order_id=v_order);

END;
$$;

-- Optional: seed a legacy api_client if you want to migrate off WEBHOOK_SHARED_TOKEN
-- Example:
-- INSERT INTO api_clients(client_name, token_hash, tenant_id, restaurant_id, scopes)
-- VALUES ('legacy', '<sha256_hex>', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', '["legacy_shared"]'::jsonb)
-- ON CONFLICT DO NOTHING;
