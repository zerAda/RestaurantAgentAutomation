# AUDIT DE SECURITE ET CONFORMITE META - RESTO BOT v3.2.4

**Date:** 2026-01-29
**Auditeur:** Claude Code (Mode Machine de Guerre Prod)
**Scope:** Intégration Meta (WhatsApp, Instagram, Messenger) via n8n

---

## 1. INVENTAIRE DES COMPOSANTS

### 1.1 Workflows Inbound (Réception Meta)
| Fichier | Endpoint | rawBody | Signature HMAC | Parsing Meta |
|---------|----------|---------|----------------|--------------|
| W0_META_VERIFY_UNIFIED.json | GET /v1/inbound/* | N/A | N/A | N/A (verify) |
| W1_IN_WA.json | POST /v1/inbound/whatsapp | **OK** | **OK** | **NON** |
| W2_IN_IG.json | POST /v1/inbound/instagram | **OK** | **OK** | **NON** |
| W3_IN_MSG.json | POST /v1/inbound/messenger | **OK** | **OK** | **NON** |

### 1.2 Workflows Outbound (Envoi Meta Graph API)
| Fichier | Channel | Graph API Ready | Token Config | DLQ/Outbox |
|---------|---------|-----------------|--------------|------------|
| W5_OUT_WA.json | WhatsApp | **OK** | WA_API_TOKEN | **OK** |
| W6_OUT_IG.json | Instagram | **OK** | IG_API_TOKEN | **OK** |
| W7_OUT_MSG.json | Messenger | **OK** | MSG_API_TOKEN | **OK** |

### 1.3 Configuration
| Fichier | Role |
|---------|------|
| docker-compose.hostinger.prod.yml | Stack production |
| config/.env.example | Template environnement |
| infra/gateway/nginx.conf | Gateway hardening |

### 1.4 Scripts de Test
| Script | Coverage |
|--------|----------|
| smoke.sh | Health + basic |
| smoke_meta.sh | Meta verify + signature |
| test_battery.sh | 100 tests |
| test_signature_verify.sh | HMAC WA/IG/MSG |
| test_e2e.sh | End-to-end flow |

---

## 2. RISQUES CRITIQUES (P0)

### P0-01: PARSING META NATIF ABSENT
**Sévérité:** CRITIQUE
**Impact:** Aucun message Meta réel ne sera traité correctement

**Constat:**
Les workflows W1/W2/W3 attendent un format legacy:
```json
{"provider":"wa","msg_id":"xxx","from":"xxx","text":"Hello"}
```

Meta envoie pour **WhatsApp**:
```json
{
  "object": "whatsapp_business_account",
  "entry": [{
    "id": "WA_BUSINESS_ID",
    "changes": [{
      "value": {
        "messaging_product": "whatsapp",
        "metadata": {"phone_number_id": "xxx"},
        "messages": [{
          "from": "212612345678",
          "id": "wamid.xxx",
          "timestamp": "1706500000",
          "type": "text",
          "text": {"body": "Hello"}
        }]
      },
      "field": "messages"
    }]
  }]
}
```

Meta envoie pour **Instagram/Messenger**:
```json
{
  "object": "instagram" | "page",
  "entry": [{
    "id": "PAGE_ID",
    "messaging": [{
      "sender": {"id": "PSID"},
      "recipient": {"id": "PAGE_ID"},
      "timestamp": 1706500000,
      "message": {"mid": "m_xxx", "text": "Hello"}
    }]
  }]
}
```

**Code actuel (W1_IN_WA.json ligne 27):**
```javascript
const body = $json.body ?? $json;
// Cherche directement body.provider, body.msg_id, body.from
// Meta n'envoie JAMAIS ces champs !
```

**Résultat:** Le parsing échoue, envelope=null, validation échoue, message rejeté.

---

### P0-02: DEFAULTS MOCK-API EN PROD
**Sévérité:** HAUTE
**Impact:** En l'absence de config explicite, messages envoyés au mock au lieu de Meta

**Constat (docker-compose.hostinger.prod.yml lignes 302-306):**
```yaml
- WA_SEND_URL=${WA_SEND_URL:-http://mock-api:8080/send/wa}
- IG_SEND_URL=${IG_SEND_URL:-http://mock-api:8080/send/ig}
- MSG_SEND_URL=${MSG_SEND_URL:-http://mock-api:8080/send/msg}
```

**Contradiction:** `mock-api` est dans `profiles: ["dev"]` donc NE SERA PAS lancé en prod. Si les env vars ne sont pas définies, n8n tentera d'envoyer vers un service inexistant.

---

### P0-03: META_SIGNATURE_REQUIRED=off PAR DEFAUT
**Sévérité:** HAUTE
**Impact:** Webhooks non authentifiés en production par défaut

**Constat (config/.env.example ligne 106, docker-compose.hostinger.prod.yml ligne 257):**
```yaml
META_SIGNATURE_REQUIRED=${META_SIGNATURE_REQUIRED:-off}
```

**Recommandation:** Default devrait être `enforce` en prod.

---

### P0-04: CONNEXIONS WORKFLOW W2/W3 INCOMPLETES
**Sévérité:** HAUTE
**Impact:** Flux de données interrompu après "Token OK?"

**Constat W2_IN_IG.json:**
La connexion `B0 - Contract Valid? -> B0 - Resolve Client (DB)` passe par position (280, -120) mais le flux `Token OK?` n'est pas correctement relié à la chaîne de déduplication.

Analyse des connections:
```json
"B0 - Contract Valid?": {
  "main": [
    [{"node": "B0 - Resolve Client (DB)"}],  // OK path
    [{"node": "B0 - Log Contract Reject (DB)"}]  // FAIL path
  ]
}
```

Mais après `Resolve Client -> Apply Auth Context -> Seal Tenant Context -> Token OK?`:
```json
"B0 - Token OK?": {
  "main": [
    [{"node": "B0 - Prepare Dedupe Key"}],  // TRUE path
    [{"node": "B0 - Log Deny (DB)"}]  // FALSE path
  ]
}
```

Le noeud `Token OK?` (position -1920, 0) est AVANT `Contract Valid?` (position -1900, 0) dans le flow visuel mais la logique de connexion semble inversée par rapport à W1.

---

### P0-05: ENVELOPE INTERNE NON CONFORME AU CONTRAT META
**Sévérité:** HAUTE
**Impact:** Impossible de tracer les messages Meta correctement

Le format envelope canonique devrait inclure:
- `channel`: wa|ig|msg
- `provider`: whatsapp|instagram|messenger
- `msg_id`: ID unique Meta (wamid.xxx ou m_xxx)
- `user_id`: PSID ou phone number
- `text`: contenu textuel
- `attachments`: array
- `timestamp`: ISO 8601
- `correlation_id`: UUID pour tracing

Actuellement, le code tente de mapper un format legacy vers ce contrat sans jamais parser le format Meta natif.

---

## 3. RISQUES ELEVES (P1)

### P1-01: ABSENCE DE VALIDATION ENTRY/CHANGES
Les workflows ne valident pas la structure `entry[].changes[].value.messages[]` avant de tenter l'extraction.

### P1-02: TIMESTAMPS META NON PARSES
Meta envoie des timestamps Unix (epoch seconds), le code attend des ISO 8601 strings.

### P1-03: STATUS MESSAGES NON FILTRES
Meta envoie des messages de statut (delivered, read) sur le meme webhook. Ces doivent etre ignores silencieusement (ACK 200, pas de traitement).

### P1-04: WEBHOOKS WA/IG/MSG SUR MEME APP SECRET
Les trois canaux utilisent le meme META_APP_SECRET. Si les apps Meta sont separees, les secrets peuvent etre differents.

### P1-05: ABSENCE DE GESTION MULTI-ENTRY
Meta peut envoyer plusieurs entries dans un seul webhook (batch). Le code ne gere qu'un seul entry.

---

## 4. RISQUES MODERES (P2)

### P2-01: HEALTHCHECK N8N NON EXPOSE
Pas de `/health` sur le gateway pour monitoring externe.

### P2-02: LOGS STRUCTURÉS INCOMPLETS
Les workflows logguent mais sans format JSON structuré pour ingestion ELK/Loki.

### P2-03: METRIQUES PROMETHEUS ABSENTES
Pas de `/metrics` endpoint pour scraping Prometheus.

### P2-04: BACKUP REDIS MANUEL
Le script backup_redis.sh existe mais pas integre dans les GitHub Actions.

---

## 5. CONFORMITE META PLATFORM POLICIES

| Requirement | Status | Notes |
|-------------|--------|-------|
| Webhook verify (GET) | **OK** | W0_META_VERIFY_UNIFIED |
| X-Hub-Signature-256 | **OK** | Implemented, mode configurable |
| ACK < 5 secondes | **PARTIEL** | Fast ACK present mais parsing peut ralentir |
| Pas de retry si 200 | **OK** | Response 200 immediate |
| 24h window (WA) | **OK** | Templates supportes |
| PSID pas PII exposed | **OK** | IDs hashes dans logs |

---

## 6. FICHIERS A MODIFIER (SANS RIEN SUPPRIMER)

| Fichier | Modification |
|---------|--------------|
| W1_IN_WA.json | Ajouter parseMetaNativeWA() avant enveloppe legacy |
| W2_IN_IG.json | Ajouter parseMetaNativeIG() avant enveloppe legacy |
| W3_IN_MSG.json | Ajouter parseMetaNativeMSG() avant enveloppe legacy |
| docker-compose.hostinger.prod.yml | Defaults vides pour WA/IG/MSG_SEND_URL |
| .env.example | META_SIGNATURE_REQUIRED=enforce en prod |

---

## 7. RECOMMANDATIONS IMMEDIATES

1. **P0-01:** Ajouter fonction `parseMetaNative()` qui detecte le format et extrait:
   - WA: `entry[0].changes[0].value.messages[0]`
   - IG/MSG: `entry[0].messaging[0]`

2. **P0-02:** Supprimer les defaults mock-api, exiger configuration explicite en prod

3. **P0-03:** Changer default META_SIGNATURE_REQUIRED a `warn` (migration douce) puis `enforce`

4. **P0-04:** Verifier les connexions W2/W3 et aligner sur W1

5. **P0-05:** Documenter le contrat canonique interne

---

## 8. CONCLUSION

Le projet a une **bonne base** de securite (HMAC, tenant isolation, scopes) mais le **parsing Meta natif est absent**, ce qui rend l'integration non fonctionnelle avec les webhooks Meta reels.

**Priorite absolue:** Implementer le parsing des payloads Meta natifs vers le contrat interne canonique.
