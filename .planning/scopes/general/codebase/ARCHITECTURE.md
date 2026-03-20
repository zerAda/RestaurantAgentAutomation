# Architecture

**Analysis Date:** 2026-03-20

## Pattern Overview

**Overall:** Multi-tier microservice platform with reverse-proxy ingress, queue-based workflow engine, and headless CMS as single source of truth.

**Key Characteristics:**
- All public traffic enters through Traefik (TLS termination) then nginx gateway (routing/auth)
- n8n operates in queue mode: n8n-main (scheduler/webhook receiver) + n8n-worker (execution)
- Strapi CMS is the single source of truth for all configuration: menu, pricing, prompts, feature flags
- Two Docker networks: `proxy` (internet-facing services) and `internal` (service-to-service only)
- All secrets are file-based Docker secrets (`/run/secrets/`), never plain-text environment variables
- Every container drops ALL Linux capabilities (`cap_drop: ALL`) with only minimal caps re-added where required

## Networks

**proxy network:**
- External Docker network named `proxy`
- Members: traefik, gateway, n8n-main, cms, admin-dashboard, kiosk-app
- Purpose: Traefik discovers services via Docker labels; only Traefik binds ports 80/443 on the host

**internal network:**
- External Docker network named `internal`
- Members: n8n-main, n8n-worker, postgres, redis, gateway, cms, ollama (ai profile), whisper (ai profile), mock-api (dev profile), db-migrate
- Purpose: Service-to-service communication; not reachable from the internet
- Key: postgres and redis are on `internal` only — never on `proxy`

## Service Inventory (12 containers)

**traefik** (`traefik:v3.6.6`):
- Purpose: TLS termination, Let's Encrypt ACME (TLS challenge), HTTP→HTTPS redirect, middleware chains
- Networks: proxy only
- Mounts: Docker socket (read-only), `secrets/traefik_usersfile`, `traefik_data` volume (ACME/cert storage)
- Resources: 0.5 CPU, 256 MB RAM

**gateway** (`nginx:1.27-alpine`):
- Purpose: Public API gateway; routes `/v1/*` to n8n webhooks and Strapi proxy; enforces rate limits, security headers, and query-token blocking
- Networks: proxy + internal
- Mounts: `infra/gateway/nginx.conf`, `infra/gateway/proxy_params` (both read-only)
- Resources: 0.25 CPU, 128 MB RAM
- Exposes port 8080 to proxy network; Traefik routes `api.<domain>` to port 8080

**n8n-main** (`docker.n8n.io/n8nio/n8n:${N8N_VERSION}`):
- Purpose: Workflow scheduler, webhook receiver, n8n editor UI at console subdomain
- Networks: proxy + internal
- Depends on: postgres (healthy), redis (healthy), db-migrate (completed)
- Resources: 1.0 CPU, 1 GB RAM
- Mounts: `n8n_data` volume, `secrets/postgres_password`, `secrets/n8n_encryption_key`, `schemas/` read-only at `/opt/resto/schemas`

**n8n-worker** (`docker.n8n.io/n8nio/n8n:${N8N_VERSION}`):
- Purpose: Queue worker for Bull/Redis; executes workflows dispatched by n8n-main
- Networks: internal only (no proxy exposure)
- Depends on: postgres (healthy), redis (healthy), db-migrate (completed)
- Resources: 0.75 CPU, 768 MB RAM
- Concurrency: `QUEUE_BULL_MAX_CONCURRENCY` (default 2)
- Custom entrypoint: `project/scripts/n8n-worker-entrypoint.sh`

**postgres** (`postgres:15-alpine`):
- Purpose: Primary database; hosts two databases: `n8n` (workflows/business logic) and `strapi` (CMS content)
- Networks: internal only
- Resources: 1.0 CPU, 1 GB RAM
- Tuning: shared_buffers=256MB, effective_cache_size=768MB, wal_buffers=16MB, max_connections=100, log_min_duration_statement=1000ms
- Init scripts: `db/bootstrap.sql` + `db/init/01_apply_migrations.sh` + `db/init/02_create_strapi_db.sh` run once at first start

**redis** (`redis:7-alpine`):
- Purpose: Bull queue broker between n8n-main and n8n-worker; AOF persistence
- Networks: internal only
- Resources: 0.5 CPU, 384 MB RAM
- Optional password auth via `REDIS_PASSWORD`; custom entrypoint: `infra/redis/entrypoint.sh`

