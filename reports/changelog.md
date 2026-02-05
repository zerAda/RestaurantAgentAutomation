# CHANGELOG - Meta Integration Production Ready

**Branche:** fix/meta-prod
**Date de début:** 2026-01-29

---

## P0-01: Parsing Meta Natif WhatsApp [DONE]

**Date:** 2026-01-29
**Fichier:** `workflows/W1_IN_WA.json`
**Noeud:** `B0 - Parse & Canonicalize`

### Changements
1. Ajouté fonction `parseMetaNativeWA()` qui:
   - Détecte le format Meta natif (`object === 'whatsapp_business_account'`)
   - Extrait `entry[0].changes[0].value.messages[0]`
   - Mappe les champs vers le format legacy (`provider`, `msg_id`, `from`, `text`)
   - Convertit timestamp epoch -> ISO 8601
   - Gère les types: text, interactive (button_reply, list_reply), button

2. Ajouté fonction `extractAttachmentsWA()` qui supporte:
   - image, audio, video, document, location, sticker, contacts

3. Ajouté détection des status updates (`value.statuses`) avec flag `_isStatusUpdate`

4. Ajouté `_metaParsing` dans la sortie:
   - `isMetaNative`: true si payload Meta natif détecté
   - `isStatusUpdate`: true si c'est un status update
   - `rawBodyType`: type original du payload

5. Corrigé signature verification pour utiliser `rawBodyInput` (original) et non `body` (parsé)

### Rétrocompatibilité
- Format legacy toujours supporté (fallback si parsing Meta échoue)
- Aucune suppression de code existant

### Tests concernés
- T2.01: WA text message parsing
- T2.02: WA image message parsing
- T2.03: WA audio message parsing
- T2.04: WA button reply parsing
- T2.05: WA location message
- T2.06: WA status message (ignore)

### Rollback
Restaurer `W1_IN_WA.json` depuis git (commit précédent).

---

---

## P0-02: Parsing Meta Natif Instagram [DONE]

**Date:** 2026-01-29
**Fichier:** `workflows/W2_IN_IG.json`
**Noeud:** `B0 - Parse & Canonicalize`

### Changements
1. Ajouté fonction `parseMetaNativeIG()` qui:
   - Détecte le format Meta natif (`object === 'instagram'`)
   - Extrait `entry[0].messaging[0]`
   - Mappe les champs vers le format legacy
   - Gère les types: text, postback, quick_reply, attachments

2. Ajouté fonction `extractAttachmentsIG()` qui supporte:
   - image, video, audio, file, share, story_mention

3. Ajouté détection des réactions pures avec flag `_isReactionOnly`

4. Ajouté `_metaParsing` dans la sortie

5. Corrigé signature verification pour utiliser `rawBodyInput`

### Tests concernés
- T2.07: IG text message parsing
- T2.08: IG story reply parsing

---

## P0-03: Parsing Meta Natif Messenger [DONE]

**Date:** 2026-01-29
**Fichier:** `workflows/W3_IN_MSG.json`
**Noeud:** `B0 - Parse & Canonicalize`

### Changements
1. Ajouté fonction `parseMetaNativeMSG()` qui:
   - Détecte le format Meta natif (`object === 'page'`)
   - Extrait `entry[0].messaging[0]`
   - Mappe les champs vers le format legacy
   - Gère les types: text, postback, quick_reply, referral, sticker

2. Ajouté fonction `extractAttachmentsMSG()` qui supporte:
   - image, video, audio, file, location, template, fallback

3. Ajouté détection des delivery/read receipts avec flag `_isReceiptOnly`

4. Ajouté `_metaParsing` dans la sortie

5. Corrigé signature verification pour utiliser `rawBodyInput`

### Tests concernés
- T2.09: MSG text message parsing
- T2.10: MSG postback parsing
- T2.11: MSG attachment parsing

---

## P0-04: Supprimer Defaults Mock-API en Prod [DONE]

**Date:** 2026-01-29
**Fichier:** `docker-compose.hostinger.prod.yml`

### Changements
1. Supprimé les defaults `:-http://mock-api:8080/send/*` pour:
   - WA_SEND_URL
   - IG_SEND_URL
   - MSG_SEND_URL
   - WA_API_TOKEN, IG_API_TOKEN, MSG_API_TOKEN
   - STT_API_URL

2. Ajouté commentaire expliquant que ces vars DOIVENT être configurées dans .env

### Impact
En production, si ces variables ne sont pas définies, les workflows échoueront au lieu d'envoyer silencieusement vers un mock inexistant.

---

## P0-05: META_SIGNATURE_REQUIRED Default [DONE]

