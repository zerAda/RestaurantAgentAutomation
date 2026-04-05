# RESTO BOT — OpenCode Context (v3.5.0)

> This file is auto-loaded by OpenCode as system context. It replaces the CLAUDE.md context file.

## Project Identity

**RESTO BOT** is a production restaurant automation platform for the Algerian market.
- **Core value**: Orders placed on any channel (WhatsApp, Instagram, Messenger, kiosk) reach the kitchen, get paid, and get delivered — reliably and without manual intervention.
- **Version**: v3.5.0
- **Host**: Hostinger VPS (72.60.190.192), 2 CPU / ~4GB RAM / 119GB disk
- **Domain**: `srv1258231.hstgr.cloud`

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Routing | Traefik | 3.6.6 |
| Gateway | Nginx | 1.27-alpine |
| Orchestration | n8n | 2.9.4 |
| Queue | Redis | 7-alpine |
| Database | PostgreSQL | 15-alpine |
| Connection Pool | pgBouncer | latest |
| Config Hub | Strapi | 5.37.1 |
| Admin UI | React | 19.2 |
| Kiosk | React | 19.2 |
| AI/LLM | Ollama | 0.6.2 (llama3.1) |
| STT | Whisper | openai |
| Node.js | 20-alpine | LTS |
| CI/CD | GitHub Actions | 13 workflows |

## Architecture (12 Docker Containers)

```
Internet → Traefik (TLS) → Nginx Gateway (8 rate-limit zones)
  ├── n8n-main (webhooks) → Redis → n8n-worker (queue)
  ├── Strapi CMS (40+ content types) → pgBouncer → PostgreSQL 15
  ├── Admin Dashboard (React 19, lazy-loaded)
  ├── Kiosk App (React 19, 5-min menu cache)
  ├── Ollama (llama3.1 LLM)
  └── Whisper (STT)
```

## Key Directories

| Path | Purpose |
|------|---------|
| `workflows/` | 100+ n8n workflow JSON files |
| `db/bootstrap.sql` | Fresh install schema + seeds |
| `db/migrations/` | Idempotent SQL patches |
| `infra/gateway/nginx.conf` | 8 routing zones, rate limiting, correlation IDs |
| `inventory-cms/` | Strapi 5.37.1 CMS (TypeScript) |
| `admin-dashboard/` | React 19 admin UI (Vite, TailwindCSS) |
| `kiosk-app/` | React 19 kiosk ordering (Vite, TailwindCSS) |
| `scripts/` | 20+ automation scripts |
| `docs/` | 60+ documentation files |
| `.planning/` | GSD roadmap, requirements, state |

## Security Invariants (NEVER VIOLATE)

1. `console.*`, `cms.*`, `admin.*` subdomains stay PRIVATE (IP allowlist + BasicAuth)
2. No secrets in git or logs — ever
3. Public API contract `https://api.<domain>/v1/*` must remain stable
4. Meta webhook signature enforcement in production (`META_SIGNATURE_REQUIRED=enforce`)
5. Query token blocking enabled (`ALLOW_QUERY_TOKEN=false`)

## Development Rules

1. **Evidence-based**: Read files, configs, scripts before making assumptions
2. **Fix-first**: No new features this milestone — stabilize before extending
3. **Atomic commits**: Each commit should be independently deployable
4. **Zero downtime**: Changes must be deployable without service interruption
5. **CMS routes**: Fix via TypeScript source in `inventory-cms/src/api/` — never runtime injection
6. **Idempotent migrations**: All SQL in `db/migrations/` must use `IF NOT EXISTS` / `DO $$ ... $$`
7. **No n8n 3.x**: Deferred until test coverage exists (high blast radius)

## Quality Gate (10-loop)

Before finalizing any plan or patch:
1. Correctness: works end-to-end?
2. Contract safety: keeps `/v1` stable?
3. Security: reduces attack surface? New leak paths?
4. Reliability: survives retries, timeouts, partial failures?
5. Ops: deployable/rollable back quickly?
6. Observability: detectable and debuggable?
7. Data safety: backups/restore/migrations safe?
8. Performance: risk of queue backlog, DB lock, memory blowup?
9. DX: new engineer can run it locally?
10. Audit readiness: can we explain & prove controls?

## Current Roadmap Status (2026-04-04)

| Phase | Status | Progress |
|-------|--------|----------|
| 1. CMS Stability & Base Upgrade | In progress | 3/4 plans |
| 2. Structured Logging & Correlation | Complete | 5/5 |
| 3. Metrics, Alerting & Audit Trail | Mostly complete | 4/5 (METR-04/05 pending) |
| 4. Test Coverage — Routing | Not started | 0/3 |
| 5. Test Coverage — n8n E2E | Not started | 0/2 |
| 6. Performance Tuning | Mostly complete | 4/5 (PERF-03/08 pending) |
| 7. NemoClaw Telegram Bot | In progress | 1/4 |

**Requirements**: 21/34 complete. See `.planning/REQUIREMENTS.md` for details.

## Key Files to Read First

1. `opencode.md` (this file)
2. `.planning/PROJECT.md` — Vision + constraints
3. `.planning/ROADMAP.md` — 7-phase strategy
4. `.planning/REQUIREMENTS.md` — 34 requirements with status
5. `.planning/STATE.md` — Current position + decisions
6. `docs/ARCHITECTURE.md` — System design
7. `docs/API_CONVENTIONS.md` — v1 API contract
8. `ENV_REFERENCE.md` — All configuration variables

## GSD Workflow

This project uses the **GSD (Get Shit Done)** methodology. Planning artifacts live in `.planning/`:
- `PROJECT.md` — Vision, requirements, constraints, key decisions
- `ROADMAP.md` — Phase breakdown with success criteria
- `REQUIREMENTS.md` — 34 tracked requirements with traceability
- `STATE.md` — Current position, velocity, accumulated context
- `phases/XX-name/` — Per-phase research, plans, summaries, verification

Use `/project:gsd-*` commands to interact with the GSD workflow.

## Naming Conventions

- **Domains**: `console` = admin, `api` = external, `cms` = Strapi
- **API paths**: `/v1/inbound/<channel>`, `/v1/internal/<area>/<action>`, `/v1/admin/<area>/<action>`
- **Workflows**: `W1..W8` core, `W_*` specialized (e.g., `W_AUDIT_WRITE`, `W_QUEUE_METRICS`)
- **Migrations**: `db/migrations/YYYY-MM-DD_pX_description.sql`
- **Branches**: `feature/*`, `fix/*`, `docs/*`