**cms** (custom build from `project/inventory-cms/`):
- Purpose: Strapi 5 CMS — central configuration hub for menus, orders, prompts, feature flags
- Networks: proxy + internal
- Depends on: postgres (healthy), db-migrate (completed)
- Resources: 0.5 CPU, 512 MB RAM
- Health: `http://127.0.0.1:1337/_health`
- CORS: restricted to `admin.<domain>`, `kiosk.<domain>`, `cms.<domain>`

**admin-dashboard** (custom build from `project/admin-dashboard/`):
- Purpose: React/Vite backoffice dashboard for restaurant operators
- Networks: proxy only
- Resources: 0.25 CPU, 128 MB RAM
- Build args: `VITE_DOMAIN`, `VITE_STRAPI_URL` = `https://cms.<domain>` (baked at image build time)

**kiosk-app** (custom build from `project/kiosk-app/`):
- Purpose: Public-facing React/Vite ordering kiosk
- Networks: proxy only
- Resources: 0.25 CPU, 128 MB RAM
- Build args: `VITE_STRAPI_URL` = `https://api.<domain>/v1/strapi` (routes through gateway, not direct to CMS)

**db-migrate** (`postgres:15-alpine`, init container):
- Purpose: Applies `db/migrations/*.sql` in lexicographic order; runs once then exits (`restart: no`)
- Networks: internal only
- Tracks applied migrations in `schema_migrations` table (idempotent via `ON CONFLICT DO NOTHING`)

**ollama** (`ollama/ollama:0.6.2`), profile `ai`:
- Purpose: Local LLM inference (llama3.1 model downloaded separately)
- Networks: internal only
- Resources: 1.5 CPU, 3 GB RAM
- Port 11434 published to host (VPS internal only)

**whisper** (`onerahmet/openai-whisper-asr-webservice:v1.2.0`), profile `ai`:
- Purpose: Speech-to-text for voice messages
- Networks: internal only; exposes port 9000

**mock-api** (custom build from `project/mock-api/`), profile `dev`:
- Purpose: Stub for Meta/n8n APIs in development. Never deployed in production.

## Data Flows

**Inbound Message Flow (Meta Webhook):**
1. Meta platform POSTs to `https://api.<domain>/v1/inbound/{whatsapp|instagram|messenger}`
2. Traefik terminates TLS, applies `api-public-chain` (rate limit 20 avg/40 burst + security headers)
3. nginx gateway enforces: method allowlist, query-token block, Content-Type check, IP-keyed rate limit (`meta_inbound` zone: 10 r/s, burst 20)
4. nginx proxies to n8n-main at `/webhook/v1/inbound/{channel}`
5. n8n-main receives webhook, enqueues execution on Redis Bull queue
6. n8n-worker picks up job; W1/W2/W3 inbound adapter workflow executes
7. Workflow validates Meta HMAC signature (`META_APP_SECRET`) and checks replay-guard (`webhook_replay_guard` table)
8. Canonical message routed to W4_CORE → cart/FAQ/support sub-workflows
9. Outbound response queued via W15_OUTBOX_WORKER → Meta send API (WA/IG/MSG)

**Kiosk Menu Flow:**
1. Kiosk SPA fetches `GET https://api.<domain>/v1/strapi/api/products`
2. Gateway applies `kiosk_menu` rate limit; strips `/v1/strapi/` prefix
3. nginx proxies to `$cms_upstream` (dynamic DNS via Docker resolver `127.0.0.11 valid=10s`)
4. Strapi returns product catalog; gateway rewrites CORS headers for kiosk origin

**Admin Dashboard Flow:**
1. Browser hits `https://admin.<domain>` — Traefik enforces IP allowlist + BasicAuth before any content
2. App authenticates: `POST https://api.<domain>/v1/portal/api/auth/local` (Strapi users-permissions JWT)
3. Subsequent API calls route through `gateway /v1/portal/` → stripped to `/` → cms:1337

**Queue Execution Flow:**
1. n8n-main receives trigger (webhook or scheduled cron)
2. Execution dispatched to Redis Bull queue (`EXECUTIONS_MODE=queue`)
3. n8n-worker polls Redis, executes with `QUEUE_BULL_MAX_CONCURRENCY` (default 2) parallelism
4. Results written to PostgreSQL `n8n` database; logs to stdout

