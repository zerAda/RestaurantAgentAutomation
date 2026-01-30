# CHANGELOG - Resto Bot Production Patch

## Version 3.3.1 - Meta Auth Fix (2026-01-29)

### 🔴 P0 - Corrections Critiques

#### P0-04: Auth Meta Signature pour IG/MSG
- **CORRECTION CRITIQUE**: Meta n'envoie PAS `x-api-token` sur les webhooks
- **W1/W2/W3**: Nouveau mode d'auth `meta_signature` quand signature valide
- Auth inbound = signature Meta (quand `META_SIGNATURE_REQUIRED=warn|enforce`)
- Token auth réservé aux appels internes/admin
- Fallback: legacy_shared token (si `LEGACY_SHARED_ALLOWED=true`)

#### P0-06: Configuration Redis pour idempotence
- **NOUVEAU**: `docs/REDIS_SETUP.md` - Guide complet Redis
- Variables Redis ajoutées: `REDIS_URL`, `DEDUPE_TTL_SEC`, `RL_MAX_PER_30S`
- Schema de clés: `ralphe:dedupe:*`, `ralphe:rl:*`, `ralphe:outbox:*`, `ralphe:dlq`
- W1/W2/W3: Préparation des clés Redis dans `_sec.redisDedupeKey` et `_sec.redisRateLimitKey`
- PostgreSQL reste en fallback si Redis non configuré

### 🟡 P1 - Tests & Observabilité

#### P1-02: Batterie de tests complète (100 tests)
- **NOUVEAU**: `scripts/test_battery.sh` - 100 tests automatisés
- 10 sections: healthcheck, GET verify, POST inbound, auth, contracts, anti-replay, idempotency, hardening, correlation, localization
- Options: `--quick` pour skip tests lents, `--section N` pour section spécifique
- Compatible CI/CD avec codes de sortie appropriés

#### P1-03: Redis Helper Workflow
- **NOUVEAU**: `workflows/W0_REDIS_HELPER.json`
- Opérations Redis: SET NX (dedupe), INCR (rate-limit)
- Peut être appelé comme sub-workflow par W1/W2/W3
- Fallback gracieux si Redis non disponible

#### P1-04: DLQ Handler & Replay
- **NOUVEAU**: `workflows/W8_DLQ_HANDLER.json` - Monitoring DLQ toutes les 5 min
- **NOUVEAU**: `workflows/W8_DLQ_REPLAY.json` - API replay manuel
- Endpoint: `POST /v1/admin/dlq/replay` (scope admin requis)
- Alertes webhook si seuil dépassé (`DLQ_ALERT_THRESHOLD`)
- Documentation dans `docs/RUNBOOK.md`

#### P1-06: Structured Logging + Correlation Propagation
- **NOUVEAU**: Logs structurés JSON avec `correlation_id` pour traçabilité end-to-end
- **NOUVEAU**: `db/migrations/2026-01-30_p1_06_structured_logging.sql` - Schema logging
  - Table `structured_logs` pour logs centralisés
  - Fonction `log_structured()` pour insertion depuis workflows
  - Vue `v_request_trace` pour tracer une requête complète
- **NOUVEAU**: Colonnes `correlation_id` ajoutées à: `security_events`, `workflow_errors`, `outbound_messages`, `inbound_messages`
- **W1/W2/W3**: `correlation_id` généré au début (header ou UUID)
- **W5/W6/W7**: Propagation du `correlation_id` dans outbox et DLQ
- **ENV**: Nouvelles variables:
  - `LOG_LEVEL` (DEBUG|INFO|WARN|ERROR)
  - `LOG_STRUCTURED` (true|false)
  - `LOG_MASK_PATTERNS` (patterns à masquer: token, password, secret...)
  - `CORRELATION_ID_HEADER` (header à utiliser, défaut: x-correlation-id)
- **Masquage secrets**: Tokens et credentials masqués automatiquement dans les logs
- **NOUVEAU**: `scripts/test_p106_logging.sh` - Tests de validation

### 🟢 P2 - Fonctionnalités

#### P2-01: FR/AR/Darija Auto-detect + LANG Command
- **NOUVEAU**: Support Darija comme locale distinct (fr, ar, darija)
- **NOUVEAU**: `db/migrations/2026-01-30_p2_01_darija_locale.sql`
  - Table `darija_patterns` pour détection par mots-clés
  - Fonction `detect_darija()` pour détection automatique
  - 20+ templates Darija (CORE, Support, Order Status, Delivery)
  - Mise à jour contrainte locale pour inclure 'darija'
