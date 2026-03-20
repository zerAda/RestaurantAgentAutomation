# CREDENTIALS CHECKLIST — RESTO BOT v3.3

## Tout ce qu'il faut pour tester la totalité du projet

> Généré: 2026-03-14 | Statut: Audit complet de 39 dépendances externes

---

## STATUT GLOBAL

| Catégorie | Requis | Configuré | Manquant |
| :--- | :--- | :--- | :--- |
| Meta APIs (WhatsApp/IG/MSG) | 8 vars | 1 (verify) | **7** |
| TikTok APIs (DMs/Publish) | 5 vars | 0 | **5** |
| AI Services (OpenAI, Replicate) | 2 vars | 0 | **2** |
| Voice & SMS (Vapi, CRM) | 2 vars | 0 | **2** |
| Tools (Weather, Maps) | 2 vars | 0 | **2** |
| Strapi secrets | 7 vars | **7** | 0 |
| n8n secrets | 2 vars | **2** | 0 |
| PostgreSQL/Redis | 2 vars | **2** | 0 |
| Paiements (Chargily, BaridiMob) | 3 vars | 0 | 3 (optionnel) |
| Monitoring (Alert Webhook) | 1 var | 0 | 1 (optionnel) |
| LLM/STT (Ollama, Whisper) | 2 vars | 1 | 1 (optionnel) |

---

## 🔴 CRITIQUE — BLOQUANTS (Système inutilisable sans eux)

### 1. Meta WhatsApp Business API

**Pourquoi**: Toutes les commandes WhatsApp passent par là (W1, W15, W18...)

| Variable `.env` | Valeur actuelle | Valeur prod |
| :--- | :--- | :--- |
| `WA_API_TOKEN` | `seed_wa_token_xyz123` | **MANQUANT** |
| `WA_PHONE_NUMBER_ID` | `seed_wa_id_555` | **MANQUANT** |
| `META_APP_SECRET` | `seed_meta_app_secret_abc123` | **MANQUANT** |
| `META_VERIFY_TOKEN` | `seed_verify_token_987` | `408c0ebe3085215d0d272f46a3f0c86c0799e2e7` |

**Comment obtenir**:

1. Aller sur <https://business.facebook.com>
2. Créer une App dans Meta Developer Portal
3. Activer le produit "WhatsApp" → Cloud API
4. Récupérer: Phone Number ID + Access Token
5. Dans l'App: Settings → Basic → App Secret
6. Configurer le Webhook dans Meta → URL: `https://api.srv1258231.hstgr.cloud/v1/inbound/whatsapp`
7. Verify Token: n'importe quelle chaîne secrète (ex: `openssl rand -hex 20`)

**Prérequis**: Compte Meta Business vérifié, numéro de téléphone WhatsApp Business

---

### 2. Meta Instagram Messaging API

**Pourquoi**: Canal Instagram DM (W2_IN_IG)

| Variable `.env` | Valeur actuelle | Valeur prod |
| :--- | :--- | :--- |
| `IG_API_TOKEN` | `seed_ig_token_456` | Page Access Token |
| `IG_PAGE_ID` | `seed_ig_page_id_777` | ID de la page Facebook liée |

**Comment obtenir**:

1. Dans Meta Developer Portal → App → Ajouter produit "Instagram"
2. Lier une page Facebook connectée au compte Instagram
3. Générer un Page Access Token avec scopes: `instagram_basic`, `instagram_manage_messages`
4. Page ID: visible dans les paramètres de la page Facebook
5. Webhook URL: `https://api.srv1258231.hstgr.cloud/v1/inbound/instagram`

---

### 3. Meta Facebook Messenger API

**Pourquoi**: Canal Messenger (W3_IN_MSG)

| Variable `.env` | Valeur actuelle | Valeur prod |
| :--- | :--- | :--- |
| `MSG_API_TOKEN` | `seed_msg_token_789` | Page Access Token |
| `MSG_PAGE_ID` | `seed_msg_page_id_888` | ID de la page Facebook |

