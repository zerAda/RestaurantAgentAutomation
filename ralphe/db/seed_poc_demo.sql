-- ============================================================================
-- SEED POC DEMO — Chez Ralphé (Full Capabilities Showcase)
-- ============================================================================
-- Idempotent: safe to re-run (ON CONFLICT DO NOTHING / DO UPDATE)
-- Covers: multi-tenant, menu, orders, delivery, payments, support, FAQ,
--         tracking, anti-fraud, L10N, drivers, kitchen, metrics, audit
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. TENANT & RESTAURANTS
-- ============================================================================

UPDATE tenants SET
  name = 'Ralphé Group',
  slug = 'ralphe-group',
  plan = 'professional',
  billing_email = 'contact@chezralphe.dz',
  settings = '{"brand_color":"#E63946","logo_url":"/assets/logo-ralphe.png","currency":"DZD"}'::jsonb
WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

UPDATE restaurants SET
  name = 'Chez Ralphé - Hydra',
  phone = '+213555123456',
  email = 'hydra@chezralphe.dz',
  default_language = 'fr',
  timezone = 'Africa/Algiers',
  currency = 'DZD',
  address = '{"street":"12 Rue Didouche Mourad","commune":"Hydra","wilaya":"Alger","zip":"16035","lat":36.7538,"lng":3.0588}'::jsonb,
  operating_hours = '{"mon":{"open":"11:00","close":"23:00"},"tue":{"open":"11:00","close":"23:00"},"wed":{"open":"11:00","close":"23:00"},"thu":{"open":"11:00","close":"23:00"},"fri":{"open":"11:00","close":"00:00"},"sat":{"open":"11:00","close":"00:00"},"sun":{"open":"12:00","close":"22:00"}}'::jsonb
WHERE restaurant_id = '00000000-0000-0000-0000-000000000000';

INSERT INTO restaurants(restaurant_id, tenant_id, name, phone, email, default_language, timezone, currency, address, operating_hours, is_active)
VALUES (
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000001',
  'Chez Ralphé - Bab Ezzouar',
  '+213555789012',
  'babez@chezralphe.dz',
  'fr',
  'Africa/Algiers',
  'DZD',
  '{"street":"Centre Commercial Bab Ezzouar","commune":"Bab Ezzouar","wilaya":"Alger","zip":"16028","lat":36.7167,"lng":3.1833}'::jsonb,
  '{"mon":{"open":"10:00","close":"22:00"},"tue":{"open":"10:00","close":"22:00"},"wed":{"open":"10:00","close":"22:00"},"thu":{"open":"10:00","close":"22:00"},"fri":{"open":"10:00","close":"23:00"},"sat":{"open":"10:00","close":"23:00"},"sun":{"open":"11:00","close":"21:00"}}'::jsonb,
  true
) ON CONFLICT (restaurant_id) DO NOTHING;

-- ============================================================================
-- 2. MENU ITEMS (18 items, 6 categories)
-- ============================================================================

INSERT INTO menu_items(restaurant_id, item_code, label, category, price_cents, active) VALUES
  -- Pizzas
  ('00000000-0000-0000-0000-000000000000', 'P01', 'Pizza Margherita',     'Pizzas',   900,  true),
  ('00000000-0000-0000-0000-000000000000', 'P02', 'Pizza Pepperoni',      'Pizzas',   1100, true),
  ('00000000-0000-0000-0000-000000000000', 'P03', 'Pizza 4 Fromages',     'Pizzas',   1200, true),
  ('00000000-0000-0000-0000-000000000000', 'P04', 'Calzone Royale',       'Pizzas',   1300, true),
  ('00000000-0000-0000-0000-000000000000', 'P05', 'Pizza Végétarienne',   'Pizzas',   1000, true),
  -- Burgers
  ('00000000-0000-0000-0000-000000000000', 'B01', 'Burger Classic',       'Burgers',  750,  true),
  ('00000000-0000-0000-0000-000000000000', 'B02', 'Double Smash Burger',  'Burgers',  1100, true),
  ('00000000-0000-0000-0000-000000000000', 'B03', 'Chicken Crispy Burger','Burgers',  950,  true),
  -- Chawarma & Wraps
  ('00000000-0000-0000-0000-000000000000', 'C01', 'Chawarma Poulet',      'Chawarma', 650,  true),
  ('00000000-0000-0000-0000-000000000000', 'C02', 'Chawarma Viande',      'Chawarma', 750,  true),
  ('00000000-0000-0000-0000-000000000000', 'C03', 'Tacos Mixte',          'Chawarma', 850,  true),
  -- Sides
  ('00000000-0000-0000-0000-000000000000', 'S01', 'Frites',              'Sides',    300,  true),
  ('00000000-0000-0000-0000-000000000000', 'S02', 'Salade César',        'Sides',    450,  true),
  ('00000000-0000-0000-0000-000000000000', 'S03', 'Mozzarella Sticks',   'Sides',    500,  true),
  -- Boissons
  ('00000000-0000-0000-0000-000000000000', 'D01', 'Coca-Cola 33cl',      'Boissons', 150,  true),
  ('00000000-0000-0000-0000-000000000000', 'D02', 'Jus d''Orange',       'Boissons', 200,  true),
  ('00000000-0000-0000-0000-000000000000', 'D03', 'Eau Minérale 50cl',   'Boissons', 80,   true),
  -- Desserts
  ('00000000-0000-0000-0000-000000000000', 'X01D','Tiramisu',            'Desserts', 400,  true),
  ('00000000-0000-0000-0000-000000000000', 'X02D','Crème Brûlée',        'Desserts', 350,  true)
ON CONFLICT (restaurant_id, item_code) DO UPDATE SET
  label = EXCLUDED.label, category = EXCLUDED.category, price_cents = EXCLUDED.price_cents, active = EXCLUDED.active;

-- ============================================================================
-- 3. MENU ITEM OPTIONS (10 options)
-- ============================================================================

INSERT INTO menu_item_options(restaurant_id, item_code, option_code, label, kind, price_delta_cents) VALUES
  ('00000000-0000-0000-0000-000000000000', 'P01', 'X01',  'Extra fromage',       'extra',  150),
  ('00000000-0000-0000-0000-000000000000', 'P01', 'R01',  'Sans olives',         'remove', 0),
  ('00000000-0000-0000-0000-000000000000', 'P02', 'X03',  'Bord fourré',         'extra',  200),
  ('00000000-0000-0000-0000-000000000000', 'B01', 'X02',  'Double steak',        'extra',  250),
  ('00000000-0000-0000-0000-000000000000', 'B01', 'R02',  'Sans oignons',        'remove', 0),
  ('00000000-0000-0000-0000-000000000000', 'B02', 'X04',  'Bacon croustillant',  'extra',  200),
  ('00000000-0000-0000-0000-000000000000', 'C01', 'X05',  'Sauce piquante',      'extra',  0),
  ('00000000-0000-0000-0000-000000000000', 'C01', 'X06',  'Supplément frites',   'extra',  150),
  ('00000000-0000-0000-0000-000000000000', 'B03', 'X07',  'Sauce algéroise',     'extra',  0),
  ('00000000-0000-0000-0000-000000000000', 'P04', 'N01',  'Bien cuit svp',       'note',   0)
ON CONFLICT (restaurant_id, option_code) DO UPDATE SET
  label = EXCLUDED.label, kind = EXCLUDED.kind, price_delta_cents = EXCLUDED.price_delta_cents;

-- ============================================================================
-- 4. DELIVERY ZONES (8 zones, 1 inactive)
-- ============================================================================

INSERT INTO delivery_zones(restaurant_id, wilaya, commune, fee_base_cents, min_order_cents, eta_min, eta_max, is_active, center_lat, center_lng) VALUES
  ('00000000-0000-0000-0000-000000000000', 'Alger', 'Hydra',       300,  1500, 25, 40, true,  36.7538, 3.0588),
  ('00000000-0000-0000-0000-000000000000', 'Alger', 'Kouba',       350,  1500, 30, 50, true,  36.7264, 3.0536),
  ('00000000-0000-0000-0000-000000000000', 'Alger', 'Bab Ezzouar', 400,  1800, 35, 55, true,  36.7167, 3.1833),
  ('00000000-0000-0000-0000-000000000000', 'Alger', 'El Biar',     350,  1500, 25, 45, true,  36.7692, 3.0303),
  ('00000000-0000-0000-0000-000000000000', 'Alger', 'Birkhadem',   450,  2000, 40, 65, true,  36.7147, 3.0506),
  ('00000000-0000-0000-0000-000000000000', 'Alger', 'Draria',      500,  2200, 50, 80, false, 36.7286, 2.9531),
  ('00000000-0000-0000-0000-000000000000', 'Alger', 'Chéraga',     450,  2000, 40, 65, true,  36.7631, 2.9556),
  ('00000000-0000-0000-0000-000000000000', 'Alger', 'Ain Naadja',  400,  1800, 35, 60, true,  36.7000, 3.0333)
