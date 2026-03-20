# Strapi CMS External Integrations

**Analysis Date:** 2026-03-20

## How Other Services Call Strapi

### Authentication Methods

Three distinct authentication mechanisms are in active use:

| Auth Type | Header | Used By |
|---|---|---|
| Users-Permissions JWT | `Authorization: Bearer <jwt>` | Admin Dashboard (after `/api/auth/local` login) |
| API Token | `Authorization: Bearer <api-token>` | n8n workflows, internal services |
| Admin JWT | `Authorization: Bearer <admin-jwt>` or `adminJwt` HttpOnly cookie | Strapi Admin Panel UI |

### Public vs Authenticated Endpoints

**Public (no auth required):**
- `GET /api/products` — kiosk product listing (requires Public role permission `product.find` explicitly granted in Strapi admin)
- `GET /api/products/:id` — kiosk product detail (requires Public role `product.findOne`)
- `POST /api/auth/local` — users-permissions login (returns JWT for dashboard)
- `GET /_health` — Strapi built-in health check

**Requires Users-Permissions JWT (admin dashboard):**
- `POST /api/agent/chat` — AI agent chat (auth validated manually in controller)
- `GET /api/control-plane/status`
- `GET /api/metrics`
- All standard CRUD endpoints for content types granted to `Authenticated` role

**Requires API Token (n8n, internal):**
- `GET /api/system-config` — W0_CONFIG_READER fetches platform config
- `POST /api/idempotency/check` — webhook dedup check before n8n processes a message
- `GET/POST /api/orders`, `GET/POST /api/customers`, all operational content types
- `POST /api/inbound-messages` — n8n writes inbound message records for audit trail

---

## Service-by-Service Call Patterns

### n8n Workflows → Strapi

**Connection details:**
- Internal Docker network hostname: `cms` (port 1337)
- Credential type: `strapiTokenApi` (n8n node v1, `apiToken + url + apiVersion`)
- API token: configured in n8n credential `sT8kApXwN2mFqUvR` on VPS
- Base URL: `http://cms:1337` (internal, not through Traefik)

**W0_CONFIG_READER:**
- `GET http://cms:1337/api/system-config` — fetches full system config, caches in Redis (TTL 60s)
- `GET http://cms:1337/api/platform-settings?filters[key]=...` — fetches specific KV settings

**W_ADMIN_AGENT (AI Agent):**
- Called by Strapi agent-chat controller via `POST http://n8n-main:5678/webhook/admin/chat`
- Reverse direction: Strapi calls n8n, not n8n calling Strapi

**Order/Customer Workflows:**
- `POST /api/orders` — create order
- `PUT /api/orders/:documentId` — update order status (`pending → confirmed → preparing → ready → delivered`)
- `GET /api/customers?filters[phone]=...` — lookup customer by phone
- `POST /api/customers` — create new customer
- `POST /api/funnel-events` — track funnel conversion events
- `POST /api/inbound-messages` — write inbound message record
- `POST /api/workflow-errors` — write workflow error for observability

**Idempotency Pattern:**
- Before processing any webhook: `POST /api/idempotency/check` with `{ messageId: "..." }`
- Returns `{ isDuplicate: true/false }` — n8n skips processing if duplicate
- WARNING: This uses `strapi.cache` which is in-memory only — resets on Strapi restart

---

### Admin Dashboard → Strapi

**Connection details:**
- External URL (browser-initiated): `https://cms.srv1258231.hstgr.cloud`
- Build-time env: `VITE_STRAPI_URL: https://cms.${DOMAIN_NAME}` in `docker-compose.hostinger.prod.yml`
- Auth: Users-Permissions JWT (obtained from `POST /api/auth/local`)

**Authentication Flow:**
1. Browser `POST https://cms.srv1258231.hstgr.cloud/api/auth/local` with `{ identifier, password }`
2. Returns `{ jwt, user }` — jwt stored in browser memory/localStorage
3. Subsequent calls: `Authorization: Bearer <jwt>` header

