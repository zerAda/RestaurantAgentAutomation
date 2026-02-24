# Rollback EPIC2 — Livraison

## Option 1 — Rollback “safe” (recommandé)

Désactivez les flags (aucun impact sur l’ancien checkout) :

```bash
DELIVERY_ENABLED=false
DELIVERY_SLOTS_ENABLED=false
DELIVERY_ADDRESS_CLARIFY=false
```

Les tables et fonctions EPIC2 peuvent rester en place : elles ne sont plus utilisées lorsque `DELIVERY_ENABLED=false`.

---

## Option 2 — Rollback DB (destructif)

⚠️ Supprime les données livraison (zones, règles, créneaux, demandes de clarification).

```sql
BEGIN;

-- Drop reservations first (FK dependencies)
DROP TABLE IF EXISTS public.delivery_slot_reservations;

-- Drop tables
DROP TABLE IF EXISTS public.address_clarification_requests;
DROP TABLE IF EXISTS public.delivery_time_slots;
DROP TABLE IF EXISTS public.delivery_fee_rules;
DROP TABLE IF EXISTS public.delivery_zones;

-- Drop functions
DROP FUNCTION IF EXISTS public.reserve_delivery_slot(uuid, uuid);
DROP FUNCTION IF EXISTS public.delivery_quote(uuid, text, text, int, timestamptz);

COMMIT;
```

---

## Option 3 — Rollback endpoints/workflows uniquement

Désactiver les workflows API (quote/admin zones) :

```sql
UPDATE workflow_entity SET active=false
WHERE name in (
  'W10 - CUSTOMER Delivery Quote (Zone + Fee + ETA)',
  'W11 - ADMIN Delivery Zones (CRUD)'
);
```
