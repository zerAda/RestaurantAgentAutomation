# Architecture

**Analysis Date:** 2026-03-14

## Pattern Overview

**Overall:** Multi-tier distributed system with external gateway isolation, headless CMS hub, queue-based orchestration, and dual-frontend pattern

**Key Characteristics:**
- **Gateway-first design**: Public API surface via Nginx at `api.srv1258231.hstgr.cloud/v1/*` shields internal services
- **Strapi as central config hub**: CMS is single source of truth for all services (menus, settings, workflows, agent config)
- **n8n queue-mode choreography**: 77 workflows orchestrate multi-channel messaging, payment, fraud, LLM, and delivery
- **Dual-frontend SPAs**: Admin dashboard (React) for operations; kiosk app (React) for public ordering
- **PostgreSQL dual-database pattern**: Separate `n8n` and `strapi` databases (shared instance) with migrations via `db-migrate` init container
- **Redis pub/sub + Bull queues**: Real-time subscriptions and async job processing for n8n workers

## Layers

**Public API Gateway (Nginx):**
- Purpose: Rate-limited, security-hardened public entrypoint for Meta webhooks (WhatsApp, Instagram, Messenger) and kiosk menu/ordering
- Location: `infra/gateway/nginx.conf`
- Contains: Request validation, rate limiting zones (by IP for meta_inbound, by token for internal), CORS handling, security headers, payload size limits
- Depends on: n8n upstream (localhost:5678), Strapi CMS (localhost:1337)
- Used by: Internet → Traefik → gateway → n8n/Strapi

**Traefik TLS/Routing Layer:**
- Purpose: HTTPS termination, Let's Encrypt cert management, routing by subdomain to backend services
- Location: Configured in `docker-compose.hostinger.prod.yml`
- Contains: Router rules (host-based), middleware chains (BasicAuth, IP allowlist, security headers), TLS certificate resolver
- Depends on: Let's Encrypt DNS challenge, Docker labels from services
- Used by: Internet → Traefik → all services (`console.*`, `cms.*`, `admin.*`, `kiosk.*`, `api.*`)

**n8n Queue-Mode Orchestration:**
- Purpose: Stateful workflow execution for inbound events, outbound delivery, LLM intent routing, payment processing, fraud checks
- Location: `workflows/` (77 JSON files), `docker-compose.hostinger.prod.yml` (n8n-main + n8n-worker)
- Contains: Event handlers (W1-W3 inbound adapters), core business logic (W4_CORE, W4.1 routing, W4.2 cart, W4.3 FAQ), outbound worker (W15), admin support console (W14), health monitoring (W16-W17)
- Depends on: PostgreSQL (n8n DB for execution history), Redis (Bull queue for task distribution), credentials (API keys, Strapi tokens)
- Used by: Gateway webhooks, Strapi CMS (via calls to n8n API), admin-dashboard (agent chat → W_ADMIN_AGENT)

**Strapi CMS Content Hub:**
- Purpose: Central configuration, content management, and API for products, orders, settings, permissions
- Location: `inventory-cms/` (source), `docker-compose.hostinger.prod.yml` (cms service)
- Contains: 41 content types (product, order, ingredient, customer, restaurant-brand, system-config, platform-setting, etc.), role-based access control, custom routes/controllers
- Depends on: PostgreSQL strapi DB, Redis (for SSE realtime), n8n for workflow config reading (W0_CONFIG_READER pulls settings)
- Used by: Admin dashboard, kiosk app (menu/product read), n8n workflows (config/data reads), gateway proxy (`/v1/strapi/*`)

**Admin Dashboard (React SPA):**
- Purpose: Staff operations hub for stock, orders, analytics, automation, brand, AI agent chat, control plane
- Location: `admin-dashboard/src/`
- Contains: View components (StockView, KitchenView, MarketingView, AnalyticsView, ControlPlaneView, AiObservatoryView, etc.), strapiClient for CMS API calls, authService for Users-Permissions login, real-time WebSocket listeners
- Depends on: Strapi CMS (API calls via `/api/` endpoints), n8n agent endpoint (`/webhook/admin/chat`), localStorage/sessionStorage for session tokens
- Used by: Staff at `admin.srv1258231.hstgr.cloud` (behind Traefik BasicAuth + IP allowlist)

