# Codebase Structure

**Analysis Date:** 2026-03-20

## Directory Layout

```
ralphé_final_patch/
├── project/                          # Main project root (all production code lives here)
│   ├── docker-compose.hostinger.prod.yml  # Production 12-service stack
│   ├── docker-compose.ghcr.yml           # GHCR-image variant of prod stack
│   ├── docker-compose.prod.yml           # Alternate prod compose
│   ├── docker-compose.dev.yml            # Dev stack
│   ├── docker-compose.base.yml           # Shared base services
│   ├── VERSION                           # Semver version (e.g. 3.4.0)
│   ├── Makefile                          # Common dev commands
│   ├── .env                              # Runtime environment (gitignored)
│   ├── .env.example                      # Template for .env
│   ├── .gitleaks.toml                    # Gitleaks secret scan config
│   ├── PATCHLOG.md                       # Session-by-session change log
│   ├── RUNBOOK.md                        # Operational runbooks
│   ├── ENV_REFERENCE.md                  # Full environment variable documentation
│   ├── TEST_REPORT.md                    # Test results log
│   ├── CHANGELOG.md                      # Release changelog
│   ├── ROLLBACK.md                       # Rollback procedures
│   │
│   ├── .github/
│   │   ├── workflows/                    # 13 GitHub Actions workflows (CI/CD/Ops)
│   │   └── actions/                      # 4 composite reusable actions
│   │
│   ├── infra/
│   │   ├── gateway/
│   │   │   ├── nginx.conf                # API gateway config (routing, rate limiting, security)
│   │   │   ├── nginx.test.conf           # Test variant of gateway config
│   │   │   └── proxy_params              # Shared nginx proxy headers
│   │   ├── nginx/                        # Additional nginx configs
│   │   └── redis/
│   │       └── entrypoint.sh             # Redis startup with optional auth
│   │
│   ├── db/
│   │   ├── bootstrap.sql                 # Consolidated idempotent schema (all tables + enums)
│   │   ├── schema.sql                    # Schema reference snapshot
│   │   ├── seed_delivery_demo.sql        # Demo seed data (delivery)
│   │   ├── seed_poc_demo.sql             # Demo seed data (POC)
│   │   ├── migrations/                   # Incremental SQL migrations (applied by db-migrate)
│   │   └── init/
│   │       ├── 01_apply_migrations.sh    # Postgres initdb hook: apply migrations
│   │       └── 02_create_strapi_db.sh    # Postgres initdb hook: create strapi database
│   │
│   ├── workflows/                        # 91 n8n workflow JSON files
│   │   ├── MANIFEST.md                   # Workflow inventory and descriptions
│   │   ├── W0_*.json                     # Core infrastructure workflows
│   │   ├── W1_IN_WA.json                 # WhatsApp inbound adapter
│   │   ├── W2_IN_IG.json                 # Instagram inbound adapter
│   │   ├── W3_IN_MSG.json                # Messenger inbound adapter
│   │   ├── W4_CORE.json                  # Core conversation engine
│   │   ├── W4.1_ROUTER.json              # Intent router sub-workflow
│   │   ├── W4.2_CART_MANAGER.json        # Cart management
│   │   ├── W4.3_FAQ_AGENT.json           # FAQ responder
│   │   ├── W5_OUT_WA.json                # WhatsApp outbound sender
│   │   ├── W6_OUT_IG.json                # Instagram outbound sender
│   │   ├── W7_OUT_MSG.json               # Messenger outbound sender
│   │   ├── W8_OPS.json                   # Operations: retention, monitoring
│   │   ├── W8_DLQ_*.json                 # Dead-letter queue handler/replay
│   │   ├── W9_ADMIN_PING.json            # Admin health ping
│   │   ├── W10-W18_*.json                # Feature workflows (delivery, orders, outbox, health)
│   │   └── W_*.json                      # Advanced/AI/driver/analytics workflows
│   │
│   ├── schemas/
│   │   ├── inbound/
│   │   │   ├── v1.json                   # Inbound message contract schema v1
│   │   │   └── v2.json                   # Inbound message contract schema v2
│   │   └── README.md
│   │
│   ├── scripts/
│   │   ├── integrity_gate.sh             # 10-point quality gate (run in CI)
│   │   ├── preflight.sh                  # Pre-launch env + secrets check
│   │   ├── preflight-prod.sh             # Production-specific preflight
│   │   ├── smoke.sh                      # Post-deploy smoke tests (gateway + DB)
│   │   ├── smoke_meta.sh                 # Meta webhook smoke tests
│   │   ├── smoke_security.sh             # Security smoke tests
│   │   ├── smoke_security_gateway.sh     # Gateway security smoke tests
│   │   ├── smoke-cms-routes.sh           # CMS route smoke tests
│   │   ├── backup_postgres.sh            # Manual Postgres backup
│   │   ├── restore_postgres.sh           # Postgres restore (CONFIRM_RESTORE gate)
│   │   ├── backup_redis.sh               # Redis backup
│   │   ├── backup_media.sh               # Media/uploads backup
│   │   ├── n8n-worker-entrypoint.sh      # Mounted as n8n-worker container entrypoint
│   │   ├── db_migrate.sh                 # Run migrations manually
│   │   ├── dora_metrics.sh               # DORA metrics collection
│   │   ├── deep-health-check.sh          # Full stack health check
│   │   ├── ci_test_runner.sh             # CI Python test runner
│   │   ├── test_harness.sh               # Full-stack test harness
│   │   ├── validate_contracts.py         # JSON schema contract tests
│   │   ├── test_darja_intents.py         # Darija NLP intent tests
│   │   ├── test_l10n_script_detection.py # L10N script detection tests
│   │   ├── test_template_render.py       # Template rendering tests
│   │   ├── requirements-ci.txt           # Python CI dependencies
│   │   ├── patch_*.js                    # One-off workflow patch scripts
│   │   ├── smoke/
│   │   │   ├── run.sh                    # Comprehensive smoke test runner
│   │   │   └── payloads/                 # Test payload JSON files (wa, ig, msg)
│   │   └── ops/
│   │       ├── deploy_to_node.sh         # Deploy to VPS node
│   │       ├── deploy_staging_to_node.sh # Deploy to staging
│   │       ├── rollback.sh               # Manual rollback script
│   │       ├── backup.sh                 # Ops backup script
│   │       ├── provision_vps.sh          # Initial VPS provisioning
│   │       └── check_drift.sh            # Config drift detection
│   │
│   ├── inventory-cms/                    # Strapi 5 CMS source (custom Docker build)
│   │   ├── Dockerfile
│   │   ├── src/api/                      # Strapi content types (product, order, etc.)
│   │   ├── src/extensions/               # Strapi customizations
│   │   ├── config/                       # Strapi configuration
│   │   └── database/                     # Strapi database config
│   │
│   ├── admin-dashboard/                  # React/Vite admin backoffice
│   │   ├── Dockerfile
│   │   ├── src/                          # React components, services
│   │   └── public/
│   │
│   ├── kiosk-app/                        # React/Vite public ordering kiosk
│   │   ├── Dockerfile
│   │   ├── src/                          # React components, Strapi API client
│   │   └── public/
│   │
│   ├── mock-api/                         # Development stub server (dev profile only)
│   │
│   ├── docker/
│   │   ├── docker-compose.yml            # Dev docker-compose (with mock-api)
│   │   └── docker-compose.test.yml       # Test harness compose
│   │
│   ├── config/
│   │   └── .env.example                  # Canonical env template (580+ vars documented)
│   │
│   ├── secrets/                          # GITIGNORED — file-based Docker secrets
│   │   ├── postgres_password             # PostgreSQL password
│   │   ├── n8n_encryption_key            # n8n credential encryption key
│   │   ├── traefik_usersfile             # htpasswd for BasicAuth
│   │   └── strapi_db_password            # Strapi DB password
│   │
│   ├── docs/                             # Operational and developer documentation
│   │   ├── BACKUP_RESTORE.md
│   │   ├── RUNBOOKS.md
│   │   ├── DELIVERY.md
│   │   ├── L10N.md
│   │   ├── SUPPORT.md
│   │   ├── TRACKING.md
│   │   └── interfaces/                   # API contract documentation
│   │
│   ├── tests/
│   │   ├── darja_phrases.json            # Darija NLP test data
│   │   └── fixtures/
│   │       └── 00_seed_api_clients.sql   # Test fixture: API clients seed
│   │
│   ├── templates/                        # Message templates (WhatsApp, delivery, etc.)
│   │   ├── whatsapp/                     # WA template JSONs (fr/ar variants)
│   │   └── delivery/                     # Delivery clarification templates (fr/ar/darja)
│   │
│   ├── patches/                          # Historical patch diffs
│   ├── releases/                         # Local release artifacts
│   └── reports/                          # Generated reports
│
└── .planning/                            # GSD planning documents
    ├── STATE.md
    ├── config.json
    ├── phases/                           # Phase plans
    ├── todos/                            # Pending/done todos
    └── scopes/general/codebase/         # This directory (codebase analysis docs)
```

