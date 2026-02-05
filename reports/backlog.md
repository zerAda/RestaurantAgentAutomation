# BACKLOG - META INTEGRATION PROD READY

**Date:** 2026-01-29
**Version cible:** v3.2.5
**Branche:** fix/meta-prod

---

## PRIORITES

| Priorite | Definition | SLA |
|----------|------------|-----|
| **P0** | BLOQUANT - Production impossible sans ce fix | Immediate |
| **P1** | MAJEUR - Fonctionnalite degradee ou risque securite | < 24h |
| **P2** | MINEUR - Amelioration, observabilite, docs | < 1 semaine |

---

## P0 - CRITIQUES (BLOQUANTS)

### P0-01: Parsing Meta Natif WhatsApp
**Status:** TODO
**Fichier:** `workflows/W1_IN_WA.json`
**Noeud:** `B0 - Parse & Canonicalize`

**Cause racine:**
Le code actuel cherche `body.provider`, `body.msg_id`, `body.from` directement. Meta envoie `entry[0].changes[0].value.messages[0]`.

**Criteres d'acceptation:**
- [ ] Detecter si payload est format Meta natif (`object === 'whatsapp_business_account'`)
- [ ] Extraire `entry[0].changes[0].value.messages[0]` -> message
- [ ] Mapper: `message.from` -> `userId`, `message.id` -> `msgId`, `message.text.body` -> `text`
- [ ] Mapper: `message.timestamp` (epoch) -> ISO 8601
- [ ] Gerer `message.type`: text, image, audio, interactive, location
- [ ] Ignorer silencieusement les `statuses` (delivery/read receipts)
- [ ] Tests T2.01-T2.06 passent

**Patch attendu:**
```javascript
// Ajouter au debut de Parse & Canonicalize:
function parseMetaNativeWA(body) {
  if (body.object !== 'whatsapp_business_account') return null;
  const entry = body.entry?.[0];
  const change = entry?.changes?.[0];
  const value = change?.value;

  // Ignore status updates
  if (value?.statuses) return { type: 'status', ignore: true };

  const msg = value?.messages?.[0];
  if (!msg) return null;

  return {
    provider: 'wa',
    msg_id: msg.id,
    from: msg.from,
    text: msg.text?.body || msg.interactive?.button_reply?.id || '',
    timestamp: new Date(parseInt(msg.timestamp) * 1000).toISOString(),
    type: msg.type,
    attachments: extractAttachments(msg),
    raw_meta: msg
  };
}
```

**Rollback:**
Retirer la fonction, le code legacy reprend.

---

### P0-02: Parsing Meta Natif Instagram
**Status:** TODO
**Fichier:** `workflows/W2_IN_IG.json`
**Noeud:** `B0 - Parse & Canonicalize`

**Cause racine:**
Instagram envoie `entry[0].messaging[0]`, pas le meme format que WhatsApp.

**Criteres d'acceptation:**
- [ ] Detecter si payload est format Meta natif (`object === 'instagram'`)
- [ ] Extraire `entry[0].messaging[0]` -> message event
- [ ] Mapper: `sender.id` -> `userId`, `message.mid` -> `msgId`, `message.text` -> `text`
- [ ] Gerer: postback, story_reply, attachments
- [ ] Tests T2.07-T2.08 passent

**Patch attendu:**
```javascript
function parseMetaNativeIG(body) {
  if (body.object !== 'instagram') return null;
  const entry = body.entry?.[0];
  const event = entry?.messaging?.[0];
  if (!event) return null;

  return {
    provider: 'ig',
    msg_id: event.message?.mid || event.postback?.mid || crypto.randomUUID(),
    from: event.sender?.id,
    text: event.message?.text || event.postback?.payload || '',
    timestamp: new Date(event.timestamp).toISOString(),
    type: event.postback ? 'postback' : 'text',
    attachments: event.message?.attachments || [],
    raw_meta: event
  };
}
```

**Rollback:**
Retirer la fonction.

---

### P0-03: Parsing Meta Natif Messenger
**Status:** TODO
**Fichier:** `workflows/W3_IN_MSG.json`
**Noeud:** `B0 - Parse & Canonicalize`

**Cause racine:**
Messenger envoie `entry[0].messaging[0]` avec `object === 'page'`.

**Criteres d'acceptation:**
- [ ] Detecter si payload est format Meta natif (`object === 'page'`)
- [ ] Extraire `entry[0].messaging[0]` -> message event
- [ ] Mapper: `sender.id` -> `userId`, `message.mid` -> `msgId`, `message.text` -> `text`
- [ ] Gerer: postback, attachments
- [ ] Tests T2.09-T2.11 passent