ON CONFLICT ON CONSTRAINT uq_delivery_zones_rest_wilaya_commune DO UPDATE SET
  fee_base_cents = EXCLUDED.fee_base_cents, min_order_cents = EXCLUDED.min_order_cents,
  eta_min = EXCLUDED.eta_min, eta_max = EXCLUDED.eta_max, is_active = EXCLUDED.is_active;

-- ============================================================================
-- 5. DELIVERY FEE RULES (3 rules)
-- ============================================================================

INSERT INTO delivery_fee_rules(restaurant_id, name, start_time, end_time, surcharge_cents, free_delivery_threshold_cents, is_active) VALUES
  ('00000000-0000-0000-0000-000000000000', 'Pic soirée',             '20:00'::time, '23:00'::time, 100,  NULL, true),
  ('00000000-0000-0000-0000-000000000000', 'Déjeuner livraison gratuite', '11:00'::time, '14:30'::time, 0, 4000, true),
  ('00000000-0000-0000-0000-000000000000', 'Vendredi gratuit 3000+', '00:00'::time, '23:59'::time, 0, 3000, true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 6. RESTAURANT USERS (7 users, multiple roles/channels)
-- ============================================================================

INSERT INTO restaurant_users(tenant_id, restaurant_id, channel, user_id, role) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'whatsapp',  '213555100001', 'customer'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'whatsapp',  '213555100002', 'customer'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'whatsapp',  '213555100003', 'customer'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'instagram', 'ig_foodie_dz', 'customer'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'messenger', 'fb_gourmet42',  'customer'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'whatsapp',  '213555900001', 'admin'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'whatsapp',  '213555900002', 'kitchen')
ON CONFLICT (restaurant_id, channel, user_id) DO NOTHING;

-- ============================================================================
-- 7. ADMIN PHONE ALLOWLIST
-- ============================================================================

INSERT INTO admin_phone_allowlist(tenant_id, restaurant_id, phone_number, display_name, role, permissions, is_active) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555900001', 'Karim (Owner)', 'owner',
   '["status","flags","flags_set","flags_unset","tickets","take","close","reply","zone_list","zone_create","zone_update","zone_delete","dlq_list","dlq_show","dlq_replay","dlq_drop","order_status","help","template_get","template_set"]'::jsonb,
   true),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555900003', 'Amina (Manager)', 'admin',
   '["status","tickets","take","close","reply","zone_list","order_status","help"]'::jsonb,
   true)
ON CONFLICT (phone_number) DO NOTHING;

-- ============================================================================
-- 8. RESTAURANT PAYMENT CONFIG
-- ============================================================================

INSERT INTO restaurant_payment_config(restaurant_id, cod_enabled, deposit_enabled, cib_enabled, edahabia_enabled,
  cod_max_amount, deposit_mode, deposit_percentage, deposit_fixed, deposit_threshold, no_deposit_min_orders, no_deposit_min_score)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  true, true, false, false,
  1000000, 'PERCENTAGE', 30, 0, 30000, 3, 70
) ON CONFLICT (restaurant_id) DO UPDATE SET
  deposit_enabled = EXCLUDED.deposit_enabled, deposit_percentage = EXCLUDED.deposit_percentage;

-- ============================================================================
-- 9. CONVERSATION STATES (5 active conversations)
-- ============================================================================

INSERT INTO conversation_state(conversation_key, tenant_id, restaurant_id, channel, user_id, state_json, correlation_id) VALUES
  ('wa:213555100001:00000000-0000-0000-0000-000000000000',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100001',
   '{"step":"COLLECTING","locale":"fr","items_count":2,"service_mode":"livraison"}'::jsonb,
   'corr-conv-001'),
  ('wa:213555100002:00000000-0000-0000-0000-000000000000',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100002',
   '{"step":"CONFIRMING","locale":"fr","items_count":3,"service_mode":"a_emporter","total_cents":2350}'::jsonb,
   'corr-conv-002'),
  ('wa:213555100003:00000000-0000-0000-0000-000000000000',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100003',
   '{"step":"START","locale":"ar"}'::jsonb,
   'corr-conv-003'),
  ('ig:ig_foodie_dz:00000000-0000-0000-0000-000000000000',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'instagram', 'ig_foodie_dz',
   '{"step":"COLLECTING","locale":"fr","items_count":1}'::jsonb,
   'corr-conv-004'),
  ('msg:fb_gourmet42:00000000-0000-0000-0000-000000000000',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'messenger', 'fb_gourmet42',
   '{"step":"COLLECTING","locale":"fr","items_count":1,"service_mode":"livraison","address_step":"WAITING_COMMUNE"}'::jsonb,
   'corr-conv-005')
ON CONFLICT (conversation_key) DO UPDATE SET state_json = EXCLUDED.state_json;

-- ============================================================================
-- 10. CARTS (2 active carts)
-- ============================================================================

INSERT INTO carts(conversation_key, cart_json) VALUES
  ('wa:213555100001:00000000-0000-0000-0000-000000000000',
   '{"items":[{"item_code":"P03","label":"Pizza 4 Fromages","qty":1,"unit_price_cents":1200,"options":[{"code":"X01","label":"Extra fromage","delta":150}],"line_total":1350},{"item_code":"D01","label":"Coca-Cola 33cl","qty":2,"unit_price_cents":150,"options":[],"line_total":300}]}'::jsonb),
  ('wa:213555100002:00000000-0000-0000-0000-000000000000',
   '{"items":[{"item_code":"B02","label":"Double Smash Burger","qty":1,"unit_price_cents":1100,"options":[{"code":"X04","label":"Bacon croustillant","delta":200}],"line_total":1300},{"item_code":"S01","label":"Frites","qty":1,"unit_price_cents":300,"options":[],"line_total":300},{"item_code":"D02","label":"Jus d''Orange","qty":1,"unit_price_cents":200,"options":[],"line_total":200}]}'::jsonb)
ON CONFLICT (conversation_key) DO UPDATE SET cart_json = EXCLUDED.cart_json;

-- ============================================================================
-- 11. ORDERS (10 orders — full lifecycle showcase)
-- ============================================================================

INSERT INTO orders(order_id, tenant_id, restaurant_id, channel, user_id, service_mode, status,
  total_cents, delivery_wilaya, delivery_commune, delivery_fee_cents, delivery_eta_min, delivery_eta_max,
  delivery_address, delivery_phone, payment_mode, payment_status, customer_phone, correlation_id, created_at, updated_at) VALUES

  -- #1: DONE — livraison WhatsApp, completed yesterday
  ('aaaaaaaa-0001-4000-a000-000000000001',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100001', 'livraison', 'DONE',
   2850, 'Alger', 'Hydra', 300, 25, 40,
   '12 Rue des Frères, Hydra', '213555100001', 'COD', 'COMPLETED',
   '213555100001', 'corr-order-001', now() - interval '26 hours', now() - interval '25 hours'),

  -- #2: DONE — sur_place WhatsApp, completed today
  ('aaaaaaaa-0002-4000-a000-000000000002',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100002', 'sur_place', 'DONE',
   1800, NULL, NULL, NULL, NULL, NULL,
   NULL, NULL, 'COD', 'COMPLETED',
   '213555100002', 'corr-order-002', now() - interval '3 hours', now() - interval '2 hours'),

  -- #3: IN_PROGRESS — livraison, being prepared now
  ('aaaaaaaa-0003-4000-a000-000000000003',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100001', 'livraison', 'IN_PROGRESS',
   3200, 'Alger', 'Kouba', 350, 30, 50,
   '45 Cité des 500 logements, Kouba', '213555100001', 'COD', 'PENDING',
   '213555100001', 'corr-order-003', now() - interval '35 minutes', now() - interval '15 minutes'),

  -- #4: READY — a_emporter, waiting for pickup
  ('aaaaaaaa-0004-4000-a000-000000000004',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100002', 'a_emporter', 'READY',
   1450, NULL, NULL, NULL, NULL, NULL,
   NULL, NULL, 'COD', 'PENDING',
   '213555100002', 'corr-order-004', now() - interval '45 minutes', now() - interval '10 minutes'),

  -- #5: ACCEPTED — livraison, just confirmed
  ('aaaaaaaa-0005-4000-a000-000000000005',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100003', 'livraison', 'ACCEPTED',
   2100, 'Alger', 'El Biar', 350, 25, 45,
   '8 Boulevard Colonel Amirouche, El Biar', '213555100003', 'COD', 'PENDING',
   '213555100003', 'corr-order-005', now() - interval '20 minutes', now() - interval '18 minutes'),

  -- #6: NEW — just placed
  ('aaaaaaaa-0006-4000-a000-000000000006',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100003', 'livraison', 'NEW',
   1650, 'Alger', 'Ain Naadja', 400, 35, 60,
   '22 Rue de la Liberté, Ain Naadja', '213555100003', 'COD', 'PENDING',
   '213555100003', 'corr-order-006', now() - interval '2 minutes', now() - interval '2 minutes'),

  -- #7: CANCELLED
  ('aaaaaaaa-0007-4000-a000-000000000007',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100002', 'livraison', 'CANCELLED',
   950, 'Alger', 'Birkhadem', 450, 40, 65,
   NULL, '213555100002', 'COD', 'CANCELLED',
   '213555100002', 'corr-order-007', now() - interval '2 days', now() - interval '2 days'),

  -- #8: OUT_FOR_DELIVERY — driver en route
  ('aaaaaaaa-0008-4000-a000-000000000008',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100001', 'livraison', 'OUT_FOR_DELIVERY',
   2600, 'Alger', 'Chéraga', 450, 40, 65,
   '3 Lotissement Ben Aknoun, Chéraga', '213555100001', 'COD', 'PENDING',
   '213555100001', 'corr-order-008', now() - interval '50 minutes', now() - interval '8 minutes'),

  -- #9: DONE — Instagram order
  ('aaaaaaaa-0009-4000-a000-000000000009',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'instagram', 'ig_foodie_dz', 'a_emporter', 'DONE',
   1900, NULL, NULL, NULL, NULL, NULL,
   NULL, NULL, 'COD', 'COMPLETED',
   NULL, 'corr-order-009', now() - interval '5 hours', now() - interval '4 hours'),

  -- #10: DONE — Messenger + deposit payment
  ('aaaaaaaa-0010-4000-a000-000000000010',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'messenger', 'fb_gourmet42', 'livraison', 'DONE',
   4500, 'Alger', 'Hydra', 300, 25, 40,
   '7 Impasse des Jardins, Hydra', NULL, 'DEPOSIT_COD', 'COMPLETED',
   NULL, 'corr-order-010', now() - interval '1 day', now() - interval '23 hours')

