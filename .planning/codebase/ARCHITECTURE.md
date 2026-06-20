# Architecture

**Analysis Date:** 2026-06-20

## Pattern Overview

**Overall:** Multi-channel, multi-tenant SaaS ordering platform built as a containerized service mesh. A reverse-proxy gateway fronts an event-driven n8n workflow mesh, a Strapi CMS that is the single source of truth, and two SPA frontends — all coordinated by Docker Compose with Postgres + Redis as shared infrastructure.

**Key Characteristics:**
- **Gateway-fronted ingress:** Traefik terminates TLS and enforces BasicAuth/IP-allowlist; an internal Nginx gateway (`infra/gateway/nginx.conf`) normalizes public `/v1/*` paths, rate-limits, and proxies to hidden n8n webhooks and the Strapi CMS.
- **Event-driven workflow mesh:** 98 n8n workflows in `workflows/*.json` run in queue mode (Redis-backed Bull queue, `n8n-main` + `n8n-worker`). Inbound channel adapters, outbound senders, an outbox/retry worker, a DLQ chain, an audit chain, and metrics monitors are all separate workflows wired by `executeWorkflow` sub-invocations.
- **CMS as source of truth:** Strapi 5 (`inventory-cms/`) holds 45+ content types (menu, orders, customers, drivers, payments, system config, and the SaaS `product-module` / `tenant-entitlement` registries). Workflows and frontends read config and write business state through Strapi.
- **SaaS multi-tenancy via entitlements + module guard:** Every gated workflow entrypoint calls the shared `W0_MODULE_GUARD` workflow to check module enablement and per-tenant entitlement before doing work. The admin dashboard mirrors this with a module-aware navigation hook.
- **Split data planes:** One Postgres 15 instance hosts two logical databases (`n8n` for workflow/execution + security/audit tables, `strapi` for CMS content), fronted by PgBouncer. Redis 7 backs the n8n queue, dedupe keys, the outbox, and CMS realtime pub/sub.
- **Defense in depth:** Meta HMAC signature verification, token-scoped auth, idempotency/dedupe, fail-closed module guard, rate-limit zones, and a security-event audit trail.

## Layers

**Edge / TLS Layer (Traefik):**
- Purpose: TLS termination, Let's Encrypt certs, host-based routing, BasicAuth + IP allowlist for private surfaces.
- Location: Traefik labels in `docker-compose.prod.yml`, `docker-compose.hostinger.prod.yml`, `docker-compose.ghcr.yml` (e.g. `admin-dash-chain`, `cms-chain` middleware chains).
- Contains: Router rules (`Host(...)`), middleware chains (`ipallowlist`, `basicauth.usersfile`, security `headers`), cert resolver `mytlschallenge`.
- Depends on: `proxy` external Docker network; secrets `traefik_usersfile`, env `ADMIN_ALLOWED_IPS`, `DOMAIN_NAME`.
- Used by: All external clients; routes to `gateway`, `cms`, `admin-dashboard`, `kiosk-app`, `n8n-main`.

**Gateway Layer (Nginx):**
- Purpose: Public API surface (`/v1/*`), method/Content-Type allowlisting, rate limiting, query-token blocking, CORS, and proxying to internal n8n webhooks and Strapi.
- Location: `infra/gateway/nginx.conf` (variants: `nginx.test.conf`, `nginx.smoke.conf`); shared proxy headers in `infra/gateway/proxy_params`.
- Contains: `upstream n8n_upstream`, rate-limit zones (`meta_inbound` 10r/s, `internal_token` 20r/s, `kiosk_menu` 30r/s, `conn_per_ip`), named locations splitting GET-verify vs POST-event, `/v1/strapi/*` (kiosk read + order create), `/v1/portal/*` (admin CRUD), `/v1/customer|internal|admin/*` (n8n).
- Depends on: `n8n-main:5678`, `cms:1337`, Docker DNS (`127.0.0.11`).
- Used by: Traefik (upstream), Meta webhooks, kiosk, admin dashboard.

