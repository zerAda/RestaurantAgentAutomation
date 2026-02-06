/*
P2-DZ-02: Delivery Wilaya/Commune + WhatsApp Location Support
- Address normalization (Arabic/Latin, typos)
- Location pin to zone matching (coordinate-based)
- Wilaya/Commune reference table for Algeria

Idempotent (safe to replay).
*/

BEGIN;

-- =============================================================================
-- 1) Wilaya Reference Table (48 wilayas of Algeria)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.wilaya_reference (
  wilaya_code    smallint PRIMARY KEY,
  name_fr        text NOT NULL,
  name_ar        text NOT NULL,
  name_latin_alt text[] NOT NULL DEFAULT '{}',  -- Alternative Latin spellings
  name_ar_alt    text[] NOT NULL DEFAULT '{}',  -- Alternative Arabic spellings
  center_lat     numeric(9,6),
  center_lng     numeric(9,6)
);

-- Insert Algeria's 48 wilayas with common spelling variants
INSERT INTO public.wilaya_reference (wilaya_code, name_fr, name_ar, name_latin_alt, name_ar_alt, center_lat, center_lng)
VALUES
  (1, 'Adrar', 'أدرار', ARRAY['adrar'], ARRAY[], 27.8742, -0.2939),
  (2, 'Chlef', 'الشلف', ARRAY['chlef', 'chelif', 'ech-cheliff'], ARRAY['شلف'], 36.1654, 1.3346),
  (3, 'Laghouat', 'الأغواط', ARRAY['laghouat', 'laghwat', 'el-aghouat'], ARRAY['الاغواط'], 33.8000, 2.8650),
  (4, 'Oum El Bouaghi', 'أم البواقي', ARRAY['oum el bouaghi', 'oum-el-bouaghi', 'um el bouaghi'], ARRAY['ام البواقي'], 35.8756, 7.1131),
  (5, 'Batna', 'باتنة', ARRAY['batna', 'bathna'], ARRAY['باتنه'], 35.5550, 6.1742),
  (6, 'Bejaia', 'بجاية', ARRAY['bejaia', 'bougie', 'bgayet', 'bejaya'], ARRAY['بجايه'], 36.7509, 5.0567),
  (7, 'Biskra', 'بسكرة', ARRAY['biskra', 'beskra'], ARRAY['بسكره'], 34.8484, 5.7287),
  (8, 'Bechar', 'بشار', ARRAY['bechar', 'becher'], ARRAY[], 31.6167, -2.2167),
  (9, 'Blida', 'البليدة', ARRAY['blida', 'el-blida', 'el blida'], ARRAY['بليدة', 'البليده'], 36.4700, 2.8300),
  (10, 'Bouira', 'البويرة', ARRAY['bouira', 'el-bouira', 'bouirah'], ARRAY['بويره', 'البويره'], 36.3800, 3.9000),
  (11, 'Tamanrasset', 'تمنراست', ARRAY['tamanrasset', 'tamanghasset', 'tamnrasset'], ARRAY['تمنغست'], 22.7850, 5.5228),
  (12, 'Tebessa', 'تبسة', ARRAY['tebessa', 'tbessa', 'tebesa'], ARRAY['تبسه'], 35.4042, 8.1242),
  (13, 'Tlemcen', 'تلمسان', ARRAY['tlemcen', 'tilimsan', 'tlemsen'], ARRAY['تلمسن'], 34.8828, -1.3167),
  (14, 'Tiaret', 'تيارت', ARRAY['tiaret', 'tahert', 'tiharet'], ARRAY['تيهارت'], 35.3708, 1.3178),
  (15, 'Tizi Ouzou', 'تيزي وزو', ARRAY['tizi ouzou', 'tizi-ouzou', 'tizi wuzzu'], ARRAY['تيزي وزو'], 36.7169, 4.0497),
  (16, 'Alger', 'الجزائر', ARRAY['alger', 'algiers', 'el-djazair', 'dzayer', 'al jazair'], ARRAY['جزائر', 'الجزاير', 'دزاير'], 36.7538, 3.0588),
  (17, 'Djelfa', 'الجلفة', ARRAY['djelfa', 'jelfa', 'el-djelfa'], ARRAY['جلفة', 'الجلفه'], 34.6704, 3.2500),
  (18, 'Jijel', 'جيجل', ARRAY['jijel', 'djidjel', 'djidgel'], ARRAY['جيجيل'], 36.8208, 5.7667),
  (19, 'Setif', 'سطيف', ARRAY['setif', 'stif', 'setiff'], ARRAY['سطيف'], 36.1900, 5.4100),
  (20, 'Saida', 'سعيدة', ARRAY['saida', 'sayda', 'saada'], ARRAY['سعيده'], 34.8333, 0.1500),
  (21, 'Skikda', 'سكيكدة', ARRAY['skikda', 'skikida', 'philippeville'], ARRAY['سكيكده'], 36.8667, 6.9000),
  (22, 'Sidi Bel Abbes', 'سيدي بلعباس', ARRAY['sidi bel abbes', 'sidi-bel-abbes', 'sba'], ARRAY['سيدي بلعباس'], 35.1833, -0.6333),
  (23, 'Annaba', 'عنابة', ARRAY['annaba', 'anaba', 'bone'], ARRAY['عنابه'], 36.9000, 7.7667),
  (24, 'Guelma', 'قالمة', ARRAY['guelma', 'galma', 'kelma'], ARRAY['قالمه'], 36.4622, 7.4267),
  (25, 'Constantine', 'قسنطينة', ARRAY['constantine', 'qsantina', 'ksantina'], ARRAY['قسنطينه'], 36.3650, 6.6147),
  (26, 'Medea', 'المدية', ARRAY['medea', 'mdea', 'el-medea'], ARRAY['مديه', 'المديه'], 36.2675, 2.7536),
  (27, 'Mostaganem', 'مستغانم', ARRAY['mostaganem', 'mestghanem', 'mostaghanem'], ARRAY['مستغانم'], 35.9333, 0.0833),
  (28, 'Msila', 'المسيلة', ARRAY['msila', 'el-msila', "m'sila"], ARRAY['مسيله', 'المسيله'], 35.7000, 4.5500),
  (29, 'Mascara', 'معسكر', ARRAY['mascara', 'maskara', 'muaskar'], ARRAY['معسكر'], 35.4000, 0.1333),
  (30, 'Ouargla', 'ورقلة', ARRAY['ouargla', 'wargla', 'wargla'], ARRAY['ورقله'], 31.9500, 5.3167),
  (31, 'Oran', 'وهران', ARRAY['oran', 'wahran', 'ouahran'], ARRAY['وهران'], 35.6969, -0.6331),
  (32, 'El Bayadh', 'البيض', ARRAY['el bayadh', 'el-bayadh', 'elbayadh'], ARRAY['البياض'], 33.6833, 1.0167),
  (33, 'Illizi', 'إليزي', ARRAY['illizi', 'ilizi'], ARRAY['اليزي'], 26.4833, 8.4667),
  (34, 'Bordj Bou Arreridj', 'برج بوعريريج', ARRAY['bordj bou arreridj', 'bba', 'bordj-bou-arreridj'], ARRAY['برج بوعريريج'], 36.0667, 4.7667),
  (35, 'Boumerdes', 'بومرداس', ARRAY['boumerdes', 'boumerdas', 'bumerdas'], ARRAY['بومرداس'], 36.7667, 3.4667),
  (36, 'El Tarf', 'الطارف', ARRAY['el tarf', 'el-tarf', 'eltarf'], ARRAY['الطارف'], 36.7667, 8.3167),
  (37, 'Tindouf', 'تندوف', ARRAY['tindouf', 'tinduf'], ARRAY['تندوف'], 27.6742, -8.1478),
  (38, 'Tissemsilt', 'تيسمسيلت', ARRAY['tissemsilt', 'tissimsilt'], ARRAY['تسمسيلت'], 35.6056, 1.8131),
  (39, 'El Oued', 'الوادي', ARRAY['el oued', 'el-oued', 'eloued', 'oued souf'], ARRAY['الواد', 'وادي سوف'], 33.3683, 6.8675),
  (40, 'Khenchela', 'خنشلة', ARRAY['khenchela', 'khanchela', 'khenshela'], ARRAY['خنشله'], 35.4356, 7.1431),
  (41, 'Souk Ahras', 'سوق أهراس', ARRAY['souk ahras', 'souk-ahras', 'souqahras'], ARRAY['سوق اهراس'], 36.2864, 7.9511),
  (42, 'Tipaza', 'تيبازة', ARRAY['tipaza', 'tipasa', 'tippaza'], ARRAY['تيبازه'], 36.5897, 2.4475),
  (43, 'Mila', 'ميلة', ARRAY['mila', 'meela'], ARRAY['ميله'], 36.4500, 6.2667),
  (44, 'Ain Defla', 'عين الدفلى', ARRAY['ain defla', 'ain-defla', 'ayn defla'], ARRAY['عين دفلى', 'عين الدفلة'], 36.2539, 1.9681),
  (45, 'Naama', 'النعامة', ARRAY['naama', 'nama', 'naamah'], ARRAY['النعامه'], 33.2667, -0.3167),
  (46, 'Ain Temouchent', 'عين تموشنت', ARRAY['ain temouchent', 'ain-temouchent', 'ayn temouchent'], ARRAY['عين تيموشنت'], 35.2975, -1.1403),
  (47, 'Ghardaia', 'غرداية', ARRAY['ghardaia', 'ghardaya', 'gardaia'], ARRAY['غردايه'], 32.4900, 3.6700),
  (48, 'Relizane', 'غليزان', ARRAY['relizane', 'ghelizane', 'ralizane'], ARRAY['رليزان'], 35.7333, 0.5500)
