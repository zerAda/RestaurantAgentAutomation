-- Migration: P2 - EPIC6 Support & FAQ
-- Consolidated into db/bootstrap.sql (support_tickets, faq_entries)
-- This file is idempotent and safe to re-run.

CREATE TABLE IF NOT EXISTS support_tickets (
  id               bigserial PRIMARY KEY,
  ticket_number    text NOT NULL UNIQUE,
  tenant_id        uuid,
  restaurant_id    uuid,
  conversation_key text NOT NULL,
  channel          text NOT NULL DEFAULT 'whatsapp',
  customer_phone   text,
  customer_name    text,
  subject          text,
  status           text NOT NULL DEFAULT 'open',
  priority         text NOT NULL DEFAULT 'normal',
  assigned_to      text,
  metadata         jsonb DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz DEFAULT now(),
  resolved_at      timestamptz,
  closed_at        timestamptz
);

CREATE TABLE IF NOT EXISTS faq_entries (
  id             serial PRIMARY KEY,
  restaurant_id  uuid,
  question       text NOT NULL,
  answer         text NOT NULL,
  locale         text NOT NULL DEFAULT 'fr',
  category       text DEFAULT 'general',
  tsv            tsvector,
  active         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_faq_tsv ON faq_entries USING gin(tsv);