## Directory Purposes

**`project/`:**
- The entire production platform. All paths below are relative to this directory.

**`project/infra/gateway/`:**
- Key files: `nginx.conf` (routing, rate limits, security), `proxy_params` (proxy headers), `nginx.test.conf`
- Changes here require gateway container recreation (not just `nginx -s reload` if conf was changed on disk while mounted)

**`project/db/`:**
- `bootstrap.sql` is the consolidated idempotent schema. Run via `psql -f bootstrap.sql` to fully recreate.
- `migrations/` are applied incrementally by the `db-migrate` init container. Filenames sort-ordered; use date-prefix format `YYYY-MM-DD_description.sql`.
- `db/init/` scripts are PostgreSQL initdb hooks (run only on first-ever postgres data volume initialization).

**`project/workflows/`:**
- 91 JSON files exported from n8n. Files named `W<N>_DESCRIPTION.json` for core workflows; `W_DESCRIPTION.json` for advanced/AI workflows.
- The `MANIFEST.md` describes each workflow's purpose, trigger, and dependencies.
- `W0_CONFIG_READER.json` fetches live config from Strapi. All other workflows call it first.
- Validated by `integrity_gate.sh` for security invariants (token gating, scope enforcement, tenant isolation).

**`project/schemas/`:**
- JSON Schema files mounted into n8n containers at `/opt/resto/schemas`. Used for inbound message contract validation.
- `inbound/v1.json` and `inbound/v2.json` — versioned webhook payload contracts.

