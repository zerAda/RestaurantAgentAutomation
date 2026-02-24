# RUNBOOK_HOSTINGER (v3.1)

## 1) DNS
Créer trois enregistrements A vers l'IP du VPS :
- `n8n.<domain>` - Console n8n
- `api.<domain>` - API Gateway
- `adminer.<domain>` - Interface DB (Adminer)

## 2) Secrets
Créer le dossier :
```bash
mkdir -p secrets
```

### Postgres password
```bash
openssl rand -base64 32 > secrets/postgres_password
```

### n8n encryption key
```bash
openssl rand -hex 32 > secrets/n8n_encryption_key
```

### Console BasicAuth (Traefik usersfile)
```bash
# Générer le fichier d'auth pour console n8n et Adminer
ADMIN_PASS=$(openssl passwd -apr1 'VOTRE_MOT_DE_PASSE')
echo "admin:${ADMIN_PASS}" > secrets/traefik_usersfile
chmod 600 secrets/traefik_usersfile
```

**Credentials par défaut (À CHANGER):**
- **Username:** `admin`
- **Password:** `RestoAdmin2026!`

## 3) Env
```bash
cp config/.env.example .env
# edite .env
./scripts/preflight.sh
```

## 4) Deploy

### 4.1) Démarrer la stack
```bash
docker compose -f docker-compose.hostinger.prod.yml pull
docker compose -f docker-compose.hostinger.prod.yml up -d
```

### 4.2) Appliquer les migrations DB (si DB existante)
```bash
./scripts/db_migrate.sh db/migrations/2026-01-21_p0_prod_patches.sql
```

### 4.3) Backups (à activer dès J1)
```bash
# Backup manuel
./scripts/backup_postgres.sh

# Restore drill (sur preprod)
CONFIRM_RESTORE=YES ./scripts/restore_postgres.sh ./backups/n8n_<date>.sql.gz
```

## 5) Import workflows
- Ouvre `https://console.<domain>` (depuis IP allowlist)
- Importe W1..W8
- Active W4, W1/W2/W3, W8
- Génère l’ID CORE :
```bash
./scripts/generate_workflow_ids.sh docker-compose.hostinger.prod.yml
# puis ajoute CORE_WORKFLOW_ID dans .env et redémarre
docker compose -f docker-compose.hostinger.prod.yml up -d
```

## 6) Smoke tests
```bash
source .env
./scripts/smoke.sh
```

## 7) Accès aux Services

### URLs de Production
| Service | URL | Auth |
|---------|-----|------|
| **n8n Console** | https://n8n.srv1258231.hstgr.cloud | BasicAuth |
| **Adminer (DB)** | https://adminer.srv1258231.hstgr.cloud | BasicAuth + IP Allowlist |
| **API Gateway** | https://api.srv1258231.hstgr.cloud | Token |
| **Health Check** | https://n8n.srv1258231.hstgr.cloud/healthz | BasicAuth |

### Adminer - Interface Base de Données

**Accès:**
- URL: `https://adminer.srv1258231.hstgr.cloud`
- Username: `admin`
- Password: `RestoAdmin2026!` (à changer!)

**Connexion PostgreSQL dans Adminer:**
- System: `PostgreSQL`
- Server: `postgres`
- Username: `n8n`
- Password: (voir `secrets/postgres_password`)
- Database: `n8n`

**Sécurité Adminer:**
- IP Allowlist configurée dans `.env` (ADMIN_ALLOWED_IPS)
- BasicAuth obligatoire
- Accès uniquement via HTTPS

## 8) Configuration avancée

### Variables d'environnement importantes
```bash
# Subdomains
DOMAIN_NAME=srv1258231.hstgr.cloud
API_SUBDOMAIN=api
CONSOLE_SUBDOMAIN=n8n

# Sécurité Adminer
ADMIN_ALLOWED_IPS=127.0.0.1/32,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16

# Traefik
TRAEFIK_TRUSTED_IPS=127.0.0.1/32,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
```

### PostgreSQL - Tuning Production
Le docker-compose inclut des optimisations PostgreSQL:
- `shared_buffers=256MB`
- `effective_cache_size=768MB`
- `maintenance_work_mem=128MB`
- `checkpoint_completion_target=0.9`
- `max_connections=100`
- `log_min_duration_statement=1000` (log queries > 1s)

### Redis - Configuration Mémoire
- `maxmemory=256mb`
- `maxmemory-policy=allkeys-lru`

## 9) Déploiement CD Pipeline

La pipeline CD détecte automatiquement:
- **Premier déploiement**: Initialise la DB et les configs
- **Mise à jour**: Vérifie les migrations et la santé DB

### Features CD Pipeline:
1. Pre-flight checks (connexion VPS, espace disque)
2. Détection type déploiement (first deploy vs update)
3. Backup automatique avant déploiement
4. Vérification santé DB (tables, migrations)
5. Cleanup VPS automatique (images Docker, logs, backups)
6. 5 smoke tests (health, HTTPS, DB, Redis, API)
7. Auto-rollback en cas d'échec
