# Strapi CMS Architecture

**Analysis Date:** 2026-03-20

## Pattern Overview

**Overall:** Strapi 5 headless CMS acting as a multi-tenant central configuration and data hub. All business services (n8n, admin-dashboard, kiosk-app) depend on it as the authoritative record store.

**Key Characteristics:**
- 40 content types across the `src/api/` directory (mix of collectionType and singleType)
- Custom extensions layer (`src/extensions/`) adds non-standard REST endpoints (agent chat, idempotency)
- Custom middleware layer (`src/middlewares/`) adds rate limiting, Prometheus metrics, and admin cookie auth
- Bootstrap (`src/index.ts`) auto-provisions admin user, API user, and seeds menu on first start
- Built-in cron job (defined in `config/server.ts`) for abandoned cart garbage collection
- Redis used directly (ioredis) for RAG cache, rate limiting, and SSE pub/sub — no Strapi Redis plugin

## Layers

**Configuration Layer (singleType):**
- Purpose: Platform-wide runtime configuration stored in the database, editable through admin UI without redeployment
- Content types: `system-config`, `restaurant-brand`, `delivery-config`
- Key endpoint: `GET/PUT /api/system-config` — singular path, no `/s`
- `system-config` has 100+ fields covering LLM params, channel tokens (private), feature flags, business rules, cron expressions

**Core Business Data (collectionType):**
- Purpose: Transactional data driving orders, customers, drivers, inventory
- Content types: `order`, `customer`, `product`, `ingredient`, `driver`, `delivery-assignment`, `payment`, `funnel-event`, `feedback`
- Relations form a graph: `product` ↔ `ingredient` (manyToMany), `order` → `customer` (manyToOne), `order` → `driver` (manyToOne)

**AI/Agent Layer (collectionType):**
- Purpose: Stores AI memory, LLM telemetry, agent conversation history
- Content types: `agent-session`, `ai-learning`, `llm-usage-log`
- `system-config.agent_system_prompt` defines the AI persona (Ralphé)

**Marketing & Social (collectionType):**
- Purpose: Campaign management, social publishing pipeline, ad performance
- Content types: `marketing-campaign`, `ad-campaign`, `scheduled-post`, `content-library`, `creative-asset`, `marketing-trigger-log`

**Operations & Logistics (collectionType):**
- Purpose: Delivery operations, driver gamification, dispatch logging
- Content types: `delivery-zone`, `delivery-config`, `driver-order-ignore`, `driver-reward`, `dispatch-log`

**Loyalty & Gamification (collectionType):**
- Purpose: Customer retention mechanics
- Content types: `loyalty-tier`, `customer-reward`, `reward-campaign`, `fortune-spin`

**System & Observability (collectionType):**
- Purpose: Audit trails, error tracking, workflow debugging
- Content types: `admin-audit-log`, `workflow-error`, `proactive-alert-log`, `quarantine`, `inbound-message`, `conversation-state`, `voice-interaction`

**Custom Non-Content APIs:**
- `metric` API: `GET /api/metrics` — exposes Prometheus text format (no content type)
- `realtime` API: `GET /api/realtime/orders/stream` (SSE), `GET /api/realtime/cortex` — no content type
- `control-plane` API: `GET /api/control-plane/status` — no content type

## Data Flow

**n8n Workflow Reads System Config:**
1. W0_CONFIG_READER workflow calls `GET /api/system-config` with Bearer STRAPI_API_TOKEN
2. Response is cached in Redis (TTL 60s)
3. Downstream n8n nodes read config values from memory (no re-fetch per step)

**Kiosk Order Flow:**
1. Kiosk-app calls `GET https://api.srv1258231.hstgr.cloud/v1/strapi/api/products` (gateway proxies to cms:1337)
2. Gateway strips `/v1/strapi` prefix, proxies GET-only to Strapi
3. Order POST hits dedicated nginx location `= /v1/strapi/api/orders` (allows POST)
4. Strapi creates order, kiosk gets response
5. n8n workflow polls or receives webhook for new orders

**Admin Dashboard Chat Flow:**
1. Browser sends `POST https://admin.domain/api/auth/local` → gets users-permissions JWT
2. Browser sends `POST https://cms.domain/api/agent/chat` with JWT in header
3. Controller in `src/api/system-config/controllers/agent-chat.ts` validates JWT manually
4. Controller performs keyword-based RAG slice detection across 16 context sources
5. Fetches live data from Strapi DB (Redis-cached 5 min per slice)
6. Forwards enriched context + message to n8n webhook `http://n8n-main:5678/webhook/admin/chat`
7. Response logged to `llm-usage-log`, session saved to `agent-session`, reply returned to browser

