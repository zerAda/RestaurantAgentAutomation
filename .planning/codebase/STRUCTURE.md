# Codebase Structure

**Analysis Date:** 2026-03-18

## Directory Layout

```
project/
├── .claude/                           # Local Claude Code skills and memory
├── .github/
│   ├── actions/                       # 4 composite GitHub Actions
│   │   ├── docker-build-scan/         # Multi-arch Docker build + security scan
│   │   ├── health-check/              # Service health verification
│   │   ├── notify/                    # Slack/email notifications
│   │   └── setup-ssh/                 # SSH tunnel setup for VPS access
│   └── workflows/                     # 13 CI/CD workflows
│       ├── ci.yml                     # Lint, test, build, security gate (triggers on PR)
│       ├── cd-deploy.yml              # Deploy to VPS (manual approval)
│       ├── build-push-artifacts.yml   # Push images to GHCR
│       ├── security-scan.yml          # Trivy + SBOM generation
│       ├── workflow-validate.yml      # n8n workflow JSON schema checks
│       ├── health-monitor.yml         # Periodic VPS health checks (via SSH)
│       ├── release.yml                # Create releases + tag commits
│       ├── rollback.yml               # Revert to previous release
│       ├── scheduled-backup.yml       # Daily DB backups
│       ├── migration-validate.yml     # Test DB migrations in isolation
│       ├── env-sync.yml               # Sync .env vars to GitHub secrets
│       ├── perf-baseline.yml          # Baseline performance metrics
│       └── debug-vps.yml              # SSH into VPS for manual debugging
├── admin-dashboard/                   # React/TypeScript admin UI
│   ├── src/
│   │   ├── App.tsx                    # Root component; auth check + view router
│   │   ├── components/                # React components
│   │   │   ├── layout/                # DashboardLayout (sidebar, nav)
│   │   │   ├── ui/                    # Reusable UI elements
│   │   │   ├── LoginView.tsx          # Strapi /api/auth/local login
│   │   │   ├── StockView.tsx          # Inventory management
│   │   │   ├── KitchenView.tsx        # Order fulfillment display
│   │   │   ├── AnalyticsView.tsx      # Metrics + charts
│   │   │   ├── AIChatBubble.tsx       # AI agent chat interface
│   │   │   ├── AiObservatoryView.tsx  # LLM behavior monitoring
│   │   │   ├── GrowthAgentView.tsx    # Growth metrics agent
│   │   │   ├── BrandView.tsx          # Restaurant configuration
│   │   │   ├── CustomerView.tsx       # Customer data browser
│   │   │   ├── MarketingView.tsx      # Campaign management
│   │   │   ├── AutomationView.tsx     # Workflow management (read-only)
│   │   │   └── ErrorBoundary.tsx      # Global error catcher
│   │   ├── pages/
│   │   │   ├── DashboardHome.tsx      # Main dashboard home
│   │   │   ├── ControlPlaneView.tsx   # System control (feature flags, configs)
│   │   │   └── NotificationCenter.tsx # Alert inbox
│   │   ├── services/
│   │   │   ├── authService.ts         # Strapi login + JWT management (sessionStorage)
│   │   │   ├── strapiClient.ts        # Strapi API client with timeout + error handling
│   │   │   ├── stockService.ts        # Inventory CRUD wrapper
│   │   │   └── orders.ts              # Order queries + subscriptions
│   │   ├── utils/
│   │   │   ├── i18n.ts                # French/Arabic translations + RTL support
│   │   │   └── format.ts              # Date/number/currency formatting
│   │   ├── lib/
│   │   │   └── utils.ts               # Helper functions (cn, classname merge)
│   │   └── main.tsx                   # React DOM mount
│   ├── public/                        # Static assets
│   ├── vite.config.ts                 # Vite build config (React + TypeScript)
│   ├── tsconfig.json                  # TypeScript config
│   └── Dockerfile                     # Multi-stage: build → serve with Nginx
├── kiosk-app/                         # React/TypeScript public kiosk UI
│   ├── src/
│   │   ├── App.tsx                    # Root component; load menu + handle routing
│   │   ├── components/
│   │   │   ├── MenuGrid.tsx           # Product display with images
│   │   │   ├── Cart.tsx               # Shopping cart + checkout button
│   │   │   ├── CustomizerModal.tsx    # Product variant picker
│   │   │   ├── VerticalVideoFeed.tsx  # Marketing video carousel
│   │   │   ├── LanguageSelector.tsx   # FR/AR lang toggle
│   │   │   ├── AppSwitcher.tsx        # Switch between kiosk/admin/cms
│   │   │   └── ErrorBoundary.tsx      # Error display
│   │   ├── pages/
│   │   │   ├── CheckoutView.tsx       # Order submission form
│   │   │   └── FortuneWheelView.tsx   # Loyalty spin feature
│   │   ├── services/
│   │   │   ├── strapiClient.ts        # Strapi API client (public role, no auth)
│   │   │   ├── menuService.ts         # Fetch products from /api/products
│   │   │   └── configService.ts       # Load restaurant config from /api/system-config
│   │   ├── context/
│   │   │   └── CartContext.tsx        # Global cart state (React Context)
│   │   ├── utils/
│   │   │   ├── i18n.ts                # FR/AR translations
│   │   │   ├── SoundManager.ts        # Audio feedback on interactions
│   │   │   └── tracking.ts            # Analytics event emission
│   │   └── main.tsx                   # React DOM mount
│   ├── public/                        # Static assets (logo, videos)
│   ├── vite.config.ts                 # Vite config (React + TypeScript)
│   ├── tsconfig.json                  # TypeScript config
│   └── Dockerfile                     # Multi-stage: build → serve with Nginx
├── inventory-cms/                     # Strapi 5 CMS application
│   ├── src/
│   │   ├── index.ts                   # Entry point; load plugins, config, types
│   │   ├── api/                       # 40+ content types
│   │   │   ├── product/               # Product menu items
│   │   │   │   ├── routes/product.ts  # GET /api/products, GET /api/products/:id
│   │   │   │   ├── controllers/       # Request handlers
│   │   │   │   └── services/          # Business logic
│   │   │   ├── order/                 # Orders (from kiosk/WhatsApp)
│   │   │   ├── customer/              # Customer profiles
│   │   │   ├── driver/                # Delivery drivers
│   │   │   ├── ingredient/            # Kitchen inventory items
│   │   │   ├── payment/               # Payment method configs
│   │   │   ├── delivery-assignment/   # Driver + order assignments
│   │   │   ├── delivery-zone/         # Geographic service areas
│   │   │   ├── funnel-event/          # Customer journey events
│   │   │   ├── inbound-message/       # Stored webhook payloads
│   │   │   ├── conversation-state/    # Per-customer chat context
│   │   │   ├── outbound-message/      # Pending/sent messages (outbox)
│   │   │   ├── quarantine/            # Failed messages for review
│   │   │   ├── system-config/         # Singleton config (delivery fee, hours)
│   │   │   ├── restaurant-brand/      # Singleton restaurant metadata
│   │   │   ├── loyalty-tier/          # Loyalty program tiers
│   │   │   ├── marketing-campaign/    # Campaign configs
│   │   │   ├── ai-learning/           # LLM training data
│   │   │   └── [20 more]              # See inventory-cms/src/api/ for full list
│   │   ├── admin/                     # Strapi admin panel customization
│   │   ├── extensions/                # Custom Strapi plugins/hooks
│   │   ├── plugins/                   # Custom plugins (auth, webhooks)
│   │   ├── middlewares/               # Custom Koa middlewares
│   │   └── bootstrap-seeds/           # Seed data for first-run
│   ├── .strapi/                       # Strapi generated files (do not commit)
│   ├── public/                        # Media uploads directory
│   ├── package.json                   # Dependencies (Strapi core + plugins)
│   └── Dockerfile                     # Multi-stage: build → Node.js runtime
├── config/                            # Non-Docker configuration files
│   ├── docker-compose.base.yml        # Base service definitions (shared)
│   ├── docker-compose.dev.yml         # Development overrides
│   ├── docker-compose.prod.yml        # Legacy production (old path)
│   ├── docker-compose.ghcr.yml        # GHCR image references
│   └── docker-compose.hostinger.prod.yml  # **ACTIVE**: Production VPS stack (12 services)
├── docker-compose.*.yml               # Compose files (see config/ above)
├── db/
│   ├── bootstrap.sql                  # Initial Strapi DB schema + seed data
│   ├── schema.sql                     # Current DB schema (reference only)
│   ├── migrations/                    # SQL migration files (applied by db-migrate)
│   │   ├── 006_separate_strapi_privileges.sql       # Strapi user + privileges
│   │   ├── 010_add_channels_fix_currency.sql        # Channel types + currency
│   │   ├── 011_platform_settings_seed.sql           # Initial system config
│   │   ├── 013_unified_identity_linking.sql         # Customer identity unification
│   │   ├── 2026-01-22_p1_*.sql                      # P1 priority fixes (indexes, SLOs)
│   │   ├── 2026-01-23_p0_*.sql                      # P0 security (Meta replay, webhooks)
│   │   └── [12+ more]                               # By date; applied sequentially
│   ├── init/                          # Setup scripts
│   │   ├── 01_create_n8n_db.sh        # n8n database + user
│   │   ├── 02_create_strapi_db.sh     # Strapi database + user
│   │   └── wait-for-postgres.sh       # Health check script
│   ├── seed_delivery_demo.sql         # Demo data: drivers, zones, orders
│   └── seed_poc_demo.sql              # PoC data: test orders, webhooks
├── infra/
│   ├── gateway/
│   │   └── nginx.conf                 # **CRITICAL**: Public API routes + rate limits
│   ├── nginx/                         # Nginx container configs (deprecated, use gateway/)
│   ├── redis/
│   │   └── redis.conf                 # Redis configuration (AOF enabled, 256MB)
│   └── [other infra]                  # Additional infrastructure configs
├── workflows/                         # **CORE LOGIC**: n8n workflow definitions
│   ├── MANIFEST.md                    # Workflow registry (names, IDs, purposes)
│   ├── W_IN_*.json                    # Inbound adapters (WhatsApp, Instagram, Messenger)
│   ├── W_OUT_*.json                   # Outbound dispatchers (send responses via channels)
│   ├── W_ORDER_*.json                 # Order processing workflows
│   ├── W_PAYMENT_*.json               # Payment processing (COD, deposit, CIB, Edahabia)
│   ├── W_AGENT_*.json                 # AI agents (customer service, growth, admin)
│   ├── W_DRIVER_*.json                # Driver management (assignment, routing, rewards)
│   ├── W_DELIVERY_*.json              # Delivery orchestration
│   ├── W_ADMIN_*.json                 # Admin panel callbacks (chat, monitoring, live updates)
│   ├── W_INVENTORY_*.json             # Stock management
│   ├── W_COMPLIANCE_*.json            # Fraud, validation, audit
│   └── [54+ workflows total]          # See MANIFEST.md for complete list
├── schemas/                           # JSON Schema definitions for validation
│   ├── order.schema.json              # Order object validation
│   ├── customer.schema.json           # Customer profile validation
│   ├── message.schema.json            # Inbound message validation
│   ├── payment.schema.json            # Payment validation
│   └── [10+ more]                     # One per major entity
├── scripts/
│   ├── ops/                           # Operational utilities
│   │   ├── backup_postgres.sh         # Dump PostgreSQL database
│   │   ├── restore_postgres.sh        # Restore from backup
│   │   ├── backup_redis.sh            # Snapshot Redis
│   │   └── deep-health-check.sh       # Comprehensive service health
│   ├── smoke/                         # Integration tests
│   │   ├── smoke.sh                   # Core smoke tests
│   │   ├── smoke_meta.sh              # Meta webhook verification
│   │   └── smoke_security_gateway.sh  # Security rule validation
│   ├── test_*.sh                      # Feature-specific test scripts
│   ├── patch_*.js                     # n8n workflow patching utilities
│   ├── preflight.sh                   # Pre-deployment checks
│   ├── ci_test_runner.sh              # Run all CI tests locally
│   ├── validate_*.py                  # Contract/schema validation
│   └── [60+ operational scripts]      # Deployment, debugging, maintenance
├── docs/
│   └── interfaces/                    # API documentation (TypeScript/OpenAPI)
├── shared/                            # Shared code (empty; for future use)
├── reports/                           # Test result reports, logs
├── templates/                         # Configuration templates (docker-compose examples)
├── test-results/                      # CI test outputs
├── tests/                             # Test files (integration, e2e)
├── releases/                          # Release artifacts + notes
├── patches/                           # Custom patch files (deprecated; use migrations)
├── .env                               # **SECRET**: Environment variables (not in git)
├── .env.example                       # Public environment template
├── docker-compose.base.yml            # Base service definitions
├── docker-compose.hostinger.prod.yml  # Production compose (ACTIVE)
├── .gitignore                         # Git ignore rules
├── CLAUDE.md                          # Claude Code operating contract + architecture
├── VERSION                            # Current RESTO BOT version (3.4.0)
└── README.md                          # Project overview (if present)
```