**Orchestration Layer (n8n workflow mesh):**
- Purpose: Execute all business logic as event-driven workflows; receive webhooks, run the conversational commerce engine, dispatch outbound messages, and run scheduled workers.
- Location: `workflows/*.json` (98 workflows). Catalogued in `config/workflow_registry.json` and segmented in `config/product_modules.json`.
- Contains: inbound adapters (`W1_IN_WA`, `W2_IN_IG`, `W3_IN_MSG`, `W1_IN_TIKTOK`), core engine (`W4_CORE`, `W4.1_ROUTER`, `W4.2_CART_MANAGER`, `W4.3_FAQ_AGENT`), outbound senders (`W5_OUT_WA`, `W6_OUT_IG`, `W7_OUT_MSG`, `W5_OUT_TIKTOK`), platform primitives (`W0_CONFIG_READER`, `W0_REDIS_HELPER`, `W0_META_VERIFY_UNIFIED`, `W0_MODULE_GUARD`), reliability (`W15_OUTBOX_WORKER`, `W8_DLQ_HANDLER`, `W8_DLQ_REPLAY`, `W18_MEDIA_FETCH_WORKER`, `W_ERROR_HANDLER`), audit chain (`W_AUDIT_WRITE`, `W_AUDIT_QUERY`, `W_AUDIT_ARCHIVE`), observability (`W_QUEUE_METRICS`, `W_REDIS_MONITOR`, `W16_HEALTHZ`, `W17_HEALTH_MONITOR`), plus addon domains (delivery/dispatch, inventory, loyalty, growth, voice, kiosk).
- Depends on: Postgres (`n8n` DB via PgBouncer), Redis (queue/dedupe/outbox), Strapi (config + business state), Ollama (LLM), Whisper (STT), external Meta/Chargily APIs.
- Used by: Gateway (webhook calls), admin dashboard (internal `/v1/internal`, `/v1/admin` calls), Strapi lifecycle hooks.

**CMS / Configuration Layer (Strapi 5):**
- Purpose: Source of truth for menu, orders, customers, drivers, payments, system config, and the SaaS module/entitlement registries; provides REST API, realtime SSE, and admin panel.
- Location: `inventory-cms/` — APIs in `inventory-cms/src/api/<content-type>/`, bootstrap + seeders in `inventory-cms/src/index.ts` and `inventory-cms/src/bootstrap-seeds/`.
- Contains: 45+ content types; key SaaS ones are `product-module` and `tenant-entitlement`; order side-effects in `inventory-cms/src/api/order/content-types/order/lifecycles.ts`; realtime in `api/realtime`.
- Depends on: Postgres (`strapi` DB via PgBouncer), Redis (order_updates pub/sub for SSE).
- Used by: n8n (config reads, entitlement checks, state writes), admin dashboard (full CRUD via `/v1/portal/*`), kiosk (read menu + create order via `/v1/strapi/*`).

**Presentation Layer (SPA frontends):**
- *Admin Dashboard* — `admin-dashboard/src/`: React + TypeScript + Vite operator console. Entry `admin-dashboard/src/main.tsx` → `App.tsx`. Module-aware nav via `admin-dashboard/src/hooks/useEntitlements.ts`. Pages in `admin-dashboard/src/pages/` (OrdersKanban, KitchenDisplay, AuditLogView, ControlPlaneView, GodMode, DashboardHome). API access via `admin-dashboard/src/services/strapiClient.ts` + `authService.ts`. Served privately behind Traefik BasicAuth/IP allowlist.
- *Kiosk App* — `kiosk-app/src/`: React + TypeScript + Vite public ordering terminal. Entry `kiosk-app/src/main.tsx` → `App.tsx`. Cart state in `kiosk-app/src/context/CartContext.tsx`; data via `kiosk-app/src/services/menuService.ts`, `configService.ts`, `strapiClient.ts`. Read-only menu + order POST through the gateway.

**Data Layer:**
- Purpose: Persistence and coordination.
- Location: `db/` (DDL + migrations), provisioned by Compose `postgres` + `db-migrate` services.
- Contains: `db/bootstrap.sql` (initial schema, loaded via docker-entrypoint-initdb.d), `db/schema.sql`, `db/migrations/*.sql` (ordered, tracked in `schema_migrations`), seed files (`db/seed_*.sql`), init scripts `db/init/01_apply_migrations.sh` + `db/init/02_create_strapi_db.sh`. SaaS constraints in `db/migrations/2026-04-06_saas_modules_entitlements.sql`.
- Depends on: Docker volumes `postgres_data`, `redis_data`; PgBouncer for pooling.
- Used by: n8n, Strapi, db-migrate init container.

## Data Flow

**Inbound message flow (e.g. WhatsApp):**