**Kiosk App (React SPA):**
- Purpose: Public-facing touchscreen ordering terminal
- Location: `kiosk-app/src/`
- Contains: VerticalVideoFeed (marketing videos), MenuGrid, Cart management, CheckoutView, FortuneWheelView (gamification), configService, menuService
- Depends on: Gateway proxy at `/v1/strapi/` (menu items, products, platform settings), Strapi public role permissions
- Used by: Customers at `kiosk.srv1258231.hstgr.cloud` (public HTTPS, rate-limited)

**PostgreSQL Data Layer:**
- Purpose: Persistent storage for n8n execution history, Strapi CMS content, operational events
- Location: Docker service in `docker-compose.hostinger.prod.yml`
- Contains: Two databases (`n8n`, `strapi`), 40+ tables (orders, customers, conversation_state, carts, products, templates, etc.)
- Depends on: Migrations applied by `db-migrate` init container
- Used by: n8n (execution logs, credentials), Strapi (content storage), n8n workflows (SQL queries for state/cart/config reads)

**Redis Cache & Pub/Sub:**
- Purpose: Bull queue for n8n worker task distribution, pub/sub for real-time subscriptions (order updates → Strapi SSE), rate-limit counters
- Location: Docker service in `docker-compose.hostinger.prod.yml`
- Contains: Queue for active jobs, pub/sub channels (order_updates), session cache, rate-limit buckets
- Depends on: Nothing (standalone)
- Used by: n8n queue mode (main publishes jobs, workers consume), Strapi realtime (SSE subscriptions), gateway (rate-limit zones)

**Optional AI/Voice Layer:**
- Purpose: LLM inference (Ollama with llama3.1) and speech-to-text (Whisper)
- Location: Docker service `ollama` in `docker-compose.hostinger.prod.yml --profile ai`
- Contains: llama3.1 model (4.9 GB), Whisper STT
- Depends on: Nothing (standalone)
- Used by: 13 workflows (W4_CORE, W_LLM_INTENT, W4.1_ROUTER, W31_VOICE_ORDER_CONFIRM, etc.) via HTTP to `http://ollama:11434/api/chat`

## Data Flow

**Inbound Message Flow (WhatsApp → Order):**

1. Meta sends webhook POST to `https://api.srv1258231.hstgr.cloud/v1/inbound/whatsapp`
2. Nginx gateway validates (Content-Type, size, token headers), rate-limits by IP, proxies to `n8n-main:5678/webhook/v1/inbound/whatsapp`
3. W1_IN_WA workflow receives event:
   - Validates required fields (channel, tenantId, userId, conversationKey, message)
   - Queries PostgreSQL: conversation_state, carts, customer_preferences, message_templates, system_configs
   - Calls W0_CONFIG_READER (sub-workflow, Redis-cached 60s) to fetch platform-setting
4. W4_CORE orchestrates:
   - L10N detection: Arabic script detection + sticky locale preference
   - Intent routing via W4.1_ROUTER (LLM if ollama available, fallback heuristics)
   - Cart management via W4.2_CART_MANAGER
   - State persistence: INSERT/UPDATE conversation_state, carts tables
5. W5-W7_OUT workflows (outbound) receive routed message:
   - Format response templates (Strapi template system with locale substitution)
   - Rate-limit check + fraud detection (flood, high-order threshold)
   - Send via Meta API (WhatsApp, Instagram, or Messenger)
   - Exponential backoff retry (max 7 attempts via W15_OUTBOX_WORKER)
6. Conversation state persisted in PostgreSQL for next message continuity

**Kiosk Checkout Flow:**

1. Customer orders via kiosk app (React)
2. POST to `https://api.srv1258231.hstgr.cloud/v1/strapi/api/orders` (gateway proxy to CMS)
3. Strapi validates order via public role (product.find, order.create perms)
4. Order created in `orders` table, triggers webhook or n8n listener
5. W12_ADMIN_ORDERS or custom listener processes order:
   - Payment method validation (COD, CIB, EDAHABIA, DEPOSIT)
   - Fraud detection (same user ordering 5+ times/min → quarantine)
   - Kitchen ticket generation + notification
6. Admin dashboard updates in real-time via Strapi SSE (Redis pub/sub on `order_updates` channel)