**Comment obtenir**:

1. Dans Meta Developer Portal → App → Ajouter produit "Messenger"
2. Sélectionner la page Facebook du restaurant
3. Générer Page Access Token avec scope: `pages_messaging`
4. Webhook URL: `https://api.srv1258231.hstgr.cloud/v1/inbound/messenger`

---

### 4. TikTok Business API (DMs & Publishing)

**Pourquoi**: Canal TikTok DM (W1_IN_TIKTOK) et publication de contenu (W_TIKTOK_PUBLISHER)

| Variable `.env` | Valeur actuelle | Valeur prod |
| :--- | :--- | :--- |
| `TIKTOK_API_TOKEN` | VIDE | Access Token (Messaging) |
| `TIKTOK_ACCESS_TOKEN` | VIDE | User Access Token (Publishing) |
| `TIKTOK_REFRESH_TOKEN` | VIDE | Refresh Token (Publishing) |
| `TIKTOK_CLIENT_KEY` | VIDE | Client Key de l'App TikTok |
| `TIKTOK_CLIENT_SECRET` | VIDE | Client Secret de l'App TikTok |

**Comment obtenir**:

1. Créer une application et activer les produits "TikTok Login" et "Video Kit"
2. Récupérer le Client Key et Client Secret
3. Configurer le Redirect URI et Webhook URL: `https://api.srv1258231.hstgr.cloud/v1/inbound/tiktok-webhook`

---

### 5. Services IA & Médias (Asset Enhancement)

**Pourquoi**: Génération d'images FLUX (W20) et Vision GPT-4 (W20)

| Variable `.env` | Provider | Type | Key Name | Use Case |
| :--- | :--- | :--- | :--- | :--- |
| `OPENAI_API_KEY` | OpenAI | Cloud | `OPENAI_API_KEY` | Hybrid/Multi-modal |
| `REPLICATE_API_TOKEN` | Replicate | Cloud | `REPLICATE_API_TOKEN` | Stable Diffusion/Video |

---

### 6. Voice AI & CRM (Engagement)

**Pourquoi**: Prise de commande vocale (W30) et Relance SMS (W51)

| Variable `.env` | Valeur prod |
| :--- | :--- |
| `VAPI_API_KEY` | Clé API Vapi.ai (ou Retell) |
| `SMS_API_URL` | Endpoint de votre fournisseur SMS |
| `SMS_API_KEY` | Clé API pour le fournisseur SMS |

---

### 7. Outils & Monitoring

**Pourquoi**: Déclencheurs météo (W_WEATHER) et Alertes Système

| Variable `.env` | Valeur prod |
| :--- | :--- |
| `OPENWEATHER_API_KEY` | Clé OpenWeatherMap |
| `SLACK_WEBHOOK_URL` | Webhook Slack ou Discord |

---

### 8. Strapi API Token (pour n8n)

**Pourquoi**: Les workflows n8n lisent la config depuis Strapi (W0_CONFIG_READER et 30+ workflows)

| Variable `.env` | Valeur actuelle | Valeur prod |
| :--- | :--- | :--- |
| `STRAPI_API_TOKEN` | VIDE | Token API complet |

**Comment obtenir**:

1. Aller sur <https://cms.srv1258231.hstgr.cloud/admin>
2. Settings → API Tokens → Create new token
3. Type: `Full access` ou `Custom` avec scopes content-manager
4. Copier le token généré (affiché une seule fois)
5. Coller dans `.env` → `STRAPI_API_TOKEN=`
6. Puis redéployer n8n: `docker compose up -d n8n-main n8n-worker`

**Credential n8n à créer aussi**:

- Ouvrir <https://console.srv1258231.hstgr.cloud>
- Credentials → Add → "Strapi Token API"
- Token: (valeur copiée ci-dessus), URL: `https://cms.srv1258231.hstgr.cloud`, API Version: `v5`

---

## 🟡 IMPORTANT — Secrets faibles à remplacer en production