1. Meta sends `POST https://api.<domain>/v1/inbound/whatsapp` (Traefik → Nginx gateway).
2. Gateway (`infra/gateway/nginx.conf`) enforces method allowlist (GET verify / POST event), `application/json` Content-Type, query-token blocking, and the `meta_inbound` rate limit; named locations rewrite to `/webhook/v1/inbound/whatsapp` on `n8n_upstream`.
3. `W1_IN_WA` (`workflows/W1_IN_WA.json`) parses Meta-native payload in `B0 - Parse & Canonicalize`: verifies `X-Hub-Signature-256` HMAC (off/warn/enforce via `META_SIGNATURE_REQUIRED`), normalizes into a versioned envelope, validates against `schemas/inbound/v1.json` (AJV), returns a fast 200 ACK, and seals tenant context with an HMAC (`B0 - Seal Tenant Context`).
4. **Module guard:** `B0 - Module Guard` calls `W0_MODULE_GUARD` with `{ module_key: 'channel_whatsapp', tenant_id }`. The guard queries Strapi `product-modules` + `tenant-entitlements` and returns `{ allowed, reason, config_overrides }`. `B0 - Guard OK?` branches; denial halts processing (fail-closed on errors).
5. Idempotency: `B0 - Prepare Dedupe Key` + `B0 - Redis Dedupe GET` check `ralphe:dedupe:<channel>:<msgId>` (48h TTL) to drop duplicates; auth/contract failures are written to the Postgres `security_events` table.
6. Valid messages invoke the core engine `W4_CORE` → `W4.1_ROUTER` (`workflows/W4.1_ROUTER.json`): verifies the tenant-context seal, ensures the customer profile, loads conversation state + cart from DB, optionally runs Whisper STT, grounds against the menu cache, classifies intent (`W_LLM_INTENT` via Ollama), and routes to `W4.2_CART_MANAGER` or `W4.3_FAQ_AGENT`.
7. Outbound: the engine invokes `W5_OUT_WA` (`executeWorkflowTrigger`), which writes to the Redis outbox (`B0 - Store in Outbox`) then sends via the Meta Cloud API.
8. Reliability: `W15_OUTBOX_WORKER` (CRON every 30s) drains the `ralphe:outbox:pending` queue with retry; exhausted messages flow to the DLQ handled by `W8_DLQ_HANDLER` (CRON every 5m) and replayable via `W8_DLQ_REPLAY` (`/v1/admin/dlq/replay`).
9. Audit: workflow lifecycle events POST to `W_AUDIT_WRITE` (`/v1/internal/audit-write`), persisted to the workflow-audit table (`db/migrations/2026-03-23_p3_workflow_audit.sql`); queryable via `W_AUDIT_QUERY` and archived by `W_AUDIT_ARCHIVE`.

**Order creation flow (Kiosk → CMS → n8n):**

1. Kiosk submits `POST https://api.<domain>/v1/strapi/api/orders`.
2. Gateway location `= /v1/strapi/api/orders` allows only POST/OPTIONS, applies `kiosk_menu` rate limit + CORS, strips the `/v1/strapi` prefix, and proxies to `cms:1337`.
3. Strapi validates and persists the order; `inventory-cms/src/api/order/content-types/order/lifecycles.ts` fires side effects (and publishes `order_updates` to Redis for SSE).
4. The kiosk ordering workflow `W_KIOSK_ORDER` (webhook `kiosk-order`) runs its own `B0 - Module Guard` (`kiosk_instore`) before validating inventory/zones, calculating fees, and triggering payment (`W_PAYMENT_CHARGILY` → `W_PAYMENT_CALLBACK` → `W_ORDER_FINALIZER`).
5. Admin dashboard receives realtime order updates via Strapi SSE (Redis pub/sub bridged in `inventory-cms/src/index.ts`).

**Admin dashboard flow:**

1. Operator authenticates against Strapi (`/api/auth/local`) via `admin-dashboard/src/services/authService.ts`; JWT stored client-side.
2. `useEntitlements()` (`admin-dashboard/src/hooks/useEntitlements.ts`) fetches `product-modules` + enabled `tenant-entitlements`, building a module set; `App.tsx` gates nav items via `hasModule(key)` (fail-open while loading).
3. CRUD calls go through the gateway `/v1/portal/*` location (full verbs, admin-origin CORS) to Strapi; ops/audit data comes from n8n `/v1/internal/*` and `/v1/admin/*`.

