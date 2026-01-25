# RUNBOOKS

## 0) P0 Security Operations (v3.2.2)

### Token Rotation (api_clients → legacy kill)

**Pre-requisites:**
- All clients migrated to `api_clients` table
- `LEGACY_SHARED_ALLOWED=false` configured

**Procedure:**
```bash
# 1. Verify all active clients
psql -c "SELECT client_id, client_name, tenant_id, is_active FROM api_clients WHERE is_active=true;"

# 2. Check no legacy token usage in last 24h
psql -c "SELECT COUNT(*) FROM security_events WHERE event_type='LEGACY_TOKEN_USED' AND created_at > now() - interval '24 hours';"

# 3. Set kill-switch (if not already)
# In .env: LEGACY_SHARED_ALLOWED=false

# 4. Deploy and monitor
docker compose restart n8n-main n8n-worker

# 5. Monitor for blocked attempts
psql -c "SELECT * FROM security_events WHERE event_type='LEGACY_TOKEN_BLOCKED' ORDER BY created_at DESC LIMIT 10;"
```

### Meta Signature Validation Rollout

**Phase 1: Warn Mode**
```env
META_SIGNATURE_REQUIRED=false
META_APP_SECRET=your_meta_app_secret_here
```

**Phase 2: Monitor**
```sql
SELECT event_type, COUNT(*) 
FROM security_events 
WHERE event_type IN ('WA_SIGNATURE_INVALID', 'WA_SIGNATURE_MISSING') 
  AND created_at > now() - interval '24 hours'
GROUP BY event_type;
```

**Phase 3: Enforce (after validation)**
```env
META_SIGNATURE_REQUIRED=true
```

### Gateway Security Validation
```bash
./scripts/smoke_security_gateway.sh
```

Expected results:
- All ?token= queries → 401
- Authorization header → passes to backend
- Rate limiting active

## 1) Backup / Restore
Voir `docs/BACKUP_RESTORE.md`.

## 2) Scopes (API clients)

### Modèle
- Les tokens **ne donnent accès qu’aux scopes** présents dans `api_clients.scopes`.
- `api_clients.scopes` est un tableau JSON (`jsonb`) de strings.

Exemples :
- `inbound:write`
- `admin:read`, `admin:write`
- `partner:read`, `partner:write`
- `delivery:write`
- `admin:*` (wildcard)

### Ajout/rotation d’un client
1) Créer le token (secret) côté client.
2) Hash sha256 (ne jamais stocker le token en clair) :
```bash
echo -n 'MY_SECRET_TOKEN' | sha256sum | awk '{print $1}'
```
3) Insérer dans DB :
```sql
INSERT INTO api_clients(client_name, token_hash, tenant_id, restaurant_id, scopes)
VALUES ('partner-app', '<sha256hex>', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', '["inbound:write"]'::jsonb);
```
4) Désactiver l’ancien token :
```sql
UPDATE api_clients SET is_active=false WHERE client_id='<id>';
```

### Politique
- Un token générique ne doit **jamais** avoir accès à `/v1/admin/*`.
- Les refus doivent être loggés en `SCOPE_DENY`.

## 3) Incident response (sécurité)

### Symptômes
- Spike de `AUTH_DENY` / `SCOPE_DENY` dans `security_events`
- Erreurs 5xx sur `/healthz`

### Actions rapides
1) Vérifier stack
```bash
docker compose -f docker-compose.hostinger.prod.yml ps
```
2) Logs
```bash
docker compose -f docker-compose.hostinger.prod.yml logs --tail=200 gateway n8n-main n8n-worker postgres redis
```
3) Vérifier DB
```bash
docker compose -f docker-compose.hostinger.prod.yml exec -T postgres sh -lc \
  "psql -U n8n -d n8n -Atc \"SELECT event_type, count(*) FROM security_events WHERE created_at > now() - interval '1 hour' GROUP BY event_type ORDER BY count(*) DESC;\""
```
4) Mitigation
- Désactiver un token compromis (`api_clients.is_active=false`)
- Tighten allowlist IP côté Traefik (`ADMIN_ALLOWED_IPS`)

## 4) QA / CI

### Test harness (local)
```bash
./scripts/test_harness.sh
```

Le harness :
- démarre une stack de test
- applique migrations
- seed fixtures
- importe workflows
- smoke tests + checks DB
- teardown


## Incident Response
See `docs/INCIDENT_RESPONSE_PLAYBOOK.md`.

## Alerting
See `docs/ALERTING.md`.