**Patch attendu:**
```javascript
function parseMetaNativeMSG(body) {
  if (body.object !== 'page') return null;
  const entry = body.entry?.[0];
  const event = entry?.messaging?.[0];
  if (!event) return null;

  return {
    provider: 'msg',
    msg_id: event.message?.mid || event.postback?.mid || crypto.randomUUID(),
    from: event.sender?.id,
    text: event.message?.text || event.postback?.payload || '',
    timestamp: new Date(event.timestamp).toISOString(),
    type: event.postback ? 'postback' : 'text',
    attachments: event.message?.attachments || [],
    raw_meta: event
  };
}
```

**Rollback:**
Retirer la fonction.

---

### P0-04: Supprimer Defaults Mock-API en Prod
**Status:** TODO
**Fichier:** `docker-compose.hostinger.prod.yml`
**Lignes:** 302-306, 397-401

**Cause racine:**
Les defaults `:-http://mock-api:8080/send/...` causent des erreurs silencieuses si les vraies URLs ne sont pas configurees.

**Criteres d'acceptation:**
- [ ] Supprimer les defaults pour WA_SEND_URL, IG_SEND_URL, MSG_SEND_URL
- [ ] Ajouter validation au demarrage (script preflight)
- [ ] Documenter dans .env.example que ces vars sont REQUIRED en prod

**Patch attendu:**
```yaml
# AVANT
- WA_SEND_URL=${WA_SEND_URL:-http://mock-api:8080/send/wa}

# APRES
- WA_SEND_URL=${WA_SEND_URL}
```

**Rollback:**
Remettre les defaults.

---

### P0-05: META_SIGNATURE_REQUIRED Default
**Status:** TODO
**Fichier:** `docker-compose.hostinger.prod.yml`
**Lignes:** 257, 362

**Cause racine:**
Default `off` desactive la securite signature en prod si non configure.

**Criteres d'acceptation:**
- [ ] Changer default de `off` a `warn` (phase migration)
- [ ] Documenter la progression: off -> warn -> enforce
- [ ] Ajouter warning au demarrage si mode != enforce

**Patch attendu:**
```yaml
# Phase 1: warn (log but don't block)
- META_SIGNATURE_REQUIRED=${META_SIGNATURE_REQUIRED:-warn}

# Phase 2 (apres validation): enforce
- META_SIGNATURE_REQUIRED=${META_SIGNATURE_REQUIRED:-enforce}
```

**Rollback:**
Remettre `:-off`.

---

### P0-06: Connexions W2/W3 Verification
**Status:** TODO
**Fichier:** `workflows/W2_IN_IG.json`, `workflows/W3_IN_MSG.json`

**Cause racine:**
Le flux apres "Contract Valid?" semble avoir des noeuds orphelins ou mal connectes par rapport a W1.

**Criteres d'acceptation:**
- [ ] Verifier que le flux W2 suit: Webhook -> Parse -> Signature OK? -> ACK -> Contract Valid? -> Resolve Client -> Apply Auth -> Seal -> Token OK? -> Dedupe -> ...
- [ ] Aligner W3 sur le meme pattern
- [ ] Tests T4.02, T4.03 passent

**Rollback:**
Restaurer depuis git.

---

## P1 - MAJEURS

### P1-01: Gestion Multi-Entry Batch
**Status:** TODO
**Fichiers:** W1, W2, W3

**Cause racine:**
Meta peut envoyer plusieurs entries dans un seul webhook. Le code ne traite que `entry[0]`.

**Criteres d'acceptation:**
- [ ] Boucler sur tous les entries
- [ ] Traiter chaque message independamment
- [ ] Test T2.12 passe

---

### P1-02: Status Messages Silent Ignore
**Status:** TODO
**Fichiers:** W1

**Cause racine:**
Les status updates (delivered, read) sont traites comme des messages normaux.

**Criteres d'acceptation:**
- [ ] Detecter `value.statuses` au lieu de `value.messages`
- [ ] ACK 200 immediat sans traitement
- [ ] Test T2.06 passe

---

### P1-03: Timestamp Epoch -> ISO Normalization
**Status:** TODO
**Fichiers:** W1, W2, W3

**Cause racine:**
Meta envoie des timestamps Unix (epoch seconds), le code attend parfois des ISO strings.

**Criteres d'acceptation:**
- [ ] Convertir systematiquement epoch -> ISO 8601
- [ ] Gerer epoch en secondes et millisecondes
- [ ] Test T10.04 passe

---

### P1-04: Healthcheck Endpoint Gateway
**Status:** TODO
**Fichier:** `infra/gateway/nginx.conf`

**Cause racine:**
Pas de `/health` expose pour monitoring externe.

