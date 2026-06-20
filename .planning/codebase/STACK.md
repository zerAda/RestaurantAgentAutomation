# Technology Stack

**Analysis Date:** 2026-06-20

> RESTO BOT ("Ralphé") — a multi-channel restaurant ordering automation platform.
> Not a single application: a **container-orchestrated stack** of polyglot services where
> n8n workflows are the core business runtime, Strapi is the data/config plane, and two
> React SPAs are the UIs. A SaaS multi-tenant layer (product modules + per-tenant
> entitlements + a shared `W0_MODULE_GUARD`) now sits on top of the original single-tenant platform.

## Languages

**Primary:**
- **JavaScript (Node.js)** — n8n workflow logic. 341 `n8n-nodes-base.code` nodes across `workflows/*.json` (98 workflow files) carry the bulk of business logic as inline JS.
- **TypeScript ~5.9** — Admin dashboard (`admin-dashboard/src/`) and kiosk app (`kiosk-app/src/`).
- **TypeScript ^5** — Strapi CMS application code (`inventory-cms/src/`, content-type controllers/services/lifecycles).
- **SQL (PostgreSQL dialect)** — DB bootstrap and idempotent migrations (`db/bootstrap.sql`, `db/migrations/*.sql`).

**Secondary:**
- **Python 3.11** — Test suites and tooling (`tests/`, validated in CI as `python-tests`).
- **Bash/sh** — DB init and migration scripts (`db/init/*.sh`), worker entrypoint (`scripts/n8n-worker-entrypoint.sh`), ops scripts (`scripts/`).
- **JSON** — n8n workflow definitions (`workflows/*.json`), module/registry config (`config/product_modules.json`, `config/workflow_registry.json`), inbound schemas (`schemas/`).

## Runtime

**Node.js — version differs per service (important):**
- **n8n 2.9.4** (`N8N_VERSION` in `.env.example`) — runs on its own bundled Node runtime via image `docker.n8n.io/n8nio/n8n:${N8N_VERSION}`. Deployed as **two services**: `n8n-main` + `n8n-worker` (queue mode).
- **Strapi CMS (`inventory-cms/`)** — **Node 20.20.0** pinned via `inventory-cms/.nvmrc`; Docker base `node:20.18.3-alpine` (`inventory-cms/Dockerfile`); `engines` declares `node >=20.0.0 <=24.x.x`.
- **Admin dashboard / kiosk app** — built with **Node 20-alpine** (`admin-dashboard/Dockerfile`, `kiosk-app/Dockerfile`, `node:20-alpine` build stage). Output is static; served by nginx, no Node at runtime.
- **mock-api** (`mock-api/Dockerfile`) — `node:20-alpine`, runs `server.js` directly.
- **CI runtime** — `NODE_VERSION: "20.20.0"`, `PYTHON_VERSION: "3.11"` (`.github/workflows/ci.yml`).

**Package Manager:**
- **npm** (uses `npm ci --legacy-peer-deps` in all Dockerfiles).
- Lockfiles present: `admin-dashboard/package-lock.json`, `kiosk-app/package-lock.json`, `inventory-cms/package-lock.json`.
- No root-level Node package; the repo root is orchestration/config, not an npm package.

## Frameworks

**Core:**
- **n8n 2.9.4** — primary workflow/automation engine and business runtime. Runs in **queue mode** (`EXECUTIONS_MODE=queue`) with `n8n-main` + `n8n-worker` backed by Redis Bull.
- **Strapi 5.37.1** (`@strapi/strapi`) — headless CMS / data + config plane. 40+ content types under `inventory-cms/src/api/` (including the SaaS `product-module` and `tenant-entitlement`).
- **React 19.2** — `admin-dashboard` and `kiosk-app` SPAs (`react`, `react-dom` ^19.2.0). Note: Strapi's admin panel pulls **React 18** internally (`inventory-cms/package.json`).
- **React Router 7.13** (`react-router-dom`) — routing in both SPAs.

**Testing:**
- **Vitest ^4** + **@testing-library/react** + **jsdom** — unit tests for both SPAs (`npm run test` → `vitest run`).
- **Python tests (3.11)** — contract/integration/destructive suites in `tests/` (`tests/contracts/`, `tests/destructive/`, `tests/fixtures/`), run in CI.
- No dedicated test runner for n8n workflows; validated via CI `workflow-validate.yml` + integration jobs spinning up Postgres.

**Build/Dev:**
- **Vite ^6** (`@vitejs/plugin-react ^5`) — bundler/dev server for both SPAs (`vite.config.ts`).
- **TypeScript compiler** — `tsc --noEmit && vite build` (typecheck then bundle). Strapi uses `strapi build` (`inventory-cms/package.json`).
- **Tailwind CSS 4.1** (`@tailwindcss/postcss`, `postcss`, `autoprefixer`) — styling for both SPAs.
- **ESLint 9** flat config (`eslint.config.js`) + `typescript-eslint ^8`, `eslint-plugin-react-hooks`, `eslint-plugin-react-refresh`.

## Key Dependencies

**Critical:**
- `@strapi/strapi` 5.37.1 + `@strapi/plugin-users-permissions` 5.37.1 — CMS core, RBAC, API tokens, admin/API user model.
- `pg` ^8.18 (in `inventory-cms`) — PostgreSQL driver for Strapi.
- `ioredis` ^5.10 (in `inventory-cms`) — Redis client; powers Strapi realtime SSE via Redis Pub/Sub (`order_updates` channel, see `inventory-cms/src/index.ts`).
- `zod` ^4.3 (in `inventory-cms`) — runtime validation in CMS extensions/services.
- `@tanstack/react-query` ^5.22 — server-state/data fetching in admin dashboard.
- `@tanstack/react-virtual` ^3.13 + `recharts` ^3.7 — virtualized lists + analytics charts (admin dashboard).
- `framer-motion` ^11, `lucide-react`, `react-markdown` + `remark-gfm` — UI/animation/markdown rendering (AI chat, admin).