## Directory Purposes

**`.github/`:**
- Purpose: CI/CD orchestration
- Contains: 13 GitHub Actions workflows for lint, test, build, security, deploy, and monitoring
- Key files: `ci.yml` (triggers on PR), `cd-deploy.yml` (manual deploy to VPS)

**`admin-dashboard/`:**
- Purpose: React TypeScript SPA for restaurant staff
- Contains: Component library, services (auth, API), utilities (i18n, formatting)
- Key files: `src/App.tsx` (entry), `src/services/authService.ts` (Strapi login)

**`kiosk-app/`:**
- Purpose: React TypeScript SPA for customer self-service
- Contains: Menu display, shopping cart, checkout form
- Key files: `src/App.tsx` (entry), `src/services/strapiClient.ts` (public API)

**`inventory-cms/`:**
- Purpose: Strapi 5 application (central config hub)
- Contains: 40+ content types, API routes, controllers, services, plugins
- Key files: `src/index.ts` (bootstrap), `src/api/*/routes/*.ts` (HTTP routes)

**`infra/gateway/`:**
- Purpose: Nginx configuration for public API gateway
- Contains: Route definitions, rate limiting, security headers
- Key files: `nginx.conf` (all routes defined here)

**`db/`:**
- Purpose: Database setup, schemas, migrations
- Contains: PostgreSQL DDL, migration files, initialization scripts
- Key files: `migrations/` (applied sequentially on startup), `bootstrap.sql` (initial schema)

