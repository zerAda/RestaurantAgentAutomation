# Codebase Structure

**Analysis Date:** 2026-06-20

## Directory Layout

```
RestaurantAgentAutomation/
├── workflows/                  # 98 n8n workflow definitions (*.json) — the orchestration mesh
├── infra/                      # Gateway + infra config
│   ├── gateway/                #   Nginx public API gateway (nginx.conf + variants, proxy_params)
│   ├── nginx/                  #   Additional nginx assets
│   ├── redis/                  #   Redis config
│   └── docker/                 #   Docker helper assets
├── inventory-cms/              # Strapi 5 CMS — source of truth (content types, seeders, plugins)
│   ├── src/api/                #   45+ content types (order, product, product-module, tenant-entitlement...)
│   ├── src/bootstrap-seeds/    #   Menu + SaaS entitlement seeders
│   ├── src/index.ts            #   register()/bootstrap() — realtime, admin sync, seeding
│   ├── src/middlewares/        #   Custom Strapi middlewares
│   ├── src/extensions/         #   Plugin extensions (e.g. agent-chat routes)
│   └── config/                 #   Strapi config (database, server, plugins, middlewares)
├── admin-dashboard/            # React + Vite operator console (private)
│   └── src/                    #   App.tsx, pages/, components/, hooks/, services/, lib/, utils/
├── kiosk-app/                  # React + Vite public ordering terminal
│   └── src/                    #   App.tsx, pages/, components/, context/, services/, lib/
├── db/                         # SQL schema, ordered migrations, seeds, init scripts
│   ├── migrations/             #   Tracked migrations (incl. SaaS modules/entitlements)
│   └── init/                   #   docker-entrypoint init shell scripts
├── schemas/inbound/            # Versioned inbound envelope JSON schemas (v1.json, v2.json)
├── config/                     # SaaS manifests: product_modules.json, workflow_registry.json
├── scripts/                    # Ops/deploy/backup/migration shell + node scripts
│   ├── ops/                    #   Operational scripts
│   └── smoke/                  #   Smoke-test scripts
├── tests/                      # Contract, destructive, and fixture test suites
├── templates/                  # Outbound message templates (whatsapp/, delivery/)
├── mock-api/                   # Mock upstream for local/dev testing
├── docs/                       # Architecture/interface docs (docs/interfaces/AGENT_*_INTERFACE.md)
├── secrets/                    # Mounted Docker secrets (gitignored)
├── docker-compose.base.yml     # Canonical service + volume/network definitions
├── docker-compose.dev.yml      # Local dev overrides (dev Dockerfiles, mock-api)
├── docker-compose.prod.yml     # Prod overrides (resource limits, Traefik labels)
├── docker-compose.hostinger.prod.yml  # Hostinger deployment topology (full stack + Traefik)
├── docker-compose.ghcr.yml     # GHCR pre-built image deployment
├── Makefile                    # Task entrypoints
├── ENV_REFERENCE.md            # Env var + secrets reference
└── README.md                   # Project overview
```

## Directory Purposes

