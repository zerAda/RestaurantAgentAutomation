BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Expand orders.status allowed values (backward compatible)
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS chk_orders_status_valid;
ALTER TABLE public.orders
  ADD CONSTRAINT chk_orders_status_valid
  CHECK (status IN (
    'NEW','ACCEPTED','IN_PROGRESS','READY',
    'OUT_FOR_DELIVERY',
    'DONE','DELIVERED',
    'CANCELLED'
  ));

-- Orders: notification tracking
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS last_notified_status text NULL,
  ADD COLUMN IF NOT EXISTS last_notified_at timestamptz NULL;

-- Admin listing index
CREATE INDEX IF NOT EXISTS idx_orders_status_created
  ON public.orders(status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_last_notified
  ON public.orders(restaurant_id, last_notified_at DESC);

-- Timeline
CREATE TABLE IF NOT EXISTS public.order_status_history (
  id bigserial PRIMARY KEY,
  order_id uuid NOT NULL REFERENCES public.orders(order_id) ON DELETE CASCADE,
  internal_status text NOT NULL,
  customer_status text NULL,
  note text NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_status_history_order_time
  ON public.order_status_history(order_id, created_at ASC);

CREATE OR REPLACE FUNCTION public.map_order_status_to_customer(
  p_internal_status text,
  p_service_mode text
)
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_internal_status IS NULL THEN
    RETURN NULL;
  END IF;

  CASE upper(p_internal_status)
    WHEN 'ACCEPTED' THEN RETURN 'CONFIRMED';
    WHEN 'IN_PROGRESS' THEN RETURN 'PREPARING';
    WHEN 'READY' THEN RETURN 'READY';
    WHEN 'OUT_FOR_DELIVERY' THEN RETURN 'OUT_FOR_DELIVERY';
    WHEN 'DONE' THEN RETURN 'DELIVERED';
    WHEN 'DELIVERED' THEN RETURN 'DELIVERED';
    WHEN 'CANCELLED' THEN RETURN 'CANCELLED';
    ELSE RETURN NULL; -- e.g. NEW
  END CASE;
END $$;

CREATE OR REPLACE FUNCTION public.wa_order_status_text(
  p_locale text,
  p_customer_status text,
  p_order_id uuid,
  p_eta_min int,
  p_eta_max int,
  p_status_link text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  loc text := lower(COALESCE(p_locale,'fr'));
  eta_txt text := '';
  link_txt text := '';
BEGIN
  IF p_eta_min IS NOT NULL OR p_eta_max IS NOT NULL THEN
    eta_txt := E'\nETA: ' || COALESCE(p_eta_min::text,'') ||
      CASE WHEN p_eta_max IS NOT NULL THEN '-'||p_eta_max::text ELSE '' END || ' min';
  END IF;

  IF p_status_link IS NOT NULL AND length(trim(p_status_link)) > 0 THEN
    link_txt := E'\nSuivi: ' || trim(p_status_link);
  END IF;

  IF loc LIKE 'ar%' THEN
    CASE p_customer_status
      WHEN 'CONFIRMED' THEN RETURN '✅ تم تأكيد طلبك #'||left(p_order_id::text,8)||eta_txt;
      WHEN 'PREPARING' THEN RETURN '👨‍🍳 يتم تحضير طلبك #'||left(p_order_id::text,8)||eta_txt;
      WHEN 'READY' THEN RETURN '📦 طلبك جاهز #'||left(p_order_id::text,8)||eta_txt;
      WHEN 'OUT_FOR_DELIVERY' THEN RETURN '🛵 طلبك في الطريق للتوصيل #'||left(p_order_id::text,8)||eta_txt;
      WHEN 'DELIVERED' THEN RETURN '🎉 تم تسليم/إنهاء الطلب #'||left(p_order_id::text,8);
      WHEN 'CANCELLED' THEN RETURN '❌ تم إلغاء الطلب #'||left(p_order_id::text,8);
      ELSE RETURN 'ℹ️ تحديث الطلب #'||left(p_order_id::text,8)||eta_txt;
    END CASE;
  END IF;

  CASE p_customer_status
    WHEN 'CONFIRMED' THEN RETURN '✅ Commande confirmée #'||left(p_order_id::text,8)||eta_txt||link_txt;
    WHEN 'PREPARING' THEN RETURN '👨‍🍳 Votre commande est en préparation #'||left(p_order_id::text,8)||eta_txt||link_txt;
    WHEN 'READY' THEN RETURN '📦 Votre commande est prête #'||left(p_order_id::text,8)||eta_txt||link_txt;
    WHEN 'OUT_FOR_DELIVERY' THEN RETURN '🛵 Votre commande est en livraison #'||left(p_order_id::text,8)||eta_txt||link_txt;
    WHEN 'DELIVERED' THEN RETURN '🎉 Commande livrée #'||left(p_order_id::text,8)||link_txt;
    WHEN 'CANCELLED' THEN RETURN '❌ Commande annulée #'||left(p_order_id::text,8)||link_txt;
    ELSE RETURN 'ℹ️ Mise à jour commande #'||left(p_order_id::text,8)||eta_txt||link_txt;
  END CASE;
END $$;

CREATE OR REPLACE FUNCTION public.build_wa_order_status_payload(
  p_order_id uuid,
  p_customer_status text,
  p_status_link text DEFAULT NULL,
  p_locale text DEFAULT 'fr'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  o RECORD;
  txt text;
BEGIN
  SELECT order_id, tenant_id, restaurant_id, channel, user_id, delivery_eta_min, delivery_eta_max
    INTO o
  FROM public.orders
  WHERE order_id = p_order_id;

  IF o.order_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  txt := public.wa_order_status_text(p_locale, p_customer_status, p_order_id, o.delivery_eta_min, o.delivery_eta_max, p_status_link);

  RETURN jsonb_build_object(
    'channel','whatsapp',
    'to', o.user_id,
    'restaurantId', o.restaurant_id,
    'text', txt,
    'buttons', '[]'::jsonb
  );
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_wa_order_status(
  p_order_id uuid,
  p_customer_status text,
  p_status_link text DEFAULT NULL,
  p_locale text DEFAULT 'fr'
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  o RECORD;
  v_dedupe text;
  v_payload jsonb;
BEGIN
  IF p_customer_status IS NULL THEN
    RETURN;
  END IF;

  SELECT tenant_id, restaurant_id, channel, user_id
    INTO o
  FROM public.orders
  WHERE order_id = p_order_id;

  IF o.tenant_id IS NULL THEN
    RETURN;
  END IF;

  IF lower(COALESCE(o.channel,'')) <> 'whatsapp' THEN
    RETURN;
  END IF;

  v_dedupe := 'order_status:' || p_order_id::text || ':' || upper(p_customer_status);
  v_payload := public.build_wa_order_status_payload(p_order_id, upper(p_customer_status), p_status_link, p_locale);

  INSERT INTO public.outbound_messages(
    dedupe_key, tenant_id, restaurant_id, conversation_key, channel, user_id, order_id,
    template, payload_json, status, next_retry_at
  ) VALUES (
    v_dedupe, o.tenant_id, o.restaurant_id, NULL, 'whatsapp', o.user_id, p_order_id,
    'WA_ORDER_STATUS_' || upper(p_customer_status), v_payload, 'PENDING', now()
  ) ON CONFLICT (dedupe_key) DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION public.trg_orders_init_tracking()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.last_notified_status IS NULL THEN NEW.last_notified_status := NULL; END IF;
  IF NEW.last_notified_at IS NULL THEN NEW.last_notified_at := NULL; END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS orders_init_tracking ON public.orders;
CREATE TRIGGER orders_init_tracking
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.trg_orders_init_tracking();

CREATE OR REPLACE FUNCTION public.trg_orders_status_tracking()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_customer text;
  v_window interval := interval '30 seconds';
  v_next timestamptz;
BEGIN
  IF TG_OP <> 'UPDATE' OR NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  v_customer := public.map_order_status_to_customer(NEW.status, NEW.service_mode);

  INSERT INTO public.order_status_history(order_id, internal_status, customer_status)
  VALUES (NEW.order_id, NEW.status, v_customer);

  IF v_customer IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.last_notified_status IS NOT NULL AND NEW.last_notified_status = v_customer THEN
    RETURN NEW;
  END IF;

  IF NEW.last_notified_at IS NOT NULL AND NEW.last_notified_at > now() - v_window THEN
    v_next := NEW.last_notified_at + v_window;
  ELSE
    v_next := now();
  END IF;

  PERFORM public.enqueue_wa_order_status(NEW.order_id, v_customer, NULL, 'fr');

  NEW.last_notified_status := v_customer;
  NEW.last_notified_at := now();

  UPDATE public.outbound_messages
     SET next_retry_at = GREATEST(next_retry_at, v_next),
         updated_at = now()
   WHERE order_id = NEW.order_id
     AND dedupe_key = ('order_status:' || NEW.order_id::text || ':' || upper(v_customer));

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS orders_status_tracking ON public.orders;
CREATE TRIGGER orders_status_tracking
BEFORE UPDATE OF status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.trg_orders_status_tracking();

COMMIT;