**Endpoints called:**
- `GET /api/orders?sort=createdAt:desc&populate=...` — order kanban board
- `GET /api/customers?populate=loyalty_tier` — customer list
- `GET /api/products` — product management
- `GET /api/ingredients?populate=supplier` — inventory view
- `GET /api/funnel-events` — analytics
- `GET /api/ai-learnings` — AI insights view
- `GET /api/llm-usage-logs` — AI observatory
- `GET /api/agent-sessions` — AI session matrix
- `GET /api/workflow-errors` — workflow error log
- `POST /api/agent/chat` — AI chat bubble (Ralphé assistant)
- `GET /api/realtime/orders/stream` — SSE stream for live order updates
- `GET /api/control-plane/status` — platform health view

---

### Kiosk App → Strapi (via gateway proxy)

**Connection details:**
- Build-time env: `VITE_STRAPI_URL: https://api.${DOMAIN_NAME}/v1/strapi` in compose
- All calls go through: `https://api.srv1258231.hstgr.cloud/v1/strapi/...`
- Gateway nginx strips `/v1/strapi` prefix and proxies to `http://cms:1337`
- Auth: Public role (no token required for GET, product.find/findOne granted)

**Gateway rules:**
- `GET /v1/strapi/*` — allowed (read-only, proxied to `$cms_upstream`)
- `POST /v1/strapi/api/orders` — explicitly allowed (kiosk order creation)
- All other methods on `/v1/strapi/*` — denied (405)
- Admin/management endpoints completely inaccessible from public internet through this path

**Endpoints called:**
- `GET /v1/strapi/api/products?filters[is_kiosk_visible]=true&populate=...` — menu display
- `POST /v1/strapi/api/orders` — place order (dine_in or takeaway, source: kiosk)

---

### Gateway (Nginx) → Strapi

**Connection details:**
- Direct internal Docker network: `http://cms:1337` (variable: `$cms_upstream`)
- DNS resolved dynamically via Docker DNS (`resolver 127.0.0.11 valid=10s`)
- No authentication added by gateway — relies on Strapi's own auth

**Proxy routes defined in `project/infra/gateway/nginx.conf`:**
- `location ^~ /v1/strapi/` — read-only proxy (GET/OPTIONS only)
- `location = /v1/strapi/api/orders` — POST allowed (kiosk checkout)
- `location ^~ /v1/portal/` — additional proxy path for CMS

---

### strapi-mcp Server → Strapi

**Connection details:**
- MCP server configured in `.mcp.json` (project) and `~/.claude.json` (secrets)
- Requires: admin email + password (admin JWT auth) AND API token (content API)
- URL: `https://cms.srv1258231.hstgr.cloud`

**Access pattern:**
- Admin-level API calls for content-manager endpoints
- Content API calls using API token Bearer auth

---

## Data Storage

