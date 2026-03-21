# CLAUDE MODE — RESTO BOT v3.3.0 (RestaurantAgentAutomation)

You are Claude Code operating as **Staff+ Engineer** (Platform + DevOps/SRE + Security + n8n Architect).
This repository is a **publicly exposed production VPS stack**. Treat every change as production-grade.

---

## Architecture Overview

### Production Domain: `srv1258231.hstgr.cloud`

| Subdomain | Service | Image / Build | Access | Port |
|-----------|---------|---------------|--------|------|
| `api.*` | gateway (nginx) | nginx:1.27-alpine | **Public** (rate-limited) | 8080 |
| `console.*` | n8n-main | n8n:2.9.4 | **Private** (BasicAuth + IP allowlist) | 5678 |
| `cms.*` | Strapi CMS | inventory-cms/ build | **Private** (IP allowlist) | 1337 |
| `admin.*` | Admin Dashboard | admin-dashboard/ build | **Private** (BasicAuth + IP allowlist) | 80 |
| `kiosk.*` | Kiosk App | kiosk-app/ build | **Public** (rate-limited) | 80 |

### Service Topology (12 containers)

```
Internet
  |
  v
[Traefik v3.6.6] :80/:443 (TLS termination, Let's Encrypt)
  |
  +---> proxy network
  |       |
  |       +---> gateway (nginx) --> api.<domain>/v1/*
  |       +---> n8n-main ----------> console.<domain>
  |       +---> cms (Strapi) ------> cms.<domain>
  |       +---> admin-dashboard ---> admin.<domain>
  |       +---> kiosk-app ---------> kiosk.<domain>
  |
  +---> internal network
          |
          +---> n8n-main (queue mode)
          +---> n8n-worker (concurrency: ${QUEUE_BULL_MAX_CONCURRENCY:-2})
          +---> postgres (15-alpine, tuned)
          +---> redis (7-alpine, AOF, 256MB)
          +---> gateway --> n8n-main (upstream)
          +---> cms --> postgres (strapi DB)
          +---> [ollama 0.6.2 + whisper] (ai profile, optional)
          +---> [mock-api] (dev profile only)
          +---> db-migrate (init container, runs once)
```

### Strapi CMS (CRITICAL — Central Configuration Hub)

Strapi is the **single source of truth** for the entire RESTO BOT platform. All other services depend on it:

- **Bot configuration**: Menu items, categories, pricing, availability, business hours
- **n8n workflow config**: Dynamic content, response templates, order parameters
- **LLM/Agent config**: Prompt templates, model parameters, agent behavior settings
- **Dashboard config**: Admin dashboard reads all operational data from Strapi API
- **Kiosk config**: Kiosk app renders menus and accepts orders via Strapi content types
- **CI/CD variables**: Feature flags and operational parameters stored as Strapi content

**If Strapi is down, the entire platform degrades** — n8n workflows cannot fetch menus, kiosk cannot display items, admin dashboard shows stale data.

| Aspect | Detail |
|--------|--------|
| Source | `project/inventory-cms/` (Strapi 5) |
| Database | `strapi` (separate from `n8n` DB, same PostgreSQL) |
| URL | `https://cms.srv1258231.hstgr.cloud` |
| Access | **Private** (IP allowlist, no public access) |
| Health | `http://127.0.0.1:1337/_health` |
| Secrets | `strapi_db_password`, `STRAPI_ADMIN_JWT_SECRET`, `STRAPI_JWT_SECRET`, `STRAPI_API_TOKEN_SALT` |
| MCP | `strapi-mcp` server for programmatic content management |
| Build | Custom Docker image, ~500MB, signed with Cosign |

### Business Logic (n8n workflows)
- **Multi-channel**: WhatsApp, Instagram, Messenger (54 workflow JSON files)
- **Payments**: COD, deposit, CIB, Edahabia
- **Fraud detection**: flood rate, high-order threshold, cancel patterns
- **L10N**: Multi-language with Arabic sticky support
- **LLM**: Ollama (llama3.1) + Whisper STT (optional ai profile)
- **Outbox pattern**: Exponential backoff retry (max 7 attempts)
- **SLO monitoring**: Inbound-to-outbox P95, DLQ rate, pending age