ON CONFLICT (order_id) DO UPDATE SET status = EXCLUDED.status, updated_at = EXCLUDED.updated_at;

-- ============================================================================
-- 12. ORDER ITEMS (27 items across 10 orders)
-- ============================================================================

INSERT INTO order_items(order_id, item_code, label, qty, unit_price_cents, options_json, line_total_cents) VALUES
  -- Order #1 (2850 DZD)
  ('aaaaaaaa-0001-4000-a000-000000000001', 'P03', 'Pizza 4 Fromages',     1, 1200, '[{"code":"X01","label":"Extra fromage","delta":150}]'::jsonb, 1350),
  ('aaaaaaaa-0001-4000-a000-000000000001', 'C01', 'Chawarma Poulet',      2, 650,  '[{"code":"X05","label":"Sauce piquante","delta":0}]'::jsonb, 1300),
  ('aaaaaaaa-0001-4000-a000-000000000001', 'D01', 'Coca-Cola 33cl',       1, 150,  '[]'::jsonb, 150),

  -- Order #2 (1800 DZD)
  ('aaaaaaaa-0002-4000-a000-000000000002', 'P01', 'Pizza Margherita',     1, 900,  '[]'::jsonb, 900),
  ('aaaaaaaa-0002-4000-a000-000000000002', 'S02', 'Salade César',         1, 450,  '[]'::jsonb, 450),
  ('aaaaaaaa-0002-4000-a000-000000000002', 'X01D','Tiramisu',             1, 400,  '[]'::jsonb, 400),

  -- Order #3 (3200 DZD)
  ('aaaaaaaa-0003-4000-a000-000000000003', 'B02', 'Double Smash Burger',  2, 1100, '[{"code":"X04","label":"Bacon croustillant","delta":200}]'::jsonb, 2600),
  ('aaaaaaaa-0003-4000-a000-000000000003', 'S01', 'Frites',              1, 300,  '[]'::jsonb, 300),
  ('aaaaaaaa-0003-4000-a000-000000000003', 'D01', 'Coca-Cola 33cl',       2, 150,  '[]'::jsonb, 300),

  -- Order #4 (1450 DZD)
  ('aaaaaaaa-0004-4000-a000-000000000004', 'C02', 'Chawarma Viande',      1, 750,  '[]'::jsonb, 750),
  ('aaaaaaaa-0004-4000-a000-000000000004', 'C01', 'Chawarma Poulet',      1, 650,  '[]'::jsonb, 650),

  -- Order #5 (2100 DZD)
  ('aaaaaaaa-0005-4000-a000-000000000005', 'P02', 'Pizza Pepperoni',      1, 1100, '[{"code":"X03","label":"Bord fourré","delta":200}]'::jsonb, 1300),
  ('aaaaaaaa-0005-4000-a000-000000000005', 'S03', 'Mozzarella Sticks',   1, 500,  '[]'::jsonb, 500),
  ('aaaaaaaa-0005-4000-a000-000000000005', 'D02', 'Jus d''Orange',       1, 200,  '[]'::jsonb, 200),

  -- Order #6 (1650 DZD)
  ('aaaaaaaa-0006-4000-a000-000000000006', 'P04', 'Calzone Royale',       1, 1300, '[{"code":"N01","label":"Bien cuit svp","delta":0}]'::jsonb, 1300),
  ('aaaaaaaa-0006-4000-a000-000000000006', 'X02D','Crème Brûlée',        1, 350,  '[]'::jsonb, 350),

  -- Order #7 (950 DZD — cancelled)
  ('aaaaaaaa-0007-4000-a000-000000000007', 'B01', 'Burger Classic',       1, 750,  '[]'::jsonb, 750),
  ('aaaaaaaa-0007-4000-a000-000000000007', 'D03', 'Eau Minérale 50cl',   1, 80,   '[]'::jsonb, 80),

  -- Order #8 (2600 DZD)
  ('aaaaaaaa-0008-4000-a000-000000000008', 'P05', 'Pizza Végétarienne',   1, 1000, '[]'::jsonb, 1000),
  ('aaaaaaaa-0008-4000-a000-000000000008', 'C03', 'Tacos Mixte',          1, 850,  '[]'::jsonb, 850),
  ('aaaaaaaa-0008-4000-a000-000000000008', 'S01', 'Frites',              1, 300,  '[]'::jsonb, 300),
  ('aaaaaaaa-0008-4000-a000-000000000008', 'D01', 'Coca-Cola 33cl',       3, 150,  '[]'::jsonb, 450),

  -- Order #9 (1900 DZD — Instagram)
  ('aaaaaaaa-0009-4000-a000-000000000009', 'B03', 'Chicken Crispy Burger',1, 950,  '[{"code":"X07","label":"Sauce algéroise","delta":0}]'::jsonb, 950),
  ('aaaaaaaa-0009-4000-a000-000000000009', 'S01', 'Frites',              1, 300,  '[]'::jsonb, 300),
  ('aaaaaaaa-0009-4000-a000-000000000009', 'X01D','Tiramisu',             1, 400,  '[]'::jsonb, 400),
  ('aaaaaaaa-0009-4000-a000-000000000009', 'D01', 'Coca-Cola 33cl',       1, 150,  '[]'::jsonb, 150),

  -- Order #10 (4500 DZD — Messenger + deposit)
  ('aaaaaaaa-0010-4000-a000-000000000010', 'P03', 'Pizza 4 Fromages',     2, 1200, '[]'::jsonb, 2400),
  ('aaaaaaaa-0010-4000-a000-000000000010', 'B02', 'Double Smash Burger',  1, 1100, '[{"code":"X04","label":"Bacon croustillant","delta":200}]'::jsonb, 1300),
  ('aaaaaaaa-0010-4000-a000-000000000010', 'S01', 'Frites',              2, 300,  '[]'::jsonb, 600),
  ('aaaaaaaa-0010-4000-a000-000000000010', 'D01', 'Coca-Cola 33cl',       1, 150,  '[]'::jsonb, 150)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 13. ORDER STATUS HISTORY (full timelines)
-- ============================================================================