### 5. Strapi JWT/Encryption Secrets

**Pourquoi**: Sécurité des sessions Strapi (rotation en cas de compromission)

| Variable `.env` | Valeur actuelle | Action |
| :--- | :--- | :--- |
| `STRAPI_ADMIN_JWT_SECRET` | `VmgqBJJ6Lb9J...` | ✅ Configuré (prod) |
| `STRAPI_JWT_SECRET` | `a0zW5Ae4Sbp...` | ✅ Configuré (prod) |
| `STRAPI_API_TOKEN_SALT` | `cDyoegxuY5ND...` | ✅ Configuré (prod) |
| `STRAPI_TRANSFER_TOKEN_SALT` | `qvPxwmH5YGd...` | ✅ Configuré (prod) |
| `STRAPI_ENCRYPTION_KEY` | `LvV8xFCNkf3...` | ✅ Configuré (prod) |
| `STRAPI_APP_KEYS` | Multiple seeds | ✅ Configuré (prod) |

---

**Note**: Rotation des JWT secrets = toutes les sessions existantes seront invalidées

---

### 6. n8n Encryption Key

**Pourquoi**: Chiffre les credentials stockés dans n8n (tokens API, mots de passe)

| Variable `.env` | Valeur actuelle | Action |
| :--- | :--- | :--- |
| `N8N_ENCRYPTION_KEY` | `c653e86b6cf...` | ✅ Configuré (prod) |

**⚠️ ATTENTION**: Changer cette clé = tous les credentials n8n existants deviennent illisibles (il faudra re-saisir tous les credentials)

---

### 7. Mots de passe base de données

| Variable `.env` | Valeur actuelle | Action |
| :--- | :--- | :--- |
| `POSTGRES_PASSWORD` | `n8npass` | ✅ Configuré (prod) |
| `N8N_BASIC_AUTH_PASSWORD` | `dev_local_password_not_for_prod_32c` | À changer manuellement |

---

## 🟢 OPTIONNEL — Fonctionnalités désactivées sans eux

### 8. Paiements en ligne (Chargily)

**Pourquoi**: Active les paiements CIB et Edahabia (cartes bancaires algériennes)

| Variable `.env` | Valeur actuelle | Valeur prod |
| :--- | :--- | :--- |
| `CHARGILY_API_KEY` | VIDE | Clé API merchant |
| `PAYMENT_CIB_ENABLED` | `false` | `true` après config |
| `PAYMENT_EDAHABIA_ENABLED` | `false` | `true` après config |

**Comment obtenir**:

1. Créer un compte merchant sur <https://chargily.com>
2. Vérification d'identité (KYC) requise
3. API Keys dans le dashboard Chargily
4. Tester d'abord en mode sandbox

---

### 9. Paiements BaridiMob (Algérie Poste)

**Pourquoi**: Active les paiements via BaridiMob

| Variable `.env` | Valeur actuelle | Valeur prod |
| :--- | :--- | :--- |
| `BARIDIMOB_MERCHANT_CODE` | VIDE | Code marchand |
| `BARIDIMOB_API_URL` | VIDE | URL API BaridiMob |

**Comment obtenir**: Contacter Algérie Poste pour un compte marchand BaridiMob

---

### 10. LLM Ollama (Intelligence Artificielle)

**Pourquoi**: Intent detection, agent IA dashboard, commandes vocales intelligentes

| Variable `.env` | Valeur actuelle | Statut |
| :--- | :--- | :--- |
| `LLM_API_URL` | `http://ollama:11434/api/chat` | Configuré |
| `LLM_MODEL` | `llama3.1` | Modèle téléchargé ✓ |

**Pour activer**:

```bash
# Sur le VPS
docker compose -f docker-compose.hostinger.prod.yml --profile ai up -d ollama
docker exec current-ollama-1 ollama pull llama3.1  # ~4.9GB, 20-30 min
```

