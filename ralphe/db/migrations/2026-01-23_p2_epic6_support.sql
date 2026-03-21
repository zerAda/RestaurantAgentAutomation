-- Migration: P2 - EPIC6 Support & FAQ
-- Guard migration: compatible with bootstrap.sql (source of truth)
-- Bootstrap schema is the source of truth for all table definitions.

-- support_tickets (bootstrap uses: ticket_id bigserial, tenant_id, restaurant_id,
--   channel, conversation_key, customer_user_id, status, priority, reason_code,
--   subject, context_json, created_at, updated_at, closed_at)
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

-- faq_entries (bootstrap uses: tenant_id, restaurant_id, locale, question, answer,
--   tags, is_active, search_tsv tsvector)
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