**Admin Chat Agent Flow:**

1. Admin dashboard sends POST `/api/agent/chat` to Strapi
2. Strapi strapiClient route calls `POST http://n8n-main:5678/webhook/admin/chat`
3. W_ADMIN_AGENT workflow executes:
   - User auth check (admin JWT scope)
   - RAG context assembly: queries Strapi for products, orders, customers, metrics (17 context slices)
   - Ollama LLM call: `POST http://ollama:11434/api/chat` with llama3.1 (if available)
   - Response formatting + streaming back to dashboard
4. Admin dashboard receives real-time response via fetch streaming

**State Management:**

- **Conversation state**: PostgreSQL `conversation_state` table (one row per conversation_key), JSON document with stage, serviceMode, locale, cart reference
- **Cart state**: PostgreSQL `carts` table (denormalized from conversation_state), tracks items, service_mode, notes
- **Config state**: Redis cache (60s TTL) from W0_CONFIG_READER reading Strapi `platform-setting` singleType → all workflows read unified config
- **Session state**: Admin dashboard session token in sessionStorage/localStorage, n8n execution history in PostgreSQL
- **Real-time subscriptions**: Strapi SSE via Redis pub/sub channel `order_updates` → connected admin dashboards

## Key Abstractions

**n8n Workflow as Service Unit:**
- Purpose: Encapsulates business logic as async, event-driven, auditable units
- Examples: `workflows/W4_CORE.json` (main conversation logic), `workflows/W4.1_ROUTER.json` (intent router), `workflows/W15_OUTBOX_WORKER.json` (retry engine)
- Pattern: Trigger → validation/normalization → DB state load → business logic → state save → external API calls

**Strapi Content Type as API Contract:**
- Purpose: Defines data shape, permissions, routes for each business domain
- Examples: `inventory-cms/src/api/product/`, `inventory-cms/src/api/order/`, `inventory-cms/src/api/platform-setting/`
- Pattern: Each content type has routes/ (HTTP API), controllers/ (handlers), services/ (business logic) following Strapi MVC pattern

**Gateway Route as Security Boundary:**
- Purpose: Isolates internal services, enforces auth/rate-limits, validates payloads
- Examples: `/v1/inbound/*` (public webhooks), `/v1/strapi/*` (kiosk proxy), `/v1/admin/*` (private internal), `/v1/customer/*` (reserved)
- Pattern: Each location block in nginx.conf has explicit method allowlist, rate limit zone, timeout, and error page routing

**Credential as Encrypted Secret:**
- Purpose: n8n credentials table stores encrypted API keys, DB passwords, Strapi tokens
- Examples: RedisConnection (id 43SDqJYMGa6RvFqW), PostgreSQL (1mZZJEscADgQ8InR), StrapiTokenAPI (sT8kApXwN2mFqUvR)
- Pattern: Workflow nodes reference credential ID, n8n decrypts at runtime, never exposed in logs

## Entry Points

**Internet Ingress:**
- Location: Traefik reverse proxy (port 80/443 on host)
- Triggers: HTTPS requests to `*.srv1258231.hstgr.cloud`
- Responsibilities: TLS termination, subdomain routing, middleware chaining (auth, IP allowlist, security headers)

**Webhook Ingress (Meta):**
- Location: `infra/gateway/nginx.conf` `/v1/inbound/{whatsapp|instagram|messenger}`
- Triggers: POST from Meta with X-Hub-Signature header, GET for webhook verify challenge
- Responsibilities: Signature validation (in n8n W0_META_VERIFY_UNIFIED), rate-limit enforcement (10 req/s by IP for meta_inbound zone), payload parsing

**API Client (Internal):**
- Location: `infra/gateway/nginx.conf` `/v1/internal/*`, `/v1/admin/*`, `/v1/customer/*`
- Triggers: Requests with X-Api-Token header from internal services
- Responsibilities: Rate-limit by token (20 req/s), method allowlist (POST for admin operations), response formatting

**Kiosk Public Display:**
- Location: `kiosk-app/` entry point at `kiosk.srv1258231.hstgr.cloud`
- Triggers: Customer interaction (menu browse, order create)
- Responsibilities: Fetch menu from `/v1/strapi/api/products`, submit order to `/v1/strapi/api/orders`, idle timer (120s default) to reset to welcome