**Infrastructure (containers, not npm):**
- **PostgreSQL 15** (`postgres:15-alpine`) — single instance hosting **two databases** (`n8n` + `strapi`). Tuned via command flags in `docker-compose.base.yml`.
- **pgBouncer** (`edoburu/pgbouncer:latest`) — transaction-mode connection pooler in front of Postgres (`POOL_MODE=transaction`, `MAX_CLIENT_CONN=500`). All services connect through `pgbouncer:5432`.
- **Redis 7** (`redis:7-alpine`) — n8n Bull queue + app cache + Strapi SSE pub/sub (AOF persistence, `allkeys-lru`, 256MB).
- **Ollama 0.6.2** (`ollama/ollama:0.6.2`) — local LLM inference (6 `n8n-nodes-base.ollamaChat` nodes; `LLM_API_URL`, `LLM_MODEL`).
- **Whisper ASR** (`onerahmet/openai-whisper-asr-webservice:v1.2.0`) — speech-to-text for the voice module.
- **nginx 1.27-alpine** — internal API gateway (`gateway` service) and SPA static servers (`nginxinc/nginx-unprivileged:1.27-alpine`).
- **Traefik v3.6.6** — edge reverse proxy / TLS termination (prod only).

## Configuration

**Environment:**
- `.env` driven (template: `.env.example` at root, plus `config/.env.example`). Reference docs: `ENV_REFERENCE.md`, `SECRETS_INVENTORY.md`.
- **Secrets are file-mounted, not inline env**, in production: `./secrets/postgres_password`, `./secrets/strapi_db_password`, `./secrets/n8n_encryption_key`, `./secrets/strapi_admin_password`, `./secrets/traefik_usersfile` (mounted to `/run/secrets/*`, read by `*_FILE` env vars and entrypoints).
- Key required vars: `DOMAIN_NAME`, `SSL_EMAIL`, `ADMIN_ALLOWED_IPS`, `TRAEFIK_TRUSTED_IPS`, `N8N_ENCRYPTION_KEY`, `STRAPI_*` (APP_KEYS, JWT/ADMIN_JWT secrets, salts, ENCRYPTION_KEY, API token), `WEBHOOK_SHARED_TOKEN`, `META_APP_SECRET`, `REDIS_PASSWORD`, `DEFAULT_TENANT_ID`.
- **n8n credential model is indirect**: workflows reference credential **IDs by env var** (`REDIS_CREDENTIAL_ID`, `N8N_DB_CREDENTIAL_ID`) or fixed IDs (`postgres-main`); actual secret values live in n8n's encrypted credential store, not in the workflow JSON. See INTEGRATIONS.md.
- SPA config is **build-time baked** `VITE_*` vars (`VITE_DOMAIN`, `VITE_STRAPI_URL`, `VITE_N8N_URL`, `VITE_API_URL`, `VITE_RESTAURANT_ID`) injected as Docker build args — values are public in the bundle (`kiosk-app/src/services/strapiClient.ts` warns against baking tokens).

**Build:**
- SPAs: `vite.config.ts`, `tsconfig.json` / `tsconfig.app.json` / `tsconfig.node.json`, `tailwind.config.js`, `postcss.config.js`, `eslint.config.js` (per SPA dir).
- Strapi: `inventory-cms/config/{server,database,admin,api,middlewares,plugins,logger}.ts`.
- DB: `db/bootstrap.sql` (fresh install: schema + seeds) and idempotent `db/migrations/*.sql` (16 files) applied by the `db-migrate` service + `db/init/01_apply_migrations.sh`, tracked in a `schema_migrations` table.

## Platform Requirements

**Development:**
- Docker + Docker Compose (the stack is compose-first). `docker-compose.dev.yml` / `docker-compose.base.yml` for local; `Makefile` orchestrates common tasks.
- For SPA-only work: Node 20.x + npm. For CMS work: Node 20.20.0 (`inventory-cms/.nvmrc`).
- Requires two external Docker networks (`internal`, `proxy`) and named external volumes (`postgres_data`, `n8n_data`, `redis_data`, `cms_uploads`, `ollama_data`, `traefik_data`).

**Production:**
- **VPS (Hostinger)** via `docker-compose.hostinger.prod.yml` — ~12-service stack: Traefik (TLS), nginx gateway, `n8n-main`, `n8n-worker`, Postgres 15, pgBouncer, Redis 7, Strapi CMS, admin-dashboard, kiosk-app, Ollama, Whisper.
- Alternative: `docker-compose.ghcr.yml` pulls prebuilt images `ghcr.io/<owner>/resto-bot-<service>:<tag>` (GitHub Container Registry) built by CI.
- Edge: Traefik v3.6.6 with Let's Encrypt (`mytlschallenge` certresolver), per-subdomain routing (`admin.`, `cms.`, `kiosk.`, `api.`, `console.`/n8n) with IP allowlists + BasicAuth on private surfaces.
- Containers are hardened: `cap_drop: ALL`, `no-new-privileges`, non-root users, read-only gateway rootfs with tmpfs.

---

*Stack analysis: 2026-06-20*
*Update after major dependency changes (n8n/Strapi version bumps, Node pinning, container image changes).*
