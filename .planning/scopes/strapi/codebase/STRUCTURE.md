# Strapi CMS Codebase Structure

**Analysis Date:** 2026-03-20

## Directory Layout

```
project/inventory-cms/
├── config/                    # Strapi configuration files
│   ├── admin.ts               # Admin panel secrets (JWT, API token salt)
│   ├── api.ts                 # REST API defaults (limit: 25, maxLimit: 10000)
│   ├── database.ts            # Multi-client DB config (postgres/mysql/sqlite)
│   ├── middlewares.ts         # Middleware stack declaration (CORS, security, custom)
│   ├── plugins.ts             # Plugin config (empty — uses defaults)
│   └── server.ts              # Server config, proxy, cron tasks
├── database/
│   └── migrations/            # Strapi-managed DB migrations (auto-applied)
├── dist/                      # Compiled JS (output of `npm run build`)
├── src/
│   ├── admin/                 # Admin panel customization (excluded from server TS compile)
│   ├── api/                   # All 40 content type APIs (routes/controllers/services/schemas)
│   ├── bootstrap-seeds/
│   │   └── restaurant-menu.ts # Demo product seeder (runs on first boot if products=0)
│   ├── extensions/
│   │   ├── agent-chat/        # Original agent chat extension (chat + tools endpoints)
│   │   ├── idempotency-endpoint/  # POST /api/idempotency/check (webhook dedup for n8n)
│   │   └── webhook-idempotency/   # Idempotency service (strapi.cache-based TTL)
│   ├── middlewares/
│   │   ├── admin-cookie-auth.ts   # Inject adminJwt cookie → Authorization header
│   │   ├── auth-ratelimit.ts      # Rate limiting (5/5min login, 300/min API, n8n exempt)
│   │   └── prometheus-tracker.ts  # In-memory Prometheus metrics collector
│   ├── plugins/
│   │   └── json-form/         # Custom admin panel plugin (JSON form UI component)
│   └── index.ts               # register() + bootstrap() lifecycle hooks
├── types/
│   └── generated/             # Auto-generated TypeScript type declarations
├── Dockerfile                 # Multi-stage build: node:20.20.0-alpine, non-root UID 1001
├── docker-entrypoint.sh       # Reads secrets from Docker secret files at runtime
├── package.json               # Strapi 5.37.1, pg, ioredis, zod, react 18
├── tsconfig.json              # ESNext/ES2022, strict, noImplicitAny, incremental
└── generate_schemas.js        # Utility script to generate JSON schemas
```

## Directory Purposes

**`config/`:**
- Purpose: Strapi server, database, middleware, and plugin configuration
- All files are TypeScript, loaded at startup
- `server.ts` is the only file with runtime logic (cron task for abandoned carts)
- Key files: `config/middlewares.ts` (middleware stack), `config/database.ts` (postgres pool config)

**`src/api/`:**
- Purpose: One directory per content type, each with `content-types/{name}/schema.json`, `controllers/`, `routes/`, `services/`
- 40 APIs total (see complete list below)
- Some APIs have only `controllers/` and `routes/` without a `content-types/` directory — these are custom-only endpoints (`metric`, `realtime`, `control-plane`)

**`src/extensions/`:**
- Purpose: Custom endpoints that cross-cut content type boundaries or extend Strapi behavior
- Not in `src/api/` because they don't have their own content type
- `agent-chat/`: Registered programmatically via `src/index.ts register()` hook
- `idempotency-endpoint/`: Route and controller for n8n webhook dedup check

**`src/middlewares/`:**
- Purpose: Global middleware applied to all requests (declared in `config/middlewares.ts` as `'global::*'`)
- Three custom middlewares: rate limiting, Prometheus tracking, admin cookie injection

## Complete Content Type Inventory

### singleType (singular REST endpoint: GET/PUT `/api/{singularName}`)

| API Directory | singular name | Endpoint | Description |
|---|---|---|---|
| `src/api/system-config/` | system-config | `/api/system-config` | Central config hub — 100+ fields: LLM params, channel tokens, feature flags |
| `src/api/restaurant-brand/` | restaurant-brand | `/api/restaurant-brand` | Brand identity for AI personalization |
| `src/api/platform-setting/` | platform-setting | `/api/platform-settings` | Key-value config store for n8n W0_CONFIG_READER |

> Note: `platform-setting` has `kind: collectionType` in schema but is described as a runtime KV store. The endpoint is plural (`/api/platform-settings`). This differs from the true singleTypes above.

