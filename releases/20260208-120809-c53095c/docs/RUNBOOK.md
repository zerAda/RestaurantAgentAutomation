# RESTO BOT - RUNBOOK PRODUCTION

## Table des matières
1. [Architecture rapide](#architecture-rapide)
2. [Commandes essentielles](#commandes-essentielles)
3. [Healthchecks](#healthchecks)
4. [Incidents courants](#incidents-courants)
5. [Rollback](#rollback)
6. [Monitoring](#monitoring)
7. [Contacts](#contacts)

---

## Architecture rapide

```
Internet
    │
    ▼
┌─────────────────┐
│    Traefik      │ :443 (TLS)
│  (reverse proxy)│
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐  ┌──────────┐
│ Nginx │  │ n8n UI   │
│ :8080 │  │ (console)│
└───┬───┘  └──────────┘
    │
    ▼
┌──────────────────┐
│  n8n-main:5678   │◄──────┐
│  (workflows)     │       │
└────────┬─────────┘       │
         │            ┌────┴────┐
         │            │  Redis  │
         ▼            │ (queue) │
┌──────────────────┐  └─────────┘
│   n8n-worker     │
│ (async execution)│
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   PostgreSQL     │
│   (data + n8n)   │
└──────────────────┘
```

---

## Commandes essentielles

### Démarrage / Arrêt

```bash
# Démarrer tous les services
docker compose -f docker-compose.hostinger.prod.yml up -d

# Arrêter tous les services
docker compose -f docker-compose.hostinger.prod.yml down

# Redémarrer un service spécifique
docker compose -f docker-compose.hostinger.prod.yml restart n8n-main

# Voir les logs
docker compose -f docker-compose.hostinger.prod.yml logs -f --tail=100

# Logs d'un service spécifique
docker compose -f docker-compose.hostinger.prod.yml logs -f n8n-main
```

### Vérification de l'état

```bash
# État de tous les containers
docker compose -f docker-compose.hostinger.prod.yml ps

# Ressources utilisées
docker stats

# Espace disque
df -h
```

### Smoke tests

```bash
# Tests rapides
./scripts/smoke.sh

# Tests Meta complets
./scripts/smoke_meta.sh
```

### Database Migrations (P0-01)

**Automatic migration on startup:**
The `db-migrate` service runs automatically on each deployment and applies any pending migrations.
n8n-main and n8n-worker will NOT start until migrations complete successfully.

```bash
# Check migration status
docker compose -f docker-compose.hostinger.prod.yml logs db-migrate

# Manual migration (if needed)
./scripts/db_migrate_all.sh

# Dry run (see what would be applied)
./scripts/db_migrate_all.sh --dry-run

# Check applied migrations in DB
docker compose -f docker-compose.hostinger.prod.yml exec postgres \
  psql -U n8n -d n8n -c "SELECT filename, applied_at FROM schema_migrations ORDER BY applied_at DESC LIMIT 10"
```

**Migration files location:** `db/migrations/`

**How it works:**
1. **Fresh install**: `docker-entrypoint-initdb.d` runs `00_bootstrap.sql` + `01_apply_migrations.sh`
2. **Upgrades**: `db-migrate` service applies pending migrations before n8n starts
3. **Fail-fast**: If any migration fails, deployment stops (n8n won't start with incomplete schema)

---

## Healthchecks

### Endpoints à vérifier

| Service | URL | Attendu |
|---------|-----|---------|
| Gateway | `https://api.{DOMAIN}/healthz` | `ok` |
| n8n UI | `https://console.{DOMAIN}` | Page login |

### Script de vérification

```bash
# Vérifier que tout répond
curl -sf https://api.yourdomain.com/healthz && echo "✅ Gateway OK"
curl -sf -o /dev/null https://console.yourdomain.com && echo "✅ Console OK"
```

### Vérifier les webhooks Meta

```bash
# Test GET verify WhatsApp
curl "https://api.yourdomain.com/v1/inbound/whatsapp?hub.mode=subscribe&hub.verify_token=YOUR_TOKEN&hub.challenge=test123"
# Doit retourner: test123

# Même chose pour Instagram et Messenger
```

---

## Incidents courants

### 1. Webhooks Meta ne répondent pas (timeout)

**Symptômes**: Meta Developer Portal affiche des erreurs de webhook

**Diagnostic**:
```bash
# Vérifier que les containers tournent
docker compose -f docker-compose.hostinger.prod.yml ps

# Vérifier les logs n8n
docker compose -f docker-compose.hostinger.prod.yml logs --tail=50 n8n-main

# Vérifier que le workflow est actif dans n8n UI
```

**Solution**:
1. Vérifier que le workflow W0_META_VERIFY_UNIFIED est **activé** dans n8n
2. Vérifier que META_VERIFY_TOKEN dans .env correspond à celui configuré dans Meta
3. Redémarrer n8n si nécessaire

---

### 2. Messages reçus mais pas de réponse

**Symptômes**: Les messages arrivent dans n8n mais l'utilisateur ne reçoit pas de réponse

**Diagnostic**:
```bash
# Vérifier les exécutions échouées dans n8n UI
# Ou via la DB:
docker compose -f docker-compose.hostinger.prod.yml exec postgres \
  psql -U n8n -d n8n -c "SELECT id, workflow_name, status FROM execution_entity WHERE status = 'error' ORDER BY id DESC LIMIT 10;"

# Vérifier les erreurs outbound
docker compose -f docker-compose.hostinger.prod.yml exec postgres \
  psql -U n8n -d n8n -c "SELECT * FROM outbound_messages WHERE status IN ('RETRY','DLQ') ORDER BY created_at DESC LIMIT 10;"
```

**Solution**:
1. Vérifier les tokens Meta (WA_API_TOKEN, IG_API_TOKEN, MSG_API_TOKEN)
2. Vérifier que les IDs (WA_PHONE_NUMBER_ID, etc.) sont corrects
3. Vérifier les permissions de l'app Meta

---

### 3. Erreurs de signature (403)

**Symptômes**: Les webhooks retournent 403 ou les security_events montrent "SIGNATURE_INVALID"

**Diagnostic**:
```bash
# Voir les événements de sécurité récents
docker compose -f docker-compose.hostinger.prod.yml exec postgres \
  psql -U n8n -d n8n -c "SELECT event_type, COUNT(*) FROM security_events WHERE created_at > now() - interval '1 hour' GROUP BY event_type;"
```

**Solution**:
1. Vérifier que META_APP_SECRET est correct (doit correspondre à l'app Meta)
2. Si en test, mettre `META_SIGNATURE_REQUIRED=off` temporairement
3. Vérifier que le rawBody est bien passé (option activée dans le webhook)

---

### 4. Rate limiting / Messages rejetés

**Symptômes**: Messages acceptés mais dropés (security_events avec RATE_LIMIT)

**Diagnostic**:
```bash
docker compose -f docker-compose.hostinger.prod.yml exec postgres \
  psql -U n8n -d n8n -c "SELECT conversation_key, COUNT(*) FROM inbound_messages WHERE received_at > now() - interval '1 minute' GROUP BY conversation_key HAVING COUNT(*) > 5;"
```

**Solution**:
1. Augmenter RATE_LIMIT_PER_30S dans .env si légitime
2. Vérifier si c'est une attaque (même IP, patterns suspects)
3. Mettre en quarantaine si nécessaire

---

### 5. Base de données pleine / Performances

**Symptômes**: Requêtes lentes, erreurs disk full

**Diagnostic**:
```bash
# Taille des tables
docker compose -f docker-compose.hostinger.prod.yml exec postgres \
  psql -U n8n -d n8n -c "SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;"
```

**Solution**:
1. Lancer le script de nettoyage: `./scripts/db_cleanup.sh`
2. Purger les vieilles exécutions n8n
3. Augmenter le disque si nécessaire

---

## Rollback

### Rollback d'un workflow

```bash
# Les workflows sont dans /opt/resto/workflows
# Ils ont des backups .bak si modifiés

# Pour restaurer:
cp workflows/W1_IN_WA.json.bak workflows/W1_IN_WA.json

# Puis réimporter dans n8n UI ou via API
```

### Rollback complet

```bash
# Si déploiement récent causant problèmes:
cd /opt/resto

# Revenir au commit précédent
git checkout HEAD~1

# Redémarrer
docker compose -f docker-compose.hostinger.prod.yml down
docker compose -f docker-compose.hostinger.prod.yml up -d
```

### Rollback de la DB

```bash
# Si backup disponible:
./scripts/restore_postgres.sh /path/to/backup.sql.gz
```

---

## Monitoring

### Métriques clés à surveiller

| Métrique | Seuil alerte | Commande |
|----------|--------------|----------|
| CPU n8n | > 80% | `docker stats n8n-main` |
| Mémoire | > 85% | `docker stats` |
| Disk | > 90% | `df -h` |
| Queue Redis | > 1000 | Voir n8n UI |
| Erreurs/heure | > 10 | Query security_events |

### Alertes recommandées

Configurer des alertes pour:
- Container down
- Healthcheck fail
- Erreurs de signature (attaque potentielle)
- Rate limit excessif
- Disk > 90%

---

## Variables d'environnement critiques

| Variable | Description | Requis |
|----------|-------------|--------|
| `META_VERIFY_TOKEN` | Token pour webhook verify | ✅ |
| `META_APP_SECRET` | Secret pour signature HMAC | ✅ Prod |
| `META_SIGNATURE_REQUIRED` | Mode signature: `off`/`warn`/`enforce` | ✅ Prod (`enforce`) |
| `WA_API_TOKEN` | Token WhatsApp Cloud API | ✅ |
| `WA_PHONE_NUMBER_ID` | ID du numéro WhatsApp | ✅ |
| `REPLAY_CHECK_ENABLED` | Protection anti-replay | Recommandé |
| `REDIS_URL` | URL Redis pour idempotence | Recommandé |

### Note sur META_SIGNATURE_REQUIRED

Quand cette variable est `warn` ou `enforce`, une signature Meta valide sert d'authentification pour les webhooks inbound:
- `authMode = 'meta_signature'` au lieu de `api_client` ou `legacy_shared`
- Ceci est **nécessaire** car Meta n'envoie PAS de header `x-api-token` personnalisé
- Le scope `inbound:write` est automatiquement accordé avec signature valide

---

## Dead Letter Queue (DLQ)

### Vérifier la DLQ

```bash
# Nombre de messages en DLQ
docker compose -f docker-compose.hostinger.prod.yml exec postgres \
  psql -U n8n -d n8n -c "SELECT COUNT(*) FROM outbound_messages WHERE status = 'DLQ';"

# Détails des messages DLQ
docker compose -f docker-compose.hostinger.prod.yml exec postgres \
  psql -U n8n -d n8n -c "SELECT id, channel, msg_id, error_message, retry_count, created_at FROM outbound_messages WHERE status = 'DLQ' ORDER BY created_at DESC LIMIT 10;"
```

### Replay DLQ (API)

```bash
# Dry run - voir ce qui serait rejoué
curl -X POST "https://api.yourdomain.com/v1/admin/dlq/replay" \
  -H "Content-Type: application/json" \
  -H "x-api-token: YOUR_ADMIN_TOKEN" \
  -d '{"dry_run": true, "max_messages": 10}'

# Replay effectif
curl -X POST "https://api.yourdomain.com/v1/admin/dlq/replay" \
  -H "Content-Type: application/json" \
  -H "x-api-token: YOUR_ADMIN_TOKEN" \
  -d '{"max_messages": 10}'

# Replay par channel
curl -X POST "https://api.yourdomain.com/v1/admin/dlq/replay" \
  -H "Content-Type: application/json" \
  -H "x-api-token: YOUR_ADMIN_TOKEN" \
  -d '{"channel": "whatsapp", "max_messages": 50}'
```

### Replay DLQ (Manuel SQL)

```bash
# Remettre tous les messages DLQ en RETRY
docker compose -f docker-compose.hostinger.prod.yml exec postgres \
  psql -U n8n -d n8n -c "UPDATE outbound_messages SET status = 'RETRY', next_retry_at = NOW() WHERE status = 'DLQ';"
```

### Alertes DLQ

Le workflow `W8_DLQ_HANDLER` vérifie la DLQ toutes les 5 minutes:
- Si `DLQ_ALERT_THRESHOLD` est dépassé, une alerte est envoyée
- Configure `ALERT_WEBHOOK_URL` pour recevoir les alertes (Slack, Discord, etc.)

---

## Contacts

| Rôle | Contact |
|------|---------|
| Admin système | [À compléter] |
| Dev principal | [À compléter] |
| Support Meta | https://developers.facebook.com/support |

---

## CI/CD Pipeline

### GitHub Actions

Le pipeline CI est défini dans `.github/workflows/ci.yml`:

| Job | Description | Trigger |
|-----|-------------|---------|
| lint | Validation JSON, bash, nginx | Push/PR |
| unit-tests | Tests Python (contracts, l10n) | Push/PR |
| integration-tests | Tests avec Postgres/Redis | Push/PR |
| docker-build | Validation docker-compose | Push/PR |
| security-scan | Scan secrets, headers nginx | Push/PR |
| deploy-staging | Déploiement staging | Push develop |
| deploy-production | Déploiement production | Push main |

### Exécution locale des tests

```bash
# Batterie de tests (100 tests)
./scripts/test_battery.sh

# Tests E2E complets
./scripts/test_e2e.sh --env local --verbose

# Tests Meta spécifiques
./scripts/smoke_meta.sh

# Tests rapides (smoke)
./scripts/smoke.sh
```

### GitLab CI

Alternative GitLab dans `.gitlab-ci.yml` avec les mêmes jobs.

---

## Checklist Go-Live

- [ ] META_VERIFY_TOKEN configuré et testé
- [ ] META_APP_SECRET configuré
- [ ] META_SIGNATURE_REQUIRED=enforce
- [ ] Webhooks configurés dans Meta Developer Portal
- [ ] GET verify réussi sur les 3 canaux
- [ ] Test message inbound → outbound sur chaque canal
- [ ] Backup DB configuré et testé
- [ ] Monitoring/alertes configurés
- [ ] IP allowlist pour console admin
- [ ] SSL/TLS valide (Let's Encrypt)
- [ ] Smoke tests passent

---

*Dernière mise à jour: 2026-01-28*
