---
name: release_and_rollback
description: Safe production releases with preflight checks, deploy, verify, and emergency rollback.
when_to_use:
  - Deploying to production
  - Changing compose or routing config
  - Rolling out P0 fixes
  - Production outage or incident
---

# Release and Rollback (RESTO BOT)

## Release flow

### Preflight (must ALL pass)

1. Config validation: `project/scripts/preflight-prod.sh`
2. ENV completeness: all `[REQUIRED]` vars present in `.env`
3. DB migration plan reviewed + backup ready
4. Smoke tests ready
5. Version bump in `project/VERSION` (currently 3.3.0)
6. PATCHLOG.md entry written

### Deploy

1. SSH to VPS: `ssh deploy@72.60.190.192`
2. Create release directory in `/opt/resto/releases/YYYYMMDD-HHMMSS-<sha>/`
3. Sync code to release dir
4. Run db-migrate (init container applies pending migrations)
5. Switch symlink: `/opt/resto/current/` -> new release
6. `docker compose -f docker-compose.hostinger.prod.yml up -d`
7. Wait for all healthchecks to pass

### Post-deploy verify

1. Run smoke tests: `project/scripts/smoke_security.sh`
2. Verify auth boundaries (console protected, API auth enforced)
3. Monitor logs and queue for 5-10 minutes
4. Record results in TEST_REPORT.md

## Rollback flow

1. Identify previous good release in `/opt/resto/releases/`
2. Switch symlink back: `/opt/resto/current/` -> previous release
3. `docker compose -f docker-compose.hostinger.prod.yml up -d`
4. Re-run smoke tests
5. Verify service stability
6. If DB migration was applied: evaluate safe roll-forward vs restore from backup

## Go/No-Go criteria

| Check | Must be |
| --- | --- |
| All healthchecks green | YES |
| Smoke tests pass | YES |
| No error spike in logs | YES |
| Queue depth stable | YES |
| Auth boundaries intact | YES |

## Key scripts

- `project/scripts/preflight-prod.sh` (preflight validation)
- `project/scripts/smoke_security.sh` (security smoke tests)
- `project/scripts/validate_go_no_go.sh` (go/no-go decision)
- `project/scripts/ops/rollback.sh` (emergency rollback)
- `project/scripts/ops/deploy_staging_to_node.sh` (staging deploy)

## Required output

- Step-by-step release checklist
- Emergency rollback procedure
- PATCHLOG.md entry
- TEST_REPORT.md entry
