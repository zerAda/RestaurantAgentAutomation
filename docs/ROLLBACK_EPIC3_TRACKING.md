# Rollback — EPIC 3 Tracking

## Option 1 — Désactiver l’endpoint admin orders
```sql
UPDATE workflow_entity SET active=false
WHERE name='W12 - ADMIN Orders (List + Timeline)';
```

## Option 2 — Désactiver uniquement le tracking WhatsApp (TRK-001)
```sql
DROP TRIGGER IF EXISTS orders_status_tracking ON public.orders;
DROP FUNCTION IF EXISTS public.trg_orders_status_tracking();
```

## Option 3 — Rollback DB complet (destructif)
```sql
DROP TRIGGER IF EXISTS orders_status_tracking ON public.orders;
DROP TRIGGER IF EXISTS orders_init_tracking ON public.orders;

DROP FUNCTION IF EXISTS public.trg_orders_status_tracking();
DROP FUNCTION IF EXISTS public.trg_orders_init_tracking();
DROP FUNCTION IF EXISTS public.enqueue_wa_order_status(uuid,text,text,text);
DROP FUNCTION IF EXISTS public.build_wa_order_status_payload(uuid,text,text,text);
DROP FUNCTION IF EXISTS public.wa_order_status_text(text,text,uuid,integer,integer,text);
DROP FUNCTION IF EXISTS public.map_order_status_to_customer(text,text);

DROP TABLE IF EXISTS public.order_status_history;

ALTER TABLE public.orders
  DROP COLUMN IF EXISTS last_notified_status,
  DROP COLUMN IF EXISTS last_notified_at;

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS chk_orders_status_valid;
ALTER TABLE public.orders
  ADD CONSTRAINT chk_orders_status_valid
  CHECK (status IN ('NEW','ACCEPTED','IN_PROGRESS','READY','DONE','CANCELLED'));
```
