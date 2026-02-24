-- ===========================================================================
-- RESTO BOT — CONSOLIDATED BOOTSTRAP SCHEMA (PostgreSQL)
-- ===========================================================================
-- Merges bootstrap.sql + all 26 migrations into a single idempotent file.
-- Run via:  psql -f bootstrap.sql
-- Do NOT wrap in BEGIN/COMMIT — this runs as a single file via psql.
-- ===========================================================================

-- ===========================
-- SECTION 1: Extensions + Schemas
-- ===========================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS ops;

-- ===========================
-- SECTION 2: Enum Types
-- ===========================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_method_enum') THEN
    CREATE TYPE payment_method_enum AS ENUM (
      'COD', 'CIB', 'EDAHABIA', 'DEPOSIT', 'FREE'
    );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status_enum') THEN
    CREATE TYPE payment_status_enum AS ENUM (
      'PENDING', 'DEPOSIT_REQUESTED', 'AUTHORIZED', 'CAPTURED', 'FAILED', 'REFUNDED', 'EXPIRED'
    );
  END IF;
END $$;

-- ===========================
-- SECTION 3: Core Tables
-- ===========================

-- ----- tenants -----
CREATE TABLE IF NOT EXISTS tenants (
  tenant_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name            text NOT NULL,
  slug            text UNIQUE,
  plan            text DEFAULT 'free',
  status          text DEFAULT 'active',
  billing_email   text,
  billing_address jsonb DEFAULT '{}'::jsonb,
  settings        jsonb DEFAULT '{}'::jsonb,
  trial_ends_at   timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_tenants_plan') THEN
    ALTER TABLE tenants ADD CONSTRAINT chk_tenants_plan
      CHECK (plan IN ('free','starter','professional','enterprise'));
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_tenants_status') THEN
    ALTER TABLE tenants ADD CONSTRAINT chk_tenants_status
      CHECK (status IN ('active','suspended','trial','cancelled'));
  END IF;
END $$;

-- ----- restaurants -----
CREATE TABLE IF NOT EXISTS restaurants (
  restaurant_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  name             text NOT NULL,
  timezone         text NOT NULL DEFAULT 'Africa/Algiers',
  currency         text NOT NULL DEFAULT 'EUR',
  phone            text,
  email            text,
  address          jsonb DEFAULT '{}'::jsonb,
  default_language text DEFAULT 'fr',
  operating_hours  jsonb DEFAULT '{}'::jsonb,
  is_active        boolean DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz DEFAULT now()
);

-- ----- api_clients -----
CREATE TABLE IF NOT EXISTS api_clients (
  client_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_name        text NOT NULL,
  token_hash         text NOT NULL UNIQUE,
  tenant_id          uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id      uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  scopes             jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_active          boolean NOT NULL DEFAULT true,
  last_used_at       timestamptz NULL,
  legacy_migrated_at timestamptz NULL,
  token_rotated_at   timestamptz NULL,
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_clients_active_hash
  ON api_clients (is_active, token_hash);

-- ----- restaurant_users -----
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

-- ----- menu_items -----
CREATE TABLE IF NOT EXISTS menu_items (
  restaurant_id   uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  item_code       text NOT NULL,
  label           text NOT NULL,
  category        text NOT NULL DEFAULT 'Autres',
  price_cents     int  NOT NULL CHECK (price_cents >= 0),
  active          boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (restaurant_id, item_code)
);

-- ----- menu_item_options -----
CREATE TABLE IF NOT EXISTS menu_item_options (
  restaurant_id       uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  item_code           text NOT NULL,
  option_code         text NOT NULL,
  label               text NOT NULL,
  kind                text NOT NULL CHECK (kind IN ('extra','remove','note')),
  price_delta_cents   int NOT NULL DEFAULT 0,
  active              boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (restaurant_id, option_code),
  FOREIGN KEY (restaurant_id, item_code) REFERENCES menu_items(restaurant_id, item_code) ON DELETE CASCADE
);

-- ----- conversation_state -----
CREATE TABLE IF NOT EXISTS conversation_state (
  conversation_key text PRIMARY KEY,
  tenant_id        uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id    uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  channel          text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
  user_id          text NOT NULL,
  state_json       jsonb NOT NULL DEFAULT '{}'::jsonb,
  correlation_id   text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- ----- carts -----
CREATE TABLE IF NOT EXISTS carts (
  conversation_key text PRIMARY KEY REFERENCES conversation_state(conversation_key) ON DELETE CASCADE,
  cart_json        jsonb NOT NULL DEFAULT '{"items":[]}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- ----- orders -----
CREATE TABLE IF NOT EXISTS orders (
  order_id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id        uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  channel              text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
  user_id              text NOT NULL,
  service_mode         text NOT NULL CHECK (service_mode IN ('sur_place','a_emporter','livraison')),
  status               text NOT NULL DEFAULT 'NEW'
                         CHECK (status IN ('NEW','ACCEPTED','IN_PROGRESS','READY','OUT_FOR_DELIVERY','DONE','DELIVERED','CANCELLED')),
  total_cents          int NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  -- Tracking
  last_notified_status text NULL,
  last_notified_at     timestamptz NULL,
  -- Delivery
  delivery_address_json jsonb NULL,
  delivery_wilaya      text NULL,
  delivery_commune     text NULL,
  delivery_phone       text NULL,
  delivery_fee_cents   int NULL CHECK (delivery_fee_cents IS NULL OR delivery_fee_cents >= 0),
  delivery_eta_min     int NULL CHECK (delivery_eta_min IS NULL OR delivery_eta_min >= 0),
  delivery_eta_max     int NULL CHECK (delivery_eta_max IS NULL OR delivery_eta_max >= 0),
  delivery_slot_id     uuid NULL,
  delivery_slot_start  timestamptz NULL,
  delivery_slot_end    timestamptz NULL,
  -- Payment (COD / no-show)
  payment_mode         text DEFAULT 'COD'
                         CHECK (payment_mode IN ('COD','DEPOSIT_COD','CIB','EDAHABIA','FREE','PREPAID')),
  payment_status       text DEFAULT 'PENDING'
                         CHECK (payment_status IN ('PENDING','DEPOSIT_REQUESTED','DEPOSIT_PAID','CONFIRMED','COLLECTED','COMPLETED','FAILED','REFUNDED','CANCELLED','NO_SHOW')),
  payment_intent_id    uuid NULL,
  delivery_address     text NULL,
  delivery_notes       text NULL,
  customer_phone       text NULL,
  -- Structured logging
  correlation_id       text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

-- ----- order_items -----
CREATE TABLE IF NOT EXISTS order_items (
  id               bigserial PRIMARY KEY,
  order_id         uuid NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
  item_code        text NOT NULL,
  label            text NOT NULL,
  qty              int NOT NULL CHECK (qty BETWEEN 1 AND 20),
  unit_price_cents int NOT NULL CHECK (unit_price_cents >= 0),
  options_json     jsonb NOT NULL DEFAULT '[]'::jsonb,
  line_total_cents int NOT NULL CHECK (line_total_cents >= 0)
);

-- ----- outbound_messages -----
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
  status              text NOT NULL DEFAULT 'PENDING'
                        CHECK (status IN ('PENDING','RETRY','SENT','DLQ','DROPPED')),
  attempts            int NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_retry_at       timestamptz NOT NULL DEFAULT now(),
  provider_message_id text NULL,
  last_error          text NULL,
  correlation_id      text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  sent_at             timestamptz NULL
);

CREATE INDEX IF NOT EXISTS idx_outbound_due
  ON outbound_messages (status, next_retry_at);

CREATE INDEX IF NOT EXISTS idx_outbound_rest_channel
  ON outbound_messages (restaurant_id, channel, created_at DESC);

-- ----- inbound_messages -----
CREATE TABLE IF NOT EXISTS inbound_messages (
  id               bigserial PRIMARY KEY,
  conversation_key text NOT NULL,
  msg_id           text NOT NULL,
  channel          text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
  message_type     text NOT NULL,
  text_hash        text,
  meta_json        jsonb NOT NULL DEFAULT '{}'::jsonb,
  correlation_id   text,
  received_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (conversation_key, msg_id, channel)
);

CREATE INDEX IF NOT EXISTS idx_inbound_messages_window
  ON inbound_messages(conversation_key, received_at DESC);

-- ----- idempotency_keys -----
CREATE TABLE IF NOT EXISTS idempotency_keys (
  conversation_key text NOT NULL,
  msg_id           text NOT NULL,
  channel          text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_key, msg_id, channel)
);

-- ----- conversation_quarantine -----
CREATE TABLE IF NOT EXISTS conversation_quarantine (
  id               bigserial PRIMARY KEY,
  conversation_key text NOT NULL,
  reason           text NOT NULL,
  active           boolean NOT NULL DEFAULT true,
  expires_at       timestamptz NULL,
  release_policy   text NOT NULL DEFAULT 'AUTO_RELEASE'
                     CHECK (release_policy IN ('AUTO_RELEASE','CONFIRMATION','MANUAL')),
  released_at      timestamptz NULL,
  released_reason  text NULL,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- ----- security_events (event_type stays TEXT NOT NULL, no enum) -----
CREATE TABLE IF NOT EXISTS security_events (
  id               bigserial PRIMARY KEY,
  tenant_id        uuid NULL,
  restaurant_id    uuid NULL,
  conversation_key text NULL,
  channel          text NULL,
  user_id          text NULL,
  event_type       text NOT NULL,
  severity         text NOT NULL DEFAULT 'MEDIUM'
                     CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
  payload_json     jsonb NOT NULL DEFAULT '{}'::jsonb,
  correlation_id   text,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- ----- workflow_errors -----
CREATE TABLE IF NOT EXISTS workflow_errors (
  id              bigserial PRIMARY KEY,
  workflow_name   text,
  node_name       text,
  error_message   text,
  stack           text,
  execution_id    text,
  correlation_id  text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- ----- voice_interactions -----
CREATE TABLE IF NOT EXISTS voice_interactions (
  id               bigserial PRIMARY KEY,
  conversation_key text NOT NULL,
  audio_url        text NOT NULL,
  transcript       text,
  confidence       numeric,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- ----- feedback_jobs -----
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

-- ----- message_templates (L10N version) -----
CREATE TABLE IF NOT EXISTS message_templates (
  id              bigserial PRIMARY KEY,
  template_key    text NOT NULL,
  locale          text NOT NULL DEFAULT 'fr',
  content         text NOT NULL DEFAULT '',
  variables       jsonb DEFAULT '[]'::jsonb,
  tenant_id       text NOT NULL DEFAULT '_GLOBAL',
  restaurant_id   uuid NULL,
  version         int NOT NULL DEFAULT 1,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_message_templates_key_locale_tenant
  ON message_templates (template_key, locale, tenant_id);

-- ----- order_status_history (epic3_tracking) -----
CREATE TABLE IF NOT EXISTS order_status_history (
  id              bigserial PRIMARY KEY,
  order_id        uuid NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
  internal_status text NOT NULL,
  customer_status text NULL,
  note            text NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_status_history_order_time
  ON order_status_history(order_id, created_at ASC);

-- ----- delivery_zones -----
CREATE TABLE IF NOT EXISTS delivery_zones (
  zone_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id    uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  wilaya           text NOT NULL,
  commune          text NOT NULL,
  fee_base_cents   int NOT NULL CHECK (fee_base_cents >= 0),
  min_order_cents  int NOT NULL DEFAULT 0 CHECK (min_order_cents >= 0),
  eta_min          int NOT NULL DEFAULT 45 CHECK (eta_min >= 0),
  eta_max          int NOT NULL DEFAULT 60 CHECK (eta_max >= eta_min),
  is_active        boolean NOT NULL DEFAULT true,
  center_lat       numeric(9,6),
  center_lng       numeric(9,6),
  radius_km        numeric(5,2) DEFAULT 10.0,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_zones_rest_wilaya_commune
  ON delivery_zones (restaurant_id, lower(wilaya), lower(commune));

CREATE INDEX IF NOT EXISTS idx_delivery_zones_active
  ON delivery_zones (restaurant_id, is_active);

-- ----- delivery_fee_rules -----
CREATE TABLE IF NOT EXISTS delivery_fee_rules (
  rule_id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id                  uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
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
  ON delivery_fee_rules (restaurant_id, is_active);

-- ----- delivery_time_slots -----
CREATE TABLE IF NOT EXISTS delivery_time_slots (
  slot_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  day_of_week   smallint NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time    time NOT NULL,
  end_time      time NOT NULL,
  capacity      int NOT NULL DEFAULT 0 CHECK (capacity >= 0),
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_slots_def
  ON delivery_time_slots (restaurant_id, day_of_week, start_time, end_time);

CREATE INDEX IF NOT EXISTS idx_delivery_slots_active
  ON delivery_time_slots (restaurant_id, day_of_week, is_active);

-- ----- delivery_slot_reservations -----
CREATE TABLE IF NOT EXISTS delivery_slot_reservations (
  id          bigserial PRIMARY KEY,
  order_id    uuid NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
  slot_id     uuid NOT NULL REFERENCES delivery_time_slots(slot_id) ON DELETE CASCADE,
  reserved_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(order_id)
);

CREATE INDEX IF NOT EXISTS idx_slot_reservations_slot
  ON delivery_slot_reservations (slot_id, reserved_at DESC);

-- FK orders.delivery_slot_id -> delivery_time_slots
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_orders_delivery_slot'
  ) THEN
    ALTER TABLE orders
      ADD CONSTRAINT fk_orders_delivery_slot
      FOREIGN KEY (delivery_slot_id)
      REFERENCES delivery_time_slots(slot_id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- ----- address_clarification_requests (with fix: order_id nullable, conversation_key) -----
CREATE TABLE IF NOT EXISTS address_clarification_requests (
  id               bigserial PRIMARY KEY,
  order_id         uuid NULL REFERENCES orders(order_id) ON DELETE CASCADE,
  conversation_key text NULL,
  missing_fields   jsonb NOT NULL DEFAULT '[]'::jsonb,
  attempts         int NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  status           text NOT NULL DEFAULT 'OPEN'
                     CHECK (status IN ('OPEN','RESOLVED','HANDOFF','CANCELLED')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_address_clarify_status
  ON address_clarification_requests (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_address_clarify_conversation
  ON address_clarification_requests (conversation_key)
  WHERE conversation_key IS NOT NULL;

-- ----- support_tickets (channel includes tiktok) -----
CREATE TABLE IF NOT EXISTS support_tickets (
  ticket_id        bigserial PRIMARY KEY,
  tenant_id        uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id    uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  channel          text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok')),
  conversation_key text NOT NULL,
  customer_user_id text NOT NULL,
  status           text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','ASSIGNED','CLOSED')),
  priority         text NOT NULL DEFAULT 'NORMAL' CHECK (priority IN ('LOW','NORMAL','HIGH')),
  reason_code      text NOT NULL DEFAULT 'HELP'
                     CHECK (reason_code IN ('HELP','DELIVERY_AMBIGUOUS','PAYMENT_ISSUE','FAQ_FALLBACK','OTHER')),
  subject          text NULL,
  context_json     jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  closed_at        timestamptz NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_support_ticket_active_conversation
  ON support_tickets(restaurant_id, conversation_key)
  WHERE status IN ('OPEN','ASSIGNED');

CREATE INDEX IF NOT EXISTS idx_support_tickets_status_rest
  ON support_tickets(restaurant_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_tickets_customer
  ON support_tickets(restaurant_id, channel, customer_user_id, created_at DESC);

-- ----- support_ticket_messages -----
CREATE TABLE IF NOT EXISTS support_ticket_messages (
  id               bigserial PRIMARY KEY,
  ticket_id        bigint NOT NULL REFERENCES support_tickets(ticket_id) ON DELETE CASCADE,
  direction        text NOT NULL CHECK (direction IN ('INBOUND','OUTBOUND','INTERNAL')),
  from_user_id     text NULL,
  to_user_id       text NULL,
  body_text        text NOT NULL,
  meta_json        jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_messages_ticket
  ON support_ticket_messages(ticket_id, created_at DESC);

-- ----- support_assignments -----
CREATE TABLE IF NOT EXISTS support_assignments (
  id              bigserial PRIMARY KEY,
  ticket_id       bigint NOT NULL REFERENCES support_tickets(ticket_id) ON DELETE CASCADE,
  admin_user_id   text NOT NULL,
  assigned_at     timestamptz NOT NULL DEFAULT now(),
  released_at     timestamptz NULL,
  UNIQUE(ticket_id, released_at)
);

CREATE INDEX IF NOT EXISTS idx_support_assignments_admin
  ON support_assignments(admin_user_id, assigned_at DESC);

-- ----- faq_entries (tsvector) -----
CREATE TABLE IF NOT EXISTS faq_entries (
  faq_id         bigserial PRIMARY KEY,
  tenant_id      uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id  uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  locale         text NOT NULL CHECK (lower(locale) IN ('fr','ar')),
  question       text NOT NULL,
  answer         text NOT NULL,
  tags           text[] NOT NULL DEFAULT '{}'::text[],
  is_active      boolean NOT NULL DEFAULT true,
  search_tsv     tsvector,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_faq_entries_active_rest_locale
  ON faq_entries(restaurant_id, locale) WHERE is_active;

CREATE INDEX IF NOT EXISTS idx_faq_entries_search
  ON faq_entries USING GIN(search_tsv);

-- ----- fraud_rules -----
CREATE TABLE IF NOT EXISTS fraud_rules (
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
  ON fraud_rules (scope, is_active);

-- ----- payment_intents -----
CREATE TABLE IF NOT EXISTS payment_intents (
  id                  bigserial PRIMARY KEY,
  intent_id           uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  tenant_id           uuid NOT NULL,
  restaurant_id       uuid NOT NULL,
  order_id            uuid REFERENCES orders(order_id),
  conversation_key    text NOT NULL,
  user_id             text NOT NULL,
  method              payment_method_enum NOT NULL DEFAULT 'COD',
  status              payment_status_enum NOT NULL DEFAULT 'PENDING',
  total_amount        integer NOT NULL CHECK (total_amount >= 0),
  deposit_amount      integer NOT NULL DEFAULT 0 CHECK (deposit_amount >= 0),
  deposit_paid        integer NOT NULL DEFAULT 0 CHECK (deposit_paid >= 0),
  cod_amount          integer NOT NULL DEFAULT 0 CHECK (cod_amount >= 0),
  cod_collected       integer NOT NULL DEFAULT 0 CHECK (cod_collected >= 0),
  external_ref        text,
  external_provider   text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  confirmed_at        timestamptz,
  completed_at        timestamptz,
  expires_at          timestamptz,
  metadata_json       jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_payment_intents_order
  ON payment_intents(order_id);
CREATE INDEX IF NOT EXISTS idx_payment_intents_conversation
  ON payment_intents(conversation_key);
CREATE INDEX IF NOT EXISTS idx_payment_intents_status
  ON payment_intents(status) WHERE status IN ('PENDING', 'DEPOSIT_REQUESTED');
CREATE INDEX IF NOT EXISTS idx_payment_intents_user
  ON payment_intents(user_id, created_at DESC);

-- ----- payment_history -----
CREATE TABLE IF NOT EXISTS payment_history (
  id                  bigserial PRIMARY KEY,
  payment_intent_id   bigint NOT NULL REFERENCES payment_intents(id),
  from_status         payment_status_enum,
  to_status           payment_status_enum NOT NULL,
  amount              integer,
  actor               text,
  reason              text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  metadata_json       jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_payment_history_intent
  ON payment_history(payment_intent_id, created_at DESC);

-- ----- customer_payment_profiles (merged: pay01 + cod_noshow with last_order_at) -----
CREATE TABLE IF NOT EXISTS customer_payment_profiles (
  id                  bigserial PRIMARY KEY,
  user_id             text NOT NULL UNIQUE,
  tenant_id           uuid NOT NULL,
  total_orders        integer NOT NULL DEFAULT 0,
  completed_orders    integer NOT NULL DEFAULT 0,
  cancelled_orders    integer NOT NULL DEFAULT 0,
  no_show_count       integer NOT NULL DEFAULT 0,
  trust_score         integer NOT NULL DEFAULT 50 CHECK (trust_score BETWEEN 0 AND 100),
  requires_deposit    boolean NOT NULL DEFAULT false,
  soft_blacklisted    boolean NOT NULL DEFAULT false,
  blacklist_reason    text,
  blacklist_until     timestamptz,
  last_order_at       timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_customer_payment_profiles_user
  ON customer_payment_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_customer_payment_profiles_blacklist
  ON customer_payment_profiles(soft_blacklisted) WHERE soft_blacklisted = true;
CREATE INDEX IF NOT EXISTS idx_cpp_tenant
  ON customer_payment_profiles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_cpp_trust
  ON customer_payment_profiles(trust_score);

-- ----- restaurant_payment_config -----
CREATE TABLE IF NOT EXISTS restaurant_payment_config (
  id                      bigserial PRIMARY KEY,
  restaurant_id           uuid NOT NULL UNIQUE,
  cod_enabled             boolean NOT NULL DEFAULT true,
  deposit_enabled         boolean NOT NULL DEFAULT false,
  cib_enabled             boolean NOT NULL DEFAULT false,
  edahabia_enabled        boolean NOT NULL DEFAULT false,
  cod_max_amount          integer NOT NULL DEFAULT 1000000,
  deposit_mode            text NOT NULL DEFAULT 'PERCENTAGE'
                            CHECK (deposit_mode IN ('PERCENTAGE','FIXED')),
  deposit_percentage      integer NOT NULL DEFAULT 30 CHECK (deposit_percentage BETWEEN 0 AND 100),
  deposit_fixed           integer NOT NULL DEFAULT 0,
  deposit_threshold       integer NOT NULL DEFAULT 300000,
  no_deposit_min_orders   integer NOT NULL DEFAULT 3,
  no_deposit_min_score    integer NOT NULL DEFAULT 70,
  cib_merchant_id         text,
  edahabia_merchant_id    text,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);

-- ----- customer_preferences (darija locale) -----
CREATE TABLE IF NOT EXISTS customer_preferences (
  tenant_id  text NOT NULL,
  phone      text NOT NULL,
  locale     text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, phone)
);

DO $$ BEGIN
  ALTER TABLE customer_preferences DROP CONSTRAINT IF EXISTS chk_customer_preferences_locale;
  ALTER TABLE customer_preferences ADD CONSTRAINT chk_customer_preferences_locale
    CHECK (lower(locale) IN ('fr','ar','darija'));
END $$;

CREATE INDEX IF NOT EXISTS idx_customer_preferences_tenant_locale
  ON customer_preferences(tenant_id, locale);

-- ----- token_usage_log -----
CREATE TABLE IF NOT EXISTS token_usage_log (
  id              bigserial PRIMARY KEY,
  client_id       uuid REFERENCES api_clients(client_id) ON DELETE SET NULL,
  token_hash      text NOT NULL,
  endpoint        text NOT NULL,
  ip_address      text,
  user_agent      text,
  success         boolean NOT NULL DEFAULT true,
  failure_reason  text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_token_usage_log_client_time
  ON token_usage_log(client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_token_usage_log_hash_time
  ON token_usage_log(token_hash, created_at DESC);

-- ----- webhook_replay_guard -----
CREATE TABLE IF NOT EXISTS webhook_replay_guard (
  id              bigserial PRIMARY KEY,
  message_hash    varchar(64) NOT NULL,
  message_id      varchar(255),
  channel         varchar(20) NOT NULL DEFAULT 'whatsapp',
  received_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_replay_guard_hash_channel UNIQUE (message_hash, channel)
);

CREATE INDEX IF NOT EXISTS idx_replay_guard_received_at
  ON webhook_replay_guard(received_at);
CREATE INDEX IF NOT EXISTS idx_replay_guard_message_id
  ON webhook_replay_guard(message_id) WHERE message_id IS NOT NULL;

-- ----- admin_wa_audit_log (FINAL version, actor_type includes system/admin/superadmin) -----
CREATE TABLE IF NOT EXISTS admin_wa_audit_log (
  id              bigserial PRIMARY KEY,
  tenant_id       uuid NULL,
  restaurant_id   uuid NULL,
  actor_phone     text NOT NULL,
  actor_role      text NOT NULL DEFAULT 'admin',
  action          text NOT NULL,
  target_type     text,
  target_id       text,
  command_raw     text,
  metadata_json   jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip_address      text,
  success         boolean NOT NULL DEFAULT true,
  error_message   text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE admin_wa_audit_log DROP CONSTRAINT IF EXISTS admin_wa_audit_action_check;
  ALTER TABLE admin_wa_audit_log DROP CONSTRAINT IF EXISTS chk_admin_wa_audit_action;
  ALTER TABLE admin_wa_audit_log ADD CONSTRAINT chk_admin_wa_audit_action
    CHECK (action IN (
      'help','tickets','take','close','reply',
      'template_get','template_set','template_vars',
      'zone_list','zone_create','zone_update','zone_delete',
      'status','flags','flags_set','flags_unset',
      'dlq_list','dlq_show','dlq_replay','dlq_drop',
      'assign','escalate','note','status_change','reopen','merge','tag','priority',
      'order_status','order_cancel','refund','block_user','unblock_user',
      'unknown','unauthorized','other'
    ));
END $$;

CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_tenant_time
  ON admin_wa_audit_log(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_actor_time
  ON admin_wa_audit_log(actor_phone, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_action_time
  ON admin_wa_audit_log(action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_wa_audit_target
  ON admin_wa_audit_log(target_type, target_id) WHERE target_type IS NOT NULL;

-- ----- admin_phone_allowlist -----
CREATE TABLE IF NOT EXISTS admin_phone_allowlist (
  id serial PRIMARY KEY,
  tenant_id      uuid,
  restaurant_id  uuid,
  phone_number   text NOT NULL UNIQUE,
  display_name   text,
  role           text NOT NULL DEFAULT 'admin' CHECK (role IN ('admin','owner','super_admin')),
  permissions    jsonb NOT NULL DEFAULT '["status","flags","dlq:list","help"]'::jsonb,
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text
);

CREATE INDEX IF NOT EXISTS idx_admin_phone_allowlist_phone
  ON admin_phone_allowlist(phone_number) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_admin_phone_allowlist_tenant
  ON admin_phone_allowlist(tenant_id, restaurant_id) WHERE is_active = true;

-- ----- system_flags -----
CREATE TABLE IF NOT EXISTS system_flags (
  flag_key    text PRIMARY KEY,
  flag_value  text NOT NULL,
  description text,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  text
);

-- ----- structured_logs (channel includes tiktok) -----
CREATE TABLE IF NOT EXISTS structured_logs (
  id               bigserial PRIMARY KEY,
  correlation_id   text NOT NULL,
  tenant_id        uuid,
  restaurant_id    uuid,
  user_id          text,
  conversation_key text,
  channel          text CHECK (channel IS NULL OR channel IN ('whatsapp','instagram','messenger','tiktok')),
  workflow_name    text,
  node_name        text,
  level            text NOT NULL CHECK (level IN ('DEBUG','INFO','WARN','ERROR')),
  event_type       text,
  message          text,
  context_json     jsonb DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_structured_logs_correlation_id
  ON structured_logs(correlation_id);
CREATE INDEX IF NOT EXISTS idx_structured_logs_created_at
  ON structured_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_structured_logs_level_created
  ON structured_logs(level, created_at DESC) WHERE level IN ('WARN','ERROR');
CREATE INDEX IF NOT EXISTS idx_structured_logs_tenant_created
  ON structured_logs(tenant_id, created_at DESC) WHERE tenant_id IS NOT NULL;

-- ----- darija_patterns -----
CREATE TABLE IF NOT EXISTS darija_patterns (
  id         serial PRIMARY KEY,
  category   text NOT NULL,
  pattern    text NOT NULL,
  priority   int NOT NULL DEFAULT 0,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_darija_patterns_unique
  ON darija_patterns(category, lower(pattern));

-- ----- daily_metrics -----
CREATE TABLE IF NOT EXISTS daily_metrics (
  id           serial PRIMARY KEY,
  metric_date  date NOT NULL DEFAULT CURRENT_DATE,
  metric_key   text NOT NULL,
  metric_value bigint NOT NULL DEFAULT 0,
  channel      text,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (metric_date, metric_key, channel)
);

CREATE INDEX IF NOT EXISTS idx_daily_metrics_date ON daily_metrics(metric_date);
CREATE INDEX IF NOT EXISTS idx_daily_metrics_key  ON daily_metrics(metric_key, metric_date);

-- ----- latency_samples -----
CREATE TABLE IF NOT EXISTS latency_samples (
  id          bigserial PRIMARY KEY,
  sample_date date NOT NULL DEFAULT CURRENT_DATE,
  workflow    text NOT NULL,
  channel     text,
  latency_ms  int NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_latency_samples_date     ON latency_samples(sample_date);
CREATE INDEX IF NOT EXISTS idx_latency_samples_workflow  ON latency_samples(workflow, sample_date);

-- ----- wilaya_reference -----
CREATE TABLE IF NOT EXISTS wilaya_reference (
  wilaya_code    smallint PRIMARY KEY,
  name_fr        text NOT NULL,
  name_ar        text NOT NULL,
  name_latin_alt text[] NOT NULL DEFAULT '{}',
  name_ar_alt    text[] NOT NULL DEFAULT '{}',
  center_lat     numeric(9,6),
  center_lng     numeric(9,6)
);

CREATE INDEX IF NOT EXISTS idx_wilaya_ref_name_fr ON wilaya_reference (lower(name_fr));

-- ----- commune_reference -----
CREATE TABLE IF NOT EXISTS commune_reference (
  commune_id     serial PRIMARY KEY,
  wilaya_code    smallint NOT NULL REFERENCES wilaya_reference(wilaya_code),
  name_fr        text NOT NULL,
  name_ar        text NOT NULL DEFAULT '',
  name_latin_alt text[] NOT NULL DEFAULT '{}',
  center_lat     numeric(9,6),
  center_lng     numeric(9,6)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_commune_ref_wilaya_name
  ON commune_reference(wilaya_code, lower(name_fr));

-- ----- orders_audit -----
CREATE TABLE IF NOT EXISTS orders_audit (
  audit_id        bigserial PRIMARY KEY,
  order_id        uuid NOT NULL,
  action          text NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  old_status      text,
  new_status      text,
  old_total_cents int,
  new_total_cents int,
  changed_by      text,
  changed_at      timestamptz NOT NULL DEFAULT now(),
  change_reason   text,
  ip_address      inet,
  user_agent      text
);

CREATE INDEX IF NOT EXISTS idx_orders_audit_order ON orders_audit(order_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_audit_time  ON orders_audit(changed_at DESC);

-- ----- api_clients_audit -----
CREATE TABLE IF NOT EXISTS api_clients_audit (
  audit_id      bigserial PRIMARY KEY,
  client_id     uuid NOT NULL,
  action        text NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE','AUTH_SUCCESS','AUTH_FAILURE')),
  old_is_active boolean,
  new_is_active boolean,
  old_scopes    jsonb,
  new_scopes    jsonb,
  changed_by    text,
  changed_at    timestamptz NOT NULL DEFAULT now(),
  change_reason text,
  ip_address    inet
);

CREATE INDEX IF NOT EXISTS idx_api_clients_audit_client ON api_clients_audit(client_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_api_clients_audit_time   ON api_clients_audit(changed_at DESC);

-- ----- ops.security_event_types -----
CREATE TABLE IF NOT EXISTS ops.security_event_types (
  code        text PRIMARY KEY,
  description text NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ----- ops.retention_runs -----
CREATE TABLE IF NOT EXISTS ops.retention_runs (
  run_id            bigserial PRIMARY KEY,
  run_started_at    timestamptz NOT NULL DEFAULT now(),
  run_finished_at   timestamptz NULL,
  dry_run           boolean NOT NULL DEFAULT false,
  table_name        text NOT NULL,
  cutoff_ts         timestamptz NOT NULL,
  batch_size        integer NOT NULL,
  deleted_rows      bigint NOT NULL DEFAULT 0,
  details_json      jsonb NOT NULL DEFAULT '{}'::jsonb,
  status            text NOT NULL DEFAULT 'STARTED'
);

CREATE INDEX IF NOT EXISTS idx_retention_runs_started_at
  ON ops.retention_runs (run_started_at DESC);

-- ----- ops_kv -----
CREATE TABLE IF NOT EXISTS ops_kv (
  key        text PRIMARY KEY,
  value_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ops_kv_updated_at_idx ON ops_kv(updated_at);

-- ----- admin_audit_log -----
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id              bigserial PRIMARY KEY,
  tenant_id       uuid NULL REFERENCES tenants(tenant_id) ON DELETE SET NULL,
  restaurant_id   uuid NULL REFERENCES restaurants(restaurant_id) ON DELETE SET NULL,
  actor_client_id uuid NULL REFERENCES api_clients(client_id) ON DELETE SET NULL,
  actor_name      text NULL,
  action          text NOT NULL,
  object_type     text NULL,
  object_id       text NULL,
  request_id      text NULL,
  ip              text NULL,
  user_agent      text NULL,
  payload_json    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_tenant_time
  ON admin_audit_log (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_action_time
  ON admin_audit_log (action, created_at DESC);

-- ===========================
-- SECTION 4: Functions
-- ===========================

-- ----- delivery_quote (FINAL from fix_create_order_ambiguity) -----
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

  t_local := (p_at AT TIME ZONE COALESCE((SELECT rest.timezone FROM public.restaurants rest WHERE rest.restaurant_id=p_restaurant_id),'Africa/Algiers'))::time;

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

-- ----- create_order (FINAL from fix_create_order_ambiguity with delivery support) -----
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

  IF v_mode = 'livraison' THEN
    SELECT * INTO q
    FROM public.delivery_quote(v_restaurant, v_wilaya, v_commune, v_items_total, now());

    IF q.reason <> 'OK' THEN
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

  UPDATE public.carts c SET cart_json='{"items":[]}'::jsonb, updated_at=now()
   WHERE c.conversation_key = p_conversation_key;

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

-- ===========================
-- SECTION 4b: Remaining Functions
-- ===========================

-- ----- map_order_status_to_customer -----
CREATE OR REPLACE FUNCTION public.map_order_status_to_customer(p_internal_status text, p_service_mode text)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  IF p_internal_status IS NULL THEN RETURN NULL; END IF;
  CASE upper(p_internal_status)
    WHEN 'ACCEPTED' THEN RETURN 'CONFIRMED';
    WHEN 'IN_PROGRESS' THEN RETURN 'PREPARING';
    WHEN 'READY' THEN RETURN 'READY';
    WHEN 'OUT_FOR_DELIVERY' THEN RETURN 'OUT_FOR_DELIVERY';
    WHEN 'DONE' THEN RETURN 'DELIVERED';
    WHEN 'DELIVERED' THEN RETURN 'DELIVERED';
    WHEN 'CANCELLED' THEN RETURN 'CANCELLED';
    ELSE RETURN NULL;
  END CASE;
END $$;

-- ----- normalize_locale (FINAL with darija) -----
CREATE OR REPLACE FUNCTION public.normalize_locale(p_locale text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  loc text := lower(trim(coalesce(p_locale,'')));
BEGIN
  IF loc IN ('darija','dz','darja','derija','marocain','moroccan') THEN RETURN 'darija'; END IF;
  IF loc LIKE 'ar%' THEN RETURN 'ar'; END IF;
  IF loc IN ('ar','ar-dz','ar_dz','arabic') THEN RETURN 'ar'; END IF;
  IF loc IN ('fr','fr-fr','fr_fr','french') THEN RETURN 'fr'; END IF;
  RETURN 'fr';
END $$;

-- ----- detect_darija -----
CREATE OR REPLACE FUNCTION public.detect_darija(p_text text)
RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE
  txt text := lower(trim(coalesce(p_text, '')));
  match_count int := 0;
BEGIN
  SELECT COUNT(*) INTO match_count
  FROM public.darija_patterns
  WHERE is_active = true AND txt LIKE '%' || lower(pattern) || '%';
  RETURN match_count >= 1;
END $$;

-- ----- wa_order_status_text (FINAL L10N: template-first) -----
CREATE OR REPLACE FUNCTION public.wa_order_status_text(
  p_locale text, p_customer_status text, p_order_id uuid,
  p_eta_min int, p_eta_max int, p_status_link text DEFAULT NULL
) RETURNS text LANGUAGE plpgsql AS $$
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
  SELECT content INTO tmpl FROM public.message_templates
  WHERE tenant_id = '_GLOBAL' AND template_key = k AND locale = loc LIMIT 1;
  IF tmpl IS NOT NULL THEN
    out_txt := replace(replace(tmpl, '{{order_id}}', order_short), '{{eta}}', eta_txt);
    RETURN out_txt || link_txt;
  END IF;
  -- Fallback
  IF loc LIKE 'ar%' THEN
    CASE p_customer_status
      WHEN 'CONFIRMED' THEN RETURN '#'||order_short||eta_txt;
      WHEN 'CANCELLED' THEN RETURN '#'||order_short;
      ELSE RETURN '#'||order_short||eta_txt;
    END CASE;
  END IF;
  CASE p_customer_status
    WHEN 'CONFIRMED' THEN RETURN 'Commande confirmee #'||order_short||eta_txt||link_txt;
    WHEN 'CANCELLED' THEN RETURN 'Commande annulee #'||order_short||link_txt;
    ELSE RETURN 'Mise a jour commande #'||order_short||eta_txt||link_txt;
  END CASE;
END $$;

-- ----- build_wa_order_status_payload (L10N with customer preference) -----
CREATE OR REPLACE FUNCTION public.build_wa_order_status_payload(
  p_order_id uuid, p_customer_status text,
  p_status_link text DEFAULT NULL, p_locale text DEFAULT 'fr'
) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE o RECORD; txt text; loc text;
BEGIN
  SELECT order_id, tenant_id, restaurant_id, channel, user_id, delivery_eta_min, delivery_eta_max
    INTO o FROM public.orders WHERE order_id = p_order_id;
  IF o.order_id IS NULL THEN RETURN '{}'::jsonb; END IF;
  loc := public.normalize_locale(COALESCE(
    (SELECT locale FROM public.customer_preferences WHERE tenant_id=o.tenant_id AND phone=o.user_id),
    p_locale, 'fr'));
  txt := public.wa_order_status_text(loc, p_customer_status, p_order_id, o.delivery_eta_min, o.delivery_eta_max, p_status_link);
  RETURN jsonb_build_object('channel','whatsapp','to',o.user_id,'restaurantId',o.restaurant_id,'text',txt,'buttons','[]'::jsonb);
END $$;

-- ----- enqueue_wa_order_status -----
CREATE OR REPLACE FUNCTION public.enqueue_wa_order_status(
  p_order_id uuid, p_customer_status text,
  p_status_link text DEFAULT NULL, p_locale text DEFAULT 'fr'
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE o RECORD; v_dedupe text; v_payload jsonb;
BEGIN
  IF p_customer_status IS NULL THEN RETURN; END IF;
  SELECT tenant_id, restaurant_id, channel, user_id INTO o FROM public.orders WHERE order_id = p_order_id;
  IF o.tenant_id IS NULL THEN RETURN; END IF;
  IF lower(COALESCE(o.channel,'')) <> 'whatsapp' THEN RETURN; END IF;
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

-- ----- compute_cart_total (antifraud) -----
CREATE OR REPLACE FUNCTION public.compute_cart_total(p_conversation_key text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_restaurant uuid; v_cart jsonb; v_total int := 0;
BEGIN
  SELECT restaurant_id INTO v_restaurant FROM public.conversation_state WHERE conversation_key = p_conversation_key;
  IF v_restaurant IS NULL THEN RETURN 0; END IF;
  SELECT cart_json INTO v_cart FROM public.carts WHERE conversation_key = p_conversation_key;
  v_cart := COALESCE(v_cart, '{"items":[]}'::jsonb);
  WITH lines AS (
    SELECT (elem->>'item')::text AS item_code, GREATEST(1, LEAST(20, COALESCE((elem->>'qty')::int, 1))) AS qty,
           COALESCE(elem->'options','[]'::jsonb) AS options_json
    FROM jsonb_array_elements(COALESCE(v_cart->'items','[]'::jsonb)) elem
  ), priced AS (
    SELECT l.qty, mi.price_cents AS base_cents,
           COALESCE((SELECT SUM(mo.price_delta_cents) FROM jsonb_array_elements_text(l.options_json) oc(option_code)
             JOIN public.menu_item_options mo ON mo.restaurant_id = v_restaurant AND mo.option_code = oc.option_code),0) AS opt_cents
    FROM lines l JOIN public.menu_items mi ON mi.restaurant_id = v_restaurant AND mi.item_code = l.item_code AND mi.active = true
  ) SELECT COALESCE(SUM((base_cents + opt_cents) * qty),0)::int INTO v_total FROM priced;
  RETURN COALESCE(v_total,0);
END $$;

-- ----- apply_quarantine -----
CREATE OR REPLACE FUNCTION public.apply_quarantine(
  p_conversation_key text, p_reason text, p_expires_at timestamptz, p_release_policy text DEFAULT 'AUTO_RELEASE'
) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint; v_tenant uuid; v_restaurant uuid; v_channel text; v_user text;
BEGIN
  SELECT tenant_id, restaurant_id, channel, user_id INTO v_tenant, v_restaurant, v_channel, v_user
  FROM public.conversation_state WHERE conversation_key = p_conversation_key;
  INSERT INTO public.conversation_quarantine(conversation_key, reason, active, expires_at, release_policy, updated_at)
  VALUES (p_conversation_key, p_reason, true, p_expires_at, p_release_policy, now()) RETURNING id INTO v_id;
  INSERT INTO public.security_events(tenant_id, restaurant_id, conversation_key, channel, user_id, event_type, severity, payload_json)
  VALUES (v_tenant, v_restaurant, p_conversation_key, v_channel, v_user, 'QUARANTINE_APPLIED', 'MEDIUM',
    jsonb_build_object('reason',p_reason,'expires_at',p_expires_at,'policy',p_release_policy));
  RETURN v_id;
END $$;

-- ----- release_expired_quarantines -----
CREATE OR REPLACE FUNCTION public.release_expired_quarantines(p_limit int DEFAULT 50)
RETURNS TABLE(quarantine_id bigint, conversation_key text, tenant_id uuid, restaurant_id uuid, channel text, user_id text, reason text, expires_at timestamptz)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT q.id FROM public.conversation_quarantine q
    WHERE q.active = true AND q.expires_at IS NOT NULL AND q.expires_at <= now() AND q.release_policy = 'AUTO_RELEASE'
    ORDER BY q.expires_at ASC LIMIT GREATEST(1, p_limit) FOR UPDATE SKIP LOCKED
  ), upd AS (
    UPDATE public.conversation_quarantine q SET active=false, released_at=now(), released_reason='AUTO_RELEASE', updated_at=now()
    WHERE q.id IN (SELECT id FROM due) RETURNING q.*
  )
  SELECT u.id, u.conversation_key, cs.tenant_id, cs.restaurant_id, cs.channel, cs.user_id, u.reason, u.expires_at
  FROM upd u JOIN public.conversation_state cs ON cs.conversation_key=u.conversation_key;
END $$;

-- ----- fraud_eval_checkout -----
CREATE OR REPLACE FUNCTION public.fraud_eval_checkout(p_conversation_key text)
RETURNS TABLE(action text, score int, total_cents int, reason text, confirm_ttl_minutes int, quarantine_minutes int)
LANGUAGE plpgsql AS $$
DECLARE v_total int := 0; v_user text; v_thr int := 30000; v_ttl int := 10; v_cancel_limit int := 3; v_window_days int := 7; v_quar int := 30; v_cancel_cnt int := 0;
BEGIN
  v_total := public.compute_cart_total(p_conversation_key);
  SELECT cs.user_id INTO v_user FROM public.conversation_state cs WHERE cs.conversation_key=p_conversation_key;
  SELECT COALESCE((params_json->>'threshold_cents')::int, v_thr), COALESCE((params_json->>'confirm_ttl_minutes')::int, v_ttl)
    INTO v_thr, v_ttl FROM public.fraud_rules WHERE scope='CHECKOUT' AND rule_key='CO_HIGH_ORDER_TOTAL' AND is_active=true LIMIT 1;
  SELECT COALESCE((params_json->>'cancel_limit')::int, v_cancel_limit), COALESCE((params_json->>'window_days')::int, v_window_days), COALESCE((params_json->>'quarantine_minutes')::int, v_quar)
    INTO v_cancel_limit, v_window_days, v_quar FROM public.fraud_rules WHERE scope='CHECKOUT' AND rule_key='CO_REPEAT_CANCELLED_7D' AND is_active=true LIMIT 1;
  IF v_user IS NOT NULL THEN
    SELECT COUNT(*)::int INTO v_cancel_cnt FROM public.orders WHERE user_id=v_user AND status='CANCELLED' AND created_at >= (now() - make_interval(days => v_window_days));
  END IF;
  IF v_cancel_cnt >= v_cancel_limit THEN RETURN QUERY SELECT 'QUARANTINE', 90, v_total, 'REPEAT_CANCELLED', v_ttl, v_quar; RETURN; END IF;
  IF v_total >= v_thr THEN RETURN QUERY SELECT 'REQUIRE_CONFIRMATION', 70, v_total, 'HIGH_ORDER_TOTAL', v_ttl, 0; RETURN; END IF;
  RETURN QUERY SELECT 'ALLOW', 0, v_total, 'OK', 0, 0;
END $$;

-- ----- log_token_usage -----
CREATE OR REPLACE FUNCTION public.log_token_usage(
  p_client_id uuid, p_token_hash text, p_endpoint text,
  p_ip text DEFAULT NULL, p_ua text DEFAULT NULL,
  p_success boolean DEFAULT true, p_failure_reason text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO token_usage_log (client_id, token_hash, endpoint, ip_address, user_agent, success, failure_reason)
  VALUES (p_client_id, p_token_hash, p_endpoint, p_ip, p_ua, p_success, p_failure_reason);
  IF p_client_id IS NOT NULL AND p_success THEN
    UPDATE api_clients SET last_used_at = now() WHERE client_id = p_client_id;
  END IF;
END $$;

-- ----- check_replay_guard -----
CREATE OR REPLACE FUNCTION public.check_replay_guard(
  p_message_hash varchar(64), p_message_id varchar(255) DEFAULT NULL, p_channel varchar(20) DEFAULT 'whatsapp'
) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.webhook_replay_guard (message_hash, message_id, channel)
  VALUES (p_message_hash, p_message_id, p_channel)
  ON CONFLICT (message_hash, channel) DO NOTHING;
  RETURN FOUND;
END $$;

-- ----- cleanup_replay_guard -----
CREATE OR REPLACE FUNCTION public.cleanup_replay_guard(p_max_age_hours int DEFAULT 24)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_deleted int;
BEGIN
  DELETE FROM public.webhook_replay_guard WHERE received_at < now() - make_interval(hours => p_max_age_hours);
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END $$;

-- ----- log_structured -----
CREATE OR REPLACE FUNCTION public.log_structured(
  p_correlation_id text, p_level text, p_event_type text, p_message text,
  p_tenant_id uuid DEFAULT NULL, p_restaurant_id uuid DEFAULT NULL,
  p_user_id text DEFAULT NULL, p_conversation_key text DEFAULT NULL,
  p_channel text DEFAULT NULL, p_workflow_name text DEFAULT NULL,
  p_node_name text DEFAULT NULL, p_context_json jsonb DEFAULT '{}'::jsonb
) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
  INSERT INTO public.structured_logs(correlation_id, tenant_id, restaurant_id, user_id, conversation_key, channel, workflow_name, node_name, level, event_type, message, context_json)
  VALUES (p_correlation_id, p_tenant_id, p_restaurant_id, p_user_id, p_conversation_key, p_channel, p_workflow_name, p_node_name, p_level, p_event_type, p_message, p_context_json)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ----- record_daily_metrics -----
CREATE OR REPLACE FUNCTION public.record_daily_metrics(p_key text, p_value bigint DEFAULT 1, p_channel text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.daily_metrics(metric_date, metric_key, metric_value, channel)
  VALUES (CURRENT_DATE, p_key, p_value, p_channel)
  ON CONFLICT (metric_date, metric_key, channel) DO UPDATE SET metric_value = daily_metrics.metric_value + p_value, updated_at = now();
END $$;

-- ----- record_latency_sample -----
CREATE OR REPLACE FUNCTION public.record_latency_sample(p_workflow text, p_latency_ms int, p_channel text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.latency_samples(sample_date, workflow, channel, latency_ms) VALUES (CURRENT_DATE, p_workflow, p_channel, p_latency_ms);
END $$;

-- ----- get_latency_stats -----
CREATE OR REPLACE FUNCTION public.get_latency_stats(p_workflow text, p_date date DEFAULT CURRENT_DATE)
RETURNS TABLE(cnt bigint, avg_ms numeric, p50_ms numeric, p95_ms numeric, p99_ms numeric, max_ms int)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN QUERY
  SELECT count(*)::bigint, avg(latency_ms)::numeric, percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_ms)::numeric,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)::numeric, percentile_cont(0.99) WITHIN GROUP (ORDER BY latency_ms)::numeric,
    max(latency_ms)::int
  FROM public.latency_samples WHERE workflow = p_workflow AND sample_date = p_date;
END $$;

-- ----- insert_admin_wa_audit (FINAL) -----
CREATE OR REPLACE FUNCTION public.insert_admin_wa_audit(
  p_tenant_id uuid, p_restaurant_id uuid, p_actor_phone text, p_actor_role text,
  p_action text, p_target_type text DEFAULT NULL, p_target_id text DEFAULT NULL,
  p_command_raw text DEFAULT NULL, p_metadata_json jsonb DEFAULT '{}'::jsonb,
  p_ip_address text DEFAULT NULL, p_success boolean DEFAULT true, p_error_message text DEFAULT NULL
) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
  INSERT INTO public.admin_wa_audit_log(tenant_id, restaurant_id, actor_phone, actor_role, action, target_type, target_id, command_raw, metadata_json, ip_address, success, error_message)
  VALUES (p_tenant_id, p_restaurant_id, p_actor_phone, p_actor_role, p_action, p_target_type, p_target_id, p_command_raw, p_metadata_json, p_ip_address, p_success, p_error_message)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ----- check_admin_allowed -----
CREATE OR REPLACE FUNCTION public.check_admin_allowed(p_phone text)
RETURNS TABLE(allowed boolean, role text, display_name text, permissions jsonb)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN QUERY
  SELECT true, a.role, a.display_name, a.permissions
  FROM public.admin_phone_allowlist a WHERE a.phone_number = p_phone AND a.is_active = true LIMIT 1;
  IF NOT FOUND THEN RETURN QUERY SELECT false, NULL::text, NULL::text, NULL::jsonb; END IF;
END $$;

-- ----- get_system_flag / set_system_flag -----
CREATE OR REPLACE FUNCTION public.get_system_flag(p_key text, p_default text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v text;
BEGIN
  SELECT flag_value INTO v FROM public.system_flags WHERE flag_key = p_key;
  RETURN COALESCE(v, p_default);
END $$;

CREATE OR REPLACE FUNCTION public.set_system_flag(p_key text, p_value text, p_by text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.system_flags(flag_key, flag_value, updated_at, updated_by)
  VALUES (p_key, p_value, now(), p_by)
  ON CONFLICT (flag_key) DO UPDATE SET flag_value = p_value, updated_at = now(), updated_by = p_by;
END $$;

-- ----- fn_orders_audit -----
CREATE OR REPLACE FUNCTION public.fn_orders_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.orders_audit (order_id, action, new_status, new_total_cents, changed_by) VALUES (NEW.order_id, 'INSERT', NEW.status, NEW.total_cents, current_user); RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.status IS DISTINCT FROM NEW.status OR OLD.total_cents IS DISTINCT FROM NEW.total_cents THEN
      INSERT INTO public.orders_audit (order_id, action, old_status, new_status, old_total_cents, new_total_cents, changed_by) VALUES (NEW.order_id, 'UPDATE', OLD.status, NEW.status, OLD.total_cents, NEW.total_cents, current_user);
    END IF; RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.orders_audit (order_id, action, old_status, old_total_cents, changed_by) VALUES (OLD.order_id, 'DELETE', OLD.status, OLD.total_cents, current_user); RETURN OLD;
  END IF; RETURN NULL;
END $$;

-- ----- fn_api_clients_audit -----
CREATE OR REPLACE FUNCTION public.fn_api_clients_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.api_clients_audit (client_id, action, new_is_active, new_scopes, changed_by) VALUES (NEW.client_id, 'INSERT', NEW.is_active, NEW.scopes, current_user); RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.is_active IS DISTINCT FROM NEW.is_active OR OLD.scopes IS DISTINCT FROM NEW.scopes THEN
      INSERT INTO public.api_clients_audit (client_id, action, old_is_active, new_is_active, old_scopes, new_scopes, changed_by) VALUES (NEW.client_id, 'UPDATE', OLD.is_active, NEW.is_active, OLD.scopes, NEW.scopes, current_user);
    END IF; RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.api_clients_audit (client_id, action, old_is_active, old_scopes, changed_by) VALUES (OLD.client_id, 'DELETE', OLD.is_active, OLD.scopes, current_user); RETURN OLD;
  END IF; RETURN NULL;
END $$;

-- ----- faq_entries_tsv_update -----
CREATE OR REPLACE FUNCTION public.faq_entries_tsv_update() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.search_tsv := setweight(to_tsvector('simple', coalesce(NEW.question,'')), 'A') ||
    setweight(to_tsvector('simple', array_to_string(coalesce(NEW.tags,'{}'::text[]),' ')), 'B') ||
    setweight(to_tsvector('simple', coalesce(NEW.answer,'')), 'C');
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- ----- purge_old_inbound_messages -----
CREATE OR REPLACE FUNCTION public.purge_old_inbound_messages(p_days INT DEFAULT 90)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_deleted INT;
BEGIN
  DELETE FROM public.inbound_messages WHERE received_at < now() - (p_days || ' days')::interval;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END $$;

-- ----- Tracking trigger functions -----
CREATE OR REPLACE FUNCTION public.trg_orders_init_tracking() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.last_notified_status IS NULL THEN NEW.last_notified_status := NULL; END IF;
  IF NEW.last_notified_at IS NULL THEN NEW.last_notified_at := NULL; END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.trg_orders_status_tracking() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_customer text; v_window interval := interval '30 seconds'; v_next timestamptz;
BEGIN
  IF TG_OP <> 'UPDATE' OR NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  v_customer := public.map_order_status_to_customer(NEW.status, NEW.service_mode);
  INSERT INTO public.order_status_history(order_id, internal_status, customer_status) VALUES (NEW.order_id, NEW.status, v_customer);
  IF v_customer IS NULL THEN RETURN NEW; END IF;
  IF NEW.last_notified_status IS NOT NULL AND NEW.last_notified_status = v_customer THEN RETURN NEW; END IF;
  IF NEW.last_notified_at IS NOT NULL AND NEW.last_notified_at > now() - v_window THEN v_next := NEW.last_notified_at + v_window; ELSE v_next := now(); END IF;
  PERFORM public.enqueue_wa_order_status(NEW.order_id, v_customer, NULL, 'fr');
  NEW.last_notified_status := v_customer;
  NEW.last_notified_at := now();
  UPDATE public.outbound_messages SET next_retry_at = GREATEST(next_retry_at, v_next), updated_at = now()
    WHERE order_id = NEW.order_id AND dedupe_key = ('order_status:' || NEW.order_id::text || ':' || upper(v_customer));
  RETURN NEW;
END $$;

-- ===========================
-- SECTION 5: Triggers
-- ===========================
DROP TRIGGER IF EXISTS orders_init_tracking ON public.orders;
CREATE TRIGGER orders_init_tracking BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.trg_orders_init_tracking();

DROP TRIGGER IF EXISTS orders_status_tracking ON public.orders;
CREATE TRIGGER orders_status_tracking BEFORE UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.trg_orders_status_tracking();

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_orders_audit') THEN
    CREATE TRIGGER trg_orders_audit AFTER INSERT OR UPDATE OR DELETE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.fn_orders_audit();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_api_clients_audit') THEN
    CREATE TRIGGER trg_api_clients_audit AFTER INSERT OR UPDATE OR DELETE ON public.api_clients FOR EACH ROW EXECUTE FUNCTION public.fn_api_clients_audit();
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_faq_entries_tsv ON public.faq_entries;
CREATE TRIGGER trg_faq_entries_tsv BEFORE INSERT OR UPDATE OF question, answer, tags ON public.faq_entries FOR EACH ROW EXECUTE FUNCTION public.faq_entries_tsv_update();

-- ===========================
-- SECTION 6: Views
-- ===========================
CREATE OR REPLACE VIEW public.v_recent_orders AS
SELECT o.order_id, o.status, o.total_cents, o.service_mode, o.channel, o.created_at,
  t.name AS tenant_name, r.name AS restaurant_name,
  (SELECT COUNT(*) FROM public.order_items oi WHERE oi.order_id = o.order_id) AS item_count,
  (SELECT string_agg(oi.label || ' x' || oi.qty, ', ') FROM public.order_items oi WHERE oi.order_id = o.order_id) AS items_summary
FROM public.orders o JOIN public.tenants t ON t.tenant_id = o.tenant_id JOIN public.restaurants r ON r.restaurant_id = o.restaurant_id
ORDER BY o.created_at DESC;

CREATE OR REPLACE VIEW public.v_tenant_stats AS
SELECT t.tenant_id, t.name AS tenant_name, t.plan, t.status,
  (SELECT COUNT(*) FROM public.restaurants r WHERE r.tenant_id = t.tenant_id) AS restaurant_count,
  (SELECT COUNT(*) FROM public.orders o WHERE o.tenant_id = t.tenant_id) AS total_orders,
  (SELECT COALESCE(SUM(o.total_cents), 0) FROM public.orders o WHERE o.tenant_id = t.tenant_id AND o.status = 'DONE') AS total_revenue_cents,
  (SELECT COUNT(*) FROM public.api_clients ac WHERE ac.tenant_id = t.tenant_id AND ac.is_active) AS active_api_clients
FROM public.tenants t;

CREATE OR REPLACE VIEW public.v_request_trace AS
SELECT sl.correlation_id, sl.level, sl.event_type, sl.message, sl.workflow_name, sl.node_name, sl.created_at AS log_ts,
  im.msg_id, im.channel, im.received_at AS inbound_ts,
  om.template, om.status AS outbound_status, om.sent_at
FROM public.structured_logs sl
LEFT JOIN public.inbound_messages im ON im.correlation_id = sl.correlation_id
LEFT JOIN public.outbound_messages om ON om.correlation_id = sl.correlation_id
ORDER BY sl.created_at DESC;

-- ===========================
-- SECTION 7: Performance Indexes
-- ===========================
CREATE INDEX IF NOT EXISTS idx_conversation_quarantine_key_active_expires ON conversation_quarantine (conversation_key, active, expires_at);
CREATE INDEX IF NOT EXISTS idx_feedback_jobs_status_scheduled ON feedback_jobs (status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_menu_items_rest_active_cat_code ON menu_items (restaurant_id, active, category, item_code);
CREATE INDEX IF NOT EXISTS idx_menu_item_options_rest_active_item_opt ON menu_item_options (restaurant_id, active, item_code, option_code);
CREATE INDEX IF NOT EXISTS idx_orders_status_created ON orders(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_last_notified ON orders(restaurant_id, last_notified_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_tenant_status_created ON orders(tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_status ON orders(restaurant_id, status);
CREATE INDEX IF NOT EXISTS idx_outbound_messages_status_retry ON outbound_messages(status, next_retry_at) WHERE status IN ('PENDING', 'RETRY');
CREATE INDEX IF NOT EXISTS idx_security_events_type_created ON security_events(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_api_clients_tenant_active ON api_clients(tenant_id, is_active);
CREATE INDEX IF NOT EXISTS idx_tenants_slug ON tenants(slug) WHERE slug IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tenants_status ON tenants(status);
CREATE INDEX IF NOT EXISTS idx_restaurants_active ON restaurants(tenant_id, is_active);
CREATE INDEX IF NOT EXISTS idx_quarantine_active_expires ON conversation_quarantine (active, expires_at);
CREATE INDEX IF NOT EXISTS idx_quarantine_conv_active ON conversation_quarantine (conversation_key, active);

-- ===========================
-- SECTION 8: Seed Data
-- ===========================

-- Default tenant + restaurant
INSERT INTO tenants(tenant_id, name, slug, plan, status) VALUES ('00000000-0000-0000-0000-000000000001', 'Default Chain', 'default-chain', 'professional', 'active') ON CONFLICT (tenant_id) DO NOTHING;
INSERT INTO restaurants(restaurant_id, tenant_id, name, phone, default_language, is_active) VALUES ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001', 'Branch 1', '+213000000000', 'fr', true) ON CONFLICT (restaurant_id) DO NOTHING;

-- Demo menu
INSERT INTO menu_items(restaurant_id,item_code,label,category,price_cents) VALUES
  ('00000000-0000-0000-0000-000000000000','P01','Pizza Margherita','Pizzas',900),
  ('00000000-0000-0000-0000-000000000000','P02','Pizza Pepperoni','Pizzas',1100),
  ('00000000-0000-0000-0000-000000000000','B01','Burger Classic','Burgers',750),
  ('00000000-0000-0000-0000-000000000000','S01','Salade','Sides',450)
ON CONFLICT DO NOTHING;

INSERT INTO menu_item_options(restaurant_id,item_code,option_code,label,kind,price_delta_cents) VALUES
  ('00000000-0000-0000-0000-000000000000','P01','X01','Extra fromage','extra',150),
  ('00000000-0000-0000-0000-000000000000','P01','R01','Sans olives','remove',0),
  ('00000000-0000-0000-0000-000000000000','B01','X02','Double steak','extra',250),
  ('00000000-0000-0000-0000-000000000000','B01','R02','Sans oignons','remove',0)
ON CONFLICT DO NOTHING;

-- Fraud rules
INSERT INTO fraud_rules(rule_key, scope, action, score, params_json) VALUES
  ('IN_FLOOD_30S', 'INBOUND', 'QUARANTINE', 80, '{"limit_30s":6,"quarantine_minutes":10}'::jsonb),
  ('IN_LONG_TEXT', 'INBOUND', 'THROTTLE', 20, '{"max_len":1200}'::jsonb),
  ('CO_HIGH_ORDER_TOTAL', 'CHECKOUT', 'REQUIRE_CONFIRMATION', 70, '{"threshold_cents":30000,"confirm_ttl_minutes":10}'::jsonb),
  ('CO_REPEAT_CANCELLED_7D', 'CHECKOUT', 'QUARANTINE', 90, '{"cancel_limit":3,"window_days":7,"quarantine_minutes":30}'::jsonb)
ON CONFLICT (rule_key) DO NOTHING;

-- Security event types
INSERT INTO ops.security_event_types(code, description) VALUES
  ('SPAM_DETECTED', 'Inbound spam/flood detected'),
  ('BOT_SUSPECTED', 'Inbound bot/payload suspected'),
  ('QUARANTINE_APPLIED', 'Conversation quarantined'),
  ('QUARANTINE_RELEASED', 'Conversation quarantine released'),
  ('FRAUD_CONFIRMATION_REQUIRED', 'Checkout requires explicit confirmation'),
  ('DELIVERY_ZONE_NOT_FOUND', 'Delivery: zone not found'),
  ('DELIVERY_ZONE_INACTIVE', 'Delivery: zone inactive'),
  ('DELIVERY_MIN_ORDER', 'Delivery: minimum order not reached'),
  ('DELIVERY_QUOTE_OK', 'Delivery: quote computed'),
  ('ADDRESS_AMBIGUOUS', 'Delivery: address clarification requested'),
  ('LEGACY_TOKEN_ATTEMPT', 'Legacy token auth attempt'),
  ('TOKEN_ROTATED', 'API token rotated'),
  ('CONTRACT_VALIDATION_FAILED', 'Contract validation failed'),
  ('SLO_BREACH', 'SLO threshold breached'),
  ('RETENTION_RUN', 'Data retention purge executed')
ON CONFLICT (code) DO NOTHING;

-- Darija detection patterns
INSERT INTO darija_patterns(category, pattern, priority) VALUES
  ('menu', 'chno kayn', 10), ('menu', 'chnou kayen', 10), ('menu', 'wach kayn', 10),
  ('menu', 'wesh kayn', 10), ('menu', 'fin menu', 10), ('menu', 'lmenu', 10),
  ('checkout', 'kml', 10), ('checkout', 'kammel', 10), ('checkout', 'ncommandi', 10),
  ('greeting', 'salam', 10), ('greeting', 'slm', 10), ('greeting', 'labas', 10),
  ('affirmative', 'wakha', 10), ('affirmative', 'wah', 10), ('affirmative', 'iyeh', 10),
  ('negative', 'la', 10), ('negative', 'lala', 10), ('negative', 'makanch', 10)
ON CONFLICT (category, lower(pattern)) DO NOTHING;

-- Message templates (FR/AR/Darija)
INSERT INTO message_templates(tenant_id, template_key, locale, content, variables) VALUES
  ('_GLOBAL','CORE_CLARIFY','fr','Je n''ai pas bien compris. Tu peux preciser ?','[]'::jsonb),
  ('_GLOBAL','CORE_CLARIFY','ar','لم أفهم جيداً. هل يمكنك التوضيح؟','[]'::jsonb),
  ('_GLOBAL','CORE_CLARIFY','darija','Ma fhemtekch mezyan. 3awdha lik?','[]'::jsonb),
  ('_GLOBAL','CORE_MENU_HEADER','fr','Menu (IDs utilisables dans ton message)\n','[]'::jsonb),
  ('_GLOBAL','CORE_MENU_HEADER','ar','القائمة (استخدم المعرفات في رسالتك)\n','[]'::jsonb),
  ('_GLOBAL','CORE_LANG_SET_FR','fr','Langue definie sur Francais. Tape "menu" pour voir la carte.','[]'::jsonb),
  ('_GLOBAL','CORE_LANG_SET_AR','ar','تم تغيير اللغة إلى العربية. اكتب "menu" لعرض القائمة.','[]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_CONFIRMED','fr','Commande confirmee (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_PREPARING','fr','Votre commande est en preparation (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_READY','fr','Votre commande est prete (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_OUT_FOR_DELIVERY','fr','Votre commande est en cours de livraison (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_DELIVERED','fr','Commande livree / terminee (#{{order_id}}). Merci !','["order_id"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_CANCELLED','fr','Commande annulee (#{{order_id}}).','["order_id"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_CONFIRMED','ar','تم تأكيد طلبك (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_PREPARING','ar','يتم تحضير طلبك (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_READY','ar','طلبك جاهز (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_OUT_FOR_DELIVERY','ar','طلبك في الطريق للتوصيل (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_DELIVERED','ar','تم تسليم/إنهاء الطلب (#{{order_id}}). شكراً لك!','["order_id"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_CANCELLED','ar','تم إلغاء الطلب (#{{order_id}}).','["order_id"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_CONFIRMED','darija','Commande dyalek tconfirmat (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_DELIVERED','darija','Commande wslet / salat (#{{order_id}}). Choukran!','["order_id"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_CANCELLED','darija','Commande t3atlat (#{{order_id}}).','["order_id"]'::jsonb),
  ('_GLOBAL','SUPPORT_HANDOFF_ACK','fr','Merci. Un agent va vous contacter rapidement.','[]'::jsonb),
  ('_GLOBAL','SUPPORT_HANDOFF_ACK','ar','شكراً. سيتواصل معك أحد الموظفين قريباً.','[]'::jsonb),
  ('_GLOBAL','FAQ_NO_MATCH','fr','Je n''ai pas trouve de reponse. Je te mets en relation avec un agent.','[]'::jsonb),
  ('_GLOBAL','FAQ_NO_MATCH','ar','لم أجد إجابة. سأحوّلك إلى موظف.','[]'::jsonb),
  ('_GLOBAL','FRAUD_CONFIRM_REQUIRED','fr','Montant eleve detecte. Pour confirmer, reponds : CONFIRM {{code}} (valable {{minutes}} min).','["code","minutes"]'::jsonb),
  ('_GLOBAL','FRAUD_CONFIRM_REQUIRED','ar','تم اكتشاف مبلغ مرتفع. للتأكيد أرسل: CONFIRM {{code}} (صالحة لمدة {{minutes}} دقيقة).','["code","minutes"]'::jsonb),
  ('_GLOBAL','FRAUD_QUARANTINED','fr','Activite suspecte detectee. Ton acces est temporairement limite.','[]'::jsonb),
  ('_GLOBAL','FRAUD_QUARANTINED','ar','تم رصد نشاط مشبوه. تم تقييد الوصول مؤقتًا.','[]'::jsonb),
  ('_GLOBAL','FRAUD_RELEASED','fr','Acces retabli. Tu peux reprendre.','[]'::jsonb),
  ('_GLOBAL','FRAUD_RELEASED','ar','تم رفع التقييد. يمكنك المتابعة.','[]'::jsonb)
ON CONFLICT (template_key, locale, tenant_id) DO NOTHING;

-- ===========================
-- SECTION 9: ANALYZE
-- ===========================
ANALYZE tenants;
ANALYZE restaurants;
ANALYZE orders;
ANALYZE order_items;
ANALYZE api_clients;
ANALYZE inbound_messages;
ANALYZE outbound_messages;
ANALYZE menu_items;