- **W4_CORE**: Détection automatique:
  - Message en script arabe → réponse en arabe
  - Message en Darija (latin) → réponse en Darija
  - Message en français → réponse en français
  - Autre langue → réponse en français (défaut)
- **LANG Command**: `LANG FR`, `LANG AR`, `LANG DARIJA` (ou `LANG DZ`)
- **Patterns Darija**: chno kayn, wakha, kml, salam, bghit, nchouf, etc.
- **NOUVEAU**: `scripts/test_p201_l10n.sh` - Tests de validation

#### P2-02: Tests End-to-End
- **NOUVEAU**: `scripts/test_e2e.sh` - Tests E2E complets
- 8 scénarios: WA flow, IG flow, MSG flow, conversation, security, verify, admin, perf
- Options: `--env local|staging|prod`, `--verbose`
- Vérification DB optionnelle avec `DB_URL`

#### P2-03: Pipeline CI/CD
- **NOUVEAU**: `.github/workflows/ci.yml` - GitHub Actions
- **NOUVEAU**: `.gitlab-ci.yml` - GitLab CI
- 6 jobs: lint, unit-tests, integration-tests, docker-build, security-scan, deploy
- Déploiement staging (develop) et production (main)
- Smoke tests post-déploiement

---

## Version 3.3.0 - Production Ready (2026-01-28)

### 🔴 P0 - Corrections Critiques Meta/Sécurité

#### P0-01: Webhook GET Verify unifié
- **NOUVEAU**: Workflow `W0_META_VERIFY_UNIFIED.json` pour les 3 canaux
- Supporte WhatsApp, Instagram, Messenger sur un seul workflow
- Comparaison timing-safe du token de vérification
- Retourne le challenge en texte brut (requis par Meta)

#### P0-02/03/04/05: Sécurité Inbound
- **W2_IN_IG.json**: Ajout `rawBody: true` + validation signature X-Hub-Signature-256
- **W3_IN_MSG.json**: Ajout `rawBody: true` + validation signature X-Hub-Signature-256
- **W1/W2/W3**: Réponse minimale `{status, channel, msg_id, correlation_id}` (plus de fuite de données)
- Nouvelle variable: `META_SIGNATURE_REQUIRED` (off/warn/enforce)

#### P0-06: Hardening Gateway nginx
- Limites de taille: `client_max_body_size 1m`
- Timeouts stricts: `proxy_connect_timeout 5s`, `proxy_read_timeout 30s`
- Restriction méthodes: GET/POST uniquement sur inbound
- Validation Content-Type: JSON obligatoire sur POST
- Headers sécurité: X-Content-Type-Options, X-Frame-Options, etc.
- Limite connexions par IP

#### P0-07: Outbound Meta API réel
- **W5_OUT_WA.json**: Support Meta Cloud API complet
  - Format messaging_product WhatsApp
  - Templates avec paramètres
  - Messages interactifs (boutons)
  - Retry avec backoff exponentiel
  - Gestion 429/5xx
- **W6_OUT_IG.json**: Support Meta Graph API Instagram
  - Quick replies
  - Retry avec backoff
- **W7_OUT_MSG.json**: Support Meta Send API Messenger
  - Button templates
  - Retry avec backoff
- Nouvelles variables: `WA_PHONE_NUMBER_ID`, `IG_PAGE_ID`, `MSG_PAGE_ID`

#### P0-08: Anti-replay protection
- Validation timestamp dans W1/W2/W3
- Fenêtre configurable: `REPLAY_WINDOW_SECONDS` (défaut: 300s)
- Rejet des messages trop vieux ou avec timestamp futur
- Nouvelles variables: `REPLAY_CHECK_ENABLED`, `REPLAY_WINDOW_SECONDS`

#### P0-09: Smoke tests Meta
- **NOUVEAU**: Script `scripts/smoke_meta.sh`
- Tests GET verify sur 3 canaux
- Tests signature valide/invalide
- Tests anti-replay
- Tests hardening gateway

### 🟡 P1 - Stabilité & Observabilité

#### P1-01: Correlation ID
- Génération UUID à l'entrée de chaque requête
- Propagation dans tous les workflows
- Inclus dans les réponses HTTP
- Support header `X-Correlation-Id` entrant

#### P1-07: Documentation Runbook
- **NOUVEAU**: `docs/RUNBOOK.md`
- Architecture rapide
- Commandes essentielles
- Diagnostic incidents courants
- Procédures de rollback
- Checklist go-live

### 🟢 P2 - Produit

#### P2-01: Localisation FR/AR
- Déjà implémenté dans version précédente
- Détection automatique script arabe
- Templates FR et AR pour statuts commande
- Sticky Arabic mode

---

