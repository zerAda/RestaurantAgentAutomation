# BACKUP & RESTORE

Ce document décrit un **playbook exécutable** pour sauvegarder et restaurer la stack.

## Prérequis
- Docker + Docker Compose
- Accès au serveur (VPS)
- Les fichiers `.env` / `secrets/` déjà configurés (prod)

## Postgres (obligatoire)

### Backup
```bash
# Prod
COMPOSE_FILE=docker-compose.hostinger.prod.yml \
BACKUP_DIR=./backups/postgres \
RETENTION_DAYS=14 \
./scripts/backup_postgres.sh
```

Le backup est créé en **format custom** (`pg_dump -Fc`) :
- `./backups/postgres/n8n_YYYY-MM-DD_HHMMSS.dump`
- `./backups/postgres/n8n_YYYY-MM-DD_HHMMSS.dump.sha256` (si `sha256sum` disponible)

Rotation : suppression des backups plus anciens que `RETENTION_DAYS`.

### Restore
⚠️ Restore = opération destructive.

```bash
# Restore recommandé (drop objects + if-exists)
CONFIRM_RESTORE=YES \
COMPOSE_FILE=docker-compose.hostinger.prod.yml \
./scripts/restore_postgres.sh --clean --if-exists ./backups/postgres/n8n_2026-01-22_120000.dump
```

Notes :
- Le script stoppe les services d’écriture (best-effort) avant restore.
- Utilise `pg_restore` avec `--exit-on-error`.

### Restore drill (exercice mensuel)
Objectif : prouver qu’on sait restaurer.

1) Créer un backup
```bash
COMPOSE_FILE=docker-compose.hostinger.prod.yml ./scripts/backup_postgres.sh
```

2) Restaurer sur une DB « vide » (sur une machine de test / ou un environnement de staging)
- Stop stack
- Démarrer postgres
- Restore avec `--clean --if-exists`

3) Vérifier des tables clés
```bash
docker compose -f docker-compose.hostinger.prod.yml exec -T postgres sh -lc \
  "psql -U n8n -d n8n -Atc \"\
  SELECT 'tenants='||(SELECT count(*) FROM tenants),
         'api_clients='||(SELECT count(*) FROM api_clients),
         'security_events='||(SELECT count(*) FROM security_events);
  \""
```

4) Documenter le résultat dans `TEST_REPORT.md`.

## Redis (si persistant)

### Pourquoi
Redis est utilisé pour le mode queue (Bull). En prod, `redis_data` est persistant.

### Backup
```bash
COMPOSE_FILE=docker-compose.hostinger.prod.yml \
BACKUP_DIR=./backups/redis \
RETENTION_DAYS=14 \
./scripts/backup_redis.sh
```

### Restore (procédure)
Le restore Redis est principalement une opération de **volume**.

1) Stopper n8n (pour éviter des écritures concurrentes)
```bash
docker compose -f docker-compose.hostinger.prod.yml stop n8n-main n8n-worker
```

2) Stopper redis
```bash
docker compose -f docker-compose.hostinger.prod.yml stop redis
```

3) Restaurer le contenu du backup dans le volume
> ⚠️ Remplace le contenu de `/data`.

```bash
# Exemple: extraire dans /data du container redis
BACKUP=./backups/redis/redis_2026-01-22_120000.tgz
cat "$BACKUP" | docker compose -f docker-compose.hostinger.prod.yml exec -T redis sh -lc "rm -rf /data/* && tar -C /data -xzf -"
```

4) Redémarrer redis puis n8n
```bash
docker compose -f docker-compose.hostinger.prod.yml up -d redis n8n-main n8n-worker
```

## Règles Ops
- Backups : **quotidien** (cron) + conserver 14 jours (par défaut)
- Restore drill : **mensuel**
- Stocker les backups hors du VPS (object storage) si possible