ON CONFLICT (wilaya_code) DO UPDATE SET
  name_fr = EXCLUDED.name_fr,
  name_ar = EXCLUDED.name_ar,
  name_latin_alt = EXCLUDED.name_latin_alt,
  name_ar_alt = EXCLUDED.name_ar_alt,
  center_lat = EXCLUDED.center_lat,
  center_lng = EXCLUDED.center_lng;

-- Index for fast lookup
CREATE INDEX IF NOT EXISTS idx_wilaya_ref_name_fr ON public.wilaya_reference (lower(name_fr));

-- =============================================================================
-- 2) Commune Reference Table (sample communes - can be expanded)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.commune_reference (
  commune_id     serial PRIMARY KEY,
  wilaya_code    smallint NOT NULL REFERENCES public.wilaya_reference(wilaya_code),
  name_fr        text NOT NULL,
  name_ar        text NOT NULL DEFAULT '',
  name_latin_alt text[] NOT NULL DEFAULT '{}',
  center_lat     numeric(9,6),
  center_lng     numeric(9,6)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_commune_ref_wilaya_name
  ON public.commune_reference(wilaya_code, lower(name_fr));

-- Insert common Alger communes as sample (expandable)
INSERT INTO public.commune_reference (wilaya_code, name_fr, name_ar, name_latin_alt, center_lat, center_lng)
VALUES
  (16, 'Alger Centre', 'الجزائر الوسطى', ARRAY['alger-centre', 'centre', 'downtown'], 36.7731, 3.0588),
  (16, 'Bab El Oued', 'باب الوادي', ARRAY['bab-el-oued', 'babeloued'], 36.7917, 3.0500),
  (16, 'Bir Mourad Rais', 'بئر مراد رايس', ARRAY['bir-mourad-rais', 'bmr'], 36.7469, 3.0461),
  (16, 'El Biar', 'الأبيار', ARRAY['el-biar', 'elbiar'], 36.7667, 3.0333),
  (16, 'Draria', 'دراريه', ARRAY['draria', 'dararia'], 36.7167, 2.9667),
  (16, 'Hussein Dey', 'حسين داي', ARRAY['hussein-dey', 'husseindey'], 36.7500, 3.1000),
  (16, 'Kouba', 'القبة', ARRAY['kouba', 'el-kouba'], 36.7333, 3.0667),
  (16, 'Bab Ezzouar', 'باب الزوار', ARRAY['bab-ezzouar', 'babezzouar'], 36.7206, 3.1822),
  (16, 'Dar El Beida', 'الدار البيضاء', ARRAY['dar-el-beida', 'darelbeida', 'dar beida'], 36.7167, 3.2167),
  (16, 'Cheraga', 'الشراقة', ARRAY['cheraga', 'cherraga'], 36.7667, 2.9500),
  (16, 'Dely Ibrahim', 'دالي ابراهيم', ARRAY['dely-ibrahim', 'delyibrahim'], 36.7500, 2.9833),
  (16, 'Hydra', 'حيدرة', ARRAY['hydra'], 36.7500, 3.0333),
  (16, 'Ben Aknoun', 'بن عكنون', ARRAY['ben-aknoun', 'benaknoun'], 36.7583, 3.0083),
  (16, 'Mohammadia', 'المحمدية', ARRAY['mohammadia', 'el-mohammadia'], 36.7333, 3.1500),
  (16, 'Bordj El Kiffan', 'برج الكيفان', ARRAY['bordj-el-kiffan', 'bordjkiffan', 'bek'], 36.7500, 3.1833),
  (16, 'Rouiba', 'الرويبة', ARRAY['rouiba', 'rouibah'], 36.7333, 3.2833),
  (16, 'Reghaia', 'رغاية', ARRAY['reghaia', 'reghaiya'], 36.7333, 3.3333),
  (16, 'Ain Benian', 'عين البنيان', ARRAY['ain-benian', 'ainbenian'], 36.8000, 2.9167),
  (16, 'Sidi Moussa', 'سيدي موسى', ARRAY['sidi-moussa', 'sidimoussa'], 36.6167, 3.0833),
  (16, 'Baraki', 'براقي', ARRAY['baraki', 'el-baraki'], 36.6667, 3.0833),
  -- Oran communes
  (31, 'Oran Centre', 'وهران الوسطى', ARRAY['oran-centre', 'centre-ville'], 35.6969, -0.6331),
  (31, 'Bir El Djir', 'بئر الجير', ARRAY['bir-el-djir', 'birdjir'], 35.7167, -0.6000),
  (31, 'Es Senia', 'السانية', ARRAY['es-senia', 'essenia', 'la senia'], 35.6500, -0.6333),
  (31, 'Arzew', 'أرزيو', ARRAY['arzew', 'arzeu'], 35.8500, -0.3167),
  (31, 'Ain El Turk', 'عين الترك', ARRAY['ain-el-turk', 'ainelturk'], 35.7500, -0.7667),
  -- Constantine communes
  (25, 'Constantine Centre', 'قسنطينة الوسطى', ARRAY['constantine-centre'], 36.3650, 6.6147),
  (25, 'El Khroub', 'الخروب', ARRAY['el-khroub', 'elkhroub'], 36.2639, 6.6931),
  (25, 'Ain Smara', 'عين سمارة', ARRAY['ain-smara', 'ainsmara'], 36.2833, 6.5000),
  (25, 'Hamma Bouziane', 'حامة بوزيان', ARRAY['hamma-bouziane', 'hammabouziane'], 36.4167, 6.6000),
  -- Annaba communes
  (23, 'Annaba Centre', 'عنابة الوسطى', ARRAY['annaba-centre'], 36.9000, 7.7667),
  (23, 'El Bouni', 'البوني', ARRAY['el-bouni', 'elbouni'], 36.8500, 7.7167),
  (23, 'Sidi Amar', 'سيدي عمار', ARRAY['sidi-amar', 'sidiamar'], 36.8167, 7.7500)
ON CONFLICT (wilaya_code, lower(name_fr)) DO UPDATE SET
  name_ar = EXCLUDED.name_ar,
  name_latin_alt = EXCLUDED.name_latin_alt,
  center_lat = EXCLUDED.center_lat,
  center_lng = EXCLUDED.center_lng;

-- =============================================================================
-- 3) Add coordinate columns to delivery_zones for polygon/center matching
-- =============================================================================