**Workflows impactés** (13): W4_CORE, W_LLM_INTENT, W4.1_ROUTER, W31_VOICE_ORDER_CONFIRM, W51_VIP_WIN_BACK, W_ADMIN_AI_AGENT...

---

### 11. Whisper STT (Commandes Vocales)

**Pourquoi**: Transcription des messages audio WhatsApp/Instagram

| Variable `.env` | Valeur actuelle | Valeur prod |
| :--- | :--- | :--- |
| `STT_API_URL` | `http://mock-api:8080/asr` | `http://whisper:9000/asr` |

**Pour activer**:

```bash
# Changer dans .env:
STT_API_URL=http://whisper:9000/asr

# Démarrer le container:
docker compose -f docker-compose.hostinger.prod.yml --profile ai up -d whisper
```

---

### 🟢 AI & Machine Learning (Local-First Priority)

- **Ollama (Llama 3.1 & Llava)**: Core logic and Visual Analysis.

### 12. Alert Webhook (Notifications)

**Pourquoi**: Recevoir des alertes sur erreurs critiques, SLO breaches

| Variable `.env` | Valeur actuelle | Valeur prod |
| :--- | :--- | :--- |
| `ALERT_WEBHOOK_URL` | VIDE | URL webhook Slack/Discord/etc. |

**Comment créer un webhook Slack**:

1. Slack → App Directory → Incoming Webhooks
2. Créer → Sélectionner canal → Copier URL

**Comment créer un webhook Discord**:

1. Discord → Paramètres serveur → Intégrations → Webhooks
2. Créer → Copier URL

---

## 📋 CREDENTIALS N8N À CRÉER (UI n8n)

Aller sur <https://console.srv1258231.hstgr.cloud> → Credentials

| Nom | Type n8n | Données requises |
| :--- | :--- | :--- |
| `Strapi Token API` | Strapi Token API | Token Strapi + URL + API Version v5 |
| `WhatsApp API` | HTTP Header Auth | `Authorization: Bearer <WA_API_TOKEN>` |
| `Instagram API` | HTTP Header Auth | `Authorization: Bearer <IG_API_TOKEN>` |
| `Messenger API` | HTTP Header Auth | `Authorization: Bearer <MSG_API_TOKEN>` |
| `Redis` | Redis | Host: redis, Port: 6379 |
| `PostgreSQL n8n` | PostgreSQL | Host: postgres, DB: n8n, User: n8n |
| `PostgreSQL Strapi` | PostgreSQL | Host: postgres, DB: strapi, User: n8n |

---

## 🔧 COMMANDES RAPIDES

### Générer tous les secrets production

```bash
echo "STRAPI_ADMIN_JWT_SECRET=$(openssl rand -base64 32)"
echo "STRAPI_JWT_SECRET=$(openssl rand -base64 32)"
echo "STRAPI_API_TOKEN_SALT=$(openssl rand -base64 32)"
echo "STRAPI_TRANSFER_TOKEN_SALT=$(openssl rand -base64 32)"
echo "STRAPI_ENCRYPTION_KEY=$(openssl rand -base64 32)"
echo "STRAPI_APP_KEYS=$(openssl rand -base64 16),$(openssl rand -base64 16),$(openssl rand -base64 16),$(openssl rand -base64 16)"
echo "N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)"
echo "POSTGRES_PASSWORD=$(openssl rand -base64 16)"
echo "META_VERIFY_TOKEN=$(openssl rand -hex 20)"
```

### Configurer Webhook Meta (après avoir les tokens)

```bash
# Vérifier que le webhook fonctionne
curl "https://api.srv1258231.hstgr.cloud/v1/inbound/whatsapp?hub.mode=subscribe&hub.challenge=TEST&hub.verify_token=VOTRE_VERIFY_TOKEN"
# Doit retourner: TEST
```

### Tester la chaîne complète par canal

