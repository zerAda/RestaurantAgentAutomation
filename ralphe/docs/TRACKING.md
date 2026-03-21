# EPIC 3 — Tracking (P2)

## TRK-001 — Tracking commande client (WhatsApp)

### Statuts client
Le client reçoit 1 message WhatsApp par changement de statut (idempotent) :
- `CONFIRMED`, `PREPARING`, `READY`, `OUT_FOR_DELIVERY`, `DELIVERED`, `CANCELLED`

Mapping DB : `public.map_order_status_to_customer(internal_status, service_mode)`.

### Mécanisme
- Trigger DB : `orders_status_tracking` (BEFORE UPDATE OF `orders.status`)
- Timeline : insert dans `public.order_status_history`
- Enqueue outbox : `public.enqueue_wa_order_status()`
- Idempotence : `outbound_messages.dedupe_key = order_status:{order_id}:{CUSTOMER_STATUS}`
- Anti-spam : fenêtre 30s, ajuste `outbound_messages.next_retry_at` si spam

Colonnes :
- `orders.last_notified_status`
- `orders.last_notified_at`

### Payload outbox (compatible W8_OPS)
`outbound_messages.payload_json` contient :
```json
{
  "channel": "whatsapp",
  "to": "<user_id>",
  "restaurantId": "<restaurant_id>",
  "text": "...",
  "buttons": []
}
```

### Templates
Référence (localisation) :
- `templates/whatsapp/WA_ORDER_STATUS_templates.fr.json`
- `templates/whatsapp/WA_ORDER_STATUS_templates.ar.json`

Le rendu effectif est produit par `public.wa_order_status_text()`.

---

## TRK-002 — Tracking admin (console)

Endpoint :
- `GET /v1/admin/orders?status=&date_from=&date_to=&limit=&include_timeline=1&export=csv`

Workflow : `workflows/W12_ADMIN_ORDERS.json`

### RBAC
Scope requis : `admin:read`.

### DB
- Index : `idx_orders_status_created` sur `orders(status, created_at)`
- Timeline : `order_status_history`

### Réponse
- JSON : `{ ok:true, count, orders:[...]} `
- CSV : `export=csv`