**Admin Operations:**
- Location: `admin-dashboard/` entry point at `admin.srv1258231.hstgr.cloud`
- Triggers: Staff authentication via `/api/auth/local` (Strapi Users-Permissions), navigation to views
- Responsibilities: RBAC check (authenticated role required), Strapi API queries, real-time order/metric updates, agent chat invocation

**Database Migrations:**
- Location: `db-migrate` init container (runs once on startup)
- Triggers: Compose service `depends_on: condition: service_completed_successfully`
- Responsibilities: Apply all .sql files in `db/migrations/` (idempotent), create indexes, seed core data

## Error Handling

**Strategy:** Layered error resilience with explicit fallbacks

**Patterns:**

1. **Validation Errors (400):** Nginx rejects malformed payloads (Content-Type, size) → 415 Unsupported Media Type or 400 Bad Request
   - File: `infra/gateway/nginx.conf` lines 154-165

2. **Rate Limit Errors (429):** Nginx rate-limit zones drop excess requests or queue them
   - File: `infra/gateway/nginx.conf` lines 35-44 (zones), lines 168, 215, 261 (zone application)

3. **Auth Errors (401/403):** Strapi auto-logs out on 401 (missing role in up_users_role_lnk table)
   - File: `admin-dashboard/src/services/strapiClient.ts` lines 63-72 (clears token, dispatches event, redirects to login)

4. **Timeout Errors (504):** Workflows have execution timeouts; nginx has proxy_read_timeout
   - File: `infra/gateway/nginx.conf` lines 76-80 (5s connect, 10s send, 30s read)
   - File: workflows (executionTimeout: 300s in W4_CORE)

5. **Dead-Letter Queue (DLQ):** Failed messages after max 7 retries go to quarantine table
   - File: `workflows/W15_OUTBOX_WORKER.json` (outbox pattern with exponential backoff)
   - Table: `quarantine` in PostgreSQL

6. **Fallback Config:** If Strapi unreachable or config read fails, workflows use environment variables as fallback
   - File: `workflows/W0_CONFIG_READER.json` (Redis TTL cache + env fallback)

## Cross-Cutting Concerns

**Logging:** Structured JSON via Nginx `json_audit` format (time, addr, proxy_ip, method, uri, status, bytes, ua, rt)
- File: `infra/gateway/nginx.conf` lines 46-55
- Aggregated by: CloudWatch or ELK stack (configured at VPS ops level)

**Validation:** Multi-layer schema enforcement
- Nginx body size (1MB max)
- n8n Code nodes perform type coercion + normalization (see W4_CORE C0_Validate Event)
- Strapi Users-Permissions plugin validates field types per content type
- JSON schema files in `schemas/inbound/` for contract validation

**Authentication:** Multi-token model
- Traefik BasicAuth for `console.*`, `admin.*` subdomains (username:password in htpasswd file)
- Strapi Users-Permissions JWT for dashboard login + role RBAC
- n8n API key (from n8n user_api_keys table) for workflow execution via HTTP
- Bearer token enforcement in gateway for internal API routes

**Rate Limiting:** Zone-based per Nginx location
- Meta inbound webhooks: 10 req/s per IP (meta_inbound zone)
- Internal API clients: 20 req/s per token (internal_token zone)
- Kiosk menu reads: 30 req/s per IP (kiosk_menu zone)
- Connection limit: 50 concurrent connections per IP (conn_per_ip zone)

**Security Headers:** Applied by Nginx middleware
- HSTS (31536000s), X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection
- File: `infra/gateway/nginx.conf` lines 84-93 (global headers), compose labels for per-route middleware

**Multi-Tenancy:** Via tenant_id foreign key in all business tables
- Restaurants scoped to tenant_id
- Workflows check tenant_id in all queries
- Strapi content can be tenant-scoped (custom middleware)

**Internationalization (L10N):** Sticky locale preference + script detection
- Arabic script auto-detection in W4_CORE C2_Merge State Defaults
- User preference persisted in `customer_preferences.locale`
- Strapi templates stored per locale (fr, ar)
- Kiosk app uses `i18n.ts` utility for view translations

---

*Architecture analysis: 2026-03-14*