**`project/scripts/`:**
- Ops, smoke, test, patch scripts. Python tests use pytest-style conventions.
- `ops/` subdirectory: deployment, rollback, provisioning scripts used on VPS.
- `smoke/payloads/` — test JSON payloads for 12 Meta webhook scenarios (wa/ig/msg × text/image/postback/etc.).

**`project/secrets/`:**
- Not committed to git. Must be created manually on VPS and developer machines before running.
- Required: `postgres_password`, `n8n_encryption_key`, `traefik_usersfile`, `strapi_db_password`.

**`project/.github/workflows/`:**
- 13 workflows: `ci.yml`, `cd-deploy.yml`, `build-push-artifacts.yml`, `security-scan.yml`, `scheduled-backup.yml`, `health-monitor.yml`, `rollback.yml`, `release.yml`, `workflow-validate.yml`, `migration-validate.yml`, `env-sync.yml`, `perf-baseline.yml`, `debug-vps.yml`

**`project/.github/actions/`:**
- 4 composite actions: `docker-build-scan/`, `health-check/`, `notify/`, `setup-ssh/`

## Key File Locations

**Entry Points:**
- `project/docker-compose.hostinger.prod.yml` — production stack definition (start here for topology)
- `project/infra/gateway/nginx.conf` — all public API routes and security rules
- `project/workflows/W4_CORE.json` — core conversation logic entry point
- `project/workflows/W1_IN_WA.json` — WhatsApp inbound (Meta webhook handler)
- `project/db/bootstrap.sql` — complete database schema

**Configuration:**
- `project/config/.env.example` — canonical template for all 580+ env variables
- `project/VERSION` — semver string read by CI/CD
- `project/.gitleaks.toml` — custom secret scan rules
- `project/scripts/preflight.sh` — validates env + secrets are present before deploy

**Critical CI Files:**
- `project/scripts/integrity_gate.sh` — 10-point quality gate (blocking CI check)
- `project/scripts/validate_contracts.py` — JSON schema unit tests
- `project/.github/workflows/ci.yml` — full CI pipeline definition

**Operations:**
- `project/scripts/backup_postgres.sh` — manual database backup
- `project/scripts/restore_postgres.sh` — database restore (requires `CONFIRM_RESTORE` env var)
- `project/scripts/smoke.sh` — post-deploy smoke tests
- `project/scripts/ops/deploy_to_node.sh` — VPS deploy script
- `project/scripts/ops/rollback.sh` — emergency rollback

## Naming Conventions

**Files:**
- n8n workflows: `W<N>_DESCRIPTION.json` (numbered core), `W_DESCRIPTION.json` (advanced)
- DB migrations: `YYYY-MM-DD_description.sql` (date-prefixed for sort order)
- Test scripts: `test_<feature>.sh` or `test_<feature>.py`
- Smoke scripts: `smoke_<scope>.sh`
- Patch scripts: `patch_<target>.js`

**Docker:**
- Images: `ghcr.io/{owner}/resto-bot-{cms|admin|kiosk}:latest` and `:{sha}`
- Networks: `proxy` (internet-facing), `internal` (service-to-service)
- Volumes: `{service}_data` (e.g. `postgres_data`, `n8n_data`, `redis_data`)

## Where to Add New Code

**New n8n workflow:**
- Add `W<N>_DESCRIPTION.json` to `project/workflows/`
- Update `project/workflows/MANIFEST.md`
- Add file presence check to `project/scripts/integrity_gate.sh` if it is a required workflow
- Add JSON validation to `project/.github/workflows/workflow-validate.yml` if it has security requirements

**New DB migration:**
- Add `project/db/migrations/YYYY-MM-DD_description.sql` (idempotent; use `CREATE TABLE IF NOT EXISTS`, `IF NOT EXISTS` constraint guards)
- Update `project/scripts/integrity_gate.sh` required files list
- Test locally: `psql -U n8n -d n8n -f <migration.sql>`

**New API gateway route:**
- Add `location` block to `project/infra/gateway/nginx.conf`
- Apply security patterns: method allowlist, rate limit zone, query-token block
- Add to `project/scripts/smoke_security_gateway.sh` smoke test

**New Strapi content type:**
- Add TypeScript source in `project/inventory-cms/src/api/<name>/`
- Add routes/controller/service files following existing patterns
- Rebuild CMS image: `docker compose build cms`

**New ops script:**
- Add to `project/scripts/` (top-level for CI-used scripts) or `project/scripts/ops/` (VPS ops)
- Add `set -euo pipefail` at top
- Add bash syntax check: it runs automatically in CI via `integrity_gate.sh` step [1/8]

---

*Structure analysis: 2026-03-20*