## Entry Points

**Public (internet-accessible):**
- `https://api.<domain>/v1/inbound/whatsapp` — Meta WhatsApp webhook
- `https://api.<domain>/v1/inbound/instagram` — Meta Instagram webhook
- `https://api.<domain>/v1/inbound/messenger` — Meta Messenger webhook
- `https://api.<domain>/v1/strapi/*` — Kiosk CMS proxy (GET only, rate limited)
- `https://api.<domain>/v1/strapi/api/orders` — Order creation (POST only)
- `https://api.<domain>/healthz` — Public health check (unauthenticated)
- `https://kiosk.<domain>/` — Kiosk SPA (rate limited)

**Private (IP allowlist + BasicAuth required):**
- `https://console.<domain>/` — n8n editor UI
- `https://cms.<domain>/` — Strapi admin panel
- `https://admin.<domain>/` — Backoffice dashboard
- `https://api.<domain>/v1/internal/*` — Internal API namespace
- `https://api.<domain>/v1/admin/*` — Admin API namespace

## Security Architecture

**Traefik Middleware Chains:**
- `api-public-chain`: rate limit (20 avg/40 burst) + security headers
- `api-internal-chain`: IP allowlist (`ADMIN_ALLOWED_IPS`) + BasicAuth + security headers
- `console-chain`: IP allowlist + BasicAuth + security headers
- `cms-chain`: IP allowlist + security headers (Strapi handles its own auth)
- `admin-dash-chain`: IP allowlist + BasicAuth + security headers
- `kiosk-chain`: rate limit (30 avg/60 burst) + security headers

**Security Headers (applied at Traefik and redundantly at nginx):**
X-Frame-Options DENY, X-Content-Type-Options nosniff, HSTS 31536000s (includeSubDomains + preload), Referrer-Policy no-referrer, Permissions-Policy (blocks camera/mic/geo/payment/usb), XCTO.

**nginx Gateway Security Layer:**
- Query-token blocking: rejects requests with `?token=`, `?access_token=`, `?api_token=`, `?webhook_token=`
- Per-route method allowlists (`limit_except GET POST { deny all; }`)
- Content-Type enforcement on POST (must be `application/json`)
- Connection limit: 50 per IP (`conn_per_ip` zone)
- Body size limit: 1 MB (`client_max_body_size 1m`)
- Proxy timeouts: connect 5s, send 10s, read 30s

## Error Handling

**Strategy:** Fail-fast at gateway layer; exponential backoff in outbox; dead-letter queue for unrecoverable failures.

**Outbox Pattern:**
- Max attempts: `OUTBOX_MAX_ATTEMPTS` (default 7)
- Base delay: `OUTBOX_BASE_DELAY_SEC` (30s), max delay: `OUTBOX_MAX_DELAY_SEC` (3600s)
- DLQ handled by `workflows/W8_DLQ_HANDLER.json` and `workflows/W8_DLQ_REPLAY.json`

**Fraud Detection:**
- Flood rate: `FRAUD_FLOOD_LIMIT_30S` (default 6/30s) triggers quarantine
- High-order threshold: `FRAUD_HIGH_ORDER_THRESHOLD` (3,000,000 DZD)
- Cancel pattern: `FRAUD_CANCEL_LIMIT` (3) cancels within `FRAUD_CANCEL_WINDOW_DAYS` (7 days)
- All fraud events written to `security_events` table for audit

## Cross-Cutting Concerns

**Logging:** JSON format (`json_audit`) on nginx gateway. All containers use `json-file` driver with rotation (5 files × 10 MB max for critical services). Structured logs from n8n to stdout.

**SLO Monitoring:** Inbound-to-outbox P95 target 2000ms; DLQ rate max 5%; pending age max 600s. Monitored by `workflows/W17_HEALTH_MONITOR.json` and GitHub Actions `health-monitor.yml` (every 6 hours).

**DB Migration:** Init container (`db-migrate`) applies `db/migrations/*.sql` in sort order. Idempotent via `schema_migrations` tracking table. Parallel validation in CI against PG 15 and PG 16.

**Secret Management:** All production secrets via file mounts (`/run/secrets/`). Required files: `secrets/postgres_password`, `secrets/n8n_encryption_key`, `secrets/traefik_usersfile`, `secrets/strapi_db_password`. Directory is gitignored and not committed.

---

*Architecture analysis: 2026-03-20*
