# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Resto Bot is a production-grade n8n-based messaging platform for restaurants. It enables receiving/sending messages across WhatsApp, Instagram, and Messenger with AI-powered responses, order management, delivery, and admin support consoles.

**Stack:** n8n workflows (queue mode) + PostgreSQL + Redis + Nginx gateway + Traefik reverse proxy

## Architecture

```
Internet → Traefik (TLS/routing) → Two paths:
├─ Console: console.<domain> → n8n UI (private, IP allowlist + BasicAuth)
└─ API: api.<domain> → Nginx Gateway → n8n webhooks (versioned /v1/...)
                              ↓
                        n8n Main + Worker (queue mode via Redis)
                              ↓
                        PostgreSQL (app + n8n schema)
```

**Key design decisions:**
- n8n hidden behind Nginx gateway exposing clean versioned API paths (`/v1/...`)
- Queue mode (main + worker) for scalability
- Multi-tenant isolation via `tenant_id` and `restaurant_id`
- Security layers: Traefik (rate limit, IP allowlist) → Nginx (token blocking) → Workflows (token/scope validation)

## Common Commands

### Development & Testing
```bash
# Smoke tests (health + basic inbound)
./scripts/smoke.sh

# Meta-specific tests (verify, signature, anti-replay)
./scripts/smoke_meta.sh

# Full test battery (100 tests)
./scripts/test_battery.sh
./scripts/test_battery.sh --section 4  # Run only section 4

# End-to-End tests
./scripts/test_e2e.sh --env local --verbose

# Security smoke tests
./scripts/smoke_security.sh
./scripts/smoke_security_gateway.sh

# Pre-commit quality checks (bash syntax, placeholders, JSON, workflow gates)
./scripts/integrity_gate.sh

# Full CI test harness (spins up stack, runs migrations, imports workflows, tests)
./scripts/test_harness.sh

# Python validators
python3 scripts/validate_contracts.py      # JSON Schema validation
python3 scripts/test_l10n_script_detection.py  # Localization
python3 scripts/test_template_render.py    # Template rendering
python3 scripts/test_darja_intents.py      # Moroccan Darija NLP
```

### Database
```bash
./scripts/db_migrate.sh          # Run migrations
./scripts/db_explain.sh          # Query explain analysis
./scripts/backup_postgres.sh     # Backup with rotation
./scripts/restore_postgres.sh    # Restore from backup
```

### Docker Compose
```bash
# Production (Hostinger)
docker compose -f docker-compose.hostinger.prod.yml up -d

# Local dev
docker compose -f docker/docker-compose.yml up -d

# CI/test
docker compose -f docker/docker-compose.test.yml up -d
```

### Workflow Management
```bash
# After importing workflows in n8n, generate workflow ID mapping
./scripts/generate_workflow_ids.sh
```

## Workflows (W0-W14)

| Workflow | Purpose |
|----------|---------|
| W0 | Meta webhook signature verification |
| W1/W2/W3 | Inbound ingestion (WhatsApp/Instagram/Messenger) |
| W4 | Core orchestration: parsing, LLM, intent routing, template rendering |
| W5/W6/W7 | Outbound adapters (WhatsApp/Instagram/Messenger) |
| W8 | Operations: retention purge, SLO alerts, daily cleanup |
| W9 | Admin ping (scope enforcement testing) |
| W10 | Customer delivery quote |
| W11/W12 | Admin delivery zones / orders |
| W14 | Admin WhatsApp support console |
| W15 | Outbox worker (retry + DLQ) |
| W16 | Health check endpoint |
| W17 | Health monitor (scheduled) |
| W18 | Media fetch worker (Graph API) |

## Request Flow

1. **Inbound** → Traefik → Nginx Gateway → n8n webhook (W1/W2/W3)
2. **Parse & Validate** → Parse payload, validate contract, enforce scopes
3. **Log & Route** → Store in `inbound_messages`, call W4 (CORE)
4. **W4 Core** → Script detection (AR/FR/Darija), LLM inference, intent recognition
5. **Outbound** → W5-W7 send via provider APIs

## Key Configuration Flags

Security (in `.env`):
- `ALLOW_QUERY_TOKEN=false` - Block tokens in query string (recommended)
- `LEGACY_SHARED_ALLOWED=false` - Kill-switch for deprecated shared token
- `META_SIGNATURE_REQUIRED` - Webhook signature validation (off/warn/enforce)

Localization:
- `L10N_ENABLED=true` - FR/AR detection & preference persistence
- `STRICT_AR_OUT=true` - AR-in → AR-out guarantee

Features:
- `DELIVERY_ENABLED`, `SUPPORT_ENABLED`, `FAQ_ENABLED`
- `FRAUD_INBOUND_ENABLED`, `FRAUD_CHECKOUT_ENABLED`
- `ADMIN_WA_CONSOLE_ENABLED`

## Database Conventions

- Tables use `snake_case`, enums are `_enum`, functions are `namespace.name`
- Migrations in `db/migrations/` are idempotent (use `IF NOT EXISTS`, `ON CONFLICT`)
- Bootstrap schema in `db/bootstrap.sql` for fresh installs
- Security events logged to `security_events` table with `event_type` enum

## API Conventions

- Public endpoints versioned: `/v1/inbound/whatsapp`, `/v1/inbound/instagram`, `/v1/inbound/messenger`
- Auth: `x-webhook-token` or `Authorization: Bearer` header (never query string in prod)
- Tokens stored hashed (sha256) in `api_clients` table
- Contract validation via JSON Schema (`schemas/` directory)
- Body `tenant_context` is never trusted; context resolved server-side from token

## Code Patterns

- Workflows follow `W<N>_<DESCRIPTION>.json` naming
- Feature flags follow `FEATURE_COMPONENT_ACTION` pattern
- All auth denials logged to `security_events` with parameterized `event_type`
- Inbound workflows must have: `ALLOW_QUERY_TOKEN` gating, `scopeOk` enforcement, contract validation
