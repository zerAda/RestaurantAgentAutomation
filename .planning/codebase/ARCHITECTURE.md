# Architecture

**Analysis Date:** 2026-03-18

## Pattern Overview

**Overall:** Multi-tier microservices architecture with API gateway pattern, event-driven workflows, and content management hub.

**Key Characteristics:**
- Public API gateway (Nginx) that terminates inbound channels (WhatsApp, Instagram, Messenger)
- Private orchestration layer (n8n with queue mode) for workflow execution
- Central configuration hub (Strapi CMS) that serves as source of truth for all services
- Separate databases for n8n and Strapi business logic
- Private admin/management interfaces protected by BasicAuth + IP allowlist
- Public kiosk and customer-facing applications

## Layers

**Gateway Layer:**
- Purpose: Single entry point for all public traffic; route validation, rate limiting, and security checks
- Location: `project/infra/gateway/nginx.conf`
- Contains: Nginx proxy rules, rate-limiting zones, security headers, method validation
- Depends on: n8n (upstream), Strapi CMS (for kiosk/admin proxies), Traefik (TLS termination)
- Used by: All public and private clients (kiosk, admin, inbound webhooks)

**Orchestration Layer:**
- Purpose: Execute business logic workflows (n8n); respond to incoming events and trigger outbound actions
- Location: `project/workflows/` (54+ JSON workflow definitions)
- Contains: Multi-channel adapters (WhatsApp, Instagram, Messenger), fulfillment workflows, fraud detection, LLM agents
- Depends on: PostgreSQL (n8n DB), Redis (queue), Strapi CMS (config/menus), external APIs (Stripe, Edahabia)
- Used by: Gateway (receives webhook calls), Admin Dashboard (workflow config), n8n UI (workflow editing)

**CMS/Configuration Layer:**
- Purpose: Central source of truth for menu items, pricing, business hours, prompt templates, order schemas
- Location: `project/inventory-cms/` (Strapi 5 application)
- Contains: 40+ content types (products, orders, customers, drivers, payment configs, system settings)
- Depends on: PostgreSQL (strapi DB), Redis (optional caching)
- Used by: Kiosk (read menu/products), Admin Dashboard (CRUD operations), n8n (workflow config fetch)

**Frontend Layers:**

*Admin Dashboard:*
- Purpose: Operator/manager interface for business operations and analytics
- Location: `project/admin-dashboard/src`
- Contains: React/TypeScript components (KitchenView, StockView, AnalyticsView, AI agents)
- Depends on: Strapi API (`/api/*`), n8n webhooks (via gateway), localStorage/sessionStorage for auth tokens
- Used by: Internal staff (admin account with BasicAuth + IP allowlist)

*Kiosk App:*
- Purpose: Public self-service ordering terminal
- Location: `project/kiosk-app/src`
- Contains: React/TypeScript components (MenuGrid, Cart, CheckoutView)
- Depends on: Strapi API (via gateway `/v1/strapi/` proxy), Vite build system
- Used by: Customers (public, rate-limited)

**Data Layer:**
- Purpose: Persistence for workflows and business logic
- Location: `project/db/` (migrations, bootstrap scripts)
- Contains: PostgreSQL 15-alpine with two databases (n8n, strapi); Redis 7-alpine for queue/caching
- Depends on: Docker volumes for data persistence
- Used by: n8n (workflow state, executions), Strapi (content), db-migrate init container

## Data Flow

**Inbound Event Flow (e.g., WhatsApp message):**

1. Meta sends webhook to `https://api.srv1258231.hstgr.cloud/v1/inbound/whatsapp`
2. Nginx gateway validates: method (GET/POST), Content-Type (JSON), X-Api-Token header if internal
3. Rate-limited by IP (meta_inbound zone: 10r/s burst 20)
4. Proxied to n8n webhook: `/webhook/v1/inbound/whatsapp`
5. n8n workflow (W1 - IN WhatsApp Adapter) processes the message:
   - Deduplicates based on message ID (idempotency key)
   - Enriches with Strapi product/customer data
   - Calls LLM agent (Ollama llama3.1) for intent classification
   - Stores conversation state in Strapi `conversation-state` collection
   - Enqueues outbound action to response workflow (W4 - OUT Outbound Dispatcher)
