-- =============================================================================
-- P2-01: FR/AR/Darija Auto-detect + LANG Command + Templates
-- Migration: Add Darija as distinct locale with templates
-- =============================================================================

BEGIN;

-- 1. Update customer_preferences constraint to allow 'darija'
ALTER TABLE public.customer_preferences
  DROP CONSTRAINT IF EXISTS chk_customer_preferences_locale;
ALTER TABLE public.customer_preferences
  ADD CONSTRAINT chk_customer_preferences_locale
  CHECK (lower(locale) IN ('fr','ar','darija'));

-- 2. Update normalize_locale function to handle Darija
CREATE OR REPLACE FUNCTION public.normalize_locale(p_locale text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  loc text := lower(trim(coalesce(p_locale,'')));
BEGIN
  -- Darija variants
  IF loc IN ('darija','dz','darja','derija','marocain','moroccan') THEN RETURN 'darija'; END IF;
  -- Arabic variants
  IF loc LIKE 'ar%' THEN RETURN 'ar'; END IF;
  IF loc IN ('ar','ar-dz','ar_dz','arabic','عربية','العربية') THEN RETURN 'ar'; END IF;
  -- French variants
  IF loc IN ('fr','fr-fr','fr_fr','français','francais','french') THEN RETURN 'fr'; END IF;
  -- Default
  RETURN 'fr';
END $$;

-- 3. Seed Darija templates (GLOBAL only)
INSERT INTO public.message_templates(tenant_id, template_key, locale, content, variables)
VALUES
  -- Core messages
  ('_GLOBAL','CORE_CLARIFY','darija','Ma fhemtekch mezyan. 3awdha lik? (ex: "menu", "2 tacos", "checkout")','[]'::jsonb),
  ('_GLOBAL','CORE_MENU_HEADER','darija','📋 Menu (Dir l''ID f message dyalek)\n','[]'::jsonb),
  ('_GLOBAL','CORE_LANG_SET_DARIJA','darija','✅ Daba ghadi njawbek b Darija. Kteb "menu" bach tchouf la carte.','[]'::jsonb),
  ('_GLOBAL','CORE_LANG_SET_FR','darija','✅ Langue définie sur Français.','[]'::jsonb),
  ('_GLOBAL','CORE_LANG_SET_AR','darija','✅ تم تغيير اللغة إلى العربية.','[]'::jsonb),

  -- Support messages
  ('_GLOBAL','SUPPORT_HANDOFF_ACK','darija','🧑‍💬 Choukran. Chi wahd ghadi yt9asd m3ak f9rib.','[]'::jsonb),
  ('_GLOBAL','FAQ_NO_MATCH','darija','Mal9it jawab. Ghadi n3ytlek chi wahd.','[]'::jsonb),

  -- Order status templates
  ('_GLOBAL','WA_ORDER_STATUS_CONFIRMED','darija','✅ Commande dyalek tconfirmat (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_PREPARING','darija','👨‍🍳 Kanhaydro commande dyalek (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_READY','darija','📦 Commande dyalek wahda (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_OUT_FOR_DELIVERY','darija','🛵 Commande dyalek f tri9 (#{{order_id}}).{{eta}}','["order_id","eta"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_DELIVERED','darija','🎉 Commande wslet / salat (#{{order_id}}). Choukran!','["order_id"]'::jsonb),
  ('_GLOBAL','WA_ORDER_STATUS_CANCELLED','darija','❌ Commande t3atlat (#{{order_id}}).','["order_id"]'::jsonb),

  -- Cart and checkout
  ('_GLOBAL','CART_EMPTY','darija','Panier dyalek khawi. Kteb MENU bach tkhtar chi plat (ex: P01 x2).','[]'::jsonb),
  ('_GLOBAL','CART_UPDATED','darija','🧺 Panier dyalek:\n{{items}}\nTotal: {{total}}€\nKteb *VALIDER* wla click ✅','["items","total"]'::jsonb),
  ('_GLOBAL','ASK_SERVICE_MODE','darija','Bghiti *sur place*, *à emporter* wla *livraison*?','[]'::jsonb),

  -- Delivery
  ('_GLOBAL','DELIVERY_ADDRESS_PROMPT','darija','📍 Bash nlivriwlek, 3tini: Wilaya, Commune, Adresse, Tel.\n\nFormat:\nWilaya: <...>\nCommune: <...>\nAdresse: <...>\nTel: <...>','[]'::jsonb),
  ('_GLOBAL','DELIVERY_MISSING_FIELDS','darija','Na9s: {{fields}}. 3awdha b format: Wilaya/Commune/Adresse/Tel.','["fields"]'::jsonb),
  ('_GLOBAL','DELIVERY_HANDOFF','darija','Ma9dertch nfhem l''adresse. Ghadi n3ytlek chi wahd.','[]'::jsonb)
ON CONFLICT (template_key, locale, tenant_id) DO NOTHING;

-- 4. Add Darija keyword patterns table for detection
CREATE TABLE IF NOT EXISTS public.darija_patterns (
  id serial PRIMARY KEY,
  category text NOT NULL,  -- 'menu', 'checkout', 'greeting', 'affirmative', 'negative'
  pattern text NOT NULL,
  priority int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_darija_patterns_unique
  ON public.darija_patterns(category, lower(pattern));

-- Seed Darija detection patterns
INSERT INTO public.darija_patterns(category, pattern, priority)
VALUES
  -- Menu intent patterns
  ('menu', 'chno kayn', 10),
  ('menu', 'chnou kayen', 10),
  ('menu', 'wach kayn', 10),
  ('menu', 'wesh kayn', 10),
  ('menu', 'fin menu', 10),
  ('menu', 'lmenu', 10),
  ('menu', 'nchouf menu', 10),
  ('menu', 'bghit nchouf', 8),
  ('menu', 'warini', 8),
  ('menu', 'ash kayn', 10),
  ('menu', 'kifach', 5),

  -- Checkout intent patterns
  ('checkout', 'kml', 10),
  ('checkout', 'kammel', 10),
  ('checkout', 'kmel', 10),
  ('checkout', 'ncommandi', 10),
  ('checkout', 'ncmdi', 10),
  ('checkout', 'bghit ndir commande', 10),
  ('checkout', 'sift', 8),
  ('checkout', 'validi', 8),

  -- Greeting patterns
  ('greeting', 'salam', 10),
  ('greeting', 'slm', 10),
  ('greeting', 'labas', 10),
  ('greeting', 'ahlan', 10),
  ('greeting', 'cv', 5),
  ('greeting', 'wesh rak', 8),

  -- Affirmative patterns
  ('affirmative', 'wakha', 10),
  ('affirmative', 'wah', 10),
  ('affirmative', 'iyeh', 10),
  ('affirmative', 'ah', 5),
  ('affirmative', 'ok', 3),
  ('affirmative', 'mzyan', 8),
  ('affirmative', 'zwina', 8),

  -- Negative patterns
  ('negative', 'la', 10),
  ('negative', 'lala', 10),
  ('negative', 'makanch', 10),
  ('negative', 'machi', 10),
  ('negative', 'ma bghitch', 10)
ON CONFLICT (category, lower(pattern)) DO NOTHING;

-- 5. Function to detect if text is likely Darija
CREATE OR REPLACE FUNCTION public.detect_darija(p_text text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  txt text := lower(trim(coalesce(p_text, '')));
  match_count int := 0;
BEGIN
  -- Count how many Darija patterns match
  SELECT COUNT(*) INTO match_count
  FROM public.darija_patterns
  WHERE is_active = true
    AND txt LIKE '%' || lower(pattern) || '%';

  -- If at least 1 pattern matches, likely Darija
  RETURN match_count >= 1;
END $$;

COMMENT ON TABLE public.darija_patterns IS 'P2-01: Darija (Moroccan Arabic in Latin script) detection patterns';
COMMENT ON FUNCTION public.detect_darija IS 'P2-01: Returns true if text contains Darija patterns';

COMMIT;