ALTER TABLE public.delivery_zones
  ADD COLUMN IF NOT EXISTS center_lat numeric(9,6),
  ADD COLUMN IF NOT EXISTS center_lng numeric(9,6),
  ADD COLUMN IF NOT EXISTS radius_km numeric(5,2) DEFAULT 10.0;

-- Index for coordinate-based lookups
CREATE INDEX IF NOT EXISTS idx_delivery_zones_coords
  ON public.delivery_zones (restaurant_id, center_lat, center_lng)
  WHERE center_lat IS NOT NULL AND center_lng IS NOT NULL;

-- =============================================================================
-- 4) Address Normalization Function
-- =============================================================================

CREATE OR REPLACE FUNCTION public.normalize_address(
  p_raw_address text,
  p_wilaya_hint text DEFAULT NULL,
  p_commune_hint text DEFAULT NULL
)
RETURNS TABLE(
  wilaya_code smallint,
  wilaya_name text,
  commune_name text,
  confidence text,  -- 'exact', 'fuzzy', 'partial', 'none'
  normalized_wilaya text,
  normalized_commune text
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_input text;
  v_wilaya_match RECORD;
  v_commune_match RECORD;
  v_confidence text := 'none';
BEGIN
  v_input := lower(trim(COALESCE(p_raw_address, '') || ' ' || COALESCE(p_wilaya_hint, '') || ' ' || COALESCE(p_commune_hint, '')));

  -- Remove common prefixes/suffixes and normalize
  v_input := regexp_replace(v_input, '\s+', ' ', 'g');
  v_input := regexp_replace(v_input, '(wilaya|commune|daira|quartier|cite|hai|حي|ولاية|بلدية|دائرة)\s*:?\s*', '', 'gi');

  -- Try exact match on wilaya first
  SELECT w.wilaya_code, w.name_fr INTO v_wilaya_match
  FROM public.wilaya_reference w
  WHERE lower(w.name_fr) = lower(trim(COALESCE(p_wilaya_hint, '')))
     OR lower(w.name_ar) = trim(COALESCE(p_wilaya_hint, ''))
     OR lower(trim(COALESCE(p_wilaya_hint, ''))) = ANY(w.name_latin_alt)
     OR trim(COALESCE(p_wilaya_hint, '')) = ANY(w.name_ar_alt)
  LIMIT 1;

  -- If no hint match, search in full address
  IF v_wilaya_match IS NULL THEN
    SELECT w.wilaya_code, w.name_fr INTO v_wilaya_match
    FROM public.wilaya_reference w
    WHERE v_input LIKE '%' || lower(w.name_fr) || '%'
       OR v_input LIKE '%' || lower(w.name_ar) || '%'
       OR EXISTS (SELECT 1 FROM unnest(w.name_latin_alt) alt WHERE v_input LIKE '%' || lower(alt) || '%')
    ORDER BY length(w.name_fr) DESC  -- Prefer longer matches (more specific)
    LIMIT 1;
  END IF;

  IF v_wilaya_match IS NOT NULL THEN
    v_confidence := 'exact';

    -- Try to find commune within that wilaya
    SELECT c.name_fr INTO v_commune_match
    FROM public.commune_reference c
    WHERE c.wilaya_code = v_wilaya_match.wilaya_code
      AND (
        lower(c.name_fr) = lower(trim(COALESCE(p_commune_hint, '')))
        OR lower(c.name_ar) = trim(COALESCE(p_commune_hint, ''))
        OR lower(trim(COALESCE(p_commune_hint, ''))) = ANY(c.name_latin_alt)
        OR v_input LIKE '%' || lower(c.name_fr) || '%'
        OR EXISTS (SELECT 1 FROM unnest(c.name_latin_alt) alt WHERE v_input LIKE '%' || lower(alt) || '%')
      )
    ORDER BY
      CASE WHEN lower(c.name_fr) = lower(trim(COALESCE(p_commune_hint, ''))) THEN 0 ELSE 1 END,
      length(c.name_fr) DESC
    LIMIT 1;

    IF v_commune_match IS NULL THEN
      v_confidence := 'partial';  -- Wilaya found but not commune
    END IF;

    RETURN QUERY SELECT
      v_wilaya_match.wilaya_code,
      v_wilaya_match.name_fr,
      COALESCE(v_commune_match.name_fr, p_commune_hint),
      v_confidence,
      v_wilaya_match.name_fr,
      COALESCE(v_commune_match.name_fr, p_commune_hint);
    RETURN;
  END IF;

  -- No match found
  RETURN QUERY SELECT
    NULL::smallint,
    NULL::text,
    NULL::text,
    'none'::text,
    p_wilaya_hint,
    p_commune_hint;
END;
$$;

-- =============================================================================
-- 5) Location Pin to Zone Matching (Coordinate-based)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.location_to_zone(
  p_restaurant_id uuid,
  p_latitude numeric,
  p_longitude numeric
)
RETURNS TABLE(
  zone_id uuid,
  wilaya text,
  commune text,
  distance_km numeric,
  is_active boolean,
  fee_base_cents int,
  min_order_cents int,
  eta_min int,
  eta_max int,
  match_type text  -- 'exact_coords', 'wilaya_center', 'nearest'
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_zone RECORD;
  v_wilaya RECORD;
BEGIN
  -- Haversine distance calculation helper (embedded)
  -- Returns distance in km between two lat/lng points

  -- First try: Exact zone match by coordinates (if zone has center defined)
  SELECT z.*,
    -- Haversine formula
    6371 * 2 * asin(sqrt(
      power(sin(radians(p_latitude - z.center_lat) / 2), 2) +
      cos(radians(z.center_lat)) * cos(radians(p_latitude)) *
      power(sin(radians(p_longitude - z.center_lng) / 2), 2)
    )) AS dist_km
  INTO v_zone
  FROM public.delivery_zones z
  WHERE z.restaurant_id = p_restaurant_id
    AND z.center_lat IS NOT NULL
    AND z.center_lng IS NOT NULL
  ORDER BY dist_km ASC
  LIMIT 1;

  IF v_zone IS NOT NULL AND v_zone.dist_km <= COALESCE(v_zone.radius_km, 10.0) THEN
    RETURN QUERY SELECT
      v_zone.zone_id,
      v_zone.wilaya,
      v_zone.commune,
      round(v_zone.dist_km::numeric, 2),
      v_zone.is_active,
      v_zone.fee_base_cents,
      v_zone.min_order_cents,
      v_zone.eta_min,
      v_zone.eta_max,
      'exact_coords'::text;
    RETURN;
  END IF;

  -- Second try: Match to nearest wilaya center, then find zone by wilaya name
  SELECT w.*,
    6371 * 2 * asin(sqrt(
      power(sin(radians(p_latitude - w.center_lat) / 2), 2) +
      cos(radians(w.center_lat)) * cos(radians(p_latitude)) *
      power(sin(radians(p_longitude - w.center_lng) / 2), 2)
    )) AS dist_km
  INTO v_wilaya
  FROM public.wilaya_reference w
  WHERE w.center_lat IS NOT NULL
    AND w.center_lng IS NOT NULL
  ORDER BY dist_km ASC
  LIMIT 1;

  IF v_wilaya IS NOT NULL THEN
    -- Try to find a delivery zone for this wilaya
    SELECT z.* INTO v_zone
    FROM public.delivery_zones z
    WHERE z.restaurant_id = p_restaurant_id
      AND lower(z.wilaya) = lower(v_wilaya.name_fr)
    LIMIT 1;

    IF v_zone IS NOT NULL THEN
      RETURN QUERY SELECT
        v_zone.zone_id,
        v_zone.wilaya,
        v_zone.commune,
        round(v_wilaya.dist_km::numeric, 2),
        v_zone.is_active,
        v_zone.fee_base_cents,
        v_zone.min_order_cents,
        v_zone.eta_min,
        v_zone.eta_max,
        'wilaya_center'::text;
      RETURN;
    END IF;
  END IF;

  -- Third try: Just return nearest zone (any match)
  IF v_zone IS NOT NULL THEN
    RETURN QUERY SELECT
      v_zone.zone_id,
      v_zone.wilaya,
      v_zone.commune,
      round(v_zone.dist_km::numeric, 2),
      v_zone.is_active,
      v_zone.fee_base_cents,
      v_zone.min_order_cents,
      v_zone.eta_min,
      v_zone.eta_max,
      'nearest'::text;
    RETURN;
  END IF;

  -- No match
  RETURN;
END;
$$;

-- =============================================================================
-- 6) Enhanced Delivery Quote with Location Support
-- =============================================================================

