/*
Schema Enhancements - Professional Production Upgrade
=====================================================
1. Extended tenants table with plan, status, billing
2. ENUM types for better performance and type safety
3. Audit triggers for orders and api_clients
4. Partitioning preparation for inbound_messages

Idempotent (safe to replay).
*/

BEGIN;

-- =============================================================================
-- 1) ENUM TYPES (Performance + Type Safety)
-- =============================================================================

-- Channel enum (used across multiple tables)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'channel_enum') THEN
    CREATE TYPE channel_enum AS ENUM ('whatsapp', 'instagram', 'messenger');
  END IF;
END $$;

-- Order status enum
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status_enum') THEN
    CREATE TYPE order_status_enum AS ENUM ('NEW', 'ACCEPTED', 'IN_PROGRESS', 'READY', 'DONE', 'CANCELLED');
  END IF;
END $$;

-- Service mode enum
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'service_mode_enum') THEN
    CREATE TYPE service_mode_enum AS ENUM ('sur_place', 'a_emporter', 'livraison');
  END IF;
END $$;

-- Tenant plan enum
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tenant_plan_enum') THEN
    CREATE TYPE tenant_plan_enum AS ENUM ('free', 'starter', 'professional', 'enterprise');
  END IF;
END $$;

-- Tenant status enum
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tenant_status_enum') THEN
    CREATE TYPE tenant_status_enum AS ENUM ('active', 'suspended', 'trial', 'cancelled');
  END IF;
END $$;

-- =============================================================================
-- 2) EXTEND TENANTS TABLE
-- =============================================================================

-- Add new columns to tenants
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS slug TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS plan TEXT DEFAULT 'free',
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS billing_email TEXT,
  ADD COLUMN IF NOT EXISTS billing_address JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS settings JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- Add check constraints for plan and status
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_tenants_plan'
  ) THEN
    ALTER TABLE public.tenants
      ADD CONSTRAINT chk_tenants_plan
      CHECK (plan IN ('free', 'starter', 'professional', 'enterprise'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_tenants_status'
  ) THEN
    ALTER TABLE public.tenants
      ADD CONSTRAINT chk_tenants_status
      CHECK (status IN ('active', 'suspended', 'trial', 'cancelled'));
  END IF;
END $$;

-- Update default tenant with slug
UPDATE public.tenants
SET slug = 'default-chain',
    plan = 'professional',
    status = 'active',
    updated_at = now()
WHERE tenant_id = '00000000-0000-0000-0000-000000000001'
  AND slug IS NULL;

-- Index for tenant lookup by slug
CREATE INDEX IF NOT EXISTS idx_tenants_slug ON public.tenants(slug) WHERE slug IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tenants_status ON public.tenants(status);

-- =============================================================================
-- 3) EXTEND RESTAURANTS TABLE
-- =============================================================================

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS email TEXT,
  ADD COLUMN IF NOT EXISTS address JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS default_language TEXT DEFAULT 'fr',
  ADD COLUMN IF NOT EXISTS operating_hours JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- Update default restaurant
UPDATE public.restaurants
SET phone = '+213000000000',
    default_language = 'fr',
    is_active = true,
    updated_at = now()
WHERE restaurant_id = '00000000-0000-0000-0000-000000000000'
  AND phone IS NULL;

CREATE INDEX IF NOT EXISTS idx_restaurants_active ON public.restaurants(tenant_id, is_active);

-- =============================================================================
-- 4) AUDIT TABLES
-- =============================================================================

-- Orders audit log
CREATE TABLE IF NOT EXISTS public.orders_audit (
  audit_id BIGSERIAL PRIMARY KEY,
  order_id UUID NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
  old_status TEXT,
  new_status TEXT,
  old_total_cents INT,
  new_total_cents INT,
  changed_by TEXT,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  change_reason TEXT,
  ip_address INET,
  user_agent TEXT
);