```bash
# WhatsApp (simuler un message entrant)
curl -X POST https://api.srv1258231.hstgr.cloud/v1/inbound/whatsapp \
  -H "Content-Type: application/json" \
  -d '{"object":"whatsapp_business_account","entry":[{"changes":[{"value":{"messages":[{"from":"213XXXXXXXXX","type":"text","text":{"body":"Bonjour"}}]}}]}]}'

# Instagram (simuler un message)
curl -X POST https://api.srv1258231.hstgr.cloud/v1/inbound/instagram \
  -H "Content-Type: application/json" \
  -d '{"object":"instagram","entry":[{"messaging":[{"sender":{"id":"TEST_SENDER"},"message":{"text":"Bonjour"}}]}]}'
```

---

## 📊 MATRICE DE TESTS PAR FONCTIONNALITÉ

| Fonctionnalité | Credentials requis | Test possible? |
| :--- | :--- | :--- |
| Kiosk menu produits | Aucun | ✅ OUI |
| Kiosk commande | Aucun | ✅ OUI |
| Admin dashboard login | Strapi users | ✅ OUI |
| Admin dashboard data | Strapi permissions | ✅ OUI |
| Agent IA dashboard | Ollama (optionnel) | ⚠️ Partiel |
| WhatsApp API | Meta | MESSENGER_TOKEN |
| Instagram API | Meta | INSTAGRAM_TOKEN |
| SMS Provider | Multi | SMS_API_KEY |
| Commande Vocale | Whisper | STT_API_URL |
| Stable Diffusion | SD_API_URL | NEW |
| Piper / TTS | TTS_API_URL | NEW |
| Llava (Vision) | LOCAL_VISION_MODEL | OK |
| Paiement COD | Aucun | ✅ OUI |
| Paiement CIB | Chargily API key | ❌ NON |
| Paiement Edahabia| Chargily API key | ❌ NON |
| Fidélité | Aucun | ✅ OUI |
| Détection fraude | Aucun | ✅ OUI |
| Health monitoring | Aucun | ✅ OUI |
| KPI digest auto | Aucun | ✅ OUI |

---

## 🚀 ORDRE DE PRIORITÉ POUR GO-LIVE

### Phase 1 — Tester sans Meta (Déjà possible)

- [ ] Kiosk: `https://kiosk.srv1258231.hstgr.cloud` → parcourir le menu, passer une commande
- [ ] Admin Dashboard: `https://admin.srv1258231.hstgr.cloud` → login `adel.zeriri@gmail.com / RestoBot2026`
- [ ] Strapi Admin: `https://cms.srv1258231.hstgr.cloud/admin` → gérer le catalogue
- [ ] n8n Console: `https://console.srv1258231.hstgr.cloud` → voir les 90 workflows

### Phase 2 — Activer les canaux Meta

- [ ] Créer/configurer App Meta Developer Portal
- [ ] Obtenir tokens WhatsApp (priorité 1) + configurer `.env`
- [ ] Configurer webhook Meta → URL publique
- [ ] Tester envoi/réception message WhatsApp
- [ ] Répéter pour Instagram et Messenger

### Phase 3 — Activer les paiements

- [ ] Créer compte Chargily
- [ ] Configurer `CHARGILY_API_KEY` dans `.env`
- [ ] Activer `PAYMENT_CIB_ENABLED=true`
- [ ] Tester en mode sandbox Chargily

### Phase 4 — Activer l'IA

- [ ] Démarrer Ollama: `docker compose --profile ai up -d ollama`
- [ ] Télécharger modèle: `docker exec current-ollama-1 ollama pull llama3.1`
- [ ] Configurer Whisper pour les commandes vocales

### Phase 5 — Hardening production

- [ ] Remplacer tous les secrets seed par des valeurs production
- [ ] Changer POSTGRES_PASSWORD
- [ ] Passer `META_SIGNATURE_REQUIRED=enforce`
- [ ] Configurer `ALERT_WEBHOOK_URL` (Slack/Discord)
- [ ] Vérifier IP allowlists (Traefik)

---

### Statut Final

Généré automatiquement — RESTO BOT v3.3.0