CREATE OR REPLACE FUNCTION public.delivery_quote_v2(
  p_restaurant_id uuid,
  p_wilaya text DEFAULT NULL,
  p_commune text DEFAULT NULL,
  p_latitude numeric DEFAULT NULL,
  p_longitude numeric DEFAULT NULL,
  p_total_cents int DEFAULT 0,
  p_at timestamptz DEFAULT now()
)
RETURNS TABLE(
  zone_found boolean,
  zone_active boolean,
  zone_id uuid,
  wilaya text,
  commune text,
  fee_base_cents int,
  surcharge_cents int,
  free_threshold_cents int,
  min_order_cents int,
  eta_min int,
  eta_max int,
  final_fee_cents int,
  distance_km numeric,
  match_type text,
  reason text
)
LANGUAGE plpgsql
AS $$
DECLARE
  z RECORD;
  r RECORD;
  loc RECORD;
  norm RECORD;
  t_local time;
  v_surcharge int := 0;
  v_free int := NULL;
  v_wilaya text;
  v_commune text;
BEGIN
  IF p_restaurant_id IS NULL THEN
    RETURN QUERY SELECT false,false,NULL::uuid,NULL::text,NULL::text,0,0,NULL::int,0,0,0,0,NULL::numeric,NULL::text,'INVALID_RESTAURANT';
    RETURN;
  END IF;

  -- Priority 1: Use location coordinates if provided
  IF p_latitude IS NOT NULL AND p_longitude IS NOT NULL THEN
    SELECT * INTO loc
    FROM public.location_to_zone(p_restaurant_id, p_latitude, p_longitude);

    IF loc.zone_id IS NOT NULL THEN
      v_wilaya := loc.wilaya;
      v_commune := loc.commune;

      IF NOT loc.is_active THEN
        RETURN QUERY SELECT true,false,loc.zone_id,loc.wilaya,loc.commune,loc.fee_base_cents,0,NULL::int,loc.min_order_cents,loc.eta_min,loc.eta_max,loc.fee_base_cents,loc.distance_km,loc.match_type,'DELIVERY_ZONE_INACTIVE';
        RETURN;
      END IF;

      IF COALESCE(p_total_cents,0) < COALESCE(loc.min_order_cents,0) THEN
        RETURN QUERY SELECT true,true,loc.zone_id,loc.wilaya,loc.commune,loc.fee_base_cents,0,NULL::int,loc.min_order_cents,loc.eta_min,loc.eta_max,loc.fee_base_cents,loc.distance_km,loc.match_type,'DELIVERY_MIN_ORDER';
        RETURN;
      END IF;

      -- Apply time-based surcharges
      t_local := (p_at AT TIME ZONE COALESCE((SELECT timezone FROM public.restaurants WHERE restaurant_id=p_restaurant_id),'Africa/Algiers'))::time;

      FOR r IN
        SELECT * FROM public.delivery_fee_rules
        WHERE restaurant_id=p_restaurant_id AND is_active=true
        ORDER BY surcharge_cents DESC
      LOOP
        IF r.start_time <= r.end_time THEN
          IF t_local >= r.start_time AND t_local < r.end_time THEN
            v_surcharge := COALESCE(r.surcharge_cents,0);
            v_free := r.free_delivery_threshold_cents;
            EXIT;
          END IF;
        ELSE
          IF t_local >= r.start_time OR t_local < r.end_time THEN
            v_surcharge := COALESCE(r.surcharge_cents,0);
            v_free := r.free_delivery_threshold_cents;
            EXIT;
          END IF;
        END IF;
      END LOOP;

      IF v_free IS NOT NULL AND COALESCE(p_total_cents,0) >= v_free THEN
        RETURN QUERY SELECT true,true,loc.zone_id,loc.wilaya,loc.commune,loc.fee_base_cents,v_surcharge,v_free,loc.min_order_cents,loc.eta_min,loc.eta_max,0,loc.distance_km,loc.match_type,'OK';
      ELSE
        RETURN QUERY SELECT true,true,loc.zone_id,loc.wilaya,loc.commune,loc.fee_base_cents,v_surcharge,v_free,loc.min_order_cents,loc.eta_min,loc.eta_max,(loc.fee_base_cents + v_surcharge),loc.distance_km,loc.match_type,'OK';
      END IF;
      RETURN;
    END IF;
  END IF;

  -- Priority 2: Normalize address and lookup by wilaya/commune
  IF p_wilaya IS NOT NULL OR p_commune IS NOT NULL THEN
    SELECT * INTO norm
    FROM public.normalize_address(NULL, p_wilaya, p_commune);

    v_wilaya := COALESCE(norm.normalized_wilaya, p_wilaya);
    v_commune := COALESCE(norm.normalized_commune, p_commune);
  ELSE
    v_wilaya := p_wilaya;
    v_commune := p_commune;
  END IF;

  -- Lookup zone by normalized wilaya/commune
  SELECT * INTO z
  FROM public.delivery_zones
  WHERE restaurant_id = p_restaurant_id
    AND lower(wilaya) = lower(COALESCE(v_wilaya,''))
    AND lower(commune) = lower(COALESCE(v_commune,''))
  LIMIT 1;

  IF z.zone_id IS NULL THEN
    RETURN QUERY SELECT false,false,NULL::uuid,v_wilaya,v_commune,0,0,NULL::int,0,0,0,0,NULL::numeric,'text_match'::text,'DELIVERY_ZONE_NOT_FOUND';
    RETURN;
  END IF;

  IF NOT z.is_active THEN
    RETURN QUERY SELECT true,false,z.zone_id,z.wilaya,z.commune,z.fee_base_cents,0,NULL::int,z.min_order_cents,z.eta_min,z.eta_max,z.fee_base_cents,NULL::numeric,'text_match'::text,'DELIVERY_ZONE_INACTIVE';
    RETURN;
  END IF;

  IF COALESCE(p_total_cents,0) < COALESCE(z.min_order_cents,0) THEN
    RETURN QUERY SELECT true,true,z.zone_id,z.wilaya,z.commune,z.fee_base_cents,0,NULL::int,z.min_order_cents,z.eta_min,z.eta_max,z.fee_base_cents,NULL::numeric,'text_match'::text,'DELIVERY_MIN_ORDER';
    RETURN;
  END IF;

  t_local := (p_at AT TIME ZONE COALESCE((SELECT timezone FROM public.restaurants WHERE restaurant_id=p_restaurant_id),'Africa/Algiers'))::time;

  FOR r IN
    SELECT * FROM public.delivery_fee_rules
    WHERE restaurant_id=p_restaurant_id AND is_active=true
    ORDER BY surcharge_cents DESC
  LOOP
    IF r.start_time <= r.end_time THEN
      IF t_local >= r.start_time AND t_local < r.end_time THEN
        v_surcharge := COALESCE(r.surcharge_cents,0);
        v_free := r.free_delivery_threshold_cents;
        EXIT;
      END IF;
    ELSE
      IF t_local >= r.start_time OR t_local < r.end_time THEN
        v_surcharge := COALESCE(r.surcharge_cents,0);
        v_free := r.free_delivery_threshold_cents;
        EXIT;
      END IF;
    END IF;
  END LOOP;

  IF v_free IS NOT NULL AND COALESCE(p_total_cents,0) >= v_free THEN
    RETURN QUERY SELECT true,true,z.zone_id,z.wilaya,z.commune,z.fee_base_cents,v_surcharge,v_free,z.min_order_cents,z.eta_min,z.eta_max,0,NULL::numeric,'text_match'::text,'OK';
  ELSE
    RETURN QUERY SELECT true,true,z.zone_id,z.wilaya,z.commune,z.fee_base_cents,v_surcharge,v_free,z.min_order_cents,z.eta_min,z.eta_max,(z.fee_base_cents + v_surcharge),NULL::numeric,'text_match'::text,'OK';
  END IF;
