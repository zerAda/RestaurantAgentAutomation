---
name: db_safety_protocol
description: Zero data loss for Postgres - backups, restore drills, idempotent migrations, performance.
when_to_use:
  - Schema changes or new migrations
  - Release prep
  - Performance issues
  - Audit readiness
  - Disaster recovery drill
---

# DB Safety Protocol (RESTO BOT)

## Current setup

- **PostgreSQL 15-alpine** with tuned parameters:
  - shared_buffers=256MB, effective_cache_size=768MB
  - maintenance_work_mem=128MB, max_connections=100
  - WAL: wal_buffers=16MB, checkpoint_completion_target=0.9
  - Logging: log_statement=ddl, log_min_duration_statement=1000ms
- **Two databases**: `n8n` (workflows/executions), `strapi` (CMS content)
- Resources: 1 CPU, 1GB RAM

## Migration system

- Init container: `db-migrate` (postgres:15-alpine)
- Migrations dir: `project/db/migrations/` (SQL files, sorted alphabetically)
- Tracking table: `schema_migrations` (filename, applied_at, checksum)
- Bootstrap: `project/db/bootstrap.sql`
- Init scripts: `project/db/init/01_apply_migrations.sh`, `02_create_strapi_db.sh`
- All migrations MUST be idempotent (safe if applied twice)

## Secrets

- Password: `project/secrets/postgres_password` mounted as `/run/secrets/postgres_password`
- Connection: user=n8n, host=postgres, port=5432

## Data safety rules

- Automated backups configured (schedule + retention)
- Restore drill documented and reproducible
- No destructive changes without forward-fix and/or restore plan
- Test migrations on staging before production

## Performance hygiene

- Index review for hot queries
- Avoid long locks; use safe migration patterns (CREATE INDEX CONCURRENTLY)
- Monitor slow queries (>1000ms logged automatically)
- Connection pooling awareness (max_connections=100)

## Key files

- `project/docker-compose.hostinger.prod.yml` (postgres service, volumes)
- `project/db/bootstrap.sql`
- `project/db/migrations/`
- `project/db/init/`
- `project/scripts/ops/` (backup/restore scripts)

## Required output

- Backup + restore steps (RUNBOOK snippet)
- Migration diff + verification SQL
- Rollback plan (or safe roll-forward plan)