**State Management:**
- **n8n execution state:** Postgres `n8n` DB (`execution` tables) + Redis Bull queue; manual executions offloaded to workers.
- **Conversation/cart state:** loaded and merged in `W4.1_ROUTER`, persisted via Strapi (`conversation-state`, `cart`) and DB.
- **Dedupe / outbox / counters:** Redis keys under the `ralphe:*` namespace.
- **Order lifecycle:** Strapi `order` content type with lifecycle hooks; realtime fan-out via Redis `order_updates`.
- **Tenant context:** carried in the inbound envelope, HMAC-sealed (`TENANT_CONTEXT_SECRET`) and re-verified downstream.

## Key Abstractions

**Module Guard (entitlement gate):**
- Purpose: Single chokepoint deciding whether a tenant may run a module; enforces SaaS segmentation.
- Examples: `workflows/W0_MODULE_GUARD.json`; invoked by `W1_IN_WA`, `W2_IN_IG`, `W3_IN_MSG`, `W1_IN_TIKTOK`, `W_KIOSK_ORDER`, `W_ORDER_FINALIZER`, `W30_VOICE_CALL_INIT`.
- Pattern: Shared sub-workflow (`executeWorkflowTrigger`) returning `{ allowed, reason, config_overrides }`; fail-closed on error. Mirrored client-side by `useEntitlements.ts`.

**Channel Adapter (inbound normalization):**
- Purpose: Convert platform-specific payloads into a versioned canonical envelope.
- Examples: `workflows/W1_IN_WA.json`, `W2_IN_IG.json`, `W3_IN_MSG.json`, `W1_IN_TIKTOK.json`.
- Pattern: Webhook → parse/canonicalize → signature verify → AJV validate (`schemas/inbound/*.json`) → seal tenant context → module guard → dedupe → core engine.

**Outbox + DLQ (reliable delivery):**
- Purpose: Guarantee outbound delivery despite crashes/rate limits.
- Examples: `W5_OUT_WA.json` (writes outbox), `W15_OUTBOX_WORKER.json` (drains/retries), `W8_DLQ_HANDLER.json`, `W8_DLQ_REPLAY.json`.
- Pattern: Redis `ralphe:outbox:pending` queue + scheduled drain with retry, then dead-letter on exhaustion.

**Audit Chain:**
- Purpose: Tamper-evident record of workflow runs and entitlement changes.
- Examples: `W_AUDIT_WRITE.json` (`/v1/internal/audit-write`), `W_AUDIT_QUERY.json`, `W_AUDIT_ARCHIVE.json`; `entitlement_audit_log` table.
- Pattern: Webhook validate → branch on status (started/completed/failed) → Postgres insert; periodic archive.

**Strapi Content Type + Lifecycle Hook:**
- Purpose: Model business entities and trigger side effects on write.
- Examples: `inventory-cms/src/api/order/content-types/order/`, `product-module/`, `tenant-entitlement/`.
- Pattern: Schema-driven REST; `lifecycles.ts` runs in-transaction hooks (e.g. Redis publish).

**Workflow Registry / Module Manifest:**
- Purpose: Declarative catalog mapping each workflow to a product module, tier, trigger kind, exposure, tenancy, dependencies, and required env vars.
- Examples: `config/workflow_registry.json`, `config/product_modules.json`.
- Pattern: Source of truth for SaaS segmentation; seeder keys must match (`inventory-cms/src/bootstrap-seeds/saas-entitlements.ts`).

**Gateway Rate-Limit Zone:**
- Purpose: Per-surface abuse protection.
- Examples: `meta_inbound`, `internal_token`, `kiosk_menu`, `conn_per_ip` in `infra/gateway/nginx.conf`.
- Pattern: `limit_req_zone` keyed by IP or `X-Api-Token` depending on surface.

## Entry Points

**Public webhook endpoints (gateway → n8n):**
- Location: `infra/gateway/nginx.conf`.
- Triggers: Meta / external HTTP.
- Responsibilities: `/v1/inbound/{whatsapp,instagram,messenger}` (GET verify via `W0_META_VERIFY_UNIFIED`, POST event via `W1_IN_WA`/`W2_IN_IG`/`W3_IN_MSG`); legacy `*-incoming-v16` aliases.

**Kiosk & admin proxies (gateway → Strapi):**
- Location: `infra/gateway/nginx.conf`.
- Triggers: Browser requests.
- Responsibilities: `/v1/strapi/api/orders` (kiosk order POST), `/v1/strapi/*` (kiosk GET menu/config), `/v1/portal/*` (admin full CRUD).

