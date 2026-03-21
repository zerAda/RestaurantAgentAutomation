-- EPIC6 Support fixtures

-- Admin WhatsApp user (for WA console)
INSERT INTO restaurant_users (tenant_id, restaurant_id, channel, user_id, role)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'whatsapp',
  'admin-wa',
  'admin'
)
ON CONFLICT (restaurant_id, channel, user_id) DO NOTHING;

-- Seed a few FAQ entries (FR + AR) to reach "RAG light" baseline
INSERT INTO faq_entries (tenant_id, restaurant_id, locale, question, answer, tags, is_active)
VALUES
(
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'fr',
  'Quels sont vos horaires ?',
  '🕒 Nous sommes ouverts tous les jours de 11:00 à 23:00.',
  ARRAY['horaires','ouverture','fermeture'],
  true
),
(
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'fr',
  'Quels moyens de paiement acceptez-vous ?',
  '💳 Paiement sur place : Espèces et carte (selon disponibilité).',
  ARRAY['paiement','carte','cash'],
  true
),
(
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'ar',
  'ما هي أوقات العمل؟',
  '🕒 نفتح يومياً من 11:00 إلى 23:00.',
  ARRAY['اوقات','ساعات','عمل'],
  true
)
ON CONFLICT DO NOTHING;