**workflows/**
- Purpose: The entire n8n orchestration mesh — every inbound adapter, core engine step, outbound sender, worker, audit, and monitor is one JSON file.
- Contains: 98 `*.json` n8n workflow exports.
- Key files: `W0_MODULE_GUARD.json` (entitlement gate), `W1_IN_WA.json`/`W2_IN_IG.json`/`W3_IN_MSG.json`/`W1_IN_TIKTOK.json` (inbound adapters), `W0_META_VERIFY_UNIFIED.json` (webhook verify), `W4_CORE.json` + `W4.1_ROUTER.json`/`W4.2_CART_MANAGER.json`/`W4.3_FAQ_AGENT.json` (engine), `W5_OUT_WA.json`/`W6_OUT_IG.json`/`W7_OUT_MSG.json`/`W5_OUT_TIKTOK.json` (outbound), `W15_OUTBOX_WORKER.json` (outbox/retry), `W8_DLQ_HANDLER.json`/`W8_DLQ_REPLAY.json` (DLQ), `W_AUDIT_WRITE.json`/`W_AUDIT_QUERY.json`/`W_AUDIT_ARCHIVE.json` (audit chain), `W_QUEUE_METRICS.json`/`W_REDIS_MONITOR.json`/`W16_HEALTHZ.json`/`W17_HEALTH_MONITOR.json` (observability).
- Subdirectories: None (flat).

**infra/gateway/**
- Purpose: Nginx public API gateway that normalizes `/v1/*` paths, rate-limits, and proxies to n8n + Strapi.
- Contains: `nginx.conf` (production), `nginx.test.conf`, `nginx.smoke.conf`, `proxy_params` (shared proxy headers).
- Key files: `nginx.conf` — upstreams, rate-limit zones, all `/v1/*` route definitions.

**inventory-cms/**
- Purpose: Strapi 5 CMS; single source of truth for content + SaaS registries; serves REST, realtime SSE, and admin panel.
- Contains: `src/api/` (content types), `src/bootstrap-seeds/`, `src/index.ts`, `src/middlewares/`, `src/extensions/`, `src/plugins/`, `config/`, `database/`, `types/`, `scripts/`.
- Key files: `src/index.ts` (bootstrap), `src/bootstrap-seeds/saas-entitlements.ts` (module/entitlement seeder), `src/bootstrap-seeds/restaurant-menu.ts` (menu seeder), `src/api/product-module/content-types/product-module/schema.json`, `src/api/tenant-entitlement/content-types/tenant-entitlement/schema.json`, `src/api/order/content-types/order/lifecycles.ts`.
- Subdirectories: `src/api/<content-type>/{content-types,controllers,routes,services}/` is the per-entity Strapi layout.

**admin-dashboard/src/**
- Purpose: Operator console (orders, kitchen, audit, control plane).
- Contains: `App.tsx`, `main.tsx`, `pages/`, `components/`, `hooks/`, `services/`, `lib/`, `utils/`, `assets/`.
- Key files: `main.tsx` (entry), `App.tsx` (entitlement-gated nav), `hooks/useEntitlements.ts` (module gating), `services/strapiClient.ts`, `services/authService.ts`, `services/orders.ts`, `pages/OrdersKanban.tsx`, `pages/KitchenDisplay.tsx`, `pages/AuditLogView.tsx`, `pages/ControlPlaneView.tsx`.

**kiosk-app/src/**
- Purpose: Public self-service ordering terminal.
- Contains: `App.tsx`, `main.tsx`, `pages/`, `components/`, `context/`, `services/`, `lib/`, `assets/`.
- Key files: `main.tsx` (entry), `App.tsx`, `context/CartContext.tsx` (cart state), `services/menuService.ts`, `services/configService.ts`, `services/strapiClient.ts`.

**db/**
- Purpose: Database schema, ordered migrations, seeds, and init scripts.
- Contains: `bootstrap.sql`, `schema.sql`, `migrations/*.sql`, `seed_*.sql`, `init/*.sh`.
- Key files: `bootstrap.sql` (initial schema), `migrations/2026-04-06_saas_modules_entitlements.sql` (SaaS constraints/indexes/audit log), `migrations/2026-04-06_master_schema_unification.sql`, `migrations/2026-03-23_p3_workflow_audit.sql`, `init/01_apply_migrations.sh`, `init/02_create_strapi_db.sh`.
- Subdirectories: `migrations/` (date/phase-prefixed), `init/`.

**config/**
- Purpose: Declarative SaaS manifests linking workflows to modules/tenancy.
- Contains: `product_modules.json` (module catalog: tier, rollout, required env, workflow lists), `workflow_registry.json` (per-workflow metadata: module_key, trigger_kind, exposure, tenant_scoped, depends_on).

**schemas/inbound/**
- Purpose: Versioned canonical inbound envelope schemas validated by adapters via AJV.
- Contains: `v1.json`, `v2.json`. Mounted into n8n at `/opt/resto/schemas`.

**scripts/**
- Purpose: Ops, deploy, backup, migration, and chaos/health tooling.
- Key files: `n8n-worker-entrypoint.sh`, `db_migrate.sh`, `git-deploy.sh`, `deep-health-check.sh`, `backup_postgres.sh`, `generate_workflow_ids.sh`, `integrity_gate.sh`.
- Subdirectories: `ops/`, `smoke/`.

## Key File Locations

**Entry Points:**
- `inventory-cms/src/index.ts` — Strapi register/bootstrap (realtime, admin sync, seeding).
- `admin-dashboard/src/main.tsx` → `admin-dashboard/src/App.tsx` — admin SPA root.
- `kiosk-app/src/main.tsx` → `kiosk-app/src/App.tsx` — kiosk SPA root.
- `infra/gateway/nginx.conf` — public API route definitions.
- `workflows/*.json` — n8n webhook/schedule/sub-workflow triggers.

**Configuration:**
- `docker-compose.base.yml` — canonical services, volumes, networks.
- `docker-compose.{dev,prod,hostinger.prod,ghcr}.yml` — environment-specific overrides + Traefik labels.
- `config/product_modules.json`, `config/workflow_registry.json` — SaaS module/workflow manifests.
- `inventory-cms/config/` — Strapi database/server/plugin/middleware config.
- `ENV_REFERENCE.md`, `SECRETS_INVENTORY.md` — env var + secrets documentation.
- `infra/gateway/proxy_params` — shared nginx proxy headers.

**Core Logic:**
- `workflows/W0_MODULE_GUARD.json` — multi-tenant entitlement gate.
- `workflows/W4_CORE.json`, `W4.1_ROUTER.json`, `W4.2_CART_MANAGER.json` — conversational commerce engine.
- `inventory-cms/src/api/<content-type>/` — Strapi business entities.
- `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` — SaaS module + entitlement seed.
- `admin-dashboard/src/hooks/useEntitlements.ts` — module-aware navigation gating.

**Testing:**
- `tests/contracts/` — contract tests.
- `tests/destructive/` — failure/chaos tests.
- `tests/fixtures/` — shared fixtures.
- Co-located frontend tests: `admin-dashboard/src/*.test.tsx`, `kiosk-app/src/*.test.ts`.
- `scripts/smoke/` — smoke tests.

**Documentation:**
- `README.md`, `COMMANDS.md`, `ENV_REFERENCE.md`, `CLAUDE_OPERATING_CONTRACT.md`.
- `docs/interfaces/AGENT_*_INTERFACE.md` — per-domain interface contracts.

## Naming Conventions

**Workflows (`workflows/*.json`):**
- `W<n>_<DESCRIPTION>` for numbered pipeline stages: `W1_IN_WA`, `W5_OUT_WA`, `W15_OUTBOX_WORKER`.
- `W<n>.<m>_<NAME>` for sub-stages of a stage: `W4.1_ROUTER`, `W4.2_CART_MANAGER`, `W4.3_FAQ_AGENT`.
- `W0_<NAME>` for shared platform primitives invoked by others: `W0_MODULE_GUARD`, `W0_CONFIG_READER`, `W0_REDIS_HELPER`, `W0_META_VERIFY_UNIFIED`.
- `W_<DOMAIN>_<NAME>` for unnumbered domain workflows: `W_AUDIT_WRITE`, `W_QUEUE_METRICS`, `W_DRIVER_DISPATCH`, `W_KIOSK_ORDER`.
- Directional infixes: `_IN_` (inbound adapter), `_OUT_` (outbound sender).
- Internal n8n node names use a step-prefix convention: `B0 -`, `C0 -`, `C1 -`, `RESP -` (block/check/response stages).

**Services (Docker Compose):**
- lowercase-hyphenated service names: `n8n-main`, `n8n-worker`, `admin-dashboard`, `kiosk-app`, `db-migrate`, `mock-api`.
- Hostnames in nginx/Strapi env match service names (`cms`, `n8n-main`, `pgbouncer`, `redis`).

**Strapi content types:**
- kebab-case singular directories: `product-module`, `tenant-entitlement`, `conversation-state`, `delivery-zone`.
- Per-entity layout `<type>/{content-types,controllers,routes,services}/`; `schema.json` defines the model; `lifecycles.ts` for hooks.

**Frontend files:**
- `PascalCase.tsx` for React components/pages (`OrdersKanban.tsx`, `CartContext.tsx`).
- `camelCase.ts` for services/hooks/utils (`strapiClient.ts`, `useEntitlements.ts`, `menuService.ts`).
- `*.test.ts(x)` co-located with source.

**Database migrations:**
- Date/phase-prefixed: `YYYY-MM-DD_p<phase>_<name>.sql` (e.g. `2026-04-06_saas_modules_entitlements.sql`); legacy numeric prefixes (`006_`, `010_`). Applied in sort order, tracked in `schema_migrations`.

**Config / schemas:**
- `schemas/inbound/v<n>.json` — versioned envelope contracts.
- `config/*.json` — SaaS manifests with a `_version` field.

## Where to Add New Code

**New inbound channel:**
- Adapter workflow: `workflows/W<n>_IN_<CHANNEL>.json` (follow `W1_IN_WA.json`: parse → verify → AJV validate → seal context → `W0_MODULE_GUARD` → dedupe → `W4_CORE`).
- Outbound sender: `workflows/W<n>_OUT_<CHANNEL>.json` (write to Redis outbox, then send).
- Gateway route: add a `location = /v1/inbound/<channel>` block (+ GET/POST named locations) in `infra/gateway/nginx.conf`.
- Module + entitlement: add a `channel_<x>` entry to `config/product_modules.json`, `config/workflow_registry.json`, and `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts`.

**New gated workflow / module:**
- Workflow: `workflows/W_<DOMAIN>_<NAME>.json`; add a `B0 - Module Guard` node calling `W0_MODULE_GUARD` with the correct `module_key`.
- Register it in `config/workflow_registry.json` and assign a module in `config/product_modules.json`.
- Seed the module + default entitlement in `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` (keys MUST match the manifest).

**New Strapi content type:**
- Implementation: `inventory-cms/src/api/<content-type>/` (`content-types/<type>/schema.json`, `routes/`, `controllers/`, `services/`).
- Side effects: `inventory-cms/src/api/<content-type>/content-types/<type>/lifecycles.ts`.
- DB constraints/indexes Strapi won't enforce: add a `db/migrations/<date>_<name>.sql`.

**New admin dashboard page/feature:**
- Page: `admin-dashboard/src/pages/<Name>.tsx`; shared UI in `admin-dashboard/src/components/`.
- Data access: `admin-dashboard/src/services/`; gate nav with `hasModule(...)` from `admin-dashboard/src/hooks/useEntitlements.ts`.
- Route admin CMS calls through the gateway `/v1/portal/*`.

**New kiosk feature:**
- UI: `kiosk-app/src/pages/` + `kiosk-app/src/components/`; cart logic in `kiosk-app/src/context/CartContext.tsx`.
- Data: `kiosk-app/src/services/` (read via `/v1/strapi/*`, order POST via `/v1/strapi/api/orders`).

**New scheduled worker:**
- `workflows/W_<NAME>.json` with a CRON trigger; register in `config/workflow_registry.json` under `platform_runtime` or its owning module.

**Ops/deploy tooling:**
- `scripts/` (or `scripts/ops/`, `scripts/smoke/`).

## Special Directories

**secrets/**
- Purpose: Docker secrets mounted read-only into containers (`/run/secrets/*`): Postgres/Strapi DB passwords, n8n encryption key, Traefik usersfile.
- Source: Operator-provisioned per environment.
- Committed: No (gitignored; see `SECRETS_INVENTORY.md`).

**Docker volumes (external):**
- `postgres_data`, `redis_data`, `n8n_data`, `cms_uploads`, `ollama_data`, `traefik_data` — declared `external: true` in `docker-compose.base.yml`; created out-of-band, persisted across deploys.

**inventory-cms/dist & .strapi:**
- Purpose: Strapi build output / cache.
- Source: Generated by `strapi build`.
- Committed: No.

**Frontend build output (admin-dashboard/dist, kiosk-app/dist):**
- Purpose: Vite production bundles served by nginx in the container images.
- Source: `vite build` during Docker build.
- Committed: No.

**mock-api/**
- Purpose: Stand-in upstream for local/dev (`docker-compose.dev.yml`); not deployed to prod topologies.
- Committed: Yes.

---

*Structure analysis: 2026-06-20*