**State Management:**
- No in-process state beyond in-memory rate limit Maps (reset on restart — documented concern)
- Redis (`ioredis`) used for: RAG cache (5 min TTL), auth rate limit (5 min window), SSE pub/sub (`order_updates` channel)
- Agent session memory stored in `agent-session` content type (persistent across restarts)

## Key Abstractions

**singleType (system-config, restaurant-brand):**
- Endpoint is singular: `GET /api/system-config` (not `/api/system-configs`)
- Route file uses `factories.createCoreRouter('api::system-config.system-config')` — Strapi generates the correct singular routes
- Must NOT use createCoreRouter with `collectionName` mismatched — previously caused crash (see CONCERNS.md)

**Agent Chat (dual implementation):**
- Two agent-chat implementations exist in parallel:
  - `src/extensions/agent-chat/` — original extension pattern (registered via `src/index.ts` `register()` hook)
  - `src/api/system-config/controllers/agent-chat.ts` + `src/api/system-config/routes/agent-chat.ts` — newer Redis-RAG version
- Route `POST /api/agent/chat` in system-config has `auth: false` (validates JWT manually inside controller)
- Route `POST /api/agent/chat` in extensions has scope-based auth
- Both target the same path — potential conflict resolved by Strapi's route priority (last registered wins)

**Custom Extensions (non-API-directory routes):**
- `src/extensions/agent-chat/` — agent chat + tools catalogue
- `src/extensions/idempotency-endpoint/` — `POST /api/idempotency/check` (n8n calls this for webhook dedup)
- `src/extensions/webhook-idempotency/services/` — idempotency service using `strapi.cache` (in-memory TTL)

**Bootstrap (`src/index.ts`):**
- `register()`: Programmatically registers agent-chat routes via `strapi.server.routes()`
- `bootstrap()`: Creates super admin + API user sync, seeds menu if no products, audits public role permissions

## Entry Points

**HTTP Server:**
- Location: `config/server.ts`
- Port: 1337 (container internal), exposed to Docker network only
- Health endpoint: `http://127.0.0.1:1337/_health` (Strapi built-in)

**Cron Job:**
- Location: `config/server.ts` cron task `*/15 * * * *`
- Purpose: Deletes orders with `status: 'cart'` older than 60 minutes from `api::order.order`

**Docker Entrypoint:**
- Location: `project/inventory-cms/docker-entrypoint.sh`
- Reads `DATABASE_PASSWORD` from Docker secret file at startup
- Reads `STRAPI_SUPER_ADMIN_PASSWORD` from Docker secret file if it's a path

## Error Handling

**Strategy:** Graceful degradation for non-critical paths. Critical paths (auth, rate limit) fail hard with 401/429.

**Patterns:**
- Agent chat: try/catch around all DB queries — falls back to empty strings for RAG slices
- Idempotency service: returns `{ isDuplicate: false }` if cache unavailable (fail-open for n8n reliability)
- Bootstrap: each section wrapped in try/catch — logs errors but does not abort Strapi startup
- Controller overrides (e.g. `inbound-message`): validates input, returns 400 on violation, delegates to `super.create(ctx)` for success path

## Cross-Cutting Concerns

**Logging:** `strapi.log.info/warn/error` throughout. Structured logging not enforced — plain string messages.

**Validation:** Input validation at controller layer (inbound-message size check, agent-chat message length cap 2000 chars, msg_id character allowlist).

**Authentication:** Three auth types in use:
1. Admin JWT (`ADMIN_JWT_SECRET`) — Strapi admin panel, stored in `adminJwt` HttpOnly cookie (24h TTL via `admin-cookie-auth` middleware)
2. Users-Permissions JWT (`JWT_SECRET`) — admin dashboard API calls, standard Bearer token
3. API Token (`API_TOKEN_SALT`) — n8n and internal service calls, `Authorization: Bearer <token>`

**Rate Limiting:**
- Login: 5 attempts / 5 min per IP (`auth-ratelimit` middleware)
- General API: 300 req/min per IP
- Trusted internal IPs (n8n container IPs from `N8N_INTERNAL_IPS` env): exempt from all rate limiting
- Agent chat (system-config version): Redis-based, 20 req/min per user ID

---

*Architecture analysis: 2026-03-20*
