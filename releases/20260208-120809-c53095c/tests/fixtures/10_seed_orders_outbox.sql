-- Test fixtures: sample order + outbox message

INSERT INTO orders(order_id, tenant_id, restaurant_id, channel, user_id, service_mode, status, created_at)
VALUES (
  '11111111-1111-1111-1111-111111111111',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'whatsapp',
  'fixture-user',
  'a_emporter',
  'NEW',
  now()
)
ON CONFLICT (order_id) DO NOTHING;

INSERT INTO outbound_messages(
  outbound_id,
  dedupe_key,
  tenant_id,
  restaurant_id,
  channel,
  user_id,
  conversation_key,
  order_id,
  template,
  payload_json,
  status,
  next_retry_at
)
VALUES (
  '22222222-2222-2222-2222-222222222222',
  'fixture:outbox:hello',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'whatsapp',
  'fixture-user',
  NULL,
  '11111111-1111-1111-1111-111111111111',
  'reply',
  jsonb_build_object(
    'channel','whatsapp',
    'to','fixture-user',
    'restaurantId','00000000-0000-0000-0000-000000000000',
    'text','hello from fixture'
  ),
  'PENDING',
  now() - interval '1 minute'
)
ON CONFLICT (dedupe_key) DO NOTHING;
