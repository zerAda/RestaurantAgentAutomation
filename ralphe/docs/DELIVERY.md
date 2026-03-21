# EPIC2 — Livraison

Implémentation des tickets **DEL-001/002/003** (P2) :
- Zones de livraison (wilaya/commune) + frais + ETA
- Quote (validation zone + calcul frais)
- Clarification d’adresse (state machine)
- Créneaux (time slots) + réservation/capacité

> Backward compatible : si `DELIVERY_ENABLED=false`, l’ancien comportement reste inchangé.

---

## Feature flags

- `DELIVERY_ENABLED` (default: `false`) : active les parcours livraison + endpoints.
- `DELIVERY_SLOTS_ENABLED` (default: `false`) : propose et réserve des créneaux.
- `DELIVERY_ADDRESS_CLARIFY` (default: `true`) : active les demandes de précisions (table + max attempts).

Env :
- `DELIVERY_DEFAULT_ETA_MIN`, `DELIVERY_DEFAULT_ETA_MAX` : valeurs fallback si zone ne renseigne pas l’ETA.
- `DELIVERY_FEE_MIN_CENTS` : garde-fou pour ne jamais descendre sous ce minimum.
- `DELIVERY_ADDRESS_MAX_ATTEMPTS` (default: 3) : max de tentatives de clarification.

---

## DB — Schéma

Migration : `db/migrations/2026-01-22_p2_epic2_delivery.sql`

Tables :
- `delivery_zones(restaurant_id, wilaya, commune, fee_base_cents, min_order_cents, eta_min, eta_max, is_active)`
- `delivery_fee_rules(restaurant_id, start_time/end_time, surcharge_cents, free_delivery_threshold_cents, is_active)`
- `delivery_time_slots(restaurant_id, day_of_week, start_time/end_time, capacity, is_active)`
- `delivery_slot_reservations(order_id, slot_id)`
- `address_clarification_requests(order_id, missing_fields, attempts, status)`

Fonctions :
- `delivery_quote(restaurant_id, wilaya, commune, total_cents)` → retourne `{fee_base, surcharge, final_fee, eta, reason}`
- `reserve_delivery_slot(order_id, slot_id)` → réserve un créneau si capacité OK.

Seed (replay-safe) : `db/seed_delivery_demo.sql`.

---

## Endpoints (Gateway → n8n)

### Customer

`POST /v1/customer/delivery/quote`

Body JSON :
```json
{
  "wilaya": "Alger",
  "commune": "Hydra",
  "total_cents": 2500,
  "slot_id": "<optional>"
}
```

Réponse (succès) :
```json
{
  "ok": true,
  "fee": {"base_cents": 300, "surcharge_cents": 0, "final_cents": 300},
  "min_order_cents": 1500,
  "eta": {"min": 35, "max": 55},
  "reason": "OK",
  "slots": [ {"slot_id": "...", "start": "18:00", "end": "19:00", "remaining": 12} ]
}
```

Réponse (zone non trouvée / inactive / min order) :
- `ok=false` + `code` ∈ `DELIVERY_ZONE_NOT_FOUND | DELIVERY_ZONE_INACTIVE | DELIVERY_MIN_ORDER`
- message FR + suggestion de clarification.

Auth : token via `x-webhook-token` (API clients table) scope requis : `delivery:quote`.

Workflow : `workflows/W10_CUSTOMER_DELIVERY_QUOTE.json`

### Admin

`GET /v1/admin/delivery/zones` → liste zones.

`POST /v1/admin/delivery/zones` → upsert zone (par wilaya/commune).

Body JSON (POST) :
```json
{
  "wilaya": "Alger",
  "commune": "Hydra",
  "fee_base_cents": 300,
  "min_order_cents": 1500,
  "eta_min": 35,
  "eta_max": 55,
  "is_active": true
}
```

Auth : token via `x-webhook-token` scope requis : `admin:write`.

Workflow : `workflows/W11_ADMIN_DELIVERY_ZONES.json`

#### Pilotage WhatsApp (sans UI)

La console admin WhatsApp (`workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json`) supporte aussi la gestion des zones :
- `!zone list`
- `!zone set <wilaya> ; <commune> ; <fee_cents> ; <min_cents> ; <eta_min> ; <eta_max> ; <active:true|false>`
- `!zone del <wilaya> ; <commune>`

Règle langue : si le message admin contient des caractères arabes et `STRICT_AR_OUT=true`, la réponse est renvoyée en arabe.

> Auto-locale : si le message admin contient de l’arabe et `STRICT_AR_OUT=true`, la réponse est renvoyée en arabe.

---

## Workflows impactés

- **W4_CORE** : collecte du mode (sur place/à emporter/livraison) + collecte d’adresse si livraison + calcul quote + proposition de créneau si activé.
- **W8_OPS** : inchangé fonctionnellement ; monitoring outbox déjà en place. Les events delivery sont loggés dans `security_events` pour analyse.

---

## State machine — Clarification adresse (DEL-002)

- Si adresse livraison incomplète : réponse de clarification + incrément tentatives.
- Si tentatives > `DELIVERY_ADDRESS_MAX_ATTEMPTS` : fallback / handoff humain (ex: ticket SUP-001).

Templates :
- `templates/delivery/clarify_fr.txt`
- `templates/delivery/clarify_ar.txt`
- `templates/delivery/clarify_darja.txt`

---

## Rollback

- DB : exécuter `docs/ROLLBACK_EPIC2_DELIVERY.md` (drop tables/functions EPIC2).
- Code : désactiver flags : `DELIVERY_ENABLED=false` (ancien checkout inchangé).

---

## Test plan

Voir : `TEST_REPORT.md` (smoke tests via `scripts/test_harness.sh`).
