# ROLLBACK — RESTO BOT v3.1 (patch 2026-01-22)

## 1) Rollback applicatif (workflows / config)
1. Stop la stack (prod)
   ```bash
   docker compose -f docker-compose.hostinger.prod.yml down
   ```
2. Restaurer l’archive précédente (avant patch) ou revenir au commit/tag précédent.
3. Redémarrer :
   ```bash
   docker compose -f docker-compose.hostinger.prod.yml up -d
   ```

### Rollback ciblé SYSTEM-3 (scopes/admin)

#### Option 1 — Mitigation “safe” sans rollback (recommandé)
Si des appels admin/partner sont bloqués en prod :
- **ne désactive pas** l’enforcement scopes.
- Corrige plutôt les scopes du client concerné :

```sql
-- Exemple : donner admin:read à un client existant
UPDATE api_clients
   SET scopes = (coalesce(scopes,'[]'::jsonb) || '"admin:read"'::jsonb)
 WHERE client_name = 'partner-app'
   AND (scopes ? 'admin:read') IS FALSE;
```

#### Option 2 — Désactiver seulement l’endpoint admin de test
Le workflow `W9 - ADMIN Ping (Scopes Enforced)` est **démonstrateur** (utile pour valider 403/200).
Vous pouvez le rendre inactif sans impacter l’inbound :

```sql
UPDATE workflow_entity SET active=false
WHERE name='W9 - ADMIN Ping (Scopes Enforced)';
```

#### Option 3 — Rollback workflows SYSTEM-3
Revenir à la version précédente des workflows W1/W2/W3 (sans enforcement scope) **ré-ouvre une surface de risque**.
Si vous devez le faire en urgence :
1) Restaurer les fichiers `workflows/W1_IN_WA.json`, `W2_IN_IG.json`, `W3_IN_MSG.json` depuis le tag/commit précédent.
2) Réimporter dans n8n.
3) Vérifier que les refus auth logguent toujours `AUTH_DENY`.

### Désactiver uniquement la rétention (sans rollback global)
- Dans n8n, laisser **W8 - OPS** inactif (ou désactiver le node “R1 - Retention Purge”).
- Optionnel : fixer `RETENTION_DRY_RUN=true` (aucune suppression) et/ou augmenter les `RETENTION_DAYS_*`.

### Rollback EPIC2 (Livraison)
Le rollback EPIC2 est documenté dans `docs/ROLLBACK_EPIC2_DELIVERY.md`.
Recommandé : désactiver les flags (aucune régression checkout legacy).

## 2) Rollback DB
Ce patch **n’impose pas de migration destructive**.
- Les changements DB sont :
  - correction d’ordre dans `db/bootstrap.sql` (impact uniquement fresh install)
  - migrations idempotentes (additive)
  - P1 DB : indexes + helpers retention (`ops.*`) + enum `security_event_type_enum`
  - SYSTEM-3 : index GIN `api_clients.scopes` + table `admin_audit_log`

### Option A — rollback sans toucher la DB (recommandé)
- Revenir aux workflows/config précédents suffit (les nouvelles valeurs `AUTH_DENY`/`AUDIO_URL_BLOCKED` sont uniquement des labels d’événements).

### Option B — rollback P1 DB (indexes/retention/constraints)
> À utiliser seulement si vous devez revenir à l’état DB pré‑P1.

1) **Supprimer la contrainte enum** (repasse en TEXT) :

```sql
-- 1) security_events.event_type -> TEXT
ALTER TABLE public.security_events
  ALTER COLUMN event_type TYPE text
  USING event_type::text;

-- 2) drop enum + ref table (optional)
DROP TYPE IF EXISTS security_event_type_enum;
DROP TABLE IF EXISTS ops.security_event_types;
```

2) **Supprimer les helpers de rétention** (optionnel) :

```sql
DROP FUNCTION IF EXISTS ops.purge_outbound_sent_batch(timestamptz, integer, boolean);
DROP FUNCTION IF EXISTS ops.purge_table_batch(text, timestamptz, integer, boolean);
DROP FUNCTION IF EXISTS ops.create_index_if_cols_exist(text, text, text, text[]);
DROP TABLE IF EXISTS ops.retention_runs;
```

3) **Supprimer les indexes ajoutés par P1** (optionnel) :

```sql
DROP INDEX IF EXISTS public.idx_inbound_messages_received_at;
DROP INDEX IF EXISTS public.idx_security_events_tenant_created_at;
DROP INDEX IF EXISTS public.idx_security_events_event_type_created_at;
DROP INDEX IF EXISTS public.idx_outbound_messages_sent_at;
DROP INDEX IF EXISTS public.idx_workflow_errors_created_at;
DROP INDEX IF EXISTS public.idx_workflow_errors_workflow_name_created_at;
```

4) Re-run smoke tests.

### Option D — rollback SYSTEM-3 DB (scopes index + admin audit)
> À utiliser seulement si vous devez revenir à l’état DB pré‑SYSTEM‑3.

```sql
DROP INDEX IF EXISTS public.idx_api_clients_scopes_gin;
DROP TABLE IF EXISTS public.admin_audit_log;
```

### Option C — rollback complet DB (si nécessaire)
1. Restore snapshot Postgres (dump/volume) :
   ```bash
   # exemple : restore volume depuis backup
   docker compose -f docker-compose.hostinger.prod.yml down
   # restaurer /var/lib/docker/volumes/... ou dump pg
   docker compose -f docker-compose.hostinger.prod.yml up -d
   ```
2. Vérifier :
   - `SELECT count(*) FROM tenants;`
   - Webhooks inbound OK

## 3) Points de vigilance
- Si un client legacy utilisait `?token=...`, il faudra (en rollback ou non) :
  - soit réactiver `ALLOW_QUERY_TOKEN=true`
  - soit migrer le client vers header `x-webhook-token` / `Authorization: Bearer`

## EPIC3 — Tracking
See `docs/ROLLBACK_EPIC3_TRACKING.md`.
## P0-OPS-01 / P0-OPS-02 / P0-OPS-03 Rollback
- Disable external SLO alerts: set `ALERT_SLO_ENABLED=false` **or** leave `ALERT_WEBHOOK_URL` empty.
- Remove cooldown state (optional): revert migration `db/migrations/2026-01-23_p0_ops_alert_kv.sql` (safe to keep even if unused).
- Revert outbox idempotency: restore previous version of `workflows/W8_OPS.json` (node `O3 - Send Outbox`).
- Disable Meta webhook verify: set `META_VERIFY_ENABLED=false` **or** deactivate `W0 - Meta Webhook Verify (WhatsApp)`.
- Disable Meta signature enforcement: set `META_SIGNATURE_REQUIRED=false` (keeps logging but does not fail-close).
- Re-enable legacy shared token (if you must during cutover): set `LEGACY_SHARED_ALLOWED=true` temporarily and revert when clients are migrated.