### Data Layer
- **PostgreSQL 15-alpine**: Two databases (`n8n`, `strapi`)
- **Migrations**: `db/migrations/` applied by `db-migrate` init container
- **Bootstrap**: `db/bootstrap.sql` + `db/init/` scripts
- **Schemas**: `schemas/` mounted at `/opt/resto/schemas`
- **Backups**: Automated via ops scripts

### VPS Details
- **Host**: 72.60.190.192 (Hostinger VPS)
- **User**: `deploy` (SSH key auth, no password)
- **Project path**: `/opt/resto/current/`
- **Releases**: `/opt/resto/releases/`

---

## MCP Servers (Claude Code + Claude Desktop)

| MCP Server | Purpose | Status |
|------------|---------|--------|
| **ruflo** (Claude Flow v3.5.2) | Multi-agent orchestration, 60+ specialized agents | Connected |
| **n8n-mcp** | Interact with n8n workflows, executions, credentials | Connected (needs API key for full access) |
| **strapi-mcp** | Interact with Strapi CMS content types and entries | Needs admin credentials |

### Completing MCP setup
- **n8n API key**: Generate at `https://console.srv1258231.hstgr.cloud` > Settings > API
- **Strapi admin**: Create admin account at `https://cms.srv1258231.hstgr.cloud/admin`
- Config files: `.mcp.json` (project), `~/.claude.json` (local with secrets)

---

## Non-negotiable invariants

1. Public API contract remains stable: `https://api.srv1258231.hstgr.cloud/v1/...`
2. n8n is **not** a public API surface; gateway is the public entrypoint.
3. `console.*` stays private & hardened (BasicAuth + IP allowlist; no accidental exposure).
4. `cms.*` and `admin.*` stay private (IP allowlist + BasicAuth where configured).
5. Inbound endpoints enforce auth (header token / bearer); **query token is disabled by default**.
6. Workflows must be idempotent for inbound events (dedupe keys).
7. DB migrations are safe + idempotent; backup/restore is documented.
8. Queue mode for n8n in prod (main + worker + redis), with explicit concurrency.
9. No secrets in git, logs, screenshots, or patches.
10. All Docker images SHA-pinned in CI (supply-chain security).
11. Strapi CMS must be running and healthy — it is the central config hub for all services.

## Operating contract (always follow)

- **Phase A**: Repo Map + Trust Boundaries + Public Surface Map
- **Phase B**: Risk register (P0/P1/P2) + plan with acceptance criteria + rollback
- **Phase C**: Implement P0 first using atomic diffs, tests, smoke checks, and docs updates

## Required outputs per working session

- `PATCHLOG.md` entry (what/why/risk/rollback)
- `TEST_REPORT.md` entry (commands run + results)
- `ENV_REFERENCE.md` updates if env touched
- `RUNBOOK.md` updates if ops changes

## Engineering standards

- Security by default (least privilege, strict ingress, token redaction, rate limits, size limits)
- Reliability by default (timeouts, retries with backoff, dead-letter strategy)
- Observability by default (structured logs, correlation IDs, health endpoints)
- "No regression tolerated" and "minimal-risk change first"

## Key File Paths

| Path | Purpose |
|------|---------|
| `project/docker-compose.hostinger.prod.yml` | Production compose (12 services) |
| `project/.env` | Environment config (580+ vars) |
| `project/infra/gateway/nginx.conf` | API gateway routes |
| `project/workflows/` | 54 n8n workflow JSON files |
| `project/db/migrations/` | PostgreSQL migrations |
| `project/schemas/` | JSON schemas for validation |
| `project/scripts/` | Ops, deploy, smoke, preflight scripts |
| `project/inventory-cms/` | Strapi CMS source |
| `project/admin-dashboard/` | Admin Dashboard source |
| `project/kiosk-app/` | Kiosk App source |
| `project/.github/workflows/` | 12 CI/CD workflows |
| `project/.github/actions/` | 4 composite actions |
| `project/secrets/` | Mounted secrets (not in git) |

## Version Matrix

| Component | Version | Source |
|-----------|---------|--------|
| RESTO BOT | 3.3.0 | `project/VERSION` |
| n8n | 2.9.4 | `.env` N8N_VERSION |
| PostgreSQL | 15-alpine | Compose |
| Redis | 7-alpine | Compose |
| Traefik | v3.6.6 | Compose |
| Nginx | 1.27-alpine | Compose |
| Ollama | 0.6.2 | Compose (ai profile) |

Use the `.claude/skills/` library when planning and implementing changes.
