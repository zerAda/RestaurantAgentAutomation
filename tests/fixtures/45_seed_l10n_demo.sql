-- EPIC5 L10N fixtures
-- Seed a customer preference for tracking + an override template for tenant.

-- Customer preference for tracking smoke (order user_id='fixture-track')
INSERT INTO customer_preferences(tenant_id, phone, locale)
VALUES ('00000000-0000-0000-0000-000000000001', 'fixture-track', 'ar')
ON CONFLICT (tenant_id, phone) DO UPDATE SET locale=EXCLUDED.locale, updated_at=now();

-- Tenant override template example (does not touch _GLOBAL)
INSERT INTO message_templates(tenant_id, key, locale, content, variables)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'CORE_CLARIFY',
  'ar',
  'لم أفهم. اكتب "menu" أو أرسل معرف الطبق (مثال: P01 x2).',
  '[]'::jsonb
)
ON CONFLICT (tenant_id, key, locale) DO UPDATE SET content=EXCLUDED.content, updated_at=now();