### collectionType (plural REST endpoint: GET `/api/{pluralName}`)

**Core Commerce:**
| API Directory | singular | plural | draftAndPublish |
|---|---|---|---|
| `src/api/product/` | product | products | true |
| `src/api/order/` | order | orders | false |
| `src/api/customer/` | customer | customers | false |
| `src/api/ingredient/` | ingredient | ingredients | true |
| `src/api/payment/` | payment | payments | unknown |
| `src/api/cart/` | cart | carts | unknown |
| `src/api/supplier/` | supplier | suppliers | unknown |

**Delivery & Logistics:**
| API Directory | singular | plural |
|---|---|---|
| `src/api/driver/` | driver | drivers |
| `src/api/delivery-assignment/` | delivery-assignment | delivery-assignments |
| `src/api/delivery-zone/` | delivery-zone | delivery-zones |
| `src/api/delivery-config/` | delivery-config | delivery-configs |
| `src/api/driver-order-ignore/` | driver-order-ignore | driver-order-ignores |
| `src/api/dispatch-log/` | dispatch-log | dispatch-logs |

**Loyalty & Gamification:**
| API Directory | singular | plural |
|---|---|---|
| `src/api/loyalty-tier/` | loyalty-tier | loyalty-tiers |
| `src/api/customer-reward/` | customer-reward | customer-rewards |
| `src/api/driver-reward/` | driver-reward | driver-rewards |
| `src/api/reward-campaign/` | reward-campaign | reward-campaigns |
| `src/api/fortune-spin/` | fortune-spin | fortune-spins |

**Marketing & Social:**
| API Directory | singular | plural |
|---|---|---|
| `src/api/marketing-campaign/` | marketing-campaign | marketing-campaigns |
| `src/api/ad-campaign/` | ad-campaign | ad-campaigns |
| `src/api/scheduled-post/` | scheduled-post | scheduled-posts |
| `src/api/content-library/` | content-library | content-libraries |
| `src/api/creative-asset/` | creative-asset | creative-assets |
| `src/api/marketing-trigger-log/` | marketing-trigger-log | marketing-trigger-logs |

**AI / Agent:**
| API Directory | singular | plural |
|---|---|---|
| `src/api/agent-session/` | agent-session | agent-sessions |
| `src/api/ai-learning/` | ai-learning | ai-learnings |
| `src/api/llm-usage-log/` | llm-usage-log | llm-usage-logs |
| `src/api/voice-interaction/` | voice-interaction | voice-interactions |

**Messaging & Events:**
| API Directory | singular | plural |
|---|---|---|
| `src/api/inbound-message/` | inbound-message | inbound-messages |
| `src/api/funnel-event/` | funnel-event | funnel-events |
| `src/api/conversation-state/` | conversation-state | conversation-states |
| `src/api/feedback/` | feedback | feedbacks |

**System & Observability:**
| API Directory | singular | plural |
|---|---|---|
| `src/api/workflow-error/` | workflow-error | workflow-errors |
| `src/api/admin-audit-log/` | admin-audit-log | admin-audit-logs |
| `src/api/proactive-alert-log/` | proactive-alert-log | proactive-alert-logs |
| `src/api/quarantine/` | quarantine | quarantines |

**Custom Route-Only APIs (no content-types directory):**
| API Directory | Routes |
|---|---|
| `src/api/metric/` | `GET /api/metrics` — Prometheus metrics |
| `src/api/realtime/` | `GET /api/realtime/orders/stream` (SSE), `GET /api/realtime/cortex` |
| `src/api/control-plane/` | `GET /api/control-plane/status` |

**Extension Routes (registered outside src/api/):**
| Source | Routes |
|---|---|
| `src/extensions/agent-chat/` | `POST /api/agent/chat`, `GET /api/agent/tools` |
| `src/extensions/idempotency-endpoint/` | `POST /api/idempotency/check` |
| `src/api/system-config/routes/agent-chat.ts` | `POST /api/agent/chat` (duplicate — see CONCERNS.md) |
| `src/api/system-config/routes/automation.ts` | `POST /api/automation/trigger` |

## Key File Locations

**Entry Points:**
- `src/index.ts`: Strapi lifecycle hooks — `register()` adds agent routes, `bootstrap()` provisions users and seeds data
- `docker-entrypoint.sh`: Runtime secret injection before `npm run start`
- `config/server.ts`: Server config and abandoned-cart cron job

