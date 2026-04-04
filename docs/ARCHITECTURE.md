# ARCHITECTURE (v3.5.0)

## High-level
```
Internet
  |
  |  HTTPS (Let's Encrypt via Traefik v3.6.6)
  v
Traefik (TLS termination, routing, allowlist, basic auth, rate limit)
  |                         |                      |
  | console.<domain>        | api.<domain>          | cms.<domain>
  v                         v                      v
n8n-main (UI, private)     Gateway (Nginx)        Strapi CMS (admin)
                              |
              ┌───────────────┼───────────────┐
              v               v               v
         n8n-main        Strapi CMS      Admin Dashboard
         (webhooks)      (API :1337)     (React :3000)
              |               |               |
              v               v               v
         Redis + Worker   pgBouncer      Kiosk App
         (Bull queue)    (conn pool)     (React :4000)
              |               |
              v               v
         Postgres 15     Ollama (LLM)
         (n8n + strapi)  Whisper (STT)
```

## 12 Services (Docker Compose)

| Service | Image | Port | Health |
|---------|-------|------|--------|
| traefik | traefik:3.6.6 | :443, :8080 | `GET /ping` |
| gateway | nginx:1.27-alpine | :8080 | `GET /healthz` |
| n8n-main | n8n:2.9.4 | :5678 | `GET /healthz` |
| n8n-worker | n8n:2.9.4 | — | `pgrep n8n` |
| postgres | postgres:15-alpine | :5432 | `pg_isready` |
| pgbouncer | edoburu/pgbouncer | :6432 | implicit |
| redis | redis:7-alpine | :6379 | `redis-cli ping` |
| cms | strapi 5.37.1 (node:20) | :1337 | `GET /_health` (204) |
| admin-dashboard | react 19 (node:20) | :3000 | `GET /` |
| kiosk-app | react 19 (node:20) | :4000 | `GET /` |
| ollama | ollama:0.6.2 | :11434 | `GET /api/tags` |
| whisper | openai/whisper-api | :9000 | `GET /docs` |

## Why this design
- **Stability**: the public API is versioned `/v1/...` and independent from n8n internal paths.
- **Security**: console is private (IP allowlist + BasicAuth). API internal namespaces are private too.
- **Scalability**: queue mode (worker) isolates execution load. pgBouncer pools connections (50 default, transaction mode).
- **Observability**: correlation IDs (X-Request-ID) from Nginx through Strapi and n8n. JSON structured logs. Queue metrics + Redis monitoring workflows.
- **Ops**: bootstrap DB single-file, idempotent migrations, scripts for preflight + smoke + deployment verification.

## Public vs Private
- Public: `api.<domain>/v1/inbound/*` (rate limit + shared token at workflow level)
- Private: `api.<domain>/v1/internal/*` and `/v1/admin/*` (enforced at Traefik: allowlist + BasicAuth)
- CMS admin: `cms.<domain>` (Traefik IP allowlist)

## Trust Boundaries
1. **Public/External** — Webhook endpoints (rate limited, Meta signature verified)
2. **Gateway** (Nginx) — Filters query tokens, blocks `/v1/admin`, `/v1/internal`, 8 rate-limit zones
3. **Internal Network** — Docker `internal` network (postgres, redis, n8n, cms, pgbouncer)
4. **Admin Console** — BasicAuth + IP allowlist (Traefik)

## Naming conventions
- Domains:
  - `console` = UI/admin
  - `api` = external integrations
  - `cms` = Strapi admin panel
- Paths:
  - `/v1/inbound/<channel>` : messages entrants
  - `/v1/internal/<area>/<action>` : ops/backoffice
  - `/v1/admin/<area>/<action>` : admin/tenants/rbac
  - `/v1/strapi/*` : CMS API proxy

## Key Data Flows
- **Inbound order**: WhatsApp → Traefik → Nginx (signature verify) → n8n-main (webhook) → Redis (queue) → n8n-worker (process) → Strapi (create order) → PostgreSQL
- **Audit trail**: n8n inbound workflows → fire-and-forget → W_AUDIT_WRITE → workflow_audit table → W_AUDIT_QUERY (admin dashboard) → W_AUDIT_ARCHIVE (90-day rotation)
- **Monitoring**: W_QUEUE_METRICS (queue depth, error rate) + W_REDIS_MONITOR (memory alerts) → structured logs / alert webhooks
