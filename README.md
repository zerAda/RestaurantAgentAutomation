# RESTO BOT – v3.5.0 (Production-grade)

## Objectif
Plateforme d'automatisation restaurant omnicanale, déployée en production sur VPS Hostinger.

### Stack
- **12 conteneurs Docker** : Traefik (TLS), Nginx (gateway), n8n 2.9.4 (main + worker), PostgreSQL 15, pgBouncer, Redis 7, Strapi 5.37.1 (CMS), admin-dashboard (React 19), kiosk-app (React 19), Ollama (LLM), Whisper (STT)
- **UI privée** (console) : `https://console.<domain>`
- **API publique** (gateway) : `https://api.<domain>/v1/...`
- n8n **non exposé** côté API (proxy via gateway)
- stack **queue mode** (n8n main + worker + Redis Bull)
- DB bootstrap **single-file** + **migrations idempotentes** (`db/migrations/`)

## Contenu
- `workflows/` : 100+ workflows n8n (inbound, core, ops, audit, metrics, AI agents)
- `db/bootstrap.sql` : schéma + seeds (fresh install)
- `db/migrations/` : patchs idempotents (upgrade in place) — indexes, audit trail, etc.
- `infra/gateway/` : config Nginx (8 zones de routing, rate limiting, correlation IDs)
- `inventory-cms/` : Strapi 5.37.1 CMS (40+ content types, plugins, RBAC)
- `admin-dashboard/` : Dashboard React 19 (orders, analytics, audit log, AI chat)
- `kiosk-app/` : Application kiosk React 19 (commande client, menu caché 5 min)
- `docker-compose.hostinger.prod.yml` : stack prod avec Traefik + TLS
- `config/.env.example` : variables requises
- `scripts/` : integrity gate, smoke tests, deployment verification, DB tools
- `docs/` : 60+ fichiers de documentation (architecture, runbooks, SLO, sécurité)
- `.planning/` : roadmap 7 phases, requirements, state tracking

## Quickstart (prod)
1) `cp config/.env.example .env` et renseigne **DOMAIN_NAME**, **SSL_EMAIL**, **ADMIN_ALLOWED_IPS** (+ `TRAEFIK_TRUSTED_IPS`).

   **Note** : `ALLOW_QUERY_TOKEN=false` par défaut (recommandé) pour éviter la fuite de token dans les logs.
2) Crée les secrets dans `./secrets/` (voir `docs/RUNBOOK_HOSTINGER.md`)
3) `docker compose -f docker-compose.hostinger.prod.yml up -d`
4) Ouvre la console : `https://console.<domain>` (BasicAuth + allowlist)
5) Importe `workflows/` et active :
   - W4 CORE
   - W1/W2/W3 inbound
   - W8 OPS
   - W_QUEUE_METRICS, W_REDIS_MONITOR (observabilité)
   - W_AUDIT_WRITE, W_AUDIT_QUERY, W_AUDIT_ARCHIVE (audit trail)
6) Lance `./scripts/generate_workflow_ids.sh` puis exporte `CORE_WORKFLOW_ID`

## API v1 (exemples)
- POST `/v1/inbound/whatsapp`
- POST `/v1/inbound/instagram`
- POST `/v1/inbound/messenger`

Auth : `x-webhook-token: <WEBHOOK_SHARED_TOKEN>` **ou** `Authorization: Bearer <WEBHOOK_SHARED_TOKEN>`

Si tu dois maintenir un ancien client qui ne sait envoyer que `?token=...`, active explicitement `ALLOW_QUERY_TOKEN=true`.

Plus : `docs/API_CONVENTIONS.md`

## Statut du projet (2026-04-04)

| Phase | Statut |
|-------|--------|
| 1. CMS Stability & Base Upgrade | 3/4 plans (gap closure pending) |
| 2. Structured Logging & Correlation | Complete |
| 3. Metrics, Alerting & Audit Trail | 4/5 plans (METR-04/05 pending) |
| 4. Test Coverage — Routing | Not started |
| 5. Test Coverage — n8n E2E | Not started |
| 6. Performance Tuning | 4/5 plans (7/9 requirements) |
| 7. NemoClaw Telegram Bot | 1/4 plans |

Voir `.planning/ROADMAP.md` pour les détails.
