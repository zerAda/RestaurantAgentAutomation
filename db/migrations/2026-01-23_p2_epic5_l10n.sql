BEGIN;

-- EPIC5 L10N: templates + customer preferences

CREATE TABLE IF NOT EXISTS public.message_templates (
  tenant_id text NOT NULL DEFAULT '_GLOBAL',
  key text NOT NULL,
  locale text NOT NULL,
  content text NOT NULL,
  variables jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, key, locale)
);

-- Ensure variables is a JSON array
ALTER TABLE public.message_templates
  DROP CONSTRAINT IF EXISTS chk_message_templates_variables_array;
ALTER TABLE public.message_templates
  ADD CONSTRAINT chk_message_templates_variables_array
  CHECK (jsonb_typeof(variables) = 'array');

CREATE INDEX IF NOT EXISTS idx_message_templates_lookup
  ON public.message_templates(tenant_id, key, locale);

CREATE TABLE IF NOT EXISTS public.customer_preferences (
  tenant_id text NOT NULL,
  phone text NOT NULL,
  locale text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, phone)
);

ALTER TABLE public.customer_preferences
  DROP CONSTRAINT IF EXISTS chk_customer_preferences_locale;
ALTER TABLE public.customer_preferences
  ADD CONSTRAINT chk_customer_preferences_locale
  CHECK (lower(locale) IN ('fr','ar'));

CREATE INDEX IF NOT EXISTS idx_customer_preferences_tenant_locale
  ON public.customer_preferences(tenant_id, locale);