**`workflows/`:**
- Purpose: n8n workflow definitions (business logic)
- Contains: 54+ JSON workflow files for messaging, payments, delivery, AI agents
- Key files: `MANIFEST.md` (registry), `W_IN_*.json` (inbound), `W_OUT_*.json` (outbound)

**`scripts/`:**
- Purpose: Operational utilities, testing, deployment
- Contains: Bash scripts for backup, restore, smoke tests, preflight checks
- Key files: `smoke/` (integration tests), `ops/` (backup/restore), `patch_*.js` (n8n patching)

**`.github/actions/`:**
- Purpose: Reusable GitHub Actions composites
- Contains: 4 actions (docker-build-scan, health-check, notify, setup-ssh)

**`config/`:**
- Purpose: Alternative location for compose files (deprecated; use root)
- Contains: Redundant copies of docker-compose files

## Key File Locations

**Entry Points:**

- **Admin Dashboard:** `project/admin-dashboard/src/App.tsx` (React root; auth check)
- **Kiosk App:** `project/kiosk-app/src/main.tsx` (React DOM mount)
- **Strapi CMS:** `project/inventory-cms/src/index.ts` (Strapi bootstrap)
- **Nginx Gateway:** `project/infra/gateway/nginx.conf` (route definitions)
- **n8n Workflows:** `project/workflows/` (54+ JSON workflow files)