INSERT INTO order_status_history(order_id, internal_status, customer_status, note, created_at) VALUES
  -- Order #1 full lifecycle
  ('aaaaaaaa-0001-4000-a000-000000000001', 'NEW',             'CONFIRMED',        NULL,                now() - interval '26 hours'),
  ('aaaaaaaa-0001-4000-a000-000000000001', 'ACCEPTED',        'CONFIRMED',        'Acceptée par cuisine', now() - interval '25 hours 55 min'),
  ('aaaaaaaa-0001-4000-a000-000000000001', 'IN_PROGRESS',     'PREPARING',        NULL,                now() - interval '25 hours 40 min'),
  ('aaaaaaaa-0001-4000-a000-000000000001', 'READY',           'READY',            NULL,                now() - interval '25 hours 20 min'),
  ('aaaaaaaa-0001-4000-a000-000000000001', 'OUT_FOR_DELIVERY','OUT_FOR_DELIVERY', 'Livreur: Yacine',   now() - interval '25 hours 15 min'),
  ('aaaaaaaa-0001-4000-a000-000000000001', 'DONE',            'DELIVERED',        'Livré avec succès', now() - interval '25 hours'),

  -- Order #2 (sur_place)
  ('aaaaaaaa-0002-4000-a000-000000000002', 'NEW',             'CONFIRMED',        NULL,                now() - interval '3 hours'),
  ('aaaaaaaa-0002-4000-a000-000000000002', 'ACCEPTED',        'CONFIRMED',        NULL,                now() - interval '2 hours 55 min'),
  ('aaaaaaaa-0002-4000-a000-000000000002', 'IN_PROGRESS',     'PREPARING',        NULL,                now() - interval '2 hours 40 min'),
  ('aaaaaaaa-0002-4000-a000-000000000002', 'READY',           'READY',            NULL,                now() - interval '2 hours 20 min'),
  ('aaaaaaaa-0002-4000-a000-000000000002', 'DONE',            'DELIVERED',        'Servi sur place',   now() - interval '2 hours'),

  -- Order #3 (en cours)
  ('aaaaaaaa-0003-4000-a000-000000000003', 'NEW',             'CONFIRMED',        NULL,                now() - interval '35 minutes'),
  ('aaaaaaaa-0003-4000-a000-000000000003', 'ACCEPTED',        'CONFIRMED',        NULL,                now() - interval '30 minutes'),
  ('aaaaaaaa-0003-4000-a000-000000000003', 'IN_PROGRESS',     'PREPARING',        NULL,                now() - interval '15 minutes'),

  -- Order #4
  ('aaaaaaaa-0004-4000-a000-000000000004', 'NEW',             'CONFIRMED',        NULL,                now() - interval '45 minutes'),
  ('aaaaaaaa-0004-4000-a000-000000000004', 'ACCEPTED',        'CONFIRMED',        NULL,                now() - interval '40 minutes'),
  ('aaaaaaaa-0004-4000-a000-000000000004', 'IN_PROGRESS',     'PREPARING',        NULL,                now() - interval '25 minutes'),
  ('aaaaaaaa-0004-4000-a000-000000000004', 'READY',           'READY',            'Prêt au comptoir',  now() - interval '10 minutes'),

  -- Order #5
  ('aaaaaaaa-0005-4000-a000-000000000005', 'NEW',             'CONFIRMED',        NULL,                now() - interval '20 minutes'),
  ('aaaaaaaa-0005-4000-a000-000000000005', 'ACCEPTED',        'CONFIRMED',        NULL,                now() - interval '18 minutes'),

  -- Order #7 (cancelled)
  ('aaaaaaaa-0007-4000-a000-000000000007', 'NEW',             'CONFIRMED',        NULL,                now() - interval '2 days'),
  ('aaaaaaaa-0007-4000-a000-000000000007', 'CANCELLED',       'CANCELLED',        'Annulé par le client', now() - interval '2 days' + interval '5 min'),

  -- Order #8 (out for delivery)
  ('aaaaaaaa-0008-4000-a000-000000000008', 'NEW',             'CONFIRMED',        NULL,                now() - interval '50 minutes'),
  ('aaaaaaaa-0008-4000-a000-000000000008', 'ACCEPTED',        'CONFIRMED',        NULL,                now() - interval '45 minutes'),
  ('aaaaaaaa-0008-4000-a000-000000000008', 'IN_PROGRESS',     'PREPARING',        NULL,                now() - interval '30 minutes'),
  ('aaaaaaaa-0008-4000-a000-000000000008', 'READY',           'READY',            NULL,                now() - interval '15 minutes'),
  ('aaaaaaaa-0008-4000-a000-000000000008', 'OUT_FOR_DELIVERY','OUT_FOR_DELIVERY', 'Livreur: Yacine',   now() - interval '8 minutes'),

  -- Order #9 (Instagram)
  ('aaaaaaaa-0009-4000-a000-000000000009', 'NEW',             'CONFIRMED',        NULL,                now() - interval '5 hours'),
  ('aaaaaaaa-0009-4000-a000-000000000009', 'ACCEPTED',        'CONFIRMED',        NULL,                now() - interval '4 hours 55 min'),
  ('aaaaaaaa-0009-4000-a000-000000000009', 'READY',           'READY',            NULL,                now() - interval '4 hours 30 min'),
  ('aaaaaaaa-0009-4000-a000-000000000009', 'DONE',            'DELIVERED',        'Récupéré sur place',now() - interval '4 hours'),

  -- Order #10 (Messenger + deposit)
  ('aaaaaaaa-0010-4000-a000-000000000010', 'NEW',             'CONFIRMED',        NULL,                now() - interval '1 day'),
  ('aaaaaaaa-0010-4000-a000-000000000010', 'ACCEPTED',        'CONFIRMED',        'Acompte reçu',     now() - interval '23 hours 50 min'),
  ('aaaaaaaa-0010-4000-a000-000000000010', 'IN_PROGRESS',     'PREPARING',        NULL,                now() - interval '23 hours 30 min'),
  ('aaaaaaaa-0010-4000-a000-000000000010', 'READY',           'READY',            NULL,                now() - interval '23 hours 10 min'),
  ('aaaaaaaa-0010-4000-a000-000000000010', 'DONE',            'DELIVERED',        'Livré + solde COD', now() - interval '23 hours')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 14. PAYMENT INTENTS
-- ============================================================================

INSERT INTO payment_intents(intent_id, tenant_id, restaurant_id, order_id, conversation_key, user_id,
  method, status, total_amount, deposit_amount, deposit_paid, cod_amount, cod_collected, created_at, confirmed_at, completed_at) VALUES
  -- Order #1: COD completed
  (gen_random_uuid(),
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'aaaaaaaa-0001-4000-a000-000000000001', 'wa:213555100001:00000000-0000-0000-0000-000000000000', '213555100001',
   'COD', 'CAPTURED', 2850, 0, 0, 2850, 2850,
   now() - interval '26 hours', now() - interval '26 hours', now() - interval '25 hours'),
  -- Order #5: COD pending
  (gen_random_uuid(),
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'aaaaaaaa-0005-4000-a000-000000000005', 'wa:213555100003:00000000-0000-0000-0000-000000000000', '213555100003',
   'COD', 'PENDING', 2100, 0, 0, 2100, 0,
   now() - interval '20 minutes', NULL, NULL),
  -- Order #10: Deposit + COD
  (gen_random_uuid(),
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'aaaaaaaa-0010-4000-a000-000000000010', 'msg:fb_gourmet42:00000000-0000-0000-0000-000000000000', 'fb_gourmet42',
   'DEPOSIT', 'CAPTURED', 4500, 1350, 1350, 3150, 3150,
   now() - interval '1 day', now() - interval '23 hours 50 min', now() - interval '23 hours'),
  -- Order #7: Expired (cancelled)
  (gen_random_uuid(),
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'aaaaaaaa-0007-4000-a000-000000000007', 'wa:213555100002:00000000-0000-0000-0000-000000000000', '213555100002',
   'COD', 'EXPIRED', 950, 0, 0, 950, 0,
   now() - interval '2 days', NULL, NULL)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 15. CUSTOMER PAYMENT PROFILES (5 profiles)
-- ============================================================================

INSERT INTO customer_payment_profiles(user_id, tenant_id, total_orders, completed_orders, cancelled_orders,
  no_show_count, trust_score, requires_deposit, soft_blacklisted, last_order_at) VALUES
  ('213555100001', '00000000-0000-0000-0000-000000000001', 12, 10, 1, 0, 85, false, false, now() - interval '50 minutes'),
  ('213555100002', '00000000-0000-0000-0000-000000000001',  2,  1, 1, 0, 50, true,  false, now() - interval '3 hours'),
  ('213555100003', '00000000-0000-0000-0000-000000000001',  8,  4, 2, 3, 25, true,  true,  now() - interval '2 minutes'),
  ('ig_foodie_dz', '00000000-0000-0000-0000-000000000001',  5,  5, 0, 0, 70, false, false, now() - interval '5 hours'),
  ('fb_gourmet42', '00000000-0000-0000-0000-000000000001', 22, 20, 1, 0, 95, false, false, now() - interval '1 day')
ON CONFLICT (user_id) DO UPDATE SET
  total_orders = EXCLUDED.total_orders, trust_score = EXCLUDED.trust_score,
  soft_blacklisted = EXCLUDED.soft_blacklisted, no_show_count = EXCLUDED.no_show_count;

-- ============================================================================
-- 16. CUSTOMER PREFERENCES (L10N)
-- ============================================================================

