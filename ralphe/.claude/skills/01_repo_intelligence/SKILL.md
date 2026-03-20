---
name: repo_intelligence
description: Build evidence-based repo map with actual file paths, trust boundaries, and operational topology.
when_to_use:
  - First session on the repo
  - Before any production change
  - Diagnosing incidents or onboarding
---

# Repo Intelligence Protocol

## Goal
Produce a verified map of the system grounded in actual file paths.

## Extraction checklist (must cite file:line)

### 1. Entry points & domains
- `docker-compose.hostinger.prod.yml` — Traefik labels define all public routes
- `api.<domain>/v1/*` — public API via `infra/gateway/nginx.conf`
- `console.<domain>` — n8n UI (IP allowlist + BasicAuth via Traefik labels)
- `cms.<domain>` — Strapi CMS
- `admin.<domain>` — Admin dashboard (IP allowlist + BasicAuth)
- `kiosk.<domain>` — Kiosk app (public, rate-limited)

### 2. Proxy chain
```
Internet -> Traefik (TLS termination, middlewares) -> Nginx gateway -> n8n/Strapi/apps
```
- Traefik: Docker CLI flags + labels only (no separate config files)
- Gateway: `infra/gateway/nginx.conf` + `infra/gateway/proxy_params`

### 3. Auth mechanisms
- Header token: `x-webhook-token` validated in gateway before proxy
- Meta signature: verified in `workflows/W0_META_VERIFY_UNIFIED.json`
- Token scope: `B0 - Token OK?` node with `scopeOk` enforcement
- Admin validator: `B1a - Admin Access Validator (SECURED)` in W1_IN_WA
- Tenant isolation: `restaurant_id.$eq` with `tenant_context` on all Strapi nodes

### 4. n8n topology
- Queue mode: `n8n-main` (webhook receiver) + `n8n-worker` (execution) + `redis`
- DLQ: `W8_DLQ_HANDLER.json`, `W8_DLQ_REPLAY.json`
- Outbox: `W15_OUTBOX_WORKER.json`
- Health: `W16_HEALTHZ.json`, `W17_HEALTH_MONITOR.json`

### 5. Data layer
- Bootstrap: `db/bootstrap.sql`
- Migrations: `db/migrations/` (date-prefixed, idempotent)
- Init: `db/init/01_apply_migrations.sh`, `db/init/02_create_strapi_db.sh`
- Schemas: `schemas/inbound/v1.json`, `schemas/inbound/v2.json`

### 6. Workflows
- Workflow JSON files in `workflows/` (count with `ls workflows/*.json | wc -l`)
- Naming: `W<N>_<NAME>.json` or `W_<NAME>.json`
- Validated by `scripts/integrity_gate.sh` (10-point check)
- Contracts validated by `scripts/validate_contracts.py`

### 7. Ops primitives
- Task runner: `Makefile` (up, down, up-prod, migrate, backup, lint, integrity, smoke, ci)
- Backup: `scripts/backup_postgres.sh`, `scripts/backup_redis.sh`, `scripts/backup_media.sh`
- Restore: `scripts/restore_postgres.sh`
- Smoke: `scripts/smoke.sh`, `scripts/smoke_security_gateway.sh`
- Tests: `scripts/test_harness.sh`, `scripts/test_battery.sh`, `tests/k6-load-test.js`
- CI: 13 GitHub Actions workflows in `.github/workflows/`

## Required output
- Repo Map (bullet list with file paths)
- Trust Boundary Diagram (ASCII)
- Public Surface Map (endpoint -> method -> auth -> upstream)
- Failure Impact Table (component -> failure -> user impact -> mitigation)

## Verification
- Every claim must reference an actual file path
- Run `make preflight` to confirm operational state