**Date:** 2026-01-29
**Fichier:** `docker-compose.hostinger.prod.yml`

### Changements
1. Changé le default de `off` à `warn`:
   - `META_SIGNATURE_REQUIRED=${META_SIGNATURE_REQUIRED:-warn}`

2. Ajouté commentaire recommandant `enforce` en production

### Impact
- `warn`: Log les échecs de signature mais ne bloque pas (phase migration)
- `enforce`: Doit être défini explicitement dans .env pour production

---

## P0-06: Connexions W2/W3 Verification [DONE]

**Date:** 2026-01-29
**Fichiers:** `workflows/W2_IN_IG.json`, `workflows/W3_IN_MSG.json`

### Vérification
Les connexions dans W2 et W3 suivent le même pattern que W1:
1. IN - Webhook -> Parse & Canonicalize
2. Parse & Canonicalize -> Signature OK?
3. Signature OK? -> RESP 200 ACK (true) / RESP 401 (false)
4. RESP 200 ACK -> Contract Valid?
5. Contract Valid? -> Resolve Client -> Apply Auth -> Seal -> Token OK?
6. Token OK? -> Dedupe -> Rate Limit -> Quarantine -> CORE_AGENT

### Résultat
Les connexions sont correctes et fonctionnelles.

---

## PHASE 0 COMPLETE

Tous les tickets P0 sont terminés:
- [x] P0-01: Parsing Meta Natif WhatsApp
- [x] P0-02: Parsing Meta Natif Instagram
- [x] P0-03: Parsing Meta Natif Messenger
- [x] P0-04: Supprimer Defaults Mock-API en Prod
- [x] P0-05: META_SIGNATURE_REQUIRED Default
- [x] P0-06: Connexions W2/W3 Verification

---

---

## P0-07: Default Tenant/Restaurant via ENV (No Hardcode) [DONE]

**Date:** 2026-01-30
**Fichiers:** `W1_IN_WA.json`, `W2_IN_IG.json`, `W3_IN_MSG.json`, `config/.env.example`

### Changements
1. Supprimé les UUIDs hardcodés dans "B0 - Apply Auth Context"
2. Ajouté validation fail-fast si `PROD_ENFORCE_DEFAULTS=true` et defaults manquants
3. Ajouté flag `LEGACY_DEFAULT_IDS=true` pour rollback (permet les UUIDs hardcodés)
4. Documenté dans `.env.example`:
   - `DEFAULT_TENANT_ID` - [REQUIRED in Production]
   - `DEFAULT_RESTAURANT_ID` - [REQUIRED in Production]
   - `PROD_ENFORCE_DEFAULTS` - fail-fast si defaults manquants
   - `LEGACY_DEFAULT_IDS` - rollback flag

### Comportement
- `PROD_ENFORCE_DEFAULTS=false` (défaut): auth silently fails si defaults manquants
- `PROD_ENFORCE_DEFAULTS=true`: denyReason=PROD_DEFAULTS_MISSING si defaults manquants
- `LEGACY_DEFAULT_IDS=true`: utilise les UUIDs hardcodés comme fallback

### Rollback
Mettre `LEGACY_DEFAULT_IDS=true` dans .env

---

---

## P1-01: Redis Dedupe Inbound [ALREADY IMPLEMENTED]

**Date:** 2026-01-30
**Status:** Déjà implémenté dans W1/W2/W3

### Architecture
```
Parse -> ... -> Token OK? -> Prepare Dedupe Key -> Redis GET -> Parse Result
                                                              |
                                    Is New? --YES--> Redis SET EX TTL -> DB Idempotency -> ...
                                            --NO---> END (drop duplicate)
```

### Nodes existants
- `B0 - Prepare Dedupe Key`: Génère `ralphe:dedupe:<channel>:<msg_id>`
- `B0 - Redis Dedupe GET`: Vérifie si clé existe
- `B0 - Parse Dedupe Result`: Détermine isNew/isDuplicate
- `B0 - Is New (Redis)?`: Branchement
- `B0 - Redis Dedupe SET`: SET key EX TTL si nouveau
- `B0 - Idempotency (DB)`: Fallback avec ON CONFLICT DO NOTHING

### Configuration
```bash
DEDUPE_ENABLED=true        # Active/désactive la déduplication
DEDUPE_TTL_SEC=172800      # TTL 48h (en secondes)
```

### Race condition
- Fenêtre GET-SET < 100ms
- Fallback DB garantit l'idempotence finale
- Acceptable pour le cas d'usage

### Amélioration future (optionnelle)
- Implémenter SET NX EX atomique via Code node + ioredis

---

---