**Configuration:**
- `config/database.ts`: PostgreSQL connection config (reads `DATABASE_*` env vars)
- `config/middlewares.ts`: Ordered middleware stack — `strapi::security`, `strapi::cors`, custom middlewares
- `config/api.ts`: Default REST pagination (`limit: 25`, `maxLimit: 10000`)
- `config/admin.ts`: Admin panel secrets (JWT, API token salt, transfer token salt, encryption key)

**Core Content Type Schemas:**
- `src/api/system-config/content-types/system-config/schema.json`: 100+ field singleType
- `src/api/product/content-types/product/schema.json`: Menu items with multilang descriptions, extras, sauces, sizes
- `src/api/order/content-types/order/schema.json`: Orders with OTP hash, delivery fields, source channel
- `src/api/driver/content-types/driver/schema.json`: Driver fleet with location, gamification fields
- `src/api/customer/content-types/customer/schema.json`: Customer profiles with cross-platform identities

**Controller Overrides:**
- `src/api/inbound-message/controllers/inbound-message.ts`: Validates `meta_json` size (10KB limit) and `msg_id` format
- `src/api/system-config/controllers/agent-chat.ts`: Full RAG+n8n-proxy agent chat (Redis rate limit, 16 context slices)

**Custom Routes:**
- `src/api/system-config/routes/agent-chat.ts`: `POST /api/agent/chat` with `auth: false`
- `src/api/system-config/routes/automation.ts`: `POST /api/automation/trigger` with `auth: true`
- `src/api/metric/routes/metric.ts`: `GET /api/metrics`
- `src/api/realtime/routes/realtime.ts`: SSE and cortex endpoints
- `src/extensions/idempotency-endpoint/routes/idempotency.ts`: `POST /api/idempotency/check`

## Naming Conventions

**Files:**
- Content type schemas: `schema.json` inside `content-types/{api-name}/`
- Routes/controllers/services: `{api-name}.ts` (matches directory name)
- Custom controllers in system-config: named by function (`agent-chat.ts`, `automation.ts`)

**Directories:**
- kebab-case for all API directories
- Content type name matches directory name exactly

**TypeScript:**
- `factories.createCoreRouter/Controller/Service` pattern for standard CRUD
- Custom controllers export default plain object with method functions
- `declare var strapi: Core.Strapi` or `declare const strapi: any` at module level (not injected via closure)

## Where to Add New Code

**New Content Type:**
- Create `src/api/{kebab-name}/content-types/{kebab-name}/schema.json` with `kind`, `collectionName`, `info`, `attributes`
- Create `src/api/{kebab-name}/routes/{kebab-name}.ts` using `factories.createCoreRouter('api::{name}.{name}')`
- Create `src/api/{kebab-name}/controllers/{kebab-name}.ts` using `factories.createCoreController`
- Create `src/api/{kebab-name}/services/{kebab-name}.ts` using `factories.createCoreService`
- Run `npm run build` to compile dist — or rebuild Docker image for production

**New Custom Endpoint (no content type):**
- If crossing multiple content types or extending behavior: create in `src/extensions/{name}/`
- If tied to an existing API: add additional route file (e.g. `src/api/system-config/routes/my-route.ts`)
- Register in `src/index.ts` via `strapi.server.routes()` if extension pattern is needed

**New Middleware:**
- Create `src/middlewares/{name}.ts` exporting `(config, { strapi }) => async (ctx, next) => {}`
- Register in `config/middlewares.ts` as `'global::{name}'`

**New Config Field on system-config:**
- Add attribute to `src/api/system-config/content-types/system-config/schema.json`
- Add to `CONFIG_ALLOWED_FIELDS` array in `src/api/system-config/controllers/agent-chat.ts` if it should be exposed to the AI agent
- Rebuild image — migrations run automatically on startup

## Special Directories

**`dist/`:**
- Purpose: Compiled TypeScript output from `npm run build`
- Generated: Yes
- Committed: Yes (for production Docker builds — avoids runtime compilation in container)
- Warning: Dist files must be kept in sync with source. Manual injection into dist without updating src creates a source/dist mismatch (the root cause of Phase 1's route hack problem — now resolved)

**`database/migrations/`:**
- Purpose: Strapi-managed schema migration files
- Generated: Partially (Strapi generates on content type change)
- Committed: Yes

**`public/uploads/`:**
- Purpose: File uploads (Strapi Media Library local storage)
- Generated: Yes (runtime)
- Committed: No

---

*Structure analysis: 2026-03-20*