**Configuration:**

- `project/.env` (environment variables; not in git)
- `project/.env.example` (public template)
- `project/docker-compose.hostinger.prod.yml` (production stack; 12 services)
- `project/VERSION` (current version: 3.4.0)

**Core Logic:**

- `project/admin-dashboard/src/services/strapiClient.ts` (API client with timeout + auth)
- `project/admin-dashboard/src/services/authService.ts` (JWT token management, sessionStorage)
- `project/kiosk-app/src/services/strapiClient.ts` (public API client, no auth)
- `project/inventory-cms/src/api/*/routes/*.ts` (Strapi HTTP routes)
- `project/infra/gateway/nginx.conf` (rate limits, proxy rules, security checks)

**Testing:**

- `project/scripts/smoke/` (integration test suite)
- `project/scripts/test_*.sh` (feature-specific tests)
- `project/tests/` (test files, organized by feature)

**Database:**

- `project/db/migrations/` (sequential SQL migrations applied at startup)
- `project/db/bootstrap.sql` (initial Strapi schema)
- `project/db/init/` (setup scripts for both n8n and Strapi databases)

## Naming Conventions

**Files:**

- **React components:** PascalCase + `.tsx` extension (e.g., `LoginView.tsx`, `MenuGrid.tsx`)
- **Services:** camelCase + `Service` suffix + `.ts` (e.g., `authService.ts`, `stockService.ts`)
- **n8n workflows:** `W_<TYPE>_<NAME>.json` (e.g., `W_IN_WHATSAPP_ADAPTER.json`, `W_OUT_OUTBOUND_DISPATCHER.json`)
- **Database migrations:** `YYYY-MM-DD_<PRIORITY>_<DESCRIPTION>.sql` (e.g., `2026-01-23_p0_sec02_meta_replay.sql`)
- **GitHub Actions workflows:** `kebab-case.yml` (e.g., `ci.yml`, `cd-deploy.yml`)
- **Strapi content types:** kebab-case directories (e.g., `product/`, `delivery-assignment/`)

