-- Test fixtures: API clients
-- Plaintext tokens (for harness only):
-- - inbound token: test-token-inbound
-- - admin token:   test-token-admin

-- Inbound client (can call /v1/inbound/*)
INSERT INTO api_clients (client_name, token_hash, tenant_id, restaurant_id, scopes, is_active)
VALUES (
  'test_inbound_client',
  '057a080348f8718bf30fce2c3af94a73230cee2feeaa8e726b626349e00fcbe2',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  '["inbound:write"]'::jsonb,
  true
)
ON CONFLICT (token_hash) DO NOTHING;

-- Admin client (can call /v1/admin/*)
INSERT INTO api_clients (client_name, token_hash, tenant_id, restaurant_id, scopes, is_active)
VALUES (
  'test_admin_client',
  'e211d8dc92775d53e4be89b8f2b0481a4bf64016e50e74113a33ea897d0e05ea',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  '["admin:read","admin:write"]'::jsonb,
  true
)
ON CONFLICT (token_hash) DO NOTHING;

-- Customer client (can call /v1/customer/*)
-- plaintext token: test-token-customer
INSERT INTO api_clients (client_name, token_hash, tenant_id, restaurant_id, scopes, is_active)
VALUES (
  'test_customer_client',
  'ad48ebfe6e69a50bfeed149de3ec5a925eb0b1ebf1c154771910e1fb19e09a80',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  '["delivery:quote"]'::jsonb,
  true
)
ON CONFLICT (token_hash) DO NOTHING;
