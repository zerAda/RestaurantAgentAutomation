# RESTO BOT

## What This Is

RESTO BOT is a production restaurant automation platform that handles customer orders across multiple channels (WhatsApp, Instagram, Messenger, and a physical kiosk). It processes payments (COD, deposit, CIB, Edahabia), manages delivery drivers and zones, and uses an AI agent (llama3.1 via Ollama) for customer service. An admin dashboard gives operators real-time visibility into orders, inventory, analytics, and AI behavior.

The platform runs as 12 Docker containers on a Hostinger VPS, with Strapi CMS as the central configuration hub for all services.

## Core Value

Orders placed on any channel (messaging or kiosk) reach the kitchen, get paid, and get delivered — reliably and without manual intervention.

## Requirements

### Validated

- ✓ Multi-channel inbound: WhatsApp, Instagram, Messenger adapters — v3.0
- ✓ Kiosk self-service ordering app (React + Strapi products API) — v3.4.5
- ✓ Admin dashboard with kitchen view, stock, analytics, AI chat — v3.4.3
- ✓ Strapi CMS as config hub (40+ content types, roles, permissions) — v3.0
- ✓ Queue-mode n8n (main + worker + Bull/Redis) — v3.0
- ✓ Payment methods: COD, deposit, CIB, Edahabia — v3.0
- ✓ Driver assignment and delivery zone management — v3.2
- ✓ AI agent (llama3.1 Ollama) for customer service and admin — v3.3
- ✓ Fraud detection (flood rate, high-order threshold, cancel patterns) — v3.1
- ✓ Outbox pattern with exponential backoff (max 7 retries) — v3.0
- ✓ TLS termination via Traefik + Let's Encrypt — v3.0
- ✓ Rate limiting at Nginx gateway (8 zones) — v3.4.2
- ✓ Security hardening: Meta signature enforcement, query token blocking — v3.4.2
- ✓ CI/CD: 13 GitHub Actions workflows (lint, test, build, deploy, rollback) — v3.3
- ✓ Multi-language support: French + Arabic (RTL) — v3.1
- ✓ Loyalty tiers, marketing campaigns — v3.2

### Active

- [ ] CMS routes persisted in source (not runtime-injected via docker cp)
- [ ] Automated daily PostgreSQL backup with S3 offload
- [ ] Structured logging with correlation IDs across all services
- [ ] Smoke test suite for all 8 nginx routing zones + CORS validation
- [ ] Strapi permission matrix integration tests
- [ ] n8n workflow audit trail (compliance + debugging)
- [ ] Node.js 18 → 20 upgrade in all Dockerfiles (EOL security fix)
- [ ] Redis eviction policy + memory alerting
- [ ] PostgreSQL indexes on orders (status, created_at) for query performance
- [ ] Observability: metrics export (error rate, queue depth, latency P95)

### Out of Scope

- Real-time WebSocket dashboard — current polling model is sufficient for v3 ops
- n8n 2.x → 3.x upgrade — high blast radius, separate milestone after test coverage exists
- Mobile app — web kiosk covers current use case
- Multi-tenant (multiple restaurants) — single-restaurant deployment for now

## Context

- **Domain**: Restaurant / food delivery automation, North Africa market (FR/AR, Edahabia)
- **Version**: v3.4.0, actively deployed at `srv1258231.hstgr.cloud`
- **Known P0 tech debt**: CMS route files for ingredient, system-config, restaurant-brand etc. were manually injected via `docker cp` — lost on any CMS rebuild
- **Disk risk**: 119GB VPS drive; ENOSPC corrupts files; npm cache can eat 5GB
- **n8n quirks**: 2.9.4 task-runner spawns despite `N8N_RUNNERS_ENABLED=false`; CPU load normalized to ~9.6%
- **Test coverage**: Essentially zero for nginx routing, Strapi permissions, and most n8n workflows
- **No automated backup**: Data loss on DB corruption would be unrecoverable

## Constraints

- **Stack**: Docker Compose + Traefik + Nginx + n8n 2.9.4 + Strapi 5.37.1 + PostgreSQL 15 + Redis 7 — no major version changes this milestone
- **VPS**: 72.60.190.192 (deploy user, SSH key), 2 CPU / ~4GB RAM, 119GB disk
- **Public API contract**: `https://api.srv1258231.hstgr.cloud/v1/*` must remain stable
- **Zero downtime**: Changes must be deployable without service interruption
- **Security invariants**: console.*/cms.*/admin.* stay private; no secrets in git/logs

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Strapi as config hub | Single source of truth avoids config drift across services | ✓ Good |
| n8n queue mode | Reliability + scalability for high message volume | ✓ Good |
| nginx DNS resolver trick | Prevents 502 on CMS restarts without container recreation | ✓ Good |
| JWT in sessionStorage | XSS protection; tab-isolated | — Pending review |
| Brownfield: fix-first milestone | Platform is live; stabilize before adding features | — Pending |

---
*Last updated: 2026-03-18 after brownfield initialization*
