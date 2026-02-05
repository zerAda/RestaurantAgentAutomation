-- =========================
-- RESTO BOT DB SCHEMA (Postgres)
-- =========================
-- Safe defaults: JSONB state, idempotency, rate-limit, quarantine, orders.
-- Requires: pgcrypto for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Tenants / Restaurants (multi-chain)
CREATE TABLE IF NOT EXISTS tenants (
  tenant_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name            text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS restaurants (
  restaurant_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  name            text NOT NULL,
  timezone        text NOT NULL DEFAULT 'Africa/Algiers',
  currency        text NOT NULL DEFAULT 'EUR',
  created_at      timestamptz NOT NULL DEFAULT now()
);


-- API clients (P0-AUTH-MULTITENANT)
-- Stores hashed tokens mapped to tenant/restaurant + scopes.
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


-- RBAC mapping per channel
CREATE TABLE IF NOT EXISTS restaurant_users (
  id              bigserial PRIMARY KEY,
  tenant_id       uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id   uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  channel         text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
  user_id         text NOT NULL,
  role            text NOT NULL CHECK (role IN ('customer','owner','admin','kitchen')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (restaurant_id, channel, user_id)
);

-- Menu (IDs visibles par le client)
CREATE TABLE IF NOT EXISTS menu_items (
  restaurant_id   uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  item_code       text NOT NULL,                 -- ex: P01
  label           text NOT NULL,
  category        text NOT NULL DEFAULT 'Autres',
  price_cents     int  NOT NULL CHECK (price_cents >= 0),
  active          boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (restaurant_id, item_code)
);

-- Options (suppléments / sans / modifications) avec IDs
CREATE TABLE IF NOT EXISTS menu_item_options (
  restaurant_id       uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  item_code           text NOT NULL,
  option_code         text NOT NULL,            -- ex: S01
  label               text NOT NULL,
  kind                text NOT NULL CHECK (kind IN ('extra','remove','note')),
  price_delta_cents   int NOT NULL DEFAULT 0,
  active              boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (restaurant_id, option_code),
  FOREIGN KEY (restaurant_id, item_code) REFERENCES menu_items(restaurant_id, item_code) ON DELETE CASCADE
);

-- Conversation state + cart
CREATE TABLE IF NOT EXISTS conversation_state (
  conversation_key text PRIMARY KEY,
  tenant_id        uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id    uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  channel          text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
  user_id          text NOT NULL,
  state_json       jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS carts (
  conversation_key text PRIMARY KEY REFERENCES conversation_state(conversation_key) ON DELETE CASCADE,
  cart_json        jsonb NOT NULL DEFAULT '{"items":[]}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- Orders
CREATE TABLE IF NOT EXISTS orders (
  order_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id   uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  channel         text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
  user_id         text NOT NULL,
  service_mode    text NOT NULL CHECK (service_mode IN ('sur_place','a_emporter','livraison')),
  status          text NOT NULL DEFAULT 'NEW' CHECK (status IN ('NEW','ACCEPTED','IN_PROGRESS','READY','DONE','CANCELLED')),
  total_cents     int NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
  id              bigserial PRIMARY KEY,
  order_id        uuid NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
  item_code       text NOT NULL,
  label           text NOT NULL,
  qty             int NOT NULL CHECK (qty BETWEEN 1 AND 20),
  unit_price_cents int NOT NULL CHECK (unit_price_cents >= 0),
  options_json    jsonb NOT NULL DEFAULT '[]'::jsonb,
  line_total_cents int NOT NULL CHECK (line_total_cents >= 0)
);

-- Outbox pattern (P0-OUTBOX-RETRY)
CREATE TABLE IF NOT EXISTS outbound_messages (
  outbound_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dedupe_key          text NOT NULL UNIQUE,
  tenant_id           uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id       uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  conversation_key    text NULL,
  channel             text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
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

-- Inbound / idempotency / rate limiting
CREATE TABLE IF NOT EXISTS inbound_messages (
  id               bigserial PRIMARY KEY,
  conversation_key text NOT NULL,
  msg_id           text NOT NULL,
  channel          text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
  message_type     text NOT NULL,
  text_hash        text,
  meta_json        jsonb NOT NULL DEFAULT '{}'::jsonb,
  received_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (conversation_key, msg_id, channel)
);

CREATE INDEX IF NOT EXISTS idx_inbound_messages_window
  ON inbound_messages(conversation_key, received_at DESC);

CREATE TABLE IF NOT EXISTS idempotency_keys (
  conversation_key text NOT NULL,
  msg_id           text NOT NULL,
  channel          text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_key, msg_id, channel)
);

-- Quarantine for abuse
CREATE TABLE IF NOT EXISTS conversation_quarantine (
  id               bigserial PRIMARY KEY,
  conversation_key text NOT NULL,
  reason           text NOT NULL,
  active           boolean NOT NULL DEFAULT true,
  expires_at       timestamptz NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- Security + errors
CREATE TABLE IF NOT EXISTS security_events (
  id               bigserial PRIMARY KEY,
  tenant_id        uuid NULL,
  restaurant_id    uuid NULL,
  conversation_key text NULL,
  channel          text NULL,
  user_id          text NULL,
  event_type       text NOT NULL,
  severity         text NOT NULL DEFAULT 'MEDIUM' CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
  payload_json     jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS workflow_errors (
  id              bigserial PRIMARY KEY,
  workflow_name   text,
  node_name       text,
  error_message   text,
  stack           text,
  execution_id    text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Voice interactions
CREATE TABLE IF NOT EXISTS voice_interactions (
  id              bigserial PRIMARY KEY,
  conversation_key text NOT NULL,
  audio_url       text NOT NULL,
  transcript      text,
  confidence      numeric,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Feedback jobs (scheduled)
CREATE TABLE IF NOT EXISTS feedback_jobs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel         text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
  user_id         text NOT NULL,
  restaurant_id   uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  order_id        uuid NULL REFERENCES orders(order_id) ON DELETE SET NULL,
  message_text    text NOT NULL,
  scheduled_at    timestamptz NOT NULL,
  sent_at         timestamptz NULL,
  status          text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','SENT')),
  last_error      text NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- =========================
-- create_order(conversation_key)
-- Converts cart_json into orders + order_items and clears cart.
-- =========================
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

-- Demo seed (enabled): tenant+restaurant with fixed UUIDs so tests work out-of-the-box
INSERT INTO tenants(tenant_id, name)
VALUES ('00000000-0000-0000-0000-000000000001', 'Default Chain')
ON CONFLICT (tenant_id) DO NOTHING;

INSERT INTO restaurants(restaurant_id, tenant_id, name)
VALUES ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001', 'Branch 1')
ON CONFLICT (restaurant_id) DO NOTHING;

-- Minimal demo menu (enabled)
INSERT INTO menu_items(restaurant_id,item_code,label,category,price_cents)
VALUES
  ('00000000-0000-0000-0000-000000000000','P01','Pizza Margherita','Pizzas',900),
  ('00000000-0000-0000-0000-000000000000','P02','Pizza Pepperoni','Pizzas',1100),
  ('00000000-0000-0000-0000-000000000000','B01','Burger Classic','Burgers',750),
  ('00000000-0000-0000-0000-000000000000','S01','Salade','Sides',450)
ON CONFLICT DO NOTHING;

INSERT INTO menu_item_options(restaurant_id,item_code,option_code,label,kind,price_delta_cents)
VALUES
  ('00000000-0000-0000-0000-000000000000','P01','X01','Extra fromage','extra',150),
  ('00000000-0000-0000-0000-000000000000','P01','R01','Sans olives','remove',0),
  ('00000000-0000-0000-0000-000000000000','B01','X02','Double steak','extra',250),
  ('00000000-0000-0000-0000-000000000000','B01','R02','Sans oignons','remove',0)
ON CONFLICT DO NOTHING;
-- =========================
-- PERF INDEXES (added 2026-01-05)
-- =========================

CREATE INDEX IF NOT EXISTS idx_conversation_quarantine_key_active_expires
  ON conversation_quarantine (conversation_key, active, expires_at);

CREATE INDEX IF NOT EXISTS idx_feedback_jobs_status_scheduled
  ON feedback_jobs (status, scheduled_at);

CREATE INDEX IF NOT EXISTS idx_menu_items_rest_active_cat_code
  ON menu_items (restaurant_id, active, category, item_code);

CREATE INDEX IF NOT EXISTS idx_menu_item_options_rest_active_item_opt
  ON menu_item_options (restaurant_id, active, item_code, option_code);