INSERT INTO customer_preferences(tenant_id, phone, locale) VALUES
  ('00000000-0000-0000-0000-000000000001', '213555100001', 'fr'),
  ('00000000-0000-0000-0000-000000000001', '213555100002', 'fr'),
  ('00000000-0000-0000-0000-000000000001', '213555100003', 'ar'),
  ('00000000-0000-0000-0000-000000000001', 'ig_foodie_dz', 'fr'),
  ('00000000-0000-0000-0000-000000000001', 'fb_gourmet42', 'fr')
ON CONFLICT (tenant_id, phone) DO UPDATE SET locale = EXCLUDED.locale;

-- ============================================================================
-- 17. OUTBOUND MESSAGES (15 messages — tracking, FAQ, support, DLQ)
-- ============================================================================

INSERT INTO outbound_messages(outbound_id, dedupe_key, tenant_id, restaurant_id, channel, user_id,
  order_id, template, payload_json, status, correlation_id, created_at) VALUES
  -- Order confirmations
  (gen_random_uuid(), 'poc:out:confirm:001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100001', 'aaaaaaaa-0001-4000-a000-000000000001',
   'WA_ORDER_STATUS_CONFIRMED', '{"text":"Commande confirmée (#0001). Livraison estimée: 25-40 min."}'::jsonb,
   'SENT', 'corr-order-001', now() - interval '26 hours'),
  -- Tracking: preparing
  (gen_random_uuid(), 'poc:out:prep:001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100001', 'aaaaaaaa-0001-4000-a000-000000000001',
   'WA_ORDER_STATUS_PREPARING', '{"text":"Votre commande est en préparation."}'::jsonb,
   'SENT', 'corr-order-001', now() - interval '25 hours 40 min'),
  -- Tracking: ready
  (gen_random_uuid(), 'poc:out:ready:001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100001', 'aaaaaaaa-0001-4000-a000-000000000001',
   'WA_ORDER_STATUS_READY', '{"text":"Votre commande est prête!"}'::jsonb,
   'SENT', 'corr-order-001', now() - interval '25 hours 20 min'),
  -- Tracking: out for delivery
  (gen_random_uuid(), 'poc:out:ofd:001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100001', 'aaaaaaaa-0001-4000-a000-000000000001',
   'WA_ORDER_STATUS_OUT_FOR_DELIVERY', '{"text":"Votre commande est en route! Livreur: Yacine."}'::jsonb,
   'SENT', 'corr-order-001', now() - interval '25 hours 15 min'),
  -- Tracking: delivered
  (gen_random_uuid(), 'poc:out:done:001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100001', 'aaaaaaaa-0001-4000-a000-000000000001',
   'WA_ORDER_STATUS_DELIVERED', '{"text":"Commande livrée! Bon appétit! 🍕"}'::jsonb,
   'SENT', 'corr-order-001', now() - interval '25 hours'),
  -- Order #3 tracking (in progress)
  (gen_random_uuid(), 'poc:out:confirm:003', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100001', 'aaaaaaaa-0003-4000-a000-000000000003',
   'WA_ORDER_STATUS_CONFIRMED', '{"text":"Commande confirmée (#0003). Livraison: 30-50 min."}'::jsonb,
   'SENT', 'corr-order-003', now() - interval '35 minutes'),
  (gen_random_uuid(), 'poc:out:prep:003', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100001', 'aaaaaaaa-0003-4000-a000-000000000003',
   'WA_ORDER_STATUS_PREPARING', '{"text":"Votre commande est en préparation."}'::jsonb,
   'SENT', 'corr-order-003', now() - interval '15 minutes'),
  -- Instagram order confirmation
  (gen_random_uuid(), 'poc:out:confirm:009', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'instagram', 'ig_foodie_dz', 'aaaaaaaa-0009-4000-a000-000000000009',
   'WA_ORDER_STATUS_CONFIRMED', '{"text":"Commande confirmée! À récupérer sur place."}'::jsonb,
   'SENT', 'corr-order-009', now() - interval '5 hours'),
  -- FAQ reply
  (gen_random_uuid(), 'poc:out:faq:001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100003', NULL,
   'reply', '{"text":"🕒 نفتح يومياً من 11:00 إلى 23:00.","meta":{"intent":"FAQ_ANSWER"}}'::jsonb,
   'SENT', 'corr-faq-001', now() - interval '4 hours'),
  -- Support handoff ack
  (gen_random_uuid(), 'poc:out:support:ack', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100002', NULL,
   'reply', '{"text":"Un agent va vous répondre rapidement. Merci de patienter.","meta":{"intent":"HANDOFF_SUPPORT"}}'::jsonb,
   'SENT', 'corr-support-001', now() - interval '1 hour'),
  -- Deposit request (order #10)
  (gen_random_uuid(), 'poc:out:deposit:010', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'messenger', 'fb_gourmet42', 'aaaaaaaa-0010-4000-a000-000000000010',
   'PAYMENT_DEPOSIT_REQUIRED', '{"text":"Un acompte de 1350 DZD est requis. Envoyez le paiement pour confirmer."}'::jsonb,
   'SENT', 'corr-order-010', now() - interval '1 day'),
  -- DLQ message (failed)
  (gen_random_uuid(), 'poc:out:dlq:001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100002', NULL,
   'reply', '{"text":"Votre feedback compte!"}'::jsonb,
   'DLQ', 'corr-dlq-001', now() - interval '6 hours'),
  -- Fraud confirmation code
  (gen_random_uuid(), 'poc:out:fraud:confirm', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555100003', NULL,
   'FRAUD_CONFIRM_REQUIRED', '{"text":"Commande de valeur élevée. Tapez le code 4821 pour confirmer."}'::jsonb,
   'SENT', 'corr-fraud-001', now() - interval '30 minutes'),
  -- Admin console reply
  (gen_random_uuid(), 'poc:out:admin:console', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', '213555900001', NULL,
   'WA_ADMIN_CONSOLE', '{"text":"📋 Tickets ouverts: 1\n#1 - 213555100002 (OPEN) - Problème livraison"}'::jsonb,
   'SENT', 'corr-admin-001', now() - interval '30 minutes')
ON CONFLICT (dedupe_key) DO NOTHING;

-- ============================================================================
-- 18. INBOUND MESSAGES (10 messages across channels)
-- ============================================================================

INSERT INTO inbound_messages(conversation_key, msg_id, channel, message_type, meta_json, correlation_id, received_at) VALUES
  ('wa:213555100001:00000000-0000-0000-0000-000000000000', 'wamid.poc001', 'whatsapp', 'text',
   '{"text":"Salam! Je veux commander","from":"213555100001"}'::jsonb, 'corr-conv-001', now() - interval '30 hours'),
  ('wa:213555100001:00000000-0000-0000-0000-000000000000', 'wamid.poc002', 'whatsapp', 'text',
   '{"text":"P03 x1 extra fromage + 2 coca","from":"213555100001"}'::jsonb, 'corr-conv-001', now() - interval '29 hours'),
  ('wa:213555100002:00000000-0000-0000-0000-000000000000', 'wamid.poc003', 'whatsapp', 'text',
   '{"text":"menu","from":"213555100002"}'::jsonb, 'corr-conv-002', now() - interval '4 hours'),
  ('wa:213555100003:00000000-0000-0000-0000-000000000000', 'wamid.poc004', 'whatsapp', 'text',
   '{"text":"ما هي أوقات العمل؟","from":"213555100003"}'::jsonb, 'corr-faq-001', now() - interval '4 hours'),
  ('wa:213555100002:00000000-0000-0000-0000-000000000000', 'wamid.poc005', 'whatsapp', 'text',
   '{"text":"help","from":"213555100002"}'::jsonb, 'corr-support-001', now() - interval '1 hour'),
  ('ig:ig_foodie_dz:00000000-0000-0000-0000-000000000000', 'igmid.poc001', 'instagram', 'text',
   '{"text":"Bonjour! C quoi votre menu?","from":"ig_foodie_dz"}'::jsonb, 'corr-conv-004', now() - interval '6 hours'),
  ('msg:fb_gourmet42:00000000-0000-0000-0000-000000000000', 'fbmid.poc001', 'messenger', 'text',
   '{"text":"Je voudrais commander pour livraison à Hydra","from":"fb_gourmet42"}'::jsonb, 'corr-conv-005', now() - interval '1 day'),
  ('wa:213555100003:00000000-0000-0000-0000-000000000000', 'wamid.poc006', 'whatsapp', 'text',
   '{"text":"chno kayn","from":"213555100003"}'::jsonb, 'corr-conv-003', now() - interval '10 minutes'),
  ('wa:213555100001:00000000-0000-0000-0000-000000000000', 'wamid.poc007', 'whatsapp', 'audio',
   '{"audio":{"id":"audio_123","mime_type":"audio/ogg"},"from":"213555100001"}'::jsonb, 'corr-voice-001', now() - interval '2 hours'),
  ('wa:213555900001:00000000-0000-0000-0000-000000000000', 'wamid.poc008', 'whatsapp', 'text',
   '{"text":"!tickets open","from":"213555900001"}'::jsonb, 'corr-admin-001', now() - interval '30 minutes')
ON CONFLICT (conversation_key, msg_id, channel) DO NOTHING;

-- ============================================================================
-- 19. SUPPORT TICKETS (3 tickets)
-- ============================================================================

INSERT INTO support_tickets(tenant_id, restaurant_id, channel, conversation_key, customer_user_id,
  status, priority, reason_code, subject, context_json, created_at, updated_at, closed_at) VALUES
  -- OPEN: delivery issue
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', 'wa:213555100002:00000000-0000-0000-0000-000000000000', '213555100002',
   'OPEN', 'HIGH', 'DELIVERY_AMBIGUOUS', 'Problème adresse livraison',
   '{"order_id":"aaaaaaaa-0003-4000-a000-000000000003","last_message":"Mon adresse est incorrecte"}'::jsonb,
   now() - interval '1 hour', now() - interval '1 hour', NULL),
  -- ASSIGNED: payment question
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'whatsapp', 'wa:213555100003:00000000-0000-0000-0000-000000000000', '213555100003',
   'ASSIGNED', 'NORMAL', 'PAYMENT_ISSUE', 'Question sur l''acompte',
   '{"last_message":"كيفاش نخلص الأكومبت؟"}'::jsonb,
   now() - interval '3 hours', now() - interval '2 hours', NULL),
  -- CLOSED: resolved FAQ fallback
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'messenger', 'msg:fb_gourmet42:00000000-0000-0000-0000-000000000000', 'fb_gourmet42',
   'CLOSED', 'LOW', 'FAQ_FALLBACK', 'Question allergènes',
   '{"last_message":"Avez-vous des options sans gluten?"}'::jsonb,
   now() - interval '2 days', now() - interval '2 days', now() - interval '2 days')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 20. SUPPORT TICKET MESSAGES