**Directories:**

- **Feature modules:** lowercase with hyphens (e.g., `delivery-assignment/`, `loyalty-tier/`)
- **Layer directories:** lowercase (e.g., `routes/`, `controllers/`, `services/`, `content-types/`)
- **Utilities:** lowercase plural (e.g., `utils/`, `services/`, `hooks/`)
- **Pages:** PascalCase (e.g., `pages/`, contains `.tsx` files)

**Functions:**

- **React components:** PascalCase (e.g., `LoginView()`, `StockView()`)
- **Hooks:** camelCase with "use" prefix (e.g., `useAuth()`, `useCart()`)
- **API methods:** camelCase (e.g., `fetchOrders()`, `createOrder()`)
- **Strapi services:** camelCase (e.g., `find()`, `findOne()`, `create()`, `update()`, `delete()`)

**Types:**

- **TypeScript interfaces:** PascalCase + "I" prefix or no prefix (e.g., `User`, `Order`, `IAuthService`)
- **Enums:** PascalCase (e.g., `OrderStatus`, `PaymentMethod`)

## Where to Add New Code

**New Feature (End-to-End):**

1. **Backend data model:** Add Strapi content type in `project/inventory-cms/src/api/<feature-name>/` with routes/controllers/services
2. **Database schema:** Add migration file to `project/db/migrations/<date>_<feature>.sql`
3. **n8n workflow:** Create new workflow JSON in `project/workflows/W_<FEATURE>.json`; register in `MANIFEST.md`
4. **Admin UI:** Add React component in `project/admin-dashboard/src/components/` + wire up in `App.tsx` routes
5. **Tests:** Add smoke tests in `project/scripts/smoke/` or `project/tests/`
6. **Documentation:** Update `CLAUDE.md` and `README.md` with feature description

