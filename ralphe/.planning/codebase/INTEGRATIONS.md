# External Integrations

**Analysis Date:** 2026-03-14

## APIs & External Services

**Messaging Platforms (Primary):**
- **WhatsApp Business API** - Multi-channel messaging
  - SDK/Client: Meta Messaging API (HTTP via n8n)
  - Auth: `WA_API_TOKEN` (env var)
  - Phone Number ID: `WA_PHONE_NUMBER_ID` (env var, in Strapi system-config)
  - Webhook: `/v1/inbound/whatsapp` (public API endpoint)
  - Send URL: `WA_SEND_URL` (production: https://graph.facebook.com/v21.0/)
  - 54+ n8n workflows process WhatsApp conversations (W0-W51 series)

- **Instagram Messaging** - Secondary channel
  - SDK/Client: Meta Messaging API
  - Auth: `IG_API_TOKEN` (env var)
  - Webhook: `/v1/inbound/instagram`
  - Send URL: `IG_SEND_URL`
  - Workflows: W0_META_VERIFY_UNIFIED (shared verification)

- **Facebook Messenger** - Tertiary channel
  - SDK/Client: Meta Messaging API
  - Auth: `MSG_API_TOKEN` (env var)
  - Webhook: `/v1/inbound/messenger`
  - Send URL: `MSG_SEND_URL`

**Meta Webhook Security:**
- Verification: `META_VERIFY_TOKEN` (shared across channels)
- Signature validation: `META_SIGNATURE_REQUIRED` (enforce | warn | off)
- Replay window: `META_REPLAY_WINDOW_SEC` (600s default)
- Audit logging: `ADMIN_WA_AUDIT_ENABLED` (true)
- Implementation: `workflows/W0_META_VERIFY_UNIFIED.json` (timing-safe token comparison)

**Speech & AI:**
- **Ollama (llama3.1)** - Local LLM service (optional ai profile)
  - Host: Internal container at `ollama:11434`
  - Endpoint: `/api/chat`
  - Model: `llama3.1` (4.9GB, pre-pulled, ID: 46e0c10c039e)
  - Client: n8n HTTP request to `http://ollama:11434/api/chat`
  - Env vars: `LLM_API_URL`, `LLM_MODEL`, `LLM_TEMPERATURE`
  - Used by: W4_CORE, W_LLM_INTENT, 13 other workflows

- **Whisper STT** - Speech-to-text (optional ai profile)
  - Image: `onerahmet/openai-whisper-asr-webservice:v1.2.0`
  - Port: 9000
  - Endpoint: `http://whisper:9000/asr` (estimated)
  - Env var: `STT_API_URL` (production not yet configured)

**Optional Legacy Integrations (flags in .env.example):**
- **OpenAI API** - Not currently deployed
  - Env var: `OPENAI_API_KEY`

- **Replicate** - Image generation
  - Env var: `REPLICATE_API_TOKEN`

- **Elevenlabs** - Text-to-speech
  - Env var: `ELEVENLABS_API_KEY`

- **Supabase** - Realtime backend (not used in current stack)
  - Env vars: `SUPABASE_URL`, `SUPABASE_ANON_KEY`

**Payment Processors:**
- **Chargily** - Algerian online payments
  - Auth: `CHARGILY_API_KEY` (env var)
  - Enabled: `PAYMENT_CIB_ENABLED`, `PAYMENT_EDAHABIA_ENABLED` (feature flags)

- **COD (Cash on Delivery)** - Local payment
  - Enabled: `PAYMENT_COD_ENABLED` (true default)
  - Max amount: `PAYMENT_COD_MAX_AMOUNT` (1,000,000 cents)

- **Deposit/Prepayment** - Platform payment
  - Enabled: `PAYMENT_DEPOSIT_ENABLED` (true)
  - Mode: `PAYMENT_DEPOSIT_MODE` (PERCENTAGE)
  - Threshold: `PAYMENT_DEPOSIT_THRESHOLD` (300,000 cents)

## Data Storage

**Databases:**
- **PostgreSQL 15-alpine** - Primary data store
  - Connection: `postgres:5432` (internal Docker network)
  - Client: `pg` (Node.js driver, `inventory-cms/package.json`)
  - Databases:
    - `n8n` - Executions, workflows, credentials (via n8n ORM)
    - `strapi` - CMS content, system config (via Strapi)
  - Username: `n8n` (default)
  - Password: Docker secret `/run/secrets/postgres_password`
  - Auth: Certificate-free (DATABASE_SSL=false in compose)
  - Tuning parameters in `docker-compose.hostinger.prod.yml`:
    - `shared_buffers=256MB`
    - `effective_cache_size=768MB`
    - `max_connections=100`
    - `log_min_duration_statement=1000` (slow query logging)

**File Storage:**
- **Local filesystem** (Docker volumes)
  - CMS uploads: `cms_uploads` volume → `/app/public/uploads` (Strapi)
  - n8n data: `n8n_data` volume → `/home/node/.n8n`
  - Ollama data: `ollama_data` volume → `/root/.ollama`
  - PostgreSQL data: `postgres_data` volume → `/var/lib/postgresql/data`
  - No external S3/blob storage configured

**Caching:**
- **Redis 7-alpine** - Job queue + cache
  - Connection: `redis:6379` (internal Docker network)
  - Client: `ioredis` (Node.js driver)
  - Memory limit: 384MB (deploy.resources.limits)
  - Persistence: AOF (append-only file)
  - Password: `REDIS_PASSWORD` (optional, env var)
  - Used by:
    - n8n Bull queue: `QUEUE_BULL_REDIS_HOST`, `QUEUE_BULL_REDIS_PORT`
    - Max concurrency: `QUEUE_BULL_MAX_CONCURRENCY` (2 workers default)
    - Strapi plugin caching (ioredis 5.10.0)

## Authentication & Identity

**Auth Provider:**
- **Custom Strapi Users-Permissions** - Built-in Strapi auth plugin
  - Endpoint: `POST /api/auth/local` (Strapi Users-Permissions plugin)
  - Credentials: Email/username + password
  - Token: JWT (`STRAPI_JWT_SECRET`, `STRAPI_ADMIN_JWT_SECRET`)
  - Roles: Public (kiosk), Authenticated (admin dashboard)
  - Implementation: `inventory-cms/package.json` includes `@strapi/plugin-users-permissions`

**API Key Auth:**
- **n8n API Keys** - Service-to-service auth
  - Generated: n8n Settings > API
  - Location: `user_api_keys` table in n8n database
  - Usage: MCP server integration (`n8n-mcp`), external workflows

- **Strapi API Tokens** - CMS content access
  - Types: `strapiApi` (email+password), `strapiTokenApi` (token)
  - Token salt: `STRAPI_API_TOKEN_SALT` (env var)
  - Managed via: Strapi admin panel or `strapi-mcp` server
  - Expiry: Configurable per token

**Admin Access Control:**
- **Traefik BasicAuth** - HTTP Basic auth
  - Credentials file: `/run/secrets/traefik_usersfile`
  - Applied to: `console.*` (n8n), `cms.*` (Strapi), `admin.*` (admin dashboard)
  - User/pass: `N8N_BASIC_AUTH_USER`, `N8N_BASIC_AUTH_PASSWORD` (n8n specific)

- **IP Allowlist** - Network-level access control
  - Variable: `ADMIN_ALLOWED_IPS` (env var, comma-separated CIDR)
  - Example: `127.0.0.1/32,176.137.184.195/32,172.18.0.0/16,172.19.0.0/16`
  - Applied to: Traefik middleware for admin routes
  - Update script: `/opt/resto/update-allowlist.sh <ip>` on VPS

**Webhook Auth:**
- **Meta Webhook Signature** - Request verification
  - Header: `X-Hub-Signature-256` (HMAC-SHA256)
  - Secret: `META_APP_SECRET` (env var)
  - Validation: `META_SIGNATURE_REQUIRED` (enforce in production)

- **n8n Webhook Tokens** - Shared token for outbound webhooks
  - Token: `WEBHOOK_SHARED_TOKEN` (env var)
  - Included in outbound requests

## Monitoring & Observability

**Error Tracking:**
- **None detected** - No Sentry, DataDog, or similar configured
- Manual monitoring: Alert webhook available (`ALERT_WEBHOOK_URL` env var)

**Logs:**
- **Docker JSON logging driver**
  - All containers: `logging.driver=json-file`
  - Max file size: 5-10MB per file
  - Max files: 3-5 rotated files
  - Access logs: Traefik access log enabled (`--accesslog=true`)

**Observability Features:**
- **SLO Monitoring** - Defined in n8n env vars:
  - `SLO_INBOUND_TO_OUTBOX_P95_MS` (2000ms target)
  - `SLO_OUTBOX_PENDING_AGE_MAX_SEC` (600s)
  - `SLO_DLQ_RATE_MAX` (0.05 - max 5% dead-letter rate)
  - `SLO_DLQ_COUNT_MAX` (5 - max 5 stuck messages)
  - Monitoring: Manual query of `execution_queue` and `message_outbox` tables

- **Health Endpoints:**
  - Traefik: `--ping=true` → `/ping`
  - n8n: `/healthz` (HTTP GET)
  - Strapi: `/_health`
  - PostgreSQL: `pg_isready` health check
  - Redis: `redis-cli ping` health check
  - Nginx gateway: `/healthz`

**Structured Logging:**
- n8n: JSON execution logs with correlation IDs (implicit via flow traces)
- Strapi: Winston transport (via `@strapi/strapi`)
- SQL: Statements logged via `log_statement=ddl`, slow queries via `log_min_duration_statement`

## CI/CD & Deployment

**Hosting:**
- **Hostinger VPS** - srv1258231.hstgr.cloud
  - IP: 72.60.190.192
  - User: `deploy` (SSH key auth)
  - Path: `/opt/resto/current/` (active symlink)

**CI Pipeline:**
- 13 GitHub Actions workflows in `.github/workflows/`
  - `ci.yml` - Lint, test, build, security scan
  - `cd-deploy.yml` - Staging → production deployment
  - `security-scan.yml` - SAST, dependencies, Docker image scanning
  - `build-push-artifacts.yml` - Docker image build + push to GHCR
  - `migration-validate.yml` - DB migration safety checks
  - `scheduled-backup.yml` - Automated daily backups

**Artifact Registry:**
- **GHCR (GitHub Container Registry)**
  - Image prefix: `ghcr.io/ralphé-rest/`
  - Images: admin-dashboard, kiosk-app, cms (inventory-cms), gateway (nginx)
  - Auth: GitHub token

**Image Versioning:**
- Git SHA + version tag (supply-chain security)
- Cosign signing (keys in secrets)
- No `:latest` tags in production

**Environment Secrets:**
- Stored in: GitHub Actions Secrets + VPS `/opt/resto/secrets/`
- VPS secrets mounted at: `/run/secrets/` (read-only)
- Required:
  - `postgres_password`
  - `n8n_encryption_key`
  - `strapi_admin_password`
  - `traefik_usersfile`

## Webhooks & Callbacks

**Incoming:**
- **Meta Webhooks** (WhatsApp, Instagram, Messenger)
  - Routes: `/v1/inbound/whatsapp`, `/v1/inbound/instagram`, `/v1/inbound/messenger`
  - Verification: GET with `hub.challenge` parameter
  - Payload: POST with messages, media, status updates
  - Auth: HMAC-SHA256 signature + IP allowlist

- **n8n Webhooks**
  - Base: `https://api.srv1258231.hstgr.cloud/webhook/`
  - Example: `/webhook/admin/chat` (admin agent endpoint)
  - Auth: `WEBHOOK_SHARED_TOKEN` (optional, can be disabled)

- **Payment Webhooks** (Chargily, COD)
  - Routes defined in workflow configuration
  - Auth: API key or signature validation

**Outgoing:**
- **Meta Send API** - Messages back to users
  - Endpoint: `https://graph.facebook.com/v21.0/` (env var prefix)
  - Method: POST to `/messages` (WhatsApp, Instagram, Messenger)
  - Auth: Bearer token in Authorization header

- **Alert Webhooks**
  - URL: `ALERT_WEBHOOK_URL` (env var, optional)
  - Triggered on: Critical errors, SLO breaches, deployment events
  - Payload: JSON with error context

- **Outbox Pattern** (Reliability)
  - Retry logic: Exponential backoff (base delay 30s, max 3600s)
  - Max attempts: 7 (configurable `OUTBOX_MAX_ATTEMPTS`)
  - Dead-letter queue: `message_outbox` table with status='DEAD_LETTER'
  - Monitoring: Track DLQ rate and pending age via SLO vars

## Data Protection & GDPR

**No explicit configuration found:**
- No GDPR consent endpoint
- No data retention policy enforced (migrations exist but no TTL delete)
- PII stored in: Strapi `customers`, `orders`, PostgreSQL `user_*` tables
- Backups: Automated (via `scheduled-backup.yml`)

---

*Integration audit: 2026-03-14*
