-- Demo seed for delivery zones / rules / slots (safe to replay)
-- Target: default restaurant id from bootstrap.

BEGIN;

-- Zones (Alger examples)
WITH rows AS (
  SELECT * FROM (VALUES
    ('00000000-0000-0000-0000-000000000000'::uuid,'Alger','Hydra',        300, 1500, 35, 55, true),
    ('00000000-0000-0000-0000-000000000000'::uuid,'Alger','Kouba',        350, 1500, 40, 60, true),
    ('00000000-0000-0000-0000-000000000000'::uuid,'Alger','Bab Ezzouar',  400, 1800, 45, 70, true),
    ('00000000-0000-0000-0000-000000000000'::uuid,'Alger','El Biar',      350, 1500, 35, 55, true),
    ('00000000-0000-0000-0000-000000000000'::uuid,'Alger','Birkhadem',    450, 2000, 50, 80, true),
    ('00000000-0000-0000-0000-000000000000'::uuid,'Alger','Draria',       500, 2200, 55, 90, true)
  ) AS t(restaurant_id, wilaya, commune, fee_base_cents, min_order_cents, eta_min, eta_max, is_active)
)
INSERT INTO public.delivery_zones(restaurant_id, wilaya, commune, fee_base_cents, min_order_cents, eta_min, eta_max, is_active)
SELECT r.restaurant_id, r.wilaya, r.commune, r.fee_base_cents, r.min_order_cents, r.eta_min, r.eta_max, r.is_active
FROM rows r
WHERE NOT EXISTS (
  SELECT 1 FROM public.delivery_zones z
  WHERE z.restaurant_id=r.restaurant_id
    AND lower(z.wilaya)=lower(r.wilaya)
    AND lower(z.commune)=lower(r.commune)
);

-- Fee rules (time windows)
WITH rules AS (
  SELECT * FROM (VALUES
    ('00000000-0000-0000-0000-000000000000'::uuid,'Evening peak','20:00'::time,'23:00'::time, 100, 5000, true),
    ('00000000-0000-0000-0000-000000000000'::uuid,'Lunch free over 40€','11:00'::time,'14:30'::time, 0, 4000, true)
  ) AS t(restaurant_id, name, start_time, end_time, surcharge_cents, free_delivery_threshold_cents, is_active)
)
INSERT INTO public.delivery_fee_rules(restaurant_id, name, start_time, end_time, surcharge_cents, free_delivery_threshold_cents, is_active)
SELECT r.restaurant_id, r.name, r.start_time, r.end_time, r.surcharge_cents, r.free_delivery_threshold_cents, r.is_active
FROM rules r
WHERE NOT EXISTS (
  SELECT 1 FROM public.delivery_fee_rules x
  WHERE x.restaurant_id=r.restaurant_id
    AND x.name=r.name
);

-- Time slots (capacity)
WITH days AS (
  SELECT generate_series(0,6) AS dow
),
slots AS (
  SELECT
    '00000000-0000-0000-0000-000000000000'::uuid AS restaurant_id,
    d.dow::smallint AS day_of_week,
    s.start_time,
    s.end_time,
    s.capacity,
    true AS is_active
  FROM days d
  CROSS JOIN (VALUES
    ('12:00'::time,'13:00'::time, 20),
    ('18:00'::time,'19:00'::time, 20),
    ('19:00'::time,'20:00'::time, 20)
  ) AS s(start_time, end_time, capacity)
)
INSERT INTO public.delivery_time_slots(restaurant_id, day_of_week, start_time, end_time, capacity, is_active)
SELECT s.restaurant_id, s.day_of_week, s.start_time, s.end_time, s.capacity, s.is_active
FROM slots s
WHERE NOT EXISTS (
  SELECT 1 FROM public.delivery_time_slots t
  WHERE t.restaurant_id=s.restaurant_id
    AND t.day_of_week=s.day_of_week
    AND t.start_time=s.start_time
    AND t.end_time=s.end_time
);

COMMIT;
