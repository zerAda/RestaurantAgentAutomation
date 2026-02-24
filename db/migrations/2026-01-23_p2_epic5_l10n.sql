-- Migration: P2 - EPIC5 Localization (L10N)
-- Guard migration: compatible with bootstrap.sql (source of truth)
-- Bootstrap schema is the source of truth for all table definitions.

-- customer_preferences (bootstrap uses: tenant_id, phone, locale PK on tenant_id+phone)
CREATE TABLE IF NOT EXISTS customer_preferences (
  tenant_id  text NOT NULL,
  phone      text NOT NULL,
  locale     text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, phone)
);

CREATE INDEX IF NOT EXISTS idx_customer_preferences_tenant_locale
  ON customer_preferences(tenant_id, locale);

-- darija_patterns (bootstrap uses: category, pattern, priority, is_active)
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

-- message_templates (bootstrap uses: template_key, locale, content, variables,
--   tenant_id, restaurant_id, version, is_active)
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