**New Component/Module (Frontend only):**

- Reusable UI: `project/admin-dashboard/src/components/ui/` (e.g., Button, Modal)
- Feature component: `project/admin-dashboard/src/components/<FeatureName>.tsx`
- Service wrapper: `project/admin-dashboard/src/services/<featureName>.ts`
- Page view: `project/admin-dashboard/src/pages/<PageName>.tsx`

**New API Endpoint (Strapi):**

- Routes: `project/inventory-cms/src/api/<content-type>/routes/<route-name>.ts`
- Controller: `project/inventory-cms/src/api/<content-type>/controllers/<controller-name>.ts`
- Service: `project/inventory-cms/src/api/<content-type>/services/<service-name>.ts`
- Content type schema: `project/inventory-cms/src/api/<content-type>/content-types/<content-type>/schema.json`

**Utilities:**

- Shared helpers: `project/admin-dashboard/src/utils/<feature>.ts`
- i18n strings: `project/admin-dashboard/src/utils/i18n.ts` (add to translations object)
- API client methods: `project/admin-dashboard/src/services/strapiClient.ts` (add to `strapi` export)

**Operational Script:**

- Bash script: `project/scripts/` (organize by type: `ops/`, `smoke/`, `test_*.sh`)
- Python script: `project/scripts/<name>.py` (for complex logic)
- Node.js patch: `project/scripts/patch_*.js` (for n8n workflow modifications)

## Special Directories

**`project/.env`:**
- Purpose: Runtime environment variables
- Generated: No (manually created on VPS; not in git)
- Committed: No (in `.gitignore`)
- Contains: 580+ variables (Strapi secrets, n8n config, API keys, database credentials)

**`project/db/migrations/`:**
- Purpose: Database schema evolution
- Generated: No (manually created)
- Committed: Yes (all migrations tracked in git)
- Applied: Sequentially by db-migrate init container on Docker Compose startup

**`project/workflows/`:**
- Purpose: n8n workflow definitions (serialized JSON)
- Generated: Partially (workflows created in n8n UI, exported to JSON; can also be created manually)
- Committed: Yes (all workflows tracked in git for version control)
- Note: Workflow IDs (UUID) must match both the exported JSON and n8n database

**`project/schemas/`:**
- Purpose: JSON Schema validation definitions
- Generated: No
- Committed: Yes
- Used by: n8n nodes for input validation, Strapi content types for schema validation

**`.github/workflows/`:**
- Purpose: CI/CD pipeline definitions
- Generated: No
- Committed: Yes
- Triggered: On events (push, PR, schedule, manual dispatch)

**`project/docker-compose.hostinger.prod.yml`:**
- Purpose: Production stack definition (12 services)
- Generated: No
- Committed: Yes (but references .env for secrets)
- Used: `docker compose -f docker-compose.hostinger.prod.yml up -d`

**`project/node_modules/`, `project/*/node_modules/`:**
- Purpose: Installed npm dependencies
- Generated: Yes (via `npm install`)
- Committed: No (in `.gitignore`)

**`project/admin-dashboard/dist/`, `project/kiosk-app/dist/`:**
- Purpose: Built frontend bundles
- Generated: Yes (via `npm run build` or Docker build)
- Committed: No (in `.gitignore`)

---

*Structure analysis: 2026-03-18*
