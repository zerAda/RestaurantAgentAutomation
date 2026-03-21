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

# DB Safety Protocol

## File layout

- Bootstrap: `db/bootstrap.sql` (initial schema)
- Full schema ref: `db/schema.sql`
- Migrations: `db/migrations/` (9 files, date-prefixed)
- Init scripts: `db/init/01_apply_migrations.sh`, `db/init/02_create_strapi_db.sh`
- Migrate runner: `scripts/db_migrate.sh`, `scripts/db_migrate_all.sh`
- Backup: `scripts/backup_postgres.sh`
- Restore: `scripts/restore_postgres.sh`
- Fixtures: `tests/fixtures/` (seed SQL for test DB)

## Migration rules

1. File naming: `YYYY-MM-DD_<patch>_<description>.sql`
2. Every statement must be idempotent (`IF NOT EXISTS`, `DO $$ ... END $$`)
3. No `DROP TABLE` or `DROP COLUMN` without migration plan + backup verification
4. Test: apply migration twice with no errors (`scripts/db_migrate.sh` is safe to re-run)
5. CI validates: `.github/workflows/migration-validate.yml`

## Backup protocol

- Automated: `.github/workflows/scheduled-backup.yml` (cron schedule)
- Manual: `make backup` or `scripts/backup_postgres.sh`
- Redis backup: `scripts/backup_redis.sh`
- VPS backup dir: `/opt/resto/backups/`
- Retention: defined in `docs/DB_RETENTION.md`

## Restore drill (must be reproducible)

```bash
# 1. Stop services
docker compose -f docker-compose.hostinger.prod.yml stop n8n-main n8n-worker

# 2. Restore from backup
scripts/restore_postgres.sh /opt/resto/backups/<backup-file>.sql.gz

# 3. Re-apply pending migrations
scripts/db_migrate_all.sh

# 4. Restart and verify
docker compose -f docker-compose.hostinger.prod.yml up -d
make smoke
```

## Performance hygiene

- Index review: `scripts/db_explain.sh` for slow query analysis
- Connection limits: check `max_connections` in compose Postgres config
- Avoid long-running transactions in migrations (use `CONCURRENTLY` for indexes)

## Deliverables

- Migration SQL (idempotent)
- Backup verification (backup exists and size > 0)
- Restore drill result (or documented last drill date)
- Rollback plan (forward-fix migration or restore from backup)