CREATE INDEX IF NOT EXISTS idx_orders_audit_order ON public.orders_audit(order_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_audit_time ON public.orders_audit(changed_at DESC);

-- API clients audit log
CREATE TABLE IF NOT EXISTS public.api_clients_audit (
  audit_id BIGSERIAL PRIMARY KEY,
  client_id UUID NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE', 'AUTH_SUCCESS', 'AUTH_FAILURE')),
  old_is_active BOOLEAN,
  new_is_active BOOLEAN,
  old_scopes JSONB,
  new_scopes JSONB,
  changed_by TEXT,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  change_reason TEXT,
  ip_address INET
);

CREATE INDEX IF NOT EXISTS idx_api_clients_audit_client ON public.api_clients_audit(client_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_api_clients_audit_time ON public.api_clients_audit(changed_at DESC);

-- =============================================================================
-- 5) AUDIT TRIGGERS
-- =============================================================================

-- Trigger function for orders audit
CREATE OR REPLACE FUNCTION public.fn_orders_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.orders_audit (order_id, action, new_status, new_total_cents, changed_by)
    VALUES (NEW.order_id, 'INSERT', NEW.status, NEW.total_cents, current_user);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Only log if status or total changed
    IF OLD.status IS DISTINCT FROM NEW.status OR OLD.total_cents IS DISTINCT FROM NEW.total_cents THEN
      INSERT INTO public.orders_audit (order_id, action, old_status, new_status, old_total_cents, new_total_cents, changed_by)
      VALUES (NEW.order_id, 'UPDATE', OLD.status, NEW.status, OLD.total_cents, NEW.total_cents, current_user);
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.orders_audit (order_id, action, old_status, old_total_cents, changed_by)
    VALUES (OLD.order_id, 'DELETE', OLD.status, OLD.total_cents, current_user);
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

-- Create trigger on orders (if not exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_orders_audit'
  ) THEN
    CREATE TRIGGER trg_orders_audit
      AFTER INSERT OR UPDATE OR DELETE ON public.orders
      FOR EACH ROW EXECUTE FUNCTION public.fn_orders_audit();
  END IF;
END $$;

-- Trigger function for api_clients audit
CREATE OR REPLACE FUNCTION public.fn_api_clients_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.api_clients_audit (client_id, action, new_is_active, new_scopes, changed_by)
    VALUES (NEW.client_id, 'INSERT', NEW.is_active, NEW.scopes, current_user);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Log any change to is_active or scopes
    IF OLD.is_active IS DISTINCT FROM NEW.is_active OR OLD.scopes IS DISTINCT FROM NEW.scopes THEN
      INSERT INTO public.api_clients_audit (client_id, action, old_is_active, new_is_active, old_scopes, new_scopes, changed_by)
      VALUES (NEW.client_id, 'UPDATE', OLD.is_active, NEW.is_active, OLD.scopes, NEW.scopes, current_user);
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.api_clients_audit (client_id, action, old_is_active, old_scopes, changed_by)
    VALUES (OLD.client_id, 'DELETE', OLD.is_active, OLD.scopes, current_user);
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

-- Create trigger on api_clients (if not exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_api_clients_audit'
  ) THEN
    CREATE TRIGGER trg_api_clients_audit
      AFTER INSERT OR UPDATE OR DELETE ON public.api_clients
      FOR EACH ROW EXECUTE FUNCTION public.fn_api_clients_audit();
  END IF;
END $$;

-- =============================================================================
-- 6) INBOUND MESSAGES PARTITIONING PREPARATION
-- =============================================================================

-- Add partition key column (for future use)
ALTER TABLE public.inbound_messages
  ADD COLUMN IF NOT EXISTS partition_key DATE GENERATED ALWAYS AS (CAST(received_at AT TIME ZONE 'UTC' AS DATE)) STORED;

-- Index for partition-like queries
CREATE INDEX IF NOT EXISTS idx_inbound_messages_partition
  ON public.inbound_messages(partition_key, conversation_key);

-- Retention helper function
CREATE OR REPLACE FUNCTION public.purge_old_inbound_messages(p_days INT DEFAULT 90)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  v_deleted INT;
BEGIN
  DELETE FROM public.inbound_messages
  WHERE received_at < now() - (p_days || ' days')::interval;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  -- Log the purge
  INSERT INTO public.security_events (event_type, severity, payload_json)
  VALUES (
    'RETENTION_RUN',
    'LOW',
    jsonb_build_object(
      'table', 'inbound_messages',
      'deleted_rows', v_deleted,
      'retention_days', p_days
    )
  );

  RETURN v_deleted;
END;
$$;

-- =============================================================================
-- 7) HELPER VIEWS
-- =============================================================================

-- View: Recent orders with details
CREATE OR REPLACE VIEW public.v_recent_orders AS
SELECT
  o.order_id,
  o.status,
  o.total_cents,
  o.service_mode,
  o.channel,
  o.created_at,
  t.name AS tenant_name,
  r.name AS restaurant_name,
  (SELECT COUNT(*) FROM public.order_items oi WHERE oi.order_id = o.order_id) AS item_count,
  (SELECT string_agg(oi.label || ' x' || oi.qty, ', ')
   FROM public.order_items oi WHERE oi.order_id = o.order_id) AS items_summary
FROM public.orders o
JOIN public.tenants t ON t.tenant_id = o.tenant_id
JOIN public.restaurants r ON r.restaurant_id = o.restaurant_id
ORDER BY o.created_at DESC;

-- View: Tenant dashboard stats
CREATE OR REPLACE VIEW public.v_tenant_stats AS
SELECT
  t.tenant_id,
  t.name AS tenant_name,
  t.plan,
  t.status,
  (SELECT COUNT(*) FROM public.restaurants r WHERE r.tenant_id = t.tenant_id) AS restaurant_count,
  (SELECT COUNT(*) FROM public.orders o WHERE o.tenant_id = t.tenant_id) AS total_orders,
  (SELECT COALESCE(SUM(o.total_cents), 0) FROM public.orders o WHERE o.tenant_id = t.tenant_id AND o.status = 'DONE') AS total_revenue_cents,
  (SELECT COUNT(*) FROM public.api_clients ac WHERE ac.tenant_id = t.tenant_id AND ac.is_active) AS active_api_clients
FROM public.tenants t;

-- =============================================================================
-- 8) PERFORMANCE INDEXES
-- =============================================================================

-- Composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_orders_tenant_status_created
  ON public.orders(tenant_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_restaurant_status
  ON public.orders(restaurant_id, status);

CREATE INDEX IF NOT EXISTS idx_outbound_messages_status_retry
  ON public.outbound_messages(status, next_retry_at)
  WHERE status IN ('PENDING', 'RETRY');

CREATE INDEX IF NOT EXISTS idx_security_events_type_created
  ON public.security_events(event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_api_clients_tenant_active
  ON public.api_clients(tenant_id, is_active);

-- =============================================================================
-- 9) STATISTICS UPDATE
-- =============================================================================

-- Analyze tables for query planner
ANALYZE public.tenants;
ANALYZE public.restaurants;
ANALYZE public.orders;
ANALYZE public.order_items;
ANALYZE public.api_clients;
ANALYZE public.inbound_messages;
ANALYZE public.outbound_messages;

COMMIT;