-- Locale normalizer
CREATE OR REPLACE FUNCTION public.normalize_locale(p_locale text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  loc text := lower(trim(coalesce(p_locale,'')));
BEGIN
  IF loc LIKE 'ar%' THEN RETURN 'ar'; END IF;
  IF loc IN ('fr','fr-fr','fr_fr','français','francais') THEN RETURN 'fr'; END IF;
  IF loc IN ('ar','ar-dz','ar_dz','arabic','عربية','العربية') THEN RETURN 'ar'; END IF;
  RETURN 'fr';
END $$;

-- Seed CORE templates (GLOBAL only). Do not overwrite tenant overrides.
INSERT INTO public.message_templates(tenant_id, key, locale, content, variables)
VALUES
  ('_GLOBAL','CORE_CLARIFY','fr','Je n’ai pas bien compris. Tu peux préciser ? (ex: “menu”, “2 tacos”, “checkout”)','[]'::jsonb),
  ('_GLOBAL','CORE_CLARIFY','ar','لم أفهم جيداً. هل يمكنك التوضيح؟ (مثال: “menu”، “2 tacos”، “checkout”)','[]'::jsonb),
  ('_GLOBAL','CORE_MENU_HEADER','fr','📋 Menu (IDs utilisables dans ton message)\n','[]'::jsonb),
  ('_GLOBAL','CORE_MENU_HEADER','ar','📋 القائمة (استخدم المعرفات في رسالتك)\n','[]'::jsonb),
  ('_GLOBAL','CORE_LANG_SET_FR','fr','✅ Langue définie sur Français. Tape “menu” pour voir la carte.','[]'::jsonb),
  ('_GLOBAL','CORE_LANG_SET_AR','ar','✅ تم تغيير اللغة إلى العربية. اكتب “menu” لعرض القائمة.','[]'::jsonb)
ON CONFLICT (tenant_id, key, locale) DO NOTHING;

-- Seed WA tracking templates (GLOBAL)
INSERT INTO public.message_templates(tenant_id, key, locale, content, variables)
VALUES
  ('_GLOBAL','WA_ORDER_STATUS_CONFIRMED','fr','✅ Commande confirmée (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_PREPARING','fr','👨‍🍳 Votre commande est en préparation (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_READY','fr','📦 Votre commande est prête (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_OUT_FOR_DELIVERY','fr','🛵 Votre commande est en cours de livraison (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_DELIVERED','fr','🎉 Commande livrée / terminée (#{{order_id}}). Merci !','["order_id"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_CANCELLED','fr','❌ Commande annulée (#{{order_id}}).','["order_id"]'::jsonb),

  ('_GLOBAL','WA_ORDER_STATUS_CONFIRMED','ar','✅ تم تأكيد طلبك (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_PREPARING','ar','👨‍🍳 يتم تحضير طلبك (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_READY','ar','📦 طلبك جاهز (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_OUT_FOR_DELIVERY','ar','🛵 طلبك في الطريق للتوصيل (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_DELIVERED','ar','🎉 تم تسليم/إنهاء الطلب (#{{order_id}}). شكراً لك!','["order_id"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_CANCELLED','ar','❌ تم إلغاء الطلب (#{{order_id}}).','["order_id"]'::jsonb)
ON CONFLICT (tenant_id, key, locale) DO NOTHING;

-- Patch wa_order_status_text: try DB template first (GLOBAL), fallback to legacy strings.
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
  loc text := public.normalize_locale(p_locale);
  eta_txt text := '';
  link_txt text := '';
  k text := 'WA_ORDER_STATUS_' || upper(coalesce(p_customer_status,''));
  tmpl text;
  out_txt text;
  order_short text := left(p_order_id::text,8);
BEGIN
  IF p_eta_min IS NOT NULL OR p_eta_max IS NOT NULL THEN
    eta_txt := E'\nETA: ' || COALESCE(p_eta_min::text,'') ||
      CASE WHEN p_eta_max IS NOT NULL THEN '-'||p_eta_max::text ELSE '' END || ' min';
  END IF;

  IF p_status_link IS NOT NULL AND length(trim(p_status_link)) > 0 THEN
    link_txt := E'\nSuivi: ' || trim(p_status_link);
  END IF;

  SELECT content INTO tmpl
  FROM public.message_templates
  WHERE tenant_id = '_GLOBAL' AND key = k AND locale = loc
  LIMIT 1;

  IF tmpl IS NOT NULL THEN
    out_txt := replace(replace(tmpl, '{{order_id}}', order_short), '{{eta}}', eta_txt);
    RETURN out_txt || link_txt;
  END IF;

  -- Legacy fallback (exact behavior EPIC3)
  IF loc LIKE 'ar%' THEN
    CASE p_customer_status
      WHEN 'CONFIRMED' THEN RETURN '✅ تم تأكيد طلبك #'||order_short||eta_txt;
      WHEN 'PREPARING' THEN RETURN '👨‍🍳 يتم تحضير طلبك #'||order_short||eta_txt;
      WHEN 'READY' THEN RETURN '📦 طلبك جاهز #'||order_short||eta_txt;
      WHEN 'OUT_FOR_DELIVERY' THEN RETURN '🛵 طلبك في الطريق للتوصيل #'||order_short||eta_txt;
      WHEN 'DELIVERED' THEN RETURN '🎉 تم تسليم/إنهاء الطلب #'||order_short;
      WHEN 'CANCELLED' THEN RETURN '❌ تم إلغاء الطلب #'||order_short;
      ELSE RETURN 'ℹ️ تحديث الطلب #'||order_short||eta_txt;
    END CASE;
  END IF;

  CASE p_customer_status
    WHEN 'CONFIRMED' THEN RETURN '✅ Commande confirmée #'||order_short||eta_txt||link_txt;
    WHEN 'PREPARING' THEN RETURN '👨‍🍳 Votre commande est en préparation #'||order_short||eta_txt||link_txt;
    WHEN 'READY' THEN RETURN '📦 Votre commande est prête #'||order_short||eta_txt||link_txt;
    WHEN 'OUT_FOR_DELIVERY' THEN RETURN '🛵 Votre commande est en livraison #'||order_short||eta_txt||link_txt;
    WHEN 'DELIVERED' THEN RETURN '🎉 Commande livrée #'||order_short||link_txt;
    WHEN 'CANCELLED' THEN RETURN '❌ Commande annulée #'||order_short||link_txt;
    ELSE RETURN 'ℹ️ Mise à jour commande #'||order_short||eta_txt||link_txt;
  END CASE;
END $$;

-- Patch build_wa_order_status_payload to use customer preference locale by default
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
  loc text;
BEGIN
  SELECT order_id, tenant_id, restaurant_id, channel, user_id, delivery_eta_min, delivery_eta_max
    INTO o
  FROM public.orders
  WHERE order_id = p_order_id;

  IF o.order_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  loc := public.normalize_locale(
    COALESCE(
      (SELECT locale FROM public.customer_preferences WHERE tenant_id=o.tenant_id AND phone=o.user_id),
      p_locale,
      'fr'
    )
  );

  txt := public.wa_order_status_text(loc, p_customer_status, p_order_id, o.delivery_eta_min, o.delivery_eta_max, p_status_link);

  RETURN jsonb_build_object(
    'channel','whatsapp',
    'to', o.user_id,
    'restaurantId', o.restaurant_id,
    'text', txt,
    'buttons', '[]'::jsonb
  );
END $$;

COMMIT;