-- ============================================================================

-- Get ticket IDs dynamically
DO $$
DECLARE
  tid1 bigint; tid2 bigint; tid3 bigint;
BEGIN
  SELECT ticket_id INTO tid1 FROM support_tickets WHERE customer_user_id = '213555100002' AND status = 'OPEN' LIMIT 1;
  SELECT ticket_id INTO tid2 FROM support_tickets WHERE customer_user_id = '213555100003' AND status = 'ASSIGNED' LIMIT 1;
  SELECT ticket_id INTO tid3 FROM support_tickets WHERE customer_user_id = 'fb_gourmet42' AND status = 'CLOSED' LIMIT 1;

  IF tid1 IS NOT NULL THEN
    INSERT INTO support_ticket_messages(ticket_id, direction, from_user_id, body_text, created_at) VALUES
      (tid1, 'INBOUND', '213555100002', 'Mon adresse de livraison est incorrecte, je suis au 45 Cité des 500 logements', now() - interval '1 hour'),
      (tid1, 'INTERNAL', '213555900001', 'Client régulier, adresse mise à jour dans la commande #0003', now() - interval '55 minutes')
    ON CONFLICT DO NOTHING;
  END IF;

  IF tid2 IS NOT NULL THEN
    INSERT INTO support_ticket_messages(ticket_id, direction, from_user_id, to_user_id, body_text, created_at) VALUES
      (tid2, 'INBOUND', '213555100003', NULL, 'كيفاش نخلص الأكومبت؟', now() - interval '3 hours'),
      (tid2, 'OUTBOUND', '213555900001', '213555100003', 'يمكنك دفع الأكومبت عبر CCP أو BaridiMob', now() - interval '2 hours 30 min'),
      (tid2, 'INBOUND', '213555100003', NULL, 'شكراً، فهمت', now() - interval '2 hours')
    ON CONFLICT DO NOTHING;
  END IF;

  IF tid3 IS NOT NULL THEN
    INSERT INTO support_ticket_messages(ticket_id, direction, from_user_id, to_user_id, body_text, created_at) VALUES
      (tid3, 'INBOUND', 'fb_gourmet42', NULL, 'Avez-vous des options sans gluten?', now() - interval '2 days'),
      (tid3, 'OUTBOUND', '213555900001', 'fb_gourmet42', 'Oui! Nos salades et chawarmas sont sans gluten. Les pizzas contiennent du gluten.', now() - interval '2 days' + interval '15 min'),
      (tid3, 'INBOUND', 'fb_gourmet42', NULL, 'Parfait merci!', now() - interval '2 days' + interval '20 min')
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- ============================================================================
-- 21. SUPPORT ASSIGNMENTS
-- ============================================================================

DO $$
DECLARE tid2 bigint;
BEGIN
  SELECT ticket_id INTO tid2 FROM support_tickets WHERE customer_user_id = '213555100003' AND status = 'ASSIGNED' LIMIT 1;
  IF tid2 IS NOT NULL THEN
    INSERT INTO support_assignments(ticket_id, admin_user_id, assigned_at) VALUES
      (tid2, '213555900001', now() - interval '2 hours 30 min')
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- ============================================================================
-- 22. FAQ ENTRIES (8 entries, FR + AR)
-- ============================================================================

INSERT INTO faq_entries(tenant_id, restaurant_id, locale, question, answer, tags, is_active) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'fr',
   'Quels sont vos horaires ?', 'Nous sommes ouverts du lundi au jeudi de 11h à 23h, vendredi-samedi de 11h à minuit, dimanche de 12h à 22h.',
   ARRAY['horaires','ouverture','fermeture','heures'], true),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'ar',
   'ما هي أوقات العمل؟', 'نفتح من الإثنين إلى الخميس من 11:00 إلى 23:00، الجمعة والسبت حتى منتصف الليل، الأحد من 12:00 إلى 22:00.',
   ARRAY['اوقات','ساعات','عمل'], true),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'fr',
   'Quels moyens de paiement acceptez-vous ?', 'Paiement à la livraison (espèces). Acompte via CCP/BaridiMob pour les grosses commandes.',
   ARRAY['paiement','carte','cash','especes','baridimob'], true),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'fr',
   'Livrez-vous dans ma zone ?', 'Nous livrons dans tout Alger-Centre: Hydra, Kouba, El Biar, Bab Ezzouar, Birkhadem, Chéraga, Ain Naadja. Tapez votre adresse pour un devis!',
   ARRAY['livraison','zone','adresse','commune'], true),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'fr',
   'Avez-vous des options sans gluten ?', 'Nos salades, chawarmas et tacos sont sans gluten. Les pizzas et burgers contiennent du gluten.',
   ARRAY['allergens','gluten','regime','sans'], true),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'fr',
   'Est-ce que tout est halal ?', 'Oui, 100% de nos viandes sont certifiées halal.',
   ARRAY['halal','viande','certifie'], true),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'fr',
   'Y a-t-il un parking ?', 'Oui, parking gratuit disponible devant le restaurant (10 places). Parking souterrain à 50m.',
   ARRAY['parking','voiture','stationnement'], true),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'ar',
   'هل يوجد واي فاي؟', 'نعم، واي فاي مجاني متاح للزبائن. اسأل الخادم عن كلمة المرور.',
   ARRAY['واي فاي','wifi','انترنت'], true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 23. SECURITY EVENTS
-- ============================================================================

INSERT INTO security_events(tenant_id, restaurant_id, conversation_key, channel, user_id,
  event_type, severity, payload_json, correlation_id, created_at) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'wa:spam_user:00000000-0000-0000-0000-000000000000', 'whatsapp', 'spam_user',
   'SPAM_DETECTED', 'HIGH', '{"messages_30s":8,"limit":6}'::jsonb, 'corr-sec-001', now() - interval '12 hours'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'wa:spam_user:00000000-0000-0000-0000-000000000000', 'whatsapp', 'spam_user',
   'QUARANTINE_APPLIED', 'HIGH', '{"reason":"FLOOD_DETECTED","expires_minutes":10}'::jsonb, 'corr-sec-001', now() - interval '12 hours'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   NULL, NULL, NULL,
   'SCOPE_DENY', 'MEDIUM', '{"token":"...e2","endpoint":"/v1/admin/ping","required_scope":"admin:read"}'::jsonb, 'corr-sec-002', now() - interval '6 hours'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'wa:213555100003:00000000-0000-0000-0000-000000000000', 'whatsapp', '213555100003',
   'FRAUD_CONFIRMATION_REQUIRED', 'MEDIUM', '{"order_total":35000,"threshold":30000,"code":"4821"}'::jsonb, 'corr-fraud-001', now() - interval '30 minutes'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   NULL, 'whatsapp', '213555100001',
   'DELIVERY_ZONE_NOT_FOUND', 'LOW', '{"wilaya":"Oran","commune":"Centre"}'::jsonb, 'corr-sec-003', now() - interval '2 days'),
  (NULL, NULL, NULL, NULL, NULL,
   'TOKEN_ROTATED', 'LOW', '{"client_name":"prod_inbound","rotated_by":"admin"}'::jsonb, 'corr-sec-004', now() - interval '7 days'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   NULL, NULL, NULL,
   'SLO_BREACH', 'HIGH', '{"metric":"p95_latency_ms","value":1200,"threshold":500,"workflow":"W1_INBOUND"}'::jsonb, 'corr-sec-005', now() - interval '3 days'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'wa:213555100003:00000000-0000-0000-0000-000000000000', 'whatsapp', '213555100003',
   'QUARANTINE_RELEASED', 'LOW', '{"quarantine_id":1,"reason":"AUTO_EXPIRE"}'::jsonb, 'corr-sec-006', now() - interval '11 hours 50 min')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 24. CONVERSATION QUARANTINE