## P1-02: Redis Rate Limit + Quarantine [DONE]

**Date:** 2026-01-30
**Fichiers:** `W1_IN_WA.json`, `W2_IN_IG.json`, `W3_IN_MSG.json`, `config/.env.example`

### Changements
1. Mis à jour le noeud `B0 - RateLimit Flag` dans W1/W2/W3 pour:
   - Supporter `RL_ENABLED` env var (toggle on/off)
   - Supporter `RL_MAX_PER_30S` en plus de `RATE_LIMIT_PER_30S`
   - Préparer `_quarantine` data quand rate limit exceeded

2. Ajouté noeuds `B0 - Redis Quarantine Push` dans W1/W2/W3:
   - LPUSH vers `ralphe:quarantine:<channel>:<userId>`
   - Payload JSON avec reason, count, limit, timestamp
   - `continueOnFail: true` pour robustesse

3. Ajouté noeuds `B0 - DB Quarantine Insert` dans W1/W2/W3:
   - INSERT INTO `conversation_quarantine` avec ON CONFLICT DO UPDATE
   - Incrémente `quarantine_count` sur conflit
   - Expire après 1 heure

4. Modifié connexions `B0 - Rate OK? FALSE`:
   - Avant: → END - Drop/Done
   - Après: → Redis Quarantine Push → DB Quarantine Insert → END - Drop/Done

5. Ajouté `RL_ENABLED=true` dans `.env.example`

### Flow Quarantine
```
Rate OK?
  --TRUE--> Quarantine Check (existing) --> ...
  --FALSE--> Redis Push --> DB Insert --> END (drop)
```

### Configuration
```bash
RL_ENABLED=true           # Toggle rate limiting on/off
RL_MAX_PER_30S=6          # Max messages per 30s per conversation
RATE_LIMIT_PER_30S=6      # Alias (backward compat)
```

### Rollback
Mettre `RL_ENABLED=false` dans .env

---

## P1-03: Redis Outbox Worker + DLQ [DONE]

**Date:** 2026-01-30
**Fichiers:** `W5_OUT_WA.json`, `W6_OUT_IG.json`, `W7_OUT_MSG.json`, `W15_OUTBOX_WORKER.json` (nouveau), `config/.env.example`

### Changements

1. **Nouveau workflow W15_OUTBOX_WORKER.json**:
   - Trigger: CRON toutes les 30s
   - Consomme `ralphe:outbox:pending` (Redis List RPOP)
   - Retry avec backoff exponentiel (baseDelay * 2^attempts)
   - DLQ `ralphe:dlq` pour échecs permanents (401, 403, 400, max retries)
   - Déduplication outbound via `ralphe:outbox:sent:<msgId>`
   - Support multi-channel (WA, IG, MSG)

2. **Modifié W5/W6/W7 - Mode Async**:
   - Ajouté `asyncEnabled` flag dans `_outbox`
   - Nouveau branchement `B0 - Async Mode?`:
     - TRUE: LPUSH vers `ralphe:outbox:pending` → END - Queued
     - FALSE: Continue vers OUT - Send Message (comportement sync original)

### Architecture

```
Mode Sync (default):
  CORE → W5/W6/W7 → OUT - Send Message → Success/DLQ

Mode Async (OUTBOX_ASYNC_ENABLED=true):
  CORE → W5/W6/W7 → LPUSH pending → END (queued)
         ↓
  W15 Worker (cron 30s) → RPOP → Dedupe Check → Send → Success/Retry/DLQ
```

### Retry Logic
- 429 (Rate Limited): Retry avec delay de Retry-After header
- 5xx (Server Error): Retry avec backoff exponentiel
- 4xx (Client Error): DLQ immédiat (pas de retry)
- Max attempts: 7 (configurable via OUTBOX_MAX_ATTEMPTS)

### Configuration
```bash
# Activer le mode async
OUTBOX_ASYNC_ENABLED=true

# Worker config
OUTBOX_WORKER_ENABLED=true
OUTBOX_WORKER_BATCH_SIZE=10

# Retry config (existant)
OUTBOX_MAX_ATTEMPTS=7
OUTBOX_BASE_DELAY_SEC=30
OUTBOX_MAX_DELAY_SEC=3600
```

### Tests concernés
- 429 → retries avec backoff
- 401 → DLQ immédiat
- Crash → reprend sans double send (dedupe outbound)

### Rollback
Mettre `OUTBOX_ASYNC_ENABLED=false` (mode sync par défaut)

---

## P1-04: Anti-Replay Guard (Payload Hash) [DONE]

**Date:** 2026-01-30
**Fichiers:** `W1_IN_WA.json`, `W2_IN_IG.json`, `W3_IN_MSG.json`, `config/.env.example`