**Database:**
- PostgreSQL 15-alpine
- Database name: `strapi` (separate from n8n's `n8n` database, same PostgreSQL instance)
- Connection: `DATABASE_HOST=postgres` (Docker service name), port 5432
- Schema: `public` (default)
- Pool: min 2, max 10 connections
- Password: Docker secret mounted at `/run/secrets/postgres_password`, read via `docker-entrypoint.sh`

**File Storage:**
- Local filesystem: `public/uploads/` inside container
- No S3/cloud storage configured (Strapi Upload plugin not configured for cloud)
- Risk: Uploads lost on container recreation — see CONCERNS.md

**Caching:**
- Redis 7-alpine (shared with n8n)
- Used directly via ioredis (not via Strapi plugin)
- Purposes: RAG context cache (5 min TTL per slice), auth rate limit tracking (5 min window), SSE pub/sub (`order_updates` channel), agent chat rate limiting (20 req/min per user, 1 min window)
- Host: `REDIS_HOST` env var, port `REDIS_PORT` (default 6379)

---

## Authentication & Identity

**Admin Panel Auth:**
- Provider: Strapi admin JWT (`ADMIN_JWT_SECRET`)
- Cookie: `adminJwt` HttpOnly, Secure, SameSite=strict, maxAge 24h
- Middleware: `src/middlewares/admin-cookie-auth.ts` injects cookie token into Authorization header

**API Auth (Users-Permissions):**
- Provider: `@strapi/plugin-users-permissions`
- Login: `POST /api/auth/local` with `{ identifier: email, password }`
- Token: JWT signed with `JWT_SECRET`, returned in response body
- Roles: `Public` (type: public, for kiosk) and `Authenticated` (type: authenticated, for admin dashboard)

**API Token Auth:**
- Provider: Strapi built-in API tokens
- Auth: `Authorization: Bearer <token>` header
- Salt: `API_TOKEN_SALT`
- Tokens created/managed in Strapi admin panel

**Permission Model (Users-Permissions):**
- Public role: Only `product.find` and `product.findOne` (for kiosk). Zero other permissions by default. Bootstrap code warns if more than 0 permissions found.
- Authenticated role: Full CRUD for business-critical content types (orders, customers, products, ingredients, funnel-events, payments, etc.)

---

## Monitoring & Observability

**Metrics:**
- Custom Prometheus-compatible endpoint: `GET /api/metrics` (protected by users-permissions auth)
- Metrics collected: `http_requests_total` (method, status, path), `http_request_duration_ms` (p50, p95, p99), `nodejs_memory_heap_used_bytes`
- Collector: `src/middlewares/prometheus-tracker.ts` — in-memory Map, resets on restart

**Health:**
- `GET http://127.0.0.1:1337/_health` — Strapi built-in, returns 204 when healthy
- Docker healthcheck: `test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:1337/_health"]`

**LLM Telemetry:**
- Every agent-chat call creates a `llm-usage-log` entry (workflow_id, model, tokens_in, tokens_out, cost_usd, latency_ms, success, error_message, session_id)
- Accessible via `GET /api/llm-usage-logs` by authenticated admin dashboard

**Error Tracking:**
- No external error tracking (Sentry/Datadog not configured)
- Workflow errors logged to `workflow-error` content type by n8n
- Proactive alerts logged to `proactive-alert-log` by W_ADMIN_PROACTIVE_AGENT

---

## CI/CD & Deployment

**Image Registry:**
- GHCR: `ghcr.io/{owner}/resto-bot-cms:{sha}`

**Build Workflow:**
- `project/.github/workflows/build-push-artifacts.yml` — builds CMS image from `project/inventory-cms/` with `project/inventory-cms/Dockerfile`
- `project/.github/workflows/ci.yml` — CI build validation (matrix includes `cms` image)

**Image Signing:**
- Cosign (`sigstore/cosign-installer@v3.7.0`) signs image with `COSIGN_PRIVATE_KEY` secret
- SBOM generated (CycloneDX), attested with Cosign
- CD workflow (`cd-deploy.yml`) verifies signatures before deploying

**Production Deployment:**
- `docker compose up -d cms` from `/opt/resto/current/` on VPS
- Image pulled from GHCR by SHA tag
- Container runs as UID 1001 (strapi user)

---

## Webhooks & Callbacks

**Incoming (Strapi receives):**
- n8n → `POST /api/idempotency/check` — dedup check
- n8n → `POST /api/inbound-messages` — webhook event audit
- n8n → `PUT /api/orders/:documentId` — order status updates
- Kiosk → `POST /api/orders` (via gateway proxy) — new orders

**Outgoing (Strapi calls external):**
- `POST http://n8n-main:5678/webhook/admin/chat` — agent chat forwards to n8n (45s timeout)
- `POST http://n8n-main:5678/webhook/admin-agent` — alternative n8n endpoint (extensions/agent-chat controller)

---

*Integration audit: 2026-03-20*