## Fichiers modifiés (v3.3.0 + v3.3.1)

```
workflows/
├── W0_META_VERIFY_UNIFIED.json  (NOUVEAU)
├── W0_REDIS_HELPER.json         (NOUVEAU - helper Redis dedupe/rate-limit)
├── W1_IN_WA.json                (signature + anti-replay + correlation_id + meta_signature auth)
├── W2_IN_IG.json                (rawBody + signature + meta_signature auth + Redis keys)
├── W3_IN_MSG.json               (rawBody + signature + meta_signature auth + Redis keys)
├── W5_OUT_WA.json               (Meta Cloud API + retry)
├── W6_OUT_IG.json               (Meta Graph API + retry)
├── W7_OUT_MSG.json              (Meta Send API + retry)
├── W8_DLQ_HANDLER.json          (NOUVEAU - monitoring DLQ)
├── W8_DLQ_REPLAY.json           (NOUVEAU - API replay DLQ)

infra/gateway/
├── nginx.conf                   (hardening complet)

config/
├── .env.example                 (nouvelles variables + Redis)

scripts/
├── smoke_meta.sh                (NOUVEAU - tests Meta)
├── test_battery.sh              (NOUVEAU - 100 tests)
├── test_e2e.sh                  (NOUVEAU - tests E2E)

.github/workflows/
├── ci.yml                       (NOUVEAU - GitHub Actions CI/CD)

.gitlab-ci.yml                   (NOUVEAU - GitLab CI/CD)

docs/
├── RUNBOOK.md                   (NOUVEAU)
├── REDIS_SETUP.md               (NOUVEAU - guide Redis)
```

---

## Variables d'environnement ajoutées

| Variable | Description | Défaut |
|----------|-------------|--------|
| `META_VERIFY_ENABLED` | Activer GET verify | `true` |
| `META_VERIFY_TOKEN` | Token vérification Meta | (requis) |
| `META_APP_SECRET` | Secret pour signature HMAC | (requis prod) |
| `META_SIGNATURE_REQUIRED` | Mode signature | `off` |
| `REPLAY_CHECK_ENABLED` | Protection anti-replay | `true` |
| `REPLAY_WINDOW_SECONDS` | Fenêtre anti-replay | `300` |
| `WA_PHONE_NUMBER_ID` | ID numéro WhatsApp | - |
| `IG_PAGE_ID` | ID page Instagram | - |
| `MSG_PAGE_ID` | ID page Messenger | - |
| `REDIS_URL` | URL Redis pour idempotence | `redis://redis:6379` |
| `DEDUPE_TTL_SEC` | TTL déduplication (secondes) | `86400` |
| `RL_MAX_PER_30S` | Rate limit par 30s | `6` |
| `OUTBOX_REDIS_TTL_SEC` | TTL outbox Redis | `604800` |
| `DLQ_ALERT_THRESHOLD` | Seuil alerte DLQ | `10` |

---

## Migration

1. Copier le nouveau `.env.example` et mettre à jour votre `.env`
2. Configurer les variables Redis (`REDIS_URL`, etc.) - voir `docs/REDIS_SETUP.md`
3. Importer les nouveaux workflows dans n8n (W0, W1, W2, W3)
4. Créer credential Redis dans n8n (si Redis utilisé)
5. **Activer** le workflow `W0_META_VERIFY_UNIFIED`
6. Tester avec `./scripts/smoke_meta.sh`
7. Lancer la batterie de tests: `./scripts/test_battery.sh`
8. Configurer les webhooks dans Meta Developer Portal
9. Passer `META_SIGNATURE_REQUIRED=enforce` en production

---

## Rollback

```bash
# Restaurer les workflows précédents
git checkout HEAD~1 -- workflows/

# Ou restaurer depuis les backups .bak
mv workflows/W0_META_VERIFY_WA.json.bak workflows/W0_META_VERIFY_WA.json
```

---

## Tests de validation

```bash
# Smoke test complet
./scripts/smoke_meta.sh

# Test manuel GET verify
curl "https://api.yourdomain.com/v1/inbound/whatsapp?hub.mode=subscribe&hub.verify_token=YOUR_TOKEN&hub.challenge=test"
# Doit retourner: test

# Test POST avec signature
PAYLOAD='{"provider":"wa","msg_id":"test1","from":"user1","text":"hello"}'
SIG=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "YOUR_APP_SECRET" | awk '{print $2}')
curl -X POST "https://api.yourdomain.com/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: sha256=$SIG" \
  -H "x-webhook-token: YOUR_TOKEN" \
  -d "$PAYLOAD"
```

---

*Patch généré le 2026-01-28*