END;
$$;

-- =============================================================================
-- 7) Message Templates for Location Requests
-- =============================================================================

INSERT INTO public.message_templates (tenant_id, restaurant_id, template_key, locale, content)
VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'delivery_location_request', 'fr',
   'Pour calculer les frais de livraison, veuillez partager votre position:\n1. Appuyez sur 📎 (trombone)\n2. Selectionnez "Position"\n3. Envoyez votre position actuelle\n\nOu indiquez votre wilaya et commune.'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'delivery_location_request', 'ar',
   'لحساب رسوم التوصيل، يرجى مشاركة موقعك:\n1. اضغط على 📎\n2. اختر "الموقع"\n3. أرسل موقعك الحالي\n\nأو أدخل الولاية والبلدية.'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'delivery_location_received', 'fr',
   'Position reçue! Votre zone: {wilaya}, {commune}\nFrais de livraison: {fee_display}\nTemps estimé: {eta_min}-{eta_max} min'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'delivery_location_received', 'ar',
   'تم استلام الموقع! منطقتك: {wilaya}، {commune}\nرسوم التوصيل: {fee_display}\nالوقت المقدر: {eta_min}-{eta_max} دقيقة'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'delivery_zone_not_found', 'fr',
   'Désolé, nous ne livrons pas encore dans votre zone ({wilaya}).\nVeuillez choisir "À emporter" ou contacter le restaurant.'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'delivery_zone_not_found', 'ar',
   'عذراً، لا نقوم بالتوصيل إلى منطقتك بعد ({wilaya}).\nيرجى اختيار "استلام من المحل" أو الاتصال بالمطعم.')
