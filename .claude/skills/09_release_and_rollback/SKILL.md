---
name: release_and_rollback
description: Safe production releases with preflight checks, deploy, verify, and emergency rollback.
when_to_use:
  - Deploying to production
  - Changing compose or routing config
  - Rolling out P0 fixes
  - Production outage or incident
---

# Release & Rollback

## Preflight (must pass before deploy)

```bash
make preflight          # integrity + lint + security
make test-unit          # contract + l10n + template tests
scripts/validate_go_no_go.sh  # go/no-go decision
```

- Config validation: compose syntax, Traefik labels, gateway nginx -t
- ENV completeness: all required vars in VPS `.env`
- DB migration plan reviewed + backup verified
- Smoke tests ready

## Release flow

1. `make backup` — backup DB (verify backup file exists and size > 0)
2. Push to main — triggers CI pipeline
3. CI passes — triggers build-push-artifacts + cd-deploy
4. cd-deploy: SSH to VPS, pull images, compose up, run health check
5. Verify: `make smoke` + check health endpoints
6. Monitor logs and queue for 10 minutes
7. Record in PATCHLOG.md + TEST_REPORT.md

## Emergency rollback

### Via GitHub Actions
- Trigger `.github/workflows/rollback.yml` (manual dispatch)
- Selects previous release and redeploys

### Manual rollback
```bash
ssh deploy@<vps>
cd /opt/resto
# Restore previous compose
cp releases/<previous>/docker-compose.yml .
docker compose -f docker-compose.hostinger.prod.yml up -d
# Restore DB if needed
scripts/restore_postgres.sh /opt/resto/backups/<latest>.sql.gz
scripts/db_migrate_all.sh
```

### Verify rollback
```bash
make smoke
curl -s https://api.<domain>/v1/health
```

## Incident triage decision tree

1. Is public API down? -> Check Traefik + gateway containers
2. Is TLS broken? -> Check ACME cert, Traefik logs
3. Gateway up but upstream failing? -> Check n8n-main, n8n-worker
4. Queue backed up? -> Check Redis, worker logs
5. DB failing? -> Check Postgres logs, disk space, connections

## Containment actions

- Auth leak: rotate tokens immediately, tighten IP allowlist
- DoS: increase rate limits, reduce body size caps, block IPs
- Data breach: isolate affected service, audit access logs, rotate all secrets

## Go/No-Go criteria

| Check | Go | No-Go |
|-------|-----|-------|
| CI pipeline | green | any failure |
| Smoke tests | all pass | any 5xx |
| Health endpoint | 200 in <2s | timeout or error |
| Queue depth | stable or decreasing | growing unbounded |
| Error rate | <1% | >5% |

## Deliverables

- Preflight results
- Release checklist (step-by-step)
- Rollback procedure (tested or documented)
- Post-release monitoring evidence