**Criteres d'acceptation:**
- [ ] Ajouter location /health { return 200 "OK"; }
- [ ] Test T14.05 ameliore

---

### P1-05: Preflight Script Production
**Status:** TODO
**Fichier:** `scripts/preflight.sh`

**Cause racine:**
Pas de validation des env vars requises avant lancement.

**Criteres d'acceptation:**
- [ ] Verifier META_APP_SECRET non vide
- [ ] Verifier WA_SEND_URL, IG_SEND_URL, MSG_SEND_URL configurees
- [ ] Verifier META_SIGNATURE_REQUIRED != off
- [ ] Exit 1 si manquant

---

### P1-06: Outbox Retry Workflow Production
**Status:** TODO
**Fichier:** `workflows/W8_DLQ_HANDLER.json`

**Cause racine:**
Le workflow DLQ existe mais n'est pas active par defaut.

**Criteres d'acceptation:**
- [ ] Documenter l'activation
- [ ] Ajouter cron schedule

---

## P2 - MINEURS

### P2-01: Documentation META_SIGNATURE_REQUIRED
**Status:** TODO
**Fichier:** `docs/RUNBOOK.md`

**Criteres d'acceptation:**
- [ ] Section dediee avec exemples
- [ ] Tableau des modes
- [ ] Troubleshooting signature failures

---

### P2-02: Logs Structures JSON
**Status:** TODO
**Fichiers:** W1, W2, W3, W5, W6, W7

**Criteres d'acceptation:**
- [ ] Format JSON pour console.log critiques
- [ ] Champs: timestamp, level, channel, msg_id, correlation_id

---

### P2-03: Metriques Prometheus
**Status:** TODO
**Fichier:** `infra/gateway/nginx.conf` ou n8n config

**Criteres d'acceptation:**
- [ ] Endpoint /metrics
- [ ] Compteurs: inbound_total, outbound_total, errors_total

---

### P2-04: Test Coverage Report
**Status:** TODO
**Fichier:** `scripts/test_coverage.sh`

**Criteres d'acceptation:**
- [ ] Generer rapport HTML
- [ ] Integrer dans CI

---

### P2-05: Backup Redis Integration
**Status:** TODO
**Fichier:** `.github/workflows/scheduled-backup.yml`

**Criteres d'acceptation:**
- [ ] Ajouter backup_redis.sh au workflow
- [ ] Retention 7 jours

---

## ORDRE D'EXECUTION

### Phase 1: Parsing Meta Natif (CRITIQUE)
1. P0-01: Parsing WA
2. P0-02: Parsing IG
3. P0-03: Parsing MSG
4. Tests Section 2 (T2.01-T2.15)

### Phase 2: Securite Defaults
5. P0-04: Supprimer defaults mock
6. P0-05: META_SIGNATURE_REQUIRED default
7. P0-06: Connexions W2/W3
8. Tests Section 3 (T3.01-T3.15)

### Phase 3: Robustesse
9. P1-01: Multi-entry batch
10. P1-02: Status ignore
11. P1-03: Timestamp normalization
12. Tests Sections 4-6

### Phase 4: Observabilite
13. P1-04: Healthcheck
14. P1-05: Preflight
15. P1-06: DLQ activation
16. Tests Sections 7-10

### Phase 5: Documentation
17. P2-01: Docs
18. P2-02: Logs
19. P2-03: Metrics
20. Tests Sections 11-15

---

## TRACKING

| Ticket | Status | Commit | Tests |
|--------|--------|--------|-------|
| P0-01 | **DONE** | - | T2.01-06 |
| P0-02 | **DONE** | - | T2.07-08 |
| P0-03 | **DONE** | - | T2.09-11 |
| P0-04 | **DONE** | - | T8.12-13 |
| P0-05 | **DONE** | - | T3.* |
| P0-06 | **DONE** | - | T4.* |
| P1-01 | TODO | - | T2.12 |
| P1-02 | TODO | - | T2.06 |
| P1-03 | TODO | - | T10.04 |
| P1-04 | TODO | - | T14.05 |
| P1-05 | TODO | - | - |
| P1-06 | TODO | - | T9.03 |
| P2-01 | TODO | - | - |
| P2-02 | TODO | - | - |
| P2-03 | TODO | - | - |
| P2-04 | TODO | - | - |
| P2-05 | TODO | - | - |

---

## DEFINITION OF DONE (PAR TICKET)

1. Code modifie (SANS suppression)
2. Tests specifiques passent
3. Smoke tests globaux passent
4. Commit avec format `P0-XX: <resume>`
5. Changelog mis a jour
6. Backlog statut mis a jour