### Changements

1. **Ajouté noeuds anti-replay dans W1/W2/W3**:
   - `B0 - Prepare Replay Key`: Génère hash `sha256(channel:msg_id:userId:textHash)`
   - `B0 - Replay Check GET`: Redis GET `ralphe:replay:<channel>:<hash>`
   - `B0 - Parse Replay Result`: Détermine si replay ou nouveau
   - `B0 - Is New (Replay)?`: Branchement
   - `B0 - Replay SET`: SET key avec TTL si nouveau
   - `B0 - Replay Detected`: Log et stop si replay

2. **Flow**:
   ```
   Contract Valid? TRUE → Prepare Replay Key → Redis GET → Parse Result
                                                              ↓
                     Is New? --YES--> Replay SET → Resolve Client → ...
                             --NO---> Replay Detected → END (drop)
   ```

3. **Modes**:
   - `warn` (défaut): Log le replay mais continue (ACK 200, drop silencieux)
   - `enforce`: Bloque le replay complètement

### Configuration
```bash
REPLAY_GUARD_ENABLED=true     # Active/désactive la protection
REPLAY_GUARD_MODE=warn        # warn|enforce
META_REPLAY_WINDOW_SEC=300    # TTL des clés (5 min par défaut)
```

### Différence avec déduplication existante
- **Dedupe (P1-01)**: Basé sur `msg_id` seul, après auth
- **Anti-Replay (P1-04)**: Basé sur hash du payload complet, avant auth

### Tests concernés
- Replay du même payload → bloqué/loggé selon mode
- Payload nouveau → OK
- Redis indisponible → fail-open (continue)

### Rollback
Mettre `REPLAY_GUARD_ENABLED=false` dans .env

---

## P1-05: Readyz + Health Monitor Alerts [DONE]

**Date:** 2026-01-30
**Fichiers:** `W16_HEALTHZ.json` (nouveau), `W17_HEALTH_MONITOR.json` (nouveau), `config/.env.example`

### Nouveaux workflows

**W16_HEALTHZ.json** - Endpoints de santé:
- `/webhook/readyz` - Readiness check (vérifie n8n + Redis + Postgres)
- `/webhook/livez` - Liveness check (simple heartbeat)

**W17_HEALTH_MONITOR.json** - Moniteur avec alertes:
- CRON toutes les minutes
- Appelle `/readyz` pour vérifier la santé
- Compte les échecs consécutifs dans Redis
- Alerte après N échecs (configurable)
- Cooldown entre alertes pour éviter le spam
- Supporte webhook générique + WhatsApp

### Endpoints

| Endpoint | Méthode | Réponse OK | Réponse Fail |
|----------|---------|------------|--------------|
| `/readyz` | GET | 200 + checks JSON | 503 + checks JSON |
| `/livez` | GET | 200 + status | - |

### Checks effectués par /readyz
- **n8n**: Toujours OK si endpoint répond
- **Postgres**: `SELECT 1 AS pg_ok`
- **Redis**: GET sur une clé de test

### Flow Monitor
```
CRON 1min → Get fail_count → Call /readyz → Health OK?
                                              ↓
                          YES → Reset fail_count → END
                          NO  → Increment fail_count → Should Alert?
                                                        ↓
                                   fail >= threshold → Check Cooldown → Send Alert
                                                    → END (no alert)
```

### Configuration
```bash
HEALTH_MONITOR_ENABLED=true
HEALTH_ALERT_THRESHOLD=3      # Échecs consécutifs avant alerte
ALERT_COOLDOWN_SEC=300        # 5 min entre alertes
ADMIN_ALERT_PHONE=            # Numéro WhatsApp admin
ALERT_WEBHOOK_URL=            # URL webhook générique (Slack, Discord...)
```

### Tests concernés
- Couper Redis → /readyz 503, fail_count++, alerte après 3 échecs
- Restaurer → /readyz 200, fail_count reset

### Rollback
Mettre `HEALTH_MONITOR_ENABLED=false` dans .env

---

## Tickets P1 (à venir)

- [x] P1-05: Readyz + Health Monitor (DONE)
- [x] P1-04: Anti-Replay Guard (DONE)
- [x] P1-03: Redis Outbox Worker + DLQ (DONE)
- [x] P1-02: Redis Rate Limit + Quarantine (DONE)
- [x] P1-01: Redis Dedupe Inbound (ALREADY IMPLEMENTED)
- [ ] P1-06: Multi-Entry Batch
- [ ] P1-07: Timestamp Epoch -> ISO Normalization
- [ ] P1-08: Preflight Script Production