**Private ops/admin endpoints (gateway → n8n):**
- Location: `infra/gateway/nginx.conf` + workflow webhooks.
- Triggers: Admin dashboard / ops tooling (token-scoped, Traefik-protected).
- Responsibilities: `/v1/customer/*`, `/v1/internal/*` (e.g. `audit-write`, `audit-log`, queue metrics), `/v1/admin/*` (e.g. `orders`, `ping`, `dlq/replay`).

**Application entry points:**
- `inventory-cms/src/index.ts` — Strapi `register`/`bootstrap`: initializes realtime SSE, syncs super-admin + API user, and runs seeders (`seedRestaurantMenu`, `seedSaaSEntitlements`).
- `admin-dashboard/src/main.tsx` → `admin-dashboard/src/App.tsx` — React root; entitlement-gated navigation.
- `kiosk-app/src/main.tsx` → `kiosk-app/src/App.tsx` — React root; cart context + menu loading.

**Infra / data entry points:**
- `db/bootstrap.sql` + `db/init/01_apply_migrations.sh` + `db/init/02_create_strapi_db.sh` — run by the `postgres` init and `db-migrate` services on first boot; migrations tracked in `schema_migrations`.
- `scripts/n8n-worker-entrypoint.sh` — n8n worker startup.

**Scheduled workers (no external trigger):**
- `W15_OUTBOX_WORKER` (30s), `W8_DLQ_HANDLER` (5m), `W18_MEDIA_FETCH_WORKER`, `W17_HEALTH_MONITOR`, `W_QUEUE_METRICS` (5m), `W_REDIS_MONITOR`, `W_AUDIT_ARCHIVE`.

## Error Handling

**Strategy:** Layered, fail-fast at the edge and fail-closed on security/entitlement; durable retry with dead-lettering for outbound.

**Patterns:**
- **Edge rejection:** Nginx returns 400/401/415 for bad method, query tokens, or wrong Content-Type before reaching n8n.
- **Signature enforcement:** `W1_IN_WA` returns 401 (`SEC-003`) when `META_SIGNATURE_REQUIRED=enforce` and the HMAC is invalid; warn mode logs only.
- **Contract validation:** AJV against `schemas/inbound/*.json`; failures written to `security_events` and ACKed without processing.
- **Module guard fail-closed:** `W0_MODULE_GUARD` denies on any Strapi/lookup error (`GUARD_ERROR_FAILCLOSED`).
- **Idempotency:** Redis dedupe keys prevent duplicate processing of replayed webhooks.
- **Outbox retry + DLQ:** `W15_OUTBOX_WORKER` retries; exhausted messages go to DLQ (`W8_DLQ_HANDLER`) and are replayable (`W8_DLQ_REPLAY`).
- **Central error workflow:** `W_ERROR_HANDLER` captures failures into Strapi `workflow-error`.
- **Frontend resilience:** `useEntitlements` fails open while loading; Strapi clients handle auth expiry.

## Cross-Cutting Concerns

**Logging:**
- Nginx JSON access log (`json_audit`) + rate-limit warn log to stderr (`docker logs gateway`).
- n8n structured execution logs; security/audit events persisted to Postgres (`security_events`, workflow-audit tables).
- Strapi `strapi.log.*`; container logs capped via Compose `json-file` limits.

**Validation:**
- Gateway: method/Content-Type/body-size (`client_max_body_size 1m`) allowlists.
- n8n: AJV envelope schemas, tenant-context seal verification, dedupe-key checks.
- Strapi: content-type schema validation + role-based permissions.

**Authentication & Tenancy:**
- Traefik BasicAuth + IP allowlist (`ADMIN_ALLOWED_IPS`) on `admin`, `cms`, and console hosts.
- Public inbound: unauthenticated but signature-verified + IP-rate-limited.
- Internal/admin n8n routes: `X-Api-Token` (token-keyed rate limit).
- Strapi admin/API: JWT (`/api/auth/local`) + users-permissions roles.
- Tenancy: `module_key` + `tenant_id` checked by `W0_MODULE_GUARD` against `product-modules`/`tenant-entitlements`; tenant context HMAC-sealed end-to-end; DB constraints in `2026-04-06_saas_modules_entitlements.sql`.

**Secrets:**
- Docker secrets mounted read-only (`./secrets/*` → `/run/secrets/*`): Postgres/Strapi DB passwords, n8n encryption key, Traefik usersfile. Documented in `ENV_REFERENCE.md`, `SECRETS_INVENTORY.md`.

---

*Architecture analysis: 2026-06-20*