-- ============================================================================

INSERT INTO conversation_quarantine(conversation_key, reason, active, expires_at, release_policy, created_at) VALUES
  ('wa:spam_user:00000000-0000-0000-0000-000000000000', 'FLOOD_DETECTED: 8 messages in 30s', true,
   now() + interval '5 minutes', 'AUTO_RELEASE', now() - interval '5 minutes'),
  ('wa:bot_user:00000000-0000-0000-0000-000000000000', 'BOT_SUSPECTED: suspicious payload', false,
   now() - interval '1 hour', 'AUTO_RELEASE', now() - interval '2 hours')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 25. DRIVERS (2 drivers)
-- ============================================================================

INSERT INTO drivers(driver_id, tenant_id, restaurant_id, user_id, name, status,
  current_lat, current_lng, last_location_update, is_active) VALUES
  ('dddddddd-0001-4000-d000-000000000001',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555800001', 'Yacine Boudiaf', 'BUSY',
   36.7450, 2.9600, now() - interval '3 minutes', true),
  ('dddddddd-0002-4000-d000-000000000002',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555800002', 'Mehdi Amrani', 'ONLINE',
   36.7538, 3.0588, now() - interval '10 minutes', true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 26. DELIVERY ASSIGNMENTS
-- ============================================================================

INSERT INTO delivery_assignments(assignment_id, order_id, driver_id, status,
  offered_at, accepted_at, picked_up_at, delivered_at) VALUES
  -- Order #1: delivered
  ('eeeeeeee-0001-4000-e000-000000000001',
   'aaaaaaaa-0001-4000-a000-000000000001', 'dddddddd-0001-4000-d000-000000000001',
   'DELIVERED', now() - interval '25 hours 15 min', now() - interval '25 hours 14 min',
   now() - interval '25 hours 10 min', now() - interval '25 hours'),
  -- Order #8: picked up, in transit
  ('eeeeeeee-0002-4000-e000-000000000002',
   'aaaaaaaa-0008-4000-a000-000000000008', 'dddddddd-0001-4000-d000-000000000001',
   'PICKED_UP', now() - interval '10 minutes', now() - interval '9 minutes',
   now() - interval '8 minutes', NULL),
  -- Order #7: rejected (cancelled order)
  ('eeeeeeee-0003-4000-e000-000000000003',
   'aaaaaaaa-0007-4000-a000-000000000007', 'dddddddd-0002-4000-d000-000000000002',
   'REJECTED', now() - interval '2 days', NULL, NULL, NULL)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 27. KITCHEN STATIONS
-- ============================================================================

INSERT INTO kitchen_stations(station_id, tenant_id, restaurant_id, name, capabilities, printer_ip, is_active) VALUES
  ('ffffffff-0001-4000-f000-000000000001',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'Grill', ARRAY['burger','chawarma','viande'], '192.168.1.101', true),
  ('ffffffff-0002-4000-f000-000000000002',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'Four à Pizza', ARRAY['pizza','calzone'], '192.168.1.102', true),
  ('ffffffff-0003-4000-f000-000000000003',
   '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'Station Froide', ARRAY['salade','dessert','boisson'], NULL, true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 28. DAILY METRICS (7 days)
-- ============================================================================

INSERT INTO daily_metrics(metric_date, metric_key, metric_value, channel) VALUES
  (CURRENT_DATE - 6, 'orders_created',    8,  'whatsapp'),
  (CURRENT_DATE - 6, 'orders_created',    2,  'instagram'),
  (CURRENT_DATE - 6, 'orders_completed',  7,  'whatsapp'),
  (CURRENT_DATE - 6, 'messages_sent',     32, 'whatsapp'),
  (CURRENT_DATE - 6, 'messages_received', 45, 'whatsapp'),
  (CURRENT_DATE - 5, 'orders_created',    12, 'whatsapp'),
  (CURRENT_DATE - 5, 'orders_created',    3,  'instagram'),
  (CURRENT_DATE - 5, 'orders_created',    2,  'messenger'),
  (CURRENT_DATE - 5, 'orders_completed',  11, 'whatsapp'),
  (CURRENT_DATE - 5, 'messages_sent',     48, 'whatsapp'),
  (CURRENT_DATE - 5, 'messages_received', 62, 'whatsapp'),
  (CURRENT_DATE - 4, 'orders_created',    15, 'whatsapp'),
  (CURRENT_DATE - 4, 'orders_created',    4,  'instagram'),
  (CURRENT_DATE - 4, 'orders_completed',  14, 'whatsapp'),
  (CURRENT_DATE - 4, 'messages_sent',     55, 'whatsapp'),
  (CURRENT_DATE - 3, 'orders_created',    10, 'whatsapp'),
  (CURRENT_DATE - 3, 'orders_completed',  9,  'whatsapp'),
  (CURRENT_DATE - 3, 'messages_sent',     40, 'whatsapp'),
  (CURRENT_DATE - 2, 'orders_created',    18, 'whatsapp'),
  (CURRENT_DATE - 2, 'orders_created',    5,  'instagram'),
  (CURRENT_DATE - 2, 'orders_created',    3,  'messenger'),
  (CURRENT_DATE - 2, 'orders_completed',  16, 'whatsapp'),
  (CURRENT_DATE - 2, 'messages_sent',     65, 'whatsapp'),
  (CURRENT_DATE - 1, 'orders_created',    14, 'whatsapp'),
  (CURRENT_DATE - 1, 'orders_created',    6,  'instagram'),
  (CURRENT_DATE - 1, 'orders_completed',  12, 'whatsapp'),
  (CURRENT_DATE - 1, 'messages_sent',     52, 'whatsapp'),
  (CURRENT_DATE,     'orders_created',    7,  'whatsapp'),
  (CURRENT_DATE,     'orders_created',    2,  'instagram'),
  (CURRENT_DATE,     'orders_created',    1,  'messenger'),
  (CURRENT_DATE,     'orders_completed',  3,  'whatsapp'),
  (CURRENT_DATE,     'messages_sent',     28, 'whatsapp')
ON CONFLICT (metric_date, metric_key, channel) DO UPDATE SET metric_value = EXCLUDED.metric_value;

-- ============================================================================
-- 29. LATENCY SAMPLES
-- ============================================================================

INSERT INTO latency_samples(sample_date, workflow, channel, latency_ms) VALUES
  (CURRENT_DATE, 'W1_INBOUND',  'whatsapp', 120),
  (CURRENT_DATE, 'W1_INBOUND',  'whatsapp', 95),
  (CURRENT_DATE, 'W1_INBOUND',  'whatsapp', 145),
  (CURRENT_DATE, 'W1_INBOUND',  'instagram', 180),
  (CURRENT_DATE, 'W1_INBOUND',  'messenger', 110),
  (CURRENT_DATE, 'W4_CORE',     'whatsapp', 250),
  (CURRENT_DATE, 'W4_CORE',     'whatsapp', 310),
  (CURRENT_DATE, 'W4_CORE',     'whatsapp', 280),
  (CURRENT_DATE, 'W4_CORE',     'instagram', 340),
  (CURRENT_DATE, 'W5_OUT_WA',   'whatsapp', 200),
  (CURRENT_DATE, 'W5_OUT_WA',   'whatsapp', 180),
  (CURRENT_DATE, 'W5_OUT_WA',   'whatsapp', 220),
  (CURRENT_DATE - 1, 'W1_INBOUND',  'whatsapp', 130),
  (CURRENT_DATE - 1, 'W1_INBOUND',  'whatsapp', 105),
  (CURRENT_DATE - 1, 'W4_CORE',     'whatsapp', 270),
  (CURRENT_DATE - 1, 'W4_CORE',     'whatsapp', 295),
  (CURRENT_DATE - 1, 'W5_OUT_WA',   'whatsapp', 190),
  (CURRENT_DATE - 2, 'W1_INBOUND',  'whatsapp', 1200),
  (CURRENT_DATE - 2, 'W4_CORE',     'whatsapp', 890),
  (CURRENT_DATE - 2, 'W5_OUT_WA',   'whatsapp', 450)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 30. MARKETING TRIGGER LOG
-- ============================================================================

INSERT INTO marketing_trigger_log(trigger_id, tenant_id, restaurant_id, rule_name,
  executed_at, affected_users_count, campaign_id, metadata_json) VALUES
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'WIN_BACK_7D', now() - interval '3 days', 15, 'camp-winback-001',
   '{"message":"Vous nous manquez! -20% sur votre prochaine commande","channel":"whatsapp"}'::jsonb),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'WEATHER_SURGE', now() - interval '1 day', 42, 'camp-weather-001',
   '{"message":"Il pleut! Commandez depuis chez vous, livraison à -50%","trigger":"rain_detected"}'::jsonb)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 31. ADMIN WA AUDIT LOG (5 entries)
