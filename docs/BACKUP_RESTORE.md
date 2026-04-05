# BACKUP & RESTORE

This document is an executable playbook for backing up and restoring the Resto Bot stack.
It covers both local VPS backups and off-site S3 object storage backups.

---

## Architecture Overview

```
VPS (PostgreSQL)
    |
    | pg_dump -Fc  (daily 03:00 UTC / weekly Sunday 04:00 UTC)
    v
/opt/resto/backups/
    |
    | GitHub Actions: scheduled-backup.yml (upload-offsite job)
    | scp download -> gunzip -t -> GPG AES-256 encrypt -> aws s3 cp
    v
S3-compatible Object Storage
  s3://<BUCKET>/postgres/<backup-name>-db.dump.gz.gpg
```

The local VPS copy provides fast same-host recovery. The S3 copy protects against
total VPS loss (disk failure, ENOSPC data corruption, provider outage).

---

## What Is Backed Up

| Artifact | Format | Location on VPS | S3 Path |
|----------|--------|-----------------|---------|
| n8n PostgreSQL DB (n8n schema) | pg_dump custom (-Fc) gzipped | `/opt/resto/backups/<name>-db.dump.gz` | `s3://<BUCKET>/postgres/<name>-db.dump.gz.gpg` |
| `.env` + `secrets/` config archive | tar.gz | `/opt/resto/backups/<name>-config.tar.gz` | (local only) |
| Backup metadata | plaintext | `/opt/resto/backups/<name>-metadata.txt` | (local only) |

The PostgreSQL dump covers the `n8n` database which contains:
- `workflow_entity` — all n8n workflows
- `execution_entity` — execution history
- Custom application tables (orders, customers, products, funnel events, etc.)

---

## Backup Schedule & Retention

| Type | Cron | Retention (VPS) | Retention (S3) |
|------|------|-----------------|----------------|
| Daily | `0 3 * * *` (03:00 UTC) | 7 most recent | Indefinite (set lifecycle rule separately) |
| Weekly full | `0 4 * * 0` (Sun 04:00 UTC) | 4 most recent | Indefinite |

S3 lifecycle rules are not configured by the workflow. Configure them manually in
your S3/R2 console to avoid unbounded storage growth (e.g. delete objects older than 90 days).

---

## Prerequisites

- Docker installed (local or VPS)
- `awscli` installed (`pip install awscli` or package manager)
- `gpg` installed
- Environment variables set (see sections below)

---

## Off-site Restore Procedure

Use this procedure when the VPS disk is unavailable or data is corrupted.

### 1. Set environment variables

```bash
export S3_BACKUP_BUCKET=your-bucket-name
export S3_BACKUP_ENDPOINT=https://s3.amazonaws.com   # or R2 endpoint
export S3_BACKUP_REGION=us-east-1                    # or 'auto' for R2
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export BACKUP_GPG_PASSPHRASE=your-gpg-passphrase
```

### 2. Identify the backup to restore

```bash
# List available backups in S3
aws s3 ls s3://${S3_BACKUP_BUCKET}/postgres/ \
  --endpoint-url ${S3_BACKUP_ENDPOINT} \
  --region ${S3_BACKUP_REGION} \
  | sort | tail -20
```

Pick the backup name (without the `.gpg` suffix), e.g. `daily-20260320-030000`.

### 3. Run the restore drill script (full automated restore to test container)

```bash
BACKUP_NAME=daily-20260320-030000 bash scripts/restore_drill.sh
```

Expected final line: `[DRILL PASS]`

The drill script:
1. Downloads `s3://<BUCKET>/postgres/<name>-db.dump.gz.gpg`
2. Decrypts with GPG
3. Decompresses
4. Spins up `postgres:15-alpine` container
5. Restores with `pg_restore`
6. Verifies `workflow_entity` row count > 0
7. Always cleans up temp container and files

### 4. Restore to production database

After verifying the drill passes, restore to production:

```bash
# Stop write services first
ssh deploy@<VPS_HOST> "cd /opt/resto/current && \
  docker compose -f docker-compose.hostinger.prod.yml stop n8n-main n8n-worker"

# Download from S3
BACKUP_NAME=daily-20260320-030000
aws s3 cp \
  s3://${S3_BACKUP_BUCKET}/postgres/${BACKUP_NAME}-db.dump.gz.gpg \
  /tmp/${BACKUP_NAME}-db.dump.gz.gpg \
  --endpoint-url ${S3_BACKUP_ENDPOINT} \
  --region ${S3_BACKUP_REGION}

# Decrypt
echo "$BACKUP_GPG_PASSPHRASE" | gpg --batch --passphrase-fd 0 \
  -d /tmp/${BACKUP_NAME}-db.dump.gz.gpg \
  > /tmp/${BACKUP_NAME}-db.dump.gz

# Decompress
gunzip /tmp/${BACKUP_NAME}-db.dump.gz

# Copy dump to VPS
scp /tmp/${BACKUP_NAME}-db.dump deploy@<VPS_HOST>:/tmp/

# Restore on VPS
ssh deploy@<VPS_HOST> << 'EOF'
PG_CONTAINER=$(docker ps -qf "name=postgres" -f "status=running" | head -1)
docker exec -i "$PG_CONTAINER" pg_restore \
  -U n8n -d n8n \
  --clean --no-owner --no-acl -Fc \
  < /tmp/daily-20260320-030000-db.dump
echo "Restore complete"
rm -f /tmp/daily-20260320-030000-db.dump
EOF

# Restart services
ssh deploy@<VPS_HOST> "cd /opt/resto/current && \
  docker compose -f docker-compose.hostinger.prod.yml up -d n8n-main n8n-worker"
```

