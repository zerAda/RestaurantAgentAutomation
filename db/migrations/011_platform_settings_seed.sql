-- Migration: 011_platform_settings_seed.sql
-- Date: 2026-03-08
-- Purpose: Seed platform_settings table with runtime config defaults.
--   These values mirror the current .env defaults so n8n W0_CONFIG_READER
--   can serve config from Strapi without needing a .env change for each tweak.
--   Secrets are marked with is_secret=true; their initial values are placeholders
--   that must be updated via Strapi admin UI (not via this migration).
-- Safety: ON CONFLICT DO NOTHING — re-runnable / idempotent.
-- Rollback: DELETE FROM platform_settings WHERE created_at >= '2026-03-08';
--           (or drop table if Strapi rebuilt from scratch)

SET search_path = strapi;

-- Ensure table exists (Strapi creates it on first boot; this guard makes
-- the migration safe to apply before Strapi has fully initialised).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'strapi'
       AND table_name   = 'platform_settings'
  ) THEN
    RAISE NOTICE 'platform_settings table not yet created by Strapi — skipping seed. Re-run after cms container first boot.';
    RETURN;
  END IF;
END $$;

-- Helper: insert only if key does not exist yet
-- (ON CONFLICT DO NOTHING keeps user-edited values safe on re-run)
INSERT INTO platform_settings (key, value, description, category, is_secret, published_at, created_at, updated_at)
VALUES
  -- LLM
  ('LLM_MODEL',              'llama3.1',                        'Primary Ollama model name',                                  'llm',          false, NOW(), NOW(), NOW()),
  ('LLM_API_URL',            'http://ollama:11434/api/chat',    'LLM API endpoint (Ollama/OpenAI compatible)',                'llm',          false, NOW(), NOW(), NOW()),
  ('LLM_TEMPERATURE',        '0.1',                             'LLM sampling temperature (0.0-1.0)',                         'llm',          false, NOW(), NOW(), NOW()),
  ('LLM_MAX_TOKENS',         '512',                             'Max tokens per LLM response',                               'llm',          false, NOW(), NOW(), NOW()),
  ('LLM_TIMEOUT_MS',         '120000',                          'LLM request timeout in milliseconds',                       'llm',          false, NOW(), NOW(), NOW()),
  ('LLM_FALLBACK_MODEL',     'llama3',                          'Fallback model if primary LLM fails',                       'llm',          false, NOW(), NOW(), NOW()),
  ('LLM_ENABLED',            'true',                            'Enable LLM/AI intent classification in W4_CORE',            'feature_flag', false, NOW(), NOW(), NOW()),

  -- Messaging — WhatsApp
  ('WA_SEND_URL',            'https://graph.facebook.com/v21.0','WhatsApp Graph API base URL',                               'messaging',    false, NOW(), NOW(), NOW()),
  ('WA_PHONE_NUMBER_ID',     '',                                'WhatsApp Cloud API Phone Number ID',                        'messaging',    false, NOW(), NOW(), NOW()),
  ('WA_API_TOKEN',           'REPLACE_IN_STRAPI_ADMIN',         'WhatsApp Bearer token (Meta Cloud API)',                    'messaging',    true,  NOW(), NOW(), NOW()),
  ('GRAPH_API_VERSION',      'v21.0',                           'Meta Graph API version',                                    'messaging',    false, NOW(), NOW(), NOW()),

  -- Messaging — Instagram
  ('IG_SEND_URL',            '',                                'Instagram send URL (auto-built from ig_page_id if empty)',  'messaging',    false, NOW(), NOW(), NOW()),
  ('IG_PAGE_ID',             '',                                'Instagram Professional Account ID',                         'messaging',    false, NOW(), NOW(), NOW()),
  ('IG_API_TOKEN',           'REPLACE_IN_STRAPI_ADMIN',         'Instagram Graph API bearer token',                          'messaging',    true,  NOW(), NOW(), NOW()),

  -- Messaging — Messenger
  ('MSG_SEND_URL',           '',                                'Messenger send URL override (auto-built if empty)',         'messaging',    false, NOW(), NOW(), NOW()),
  ('MESSENGER_PAGE_ID',      '',                                'Facebook Messenger Page ID',                                'messaging',    false, NOW(), NOW(), NOW()),
  ('MSG_API_TOKEN',          'REPLACE_IN_STRAPI_ADMIN',         'Messenger Page Access Token',                               'messaging',    true,  NOW(), NOW(), NOW()),

  -- Payment
  ('PAYMENT_COD_ENABLED',         'true',  'Enable Cash on Delivery payment method',                    'payment', false, NOW(), NOW(), NOW()),
  ('PAYMENT_DEPOSIT_PERCENTAGE',  '30',    'Deposit percentage required for large orders (0-100)',       'payment', false, NOW(), NOW(), NOW()),
  ('PAYMENT_DEPOSIT_THRESHOLD',   '5000',  'Order total (DZD) above which deposit is required',         'payment', false, NOW(), NOW(), NOW()),

  -- Fraud detection
  ('FRAUD_FLOOD_LIMIT_30S',       '5',     'Max inbound messages per user in 30 seconds',               'fraud',   false, NOW(), NOW(), NOW()),
  ('FRAUD_HIGH_ORDER_THRESHOLD',  '10000', 'Order value (DZD) that triggers fraud review',              'fraud',   false, NOW(), NOW(), NOW()),
  ('FRAUD_CANCEL_PATTERN_LIMIT',  '3',     'Cancel attempts before fraud flag triggers',                'fraud',   false, NOW(), NOW(), NOW()),

  -- Outbox / SLO
  ('OUTBOX_MAX_ATTEMPTS',         '7',     'Max retry attempts for outbound message delivery',           'slo',     false, NOW(), NOW(), NOW()),
  ('OUTBOX_BASE_DELAY_SEC',       '1',     'Base exponential backoff delay in seconds',                 'slo',     false, NOW(), NOW(), NOW()),
  ('OUTBOX_MAX_DELAY_SEC',        '60',    'Max backoff delay cap in seconds',                          'slo',     false, NOW(), NOW(), NOW()),
  ('OUTBOX_ASYNC_ENABLED',        'false', 'Queue messages for async worker instead of inline send',    'slo',     false, NOW(), NOW(), NOW()),
  ('RATE_LIMIT_PER_30S',          '30',    'Max API gateway requests per 30 seconds per IP',            'slo',     false, NOW(), NOW(), NOW()),
  ('SLO_INBOUND_TO_OUTBOX_P95_MS','8000',  'P95 SLO target for inbound-to-outbox in milliseconds',     'slo',     false, NOW(), NOW(), NOW()),

  -- Feature flags
  ('L10N_ENABLED',            'true',  'Enable Arabic/Darija/FR multilingual detection',                'feature_flag', false, NOW(), NOW(), NOW()),
  ('FAQ_ENABLED',             'true',  'Enable FAQ/RAG knowledge base queries',                         'feature_flag', false, NOW(), NOW(), NOW()),
  ('SUPPORT_ENABLED',         'true',  'Enable human support handoff via keywords',                     'feature_flag', false, NOW(), NOW(), NOW()),

  -- Delivery
  ('DRIVER_PHONE_NUMBER',     '',      'Primary driver contact phone number',                           'driver',  false, NOW(), NOW(), NOW()),
  ('CALL_CENTER_PHONE',       '',      'Call center phone number for voice handoff',                    'driver',  false, NOW(), NOW(), NOW()),

  -- Kiosk
  ('KIOSK_ENABLED',           'false', 'Enable in-store kiosk ordering mode',                          'kiosk',   false, NOW(), NOW(), NOW()),
  ('KIOSK_IDLE_TIMEOUT_SEC',  '120',   'Seconds of inactivity before kiosk resets to home',            'kiosk',   false, NOW(), NOW(), NOW())

ON CONFLICT (key) DO NOTHING;

-- Verify seed
DO $$
DECLARE
  cnt INTEGER;
BEGIN
  SELECT COUNT(*) INTO cnt FROM platform_settings;
  RAISE NOTICE '011_platform_settings_seed: % rows in platform_settings after seed', cnt;
END $$;
