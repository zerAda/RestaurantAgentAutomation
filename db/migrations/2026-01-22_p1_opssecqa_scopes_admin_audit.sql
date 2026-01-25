-- P1-OPS-SEC-QA (Release-grade)
-- Adds: scopes indexing + admin audit log
-- Idempotent.

-- 1) Speed up scope queries / containment checks
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'idx_api_clients_scopes_gin'
  ) THEN
    CREATE INDEX idx_api_clients_scopes_gin ON api_clients USING GIN (scopes);
  END IF;
END$$;

-- 2) Admin audit log (who did what, when)
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id              bigserial PRIMARY KEY,
  tenant_id       uuid NULL REFERENCES tenants(tenant_id) ON DELETE SET NULL,
  restaurant_id   uuid NULL REFERENCES restaurants(restaurant_id) ON DELETE SET NULL,
  actor_client_id uuid NULL REFERENCES api_clients(client_id) ON DELETE SET NULL,
  actor_name      text NULL,
  action          text NOT NULL,
  object_type     text NULL,
  object_id       text NULL,
  request_id      text NULL,
  ip              text NULL,
  user_agent      text NULL,
  payload_json    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_tenant_time
  ON admin_audit_log (tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_audit_action_time
  ON admin_audit_log (action, created_at DESC);

-- 3) Optional: normalize existing clients with NULL scopes (safety)
UPDATE api_clients
   SET scopes = '[]'::jsonb
 WHERE scopes IS NULL;
