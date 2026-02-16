-- Migration: P2 - EPIC5 Localization (L10N)
-- Consolidated into db/bootstrap.sql (customer_preferences, darija_patterns, message_templates)
-- This file is idempotent and safe to re-run.

CREATE TABLE IF NOT EXISTS customer_preferences (
  tenant_id  text NOT NULL,
  phone      text NOT NULL,
  locale     text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, phone)
);

CREATE TABLE IF NOT EXISTS darija_patterns (
  id          serial PRIMARY KEY,
  pattern     text NOT NULL UNIQUE,
  intent      text NOT NULL,
  confidence  numeric NOT NULL DEFAULT 0.8,
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS message_templates (
  id             serial PRIMARY KEY,
  template_key   text NOT NULL,
  locale         text NOT NULL DEFAULT 'fr',
  channel        text NOT NULL DEFAULT 'whatsapp',
  body           text NOT NULL,
  metadata       jsonb DEFAULT '{}'::jsonb,
  active         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz DEFAULT now(),
  UNIQUE (template_key, locale, channel)
);