ON CONFLICT (template_key, locale, tenant_id) DO UPDATE SET
  content = EXCLUDED.content;

-- =============================================================================
-- 8) Security Event Types
-- =============================================================================

INSERT INTO ops.security_event_types(code, description) VALUES
  ('LOCATION_PIN_RECEIVED', 'Delivery: WhatsApp location pin received'),
  ('LOCATION_ZONE_MATCHED', 'Delivery: Location matched to delivery zone'),
  ('LOCATION_ZONE_NOT_FOUND', 'Delivery: Location could not be matched to any zone'),
  ('ADDRESS_NORMALIZED', 'Delivery: Address normalized successfully'),
  ('ADDRESS_NORMALIZATION_FAILED', 'Delivery: Address normalization failed')
ON CONFLICT (code) DO NOTHING;

-- Add to enum if possible
DO $$
DECLARE
  v_code TEXT;
BEGIN
  FOR v_code IN SELECT code FROM ops.security_event_types WHERE code IN (
    'LOCATION_PIN_RECEIVED', 'LOCATION_ZONE_MATCHED', 'LOCATION_ZONE_NOT_FOUND',
    'ADDRESS_NORMALIZED', 'ADDRESS_NORMALIZATION_FAILED'
  ) LOOP
    BEGIN
      EXECUTE format('ALTER TYPE security_event_type_enum ADD VALUE %L', v_code);
    EXCEPTION WHEN duplicate_object THEN
      NULL;
    END;
  END LOOP;
END $$;

COMMIT;