6. Outbound workflow sends response via WhatsApp Business API
7. Event logged to Strapi `inbound-message` and `funnel-event` collections
8. Dead letter queue (DLQ) captures failures for manual review

**Order Creation Flow (Kiosk → CMS → n8n):**

1. Kiosk user submits order via `POST https://api.srv1258231.hstgr.cloud/v1/strapi/api/orders`
2. Nginx gateway validates method (POST), Content-Type, CORS headers
3. Rate-limited by IP (kiosk_menu zone: 30r/s)
4. Proxied to Strapi CMS: `POST /api/orders`
5. Strapi validates schema, creates order in database
6. Strapi emits webhook to n8n: `POST https://console.srv1258231.hstgr.cloud/api/orders` (internal)
7. n8n workflow (W12 - KIOSK_ORDER) triggers:
   - Validates order against inventory/delivery zones
   - Calculates delivery fee from Strapi `system-config`
   - Triggers payment processing workflow (W20 - PAYMENT_PROCESSOR)
   - Enqueues fulfillment task
8. Admin dashboard updates in real-time via Strapi subscriptions

**Admin Dashboard → Strapi Flow:**

1. Manager logs in with email/password
2. Request: `POST /api/auth/local` with `{identifier, password}`
3. Strapi validates via Users-Permissions plugin
4. Returns JWT token (stored in sessionStorage for XSS protection)
5. Manager clicks "View Orders" → `GET /api/orders?populate=customer,payment`
6. Nginx gateway proxies via `/v1/portal/api/orders` (internal_token rate limit: 20r/s)
7. Strapi queries from `strapi` database, applies role-based permissions
8. Dashboard renders with real-time updates via WebSocket (Strapi Real-time plugin)

**State Management:**
- **n8n Execution State:** Stored in PostgreSQL `execution` table; Redis queue for pending tasks
- **User Session:** JWT in sessionStorage (admin/kiosk); renewed on each request
- **Conversation State:** Stored in Strapi `conversation-state` collection (customer context, preferences)
- **Order State:** Stored in Strapi `order` collection with lifecycle hooks (created → submitted → payment_pending → delivered)

## Key Abstractions

**Adapter Pattern (Channels):**
- Purpose: Normalize incoming messages from different platforms (WhatsApp, Instagram, Messenger) into unified internal format
- Examples: `project/workflows/W_IN_WHATSAPP_ADAPTER.json`, `project/workflows/W_IN_INSTAGRAM_ADAPTER.json`
- Pattern: Each adapter maps platform-specific payload → `{sender_id, channel, message, timestamp, media}` → shared processing queue

**Outbox Pattern (Reliability):**
- Purpose: Ensure messages are delivered even if service crashes between commit and send
- Examples: `project/workflows/W_OUT_OUTBOUND_DISPATCHER.json` (retries up to 7 times with exponential backoff)
- Pattern: Write outbound event to Strapi `outbound-message` table → n8n polls → sends → marks complete

