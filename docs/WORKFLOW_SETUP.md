# Configuration des Workflows n8n - Resto Bot

Ce guide explique comment configurer les workflows Resto Bot pour qu'ils fonctionnent correctement.

## Problèmes Identifiés et Solutions

### 1. Credentials PostgreSQL Manquantes

**Problème:** Les nodes PostgreSQL dans les workflows n'ont pas de credentials configurées.

**Solution:** Créer une credential PostgreSQL dans n8n.

#### Étapes:

1. Ouvrez n8n : https://n8n.srv1258231.hstgr.cloud
2. Allez dans **Settings** → **Credentials**
3. Cliquez **Add Credential** → **PostgreSQL**
4. Configurez:
   - **Credential Name**: `PostgreSQL Resto Bot`
   - **Host**: `postgres` (nom du container Docker)
   - **Database**: `n8n`
   - **User**: `n8n`
   - **Password**: (voir CREDENTIALS.md local)
   - **Port**: `5432`
   - **SSL**: Désactivé (connexion interne Docker)
5. Cliquez **Save**

#### Ensuite, pour chaque workflow:
1. Ouvrez le workflow
2. Cliquez sur chaque node PostgreSQL (ils auront une erreur rouge)
3. Sélectionnez la credential "PostgreSQL Resto Bot"
4. Sauvegardez le workflow

### 2. Variables d'Environnement Manquantes

**Problème:** Les nodes "Execute Workflow" référencent des variables qui n'existent pas.

**Solution:** Ajouter les variables dans le fichier `.env` du VPS.

#### Variables Requises:

```bash
# Workflow IDs (à remplacer par les vrais IDs après import)
CORE_WORKFLOW_ID=<ID du workflow W4>
ADMIN_WA_CONSOLE_WORKFLOW_ID=<ID du workflow W14>

# Sécurité
ALLOW_QUERY_TOKEN=false
LEGACY_SHARED_ALLOWED=false
# META_SIGNATURE_REQUIRED: off (dev) | warn (staging) | enforce (PRODUCTION)
META_SIGNATURE_REQUIRED=off  # Change to 'enforce' in production!

# Rate limiting
RATE_LIMIT_PER_30S=6

# Features
ADMIN_WA_CONSOLE_ENABLED=false
L10N_ENABLED=true
DELIVERY_ENABLED=true

# Schemas
SCHEMAS_ROOT=/home/node/.n8n/schemas
```

### 3. Obtenir les Workflow IDs

Après avoir importé et sauvegardé les workflows dans n8n:

1. Ouvrez chaque workflow
2. L'ID est dans l'URL: `https://n8n.../workflow/XXXXXX`
3. Notez les IDs pour W4 (CORE) et W14 (ADMIN WA CONSOLE)
4. Mettez à jour le `.env` sur le VPS

### 4. Configuration des Schemas JSON

Les workflows utilisent des schemas JSON pour valider les payloads.

1. Copiez les schemas sur le VPS:
```bash
ssh root@72.60.190.192
mkdir -p /docker/n8n/schemas/inbound
cp /local-files/ralphe/n8n-project/schemas/inbound/*.json /docker/n8n/schemas/inbound/
```

2. Montez le dossier dans le container n8n (déjà fait dans docker-compose.hostinger.prod.yml)

## Ordre d'Activation des Workflows

Activez les workflows dans cet ordre pour respecter les dépendances:

1. **W4 - CORE** (central, appelé par tous les inbound)
2. **W5, W6, W7 - OUT** (outbound, appelés par W4)
3. **W8 - OPS** (opérations, indépendant)
4. **W0 - Meta Verify** (optionnel, pour signature WhatsApp)
5. **W1, W2, W3 - IN** (inbound, appellent W4)
6. **W9-W14 - Admin** (optionnel)

## Vérification

Après configuration, testez avec:

```bash
# Health check
curl https://api.srv1258231.hstgr.cloud/healthz

# Test inbound (avec token)
curl -X POST https://api.srv1258231.hstgr.cloud/v1/inbound/whatsapp \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: test-token-inbound" \
  -d '{"text":"test","from":"smoke","msgId":"test-1"}'
```
