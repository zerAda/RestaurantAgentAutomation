# RUNBOOK_HOSTINGER (v3.0)

## 1) DNS
Créer deux enregistrements A vers l'IP du VPS :
- `console.<domain>`
- `api.<domain>`

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
docker run --rm httpd:2.4-alpine htpasswd -nbB admin 'REPLACE_WITH_STRONG_PASSWORD' > secrets/traefik_usersfile
```

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