-- ============================================================================

INSERT INTO admin_wa_audit_log(tenant_id, restaurant_id, actor_phone, actor_role, action,
  target_type, target_id, command_raw, success, created_at) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555900001', 'owner', 'zone_create', 'delivery_zone', NULL,
   '!zone set Alger ; Ain Naadja ; 400 ; 1800 ; 35 ; 60 ; true', true, now() - interval '5 days'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555900001', 'owner', 'tickets', 'support_ticket', NULL,
   '!tickets open', true, now() - interval '30 minutes'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555900001', 'owner', 'take', 'support_ticket', '2',
   '!take 2', true, now() - interval '2 hours 30 min'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555900001', 'owner', 'status', NULL, NULL,
   '!status', true, now() - interval '1 hour'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555900001', 'owner', 'order_status', 'order', 'aaaaaaaa-0005-4000-a000-000000000005',
   '!order_status aaaaaaaa-0005 ACCEPTED', true, now() - interval '18 minutes')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 32. STRUCTURED LOGS (10 entries)
-- ============================================================================

INSERT INTO structured_logs(correlation_id, tenant_id, restaurant_id, user_id, conversation_key,
  channel, workflow_name, node_name, level, event_type, message, context_json) VALUES
  ('corr-order-001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555100001', 'wa:213555100001:00000000-0000-0000-0000-000000000000', 'whatsapp',
   'W1_INBOUND', 'Webhook Receive', 'INFO', 'INBOUND_RECEIVED', 'Message received from WhatsApp',
   '{"msg_id":"wamid.poc001","type":"text"}'::jsonb),
  ('corr-order-001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555100001', 'wa:213555100001:00000000-0000-0000-0000-000000000000', 'whatsapp',
   'W4_CORE', 'State Machine', 'INFO', 'STATE_TRANSITION', 'State: START → COLLECTING',
   '{"from_state":"START","to_state":"COLLECTING"}'::jsonb),
  ('corr-order-003', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555100001', NULL, 'whatsapp',
   'W4_CORE', 'Create Order', 'INFO', 'ORDER_CREATED', 'Order created: 3200 DZD',
   '{"order_id":"aaaaaaaa-0003-4000-a000-000000000003","total_cents":3200}'::jsonb),
  ('corr-sec-001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'spam_user', 'wa:spam_user:00000000-0000-0000-0000-000000000000', 'whatsapp',
   'W1_INBOUND', 'Fraud Check', 'WARN', 'FLOOD_DETECTED', 'Flood detected: 8 msgs in 30s (limit: 6)',
   '{"count":8,"window_s":30,"limit":6}'::jsonb),
  ('corr-fraud-001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555100003', 'wa:213555100003:00000000-0000-0000-0000-000000000000', 'whatsapp',
   'W4_CORE', 'Fraud Eval', 'WARN', 'FRAUD_CONFIRM_REQUIRED', 'High order total: 35000 DZD (threshold: 30000)',
   '{"total_cents":35000,"threshold":30000,"code":"4821"}'::jsonb),
  ('corr-dlq-001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555100002', NULL, 'whatsapp',
   'W5_OUT_WA', 'Send Message', 'ERROR', 'SEND_FAILED', 'WhatsApp API 500: internal server error after 3 retries',
   '{"attempts":3,"last_error":"500 Internal Server Error","moved_to":"DLQ"}'::jsonb),
  ('corr-voice-001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555100001', 'wa:213555100001:00000000-0000-0000-0000-000000000000', 'whatsapp',
   'W1_INBOUND', 'Voice STT', 'INFO', 'VOICE_TRANSCRIBED', 'Audio transcribed: "Je veux une pizza 4 fromages"',
   '{"confidence":0.92,"duration_ms":3200,"transcript":"Je veux une pizza 4 fromages"}'::jsonb),
  ('corr-conv-003', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   '213555100003', 'wa:213555100003:00000000-0000-0000-0000-000000000000', 'whatsapp',
   'W1_INBOUND', 'Darija Detect', 'INFO', 'DARIJA_DETECTED', 'Darija pattern matched: "chno kayn" → menu intent',
   '{"pattern":"chno kayn","category":"menu","locale_override":"ar"}'::jsonb),
  ('corr-sec-005', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   NULL, NULL, NULL,
   'W8_OPS', 'SLO Monitor', 'ERROR', 'SLO_BREACH', 'p95 latency 1200ms exceeds 500ms threshold',
   '{"metric":"p95_latency_ms","value":1200,"threshold":500}'::jsonb),
  ('corr-order-010', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'fb_gourmet42', 'msg:fb_gourmet42:00000000-0000-0000-0000-000000000000', 'messenger',
   'W3_INBOUND', 'Webhook Receive', 'INFO', 'INBOUND_RECEIVED', 'Message received from Messenger',
   '{"msg_id":"fbmid.poc001","type":"text"}'::jsonb)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 33. VOICE INTERACTIONS
-- ============================================================================

INSERT INTO voice_interactions(conversation_key, audio_url, transcript, confidence) VALUES
  ('wa:213555100001:00000000-0000-0000-0000-000000000000',
   'https://mmg.whatsapp.net/v/audio_123.ogg',
   'Je veux une pizza 4 fromages avec extra fromage',
   0.92)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 34. SYSTEM EVENT BUS
-- ============================================================================

INSERT INTO system_event_bus(event_type, payload, status, priority, created_at, processed_at) VALUES
  ('ORDER_CREATED', '{"order_id":"aaaaaaaa-0006-4000-a000-000000000006","channel":"whatsapp","total":1650}'::jsonb,
   'PROCESSED', 0, now() - interval '2 minutes', now() - interval '2 minutes'),
  ('WEATHER_ALERT', '{"city":"Algiers","condition":"rain","temp":12,"trigger":"delivery_surge"}'::jsonb,
   'PROCESSED', 5, now() - interval '1 day', now() - interval '1 day'),
  ('STOCK_LOW', '{"item_code":"P04","label":"Calzone Royale","remaining":2,"threshold":5}'::jsonb,
   'PENDING', 3, now() - interval '10 minutes', NULL)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- DONE
-- ============================================================================

COMMIT;

-- Quick verification
DO $$
DECLARE r record;
BEGIN
  RAISE NOTICE '=== POC SEED VERIFICATION ===';
  FOR r IN
    SELECT 'tenants' AS t, count(*) AS n FROM tenants
    UNION ALL SELECT 'restaurants', count(*) FROM restaurants
    UNION ALL SELECT 'menu_items', count(*) FROM menu_items
    UNION ALL SELECT 'menu_options', count(*) FROM menu_item_options
    UNION ALL SELECT 'delivery_zones', count(*) FROM delivery_zones
    UNION ALL SELECT 'orders', count(*) FROM orders
    UNION ALL SELECT 'order_items', count(*) FROM order_items
    UNION ALL SELECT 'order_history', count(*) FROM order_status_history
    UNION ALL SELECT 'outbound_msgs', count(*) FROM outbound_messages
    UNION ALL SELECT 'inbound_msgs', count(*) FROM inbound_messages
    UNION ALL SELECT 'support_tickets', count(*) FROM support_tickets
    UNION ALL SELECT 'faq_entries', count(*) FROM faq_entries
    UNION ALL SELECT 'security_events', count(*) FROM security_events
    UNION ALL SELECT 'drivers', count(*) FROM drivers
    UNION ALL SELECT 'daily_metrics', count(*) FROM daily_metrics
    UNION ALL SELECT 'payment_intents', count(*) FROM payment_intents
    UNION ALL SELECT 'conv_states', count(*) FROM conversation_state
    UNION ALL SELECT 'payment_profiles', count(*) FROM customer_payment_profiles
  LOOP
    RAISE NOTICE '  % : %', rpad(r.t, 18), r.n;
  END LOOP;
  RAISE NOTICE '=== SEED COMPLETE ===';
END $$;
