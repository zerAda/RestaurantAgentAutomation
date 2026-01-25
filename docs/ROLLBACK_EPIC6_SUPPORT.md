# Rollback — EPIC6 Support (P2)

## 1) Désactiver les features

Mettre les flags à `false` puis redémarrer n8n :

```bash
SUPPORT_ENABLED=false
FAQ_ENABLED=false
ADMIN_WA_CONSOLE_ENABLED=false
```

## 2) Stopper le routage admin WhatsApp

Si vous gardez le workflow W1 mais ne voulez plus de console admin, laissez `ADMIN_WA_CONSOLE_ENABLED=false`.

## 3) Rollback DB

Cette EPIC ajoute uniquement des tables/trigger dédiés :

- `support_tickets`
- `support_ticket_messages`
- `support_assignments`
- `faq_entries` (+ trigger `trg_faq_entries_tsv` + fonction `faq_entries_tsv_update()`)
- templates `_GLOBAL` : `SUPPORT_HANDOFF_ACK` (fr/ar), `FAQ_NO_MATCH` (fr/ar)

### Option A — conserver les tables (recommandé)

Le plus sûr est de **désactiver les flags** et de conserver les tables (aucun impact runtime).

### Option B — supprimer

```sql
BEGIN;

DROP TRIGGER IF EXISTS trg_faq_entries_tsv ON public.faq_entries;
DROP FUNCTION IF EXISTS public.faq_entries_tsv_update();

DROP TABLE IF EXISTS public.support_assignments;
DROP TABLE IF EXISTS public.support_ticket_messages;
DROP TABLE IF EXISTS public.support_tickets;
DROP TABLE IF EXISTS public.faq_entries;

DELETE FROM public.message_templates
WHERE tenant_id='_GLOBAL'
  AND key IN ('SUPPORT_HANDOFF_ACK','FAQ_NO_MATCH');

COMMIT;
```

⚠️ Attention : option B supprime l’historique support.