---

## Manual Emergency Restore (GitHub Actions unavailable)

If GitHub Actions is unavailable, restore entirely from VPS local backups:

```bash
# SSH to VPS
ssh deploy@<VPS_HOST>

# List local backups
ls -lht /opt/resto/backups/ | head -20

# Verify integrity
gunzip -t /opt/resto/backups/daily-20260320-030000-db.dump.gz

# Stop write services
cd /opt/resto/current
docker compose -f docker-compose.hostinger.prod.yml stop n8n-main n8n-worker

# Find postgres container
PG_CONTAINER=$(docker ps -qf "name=postgres" -f "status=running" | head -1)

# Restore (decompress on the fly)
gunzip -c /opt/resto/backups/daily-20260320-030000-db.dump.gz | \
  docker exec -i "$PG_CONTAINER" pg_restore \
    -U n8n -d n8n \
    --clean --no-owner --no-acl -Fc

# Restart services
docker compose -f docker-compose.hostinger.prod.yml up -d n8n-main n8n-worker
```

---

## Verification Queries

Run these after any restore to confirm data integrity:

```sql
-- Connect
docker exec -it $(docker ps -qf "name=postgres" | head -1) psql -U n8n -d n8n

-- Key row counts
SELECT 'workflow_entity'   AS table_name, COUNT(*) FROM workflow_entity
UNION ALL
SELECT 'execution_entity',               COUNT(*) FROM execution_entity
UNION ALL
SELECT 'workflow_statistics',            COUNT(*) FROM workflow_statistics;

-- Verify most recent workflow
SELECT id, name, active, updated_at
FROM workflow_entity
ORDER BY updated_at DESC
LIMIT 5;
```

Expected: `workflow_entity` count > 0. A fresh n8n install has 0; a restored production
database should have many rows (76+ workflows as of 2026-03-21).

---

## Local Postgres Backup (scripts/backup_postgres.sh)

For ad-hoc local backup (not off-site):

```bash
COMPOSE_FILE=docker-compose.hostinger.prod.yml \
BACKUP_DIR=./backups/postgres \
RETENTION_DAYS=14 \
./scripts/backup_postgres.sh
```

Output: `./backups/postgres/n8n_YYYY-MM-DD_HHMMSS.dump` (pg_dump -Fc custom format)

---

## Redis Backup

Redis is used for the Bull queue (n8n queue mode). It does not contain permanent data
(jobs re-queue on restart). If needed:

```bash
# Backup
COMPOSE_FILE=docker-compose.hostinger.prod.yml \
BACKUP_DIR=./backups/redis \
RETENTION_DAYS=14 \
./scripts/backup_redis.sh

# Restore
BACKUP=./backups/redis/redis_YYYY-MM-DD_HHMMSS.tgz
docker compose -f docker-compose.hostinger.prod.yml stop n8n-main n8n-worker redis
cat "$BACKUP" | docker compose -f docker-compose.hostinger.prod.yml exec -T redis \
  sh -lc "rm -rf /data/* && tar -C /data -xzf -"
docker compose -f docker-compose.hostinger.prod.yml up -d redis n8n-main n8n-worker
```

---

## GitHub Actions Secrets Required

For the automated off-site upload to work, configure these in
**Settings > Secrets and variables > Actions**:

| Secret / Variable | Type | Description |
|-------------------|------|-------------|
| `S3_ACCESS_KEY_ID` | Secret | S3/R2 access key ID |
| `S3_SECRET_ACCESS_KEY` | Secret | S3/R2 secret key |
| `BACKUP_GPG_PASSPHRASE` | Secret | GPG passphrase for encryption |
| `S3_BACKUP_BUCKET` | Variable | Bucket name |
| `S3_BACKUP_ENDPOINT` | Variable | S3 endpoint URL |
| `S3_BACKUP_REGION` | Variable | Region or `auto` (for R2) |

If any of these are missing, the `upload-offsite` job will **fail the workflow** — not skip silently.

---

## Ops Rules

- Backups run: **daily** (03:00 UTC) + **weekly** (Sunday 04:00 UTC)
- VPS retention: 7 daily, 4 weekly
- S3 retention: indefinite (configure lifecycle rules separately)
- Restore drill: run **monthly** using `restore_drill.sh`
- After any restore: restart services + run `./scripts/smoke.sh`
- See also: `docs/RUNBOOK.md` section "Restore from Off-site Backup"