**Content Type Router:**
- Purpose: Route API requests to correct Strapi content type based on URL path
- Examples: `/api/orders` → order service, `/api/products` → product service, `/api/system-config` → system config
- Pattern: Strapi routes (src/api/*/routes/*.ts) map HTTP methods to controllers; controllers delegate to services

**Rate Limiting Zones (Nginx):**
- Purpose: Prevent abuse of public endpoints while allowing legitimate traffic
- Examples: `meta_inbound` (10r/s by IP), `internal_token` (20r/s by token), `kiosk_menu` (30r/s by IP)
- Pattern: Nginx limit_req_zone + conditional rate limit checks per route

**Strapi Hooks (Lifecycle):**
- Purpose: Trigger side effects when content is created/updated (e.g., notify n8n, update cache)
- Examples: `project/inventory-cms/src/api/order/content-types/order/lifecycles.ts` (beforeCreate, afterCreate)
- Pattern: Hook runs inside Strapi transaction; can throw to rollback

## Entry Points

**Public API Endpoints:**
- Location: `project/infra/gateway/nginx.conf` (routes 1-444)
- Triggers: HTTP requests from external clients
- Responsibilities:
  - `/v1/inbound/whatsapp` (GET for verify, POST for events) → n8n W1
  - `/v1/inbound/instagram` (GET/POST) → n8n W2
  - `/v1/inbound/messenger` (GET/POST) → n8n W3
  - `/v1/strapi/*` (GET only for kiosk read) → Strapi CMS

**Private Admin Endpoints:**
- Location: `project/infra/gateway/nginx.conf` (routes 323-438)
- Triggers: HTTPS requests from internal staff (BasicAuth + IP allowlist at Traefik)
- Responsibilities:
  - `/v1/customer/*` → n8n customer service endpoints
  - `/v1/internal/*` → n8n internal service endpoints
  - `/v1/admin/*` → n8n admin service endpoints
  - `/v1/portal/*` → Strapi CMS (admin dashboard full CRUD)

**Application Entry Points:**
- `project/admin-dashboard/src/App.tsx` - React root; checks auth before rendering views
- `project/kiosk-app/src/main.tsx` - React root; loads menu and cart context
- `project/inventory-cms/src/index.ts` - Strapi bootstrap; loads plugins, middlewares, content types

**Database Entry Points:**
- `project/db/migrations/` - Applied by db-migrate init container on first run
- `project/db/bootstrap.sql` - Strapi DB schema and initial data
- `project/db/init/` - Setup scripts for n8n and shared configurations

**n8n Workflow Entry Points:**
- `project/workflows/W_*_ADAPTER.json` - Inbound webhook handlers
- `project/workflows/W_*_DISPATCHER.json` - Async outbound processors
- `project/workflows/W_*_AGENT.json` - AI-driven decision makers

## Error Handling

**Strategy:** Multi-layer error recovery with dead-letter queue and manual review.

**Patterns:**
- **Webhook Validation:** Gateway rejects invalid requests at Nginx level (returns 400/401/415) before passing to n8n
- **Idempotency Keys:** n8n workflows check `webhook_entity` table (n8n 2.x) for duplicate message IDs; skip if already processed
- **Exponential Backoff:** Outbox pattern retries failed sends with delays: 1s, 2s, 4s, 8s, 16s, 32s, 64s (max 7 attempts)
- **Dead-Letter Queue:** Failed outbound messages after 7 retries stored in Strapi `quarantine` collection for manual intervention
- **Strapi Validation:** Content type schema validation; returns 400 with field errors if data invalid
- **Session Recovery:** Admin dashboard detects 401 (token expired); redirects to login while preserving current route in sessionStorage
- **Network Timeout:** All browser requests timeout at 10s (configurable per request); shows "network error" toast

## Cross-Cutting Concerns

**Logging:**
- Nginx access log: JSON format at `/var/log/nginx/access.json` with timing and real IP
- n8n: Structured logs (timestamp, workflow ID, execution ID, step name, error details)
- Strapi: Console logs (colorized for dev, JSON for prod via Winston)
- Dashboard: Browser console logs + network request logs (developer tools)

**Validation:**
- Gateway: HTTP method, Content-Type header, body size (max 1MB)
- Strapi: Content type schema (JSON Schema), role-based permission checks per API call
- n8n: Type validation in node inputs, deduplication key format, required field checks

**Authentication:**
- Public endpoints: No auth (rate-limited by IP)
- Internal endpoints: X-Api-Token header (rate-limited by token)
- Admin UI: JWT token from Strapi `/api/auth/local` → stored in sessionStorage
- Strapi API: Role-based permissions (Authenticated, Public, Admin roles with associated permissions)

---

*Architecture analysis: 2026-03-18*
