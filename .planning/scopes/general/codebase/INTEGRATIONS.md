# External Integrations

**Analysis Date:** 2026-03-20

## APIs & External Services

**Meta Platform (WhatsApp, Instagram, Messenger):**
- What: Inbound webhooks (message events) and outbound message sending
- Inbound: Meta POSTs to `https://api.<domain>/v1/inbound/{whatsapp|instagram|messenger}`
- Verification: Meta sends GET with `hub.verify_token` challenge → handled by `W0_META_VERIFY_UNIFIED.json`
- Security: HMAC-SHA256 signature validation using `META_APP_SECRET` env var; replay window enforced (`META_REPLAY_WINDOW_SEC=600`); guard table: `webhook_replay_guard`
- Outbound: n8n workflows call Meta Graph API send URLs via `WA_SEND_URL`, `IG_SEND_URL`, `MSG_SEND_URL` env vars
- Auth tokens: `WA_API_TOKEN`, `IG_API_TOKEN`, `MSG_API_TOKEN` (never passed as query params)
- Audio CDN allowlist: `cdn.fbsbx.com,lookaside.fbsbx.com,mmg.whatsapp.net,graph.facebook.com` (SSRF protection)
- Legacy alias routes: `/v1/inbound/wa-incoming-v16`, `/v1/inbound/ig-incoming-v16`, `/v1/inbound/msg-incoming-v16` (backward compat)
- Workflows: `project/workflows/W1_IN_WA.json`, `W2_IN_IG.json`, `W3_IN_MSG.json`, `W5_OUT_WA.json`, `W6_OUT_IG.json`, `W7_OUT_MSG.json`

**TikTok:**
- What: TikTok inbound messages and outbound publishing
- Workflows: `project/workflows/W1_IN_TIKTOK.json`, `W5_OUT_TIKTOK.json`, `W_TIKTOK_PUBLISHER.json`
- Integration details not deeply verified (experimental feature)

## Payment Providers

**CIB (Algerian bank card):**
- Status: Disabled by default (`PAYMENT_CIB_ENABLED=false`)
- Env var: `PAYMENT_CIB_ENABLED`
- Integration type: flag-gated; actual payment processing details in n8n workflows

**Edahabia (Algérie Poste card):**
- Status: Disabled by default (`PAYMENT_EDAHABIA_ENABLED=false`)
- Env var: `PAYMENT_EDAHABIA_ENABLED`
- Integration type: flag-gated

**COD (Cash on Delivery):**
- Status: Enabled by default (`PAYMENT_COD_ENABLED=true`)
- Max amount: `PAYMENT_COD_MAX_AMOUNT` (default 1,000,000 DZD)

**Deposit:**
- Status: Enabled by default (`PAYMENT_DEPOSIT_ENABLED=true`)
- Mode: `PAYMENT_DEPOSIT_MODE=PERCENTAGE` (default 30% of order total)
- Threshold: Only for orders above `PAYMENT_DEPOSIT_THRESHOLD` (default 300,000 DZD)
- Timeout: `PAYMENT_DEPOSIT_TIMEOUT_MIN` (default 30 minutes)

**Chargily (online payments):**
- Workflow: `project/workflows/W_PAYMENT_CHARGILY.json`
- Callback handler: `project/workflows/W_PAYMENT_CALLBACK.json`

## Data Storage

**Databases:**
- PostgreSQL 15-alpine at `postgres:5432` (internal network only)
  - Database `n8n`: workflow execution data, business logic tables (see `db/bootstrap.sql` for full schema)
  - Database `strapi`: Strapi CMS content (menus, orders, config)
  - Single PostgreSQL instance hosts both databases
  - Connection env vars: `DB_POSTGRESDB_HOST`, `DB_POSTGRESDB_DATABASE`, `DB_POSTGRESDB_USER`
  - Password: file-based secret at `/run/secrets/postgres_password`

**Cache/Queue:**
- Redis 7-alpine at `redis:6379` (internal network only)
  - Purpose: Bull queue for n8n workflow execution queue
  - Auth: optional `REDIS_PASSWORD`
  - Persistence: AOF enabled
  - Max memory: 384 MB

**File Storage:**
- Strapi uploads: Docker volume `cms_uploads` at `/app/public/uploads` in cms container
- No external object storage (S3/GCS) configured; all file storage is local volume

## Authentication & Identity

**Traefik BasicAuth:**
- Applied to: `console.<domain>`, `admin.<domain>`, `api.<domain>/v1/internal/*`, `api.<domain>/v1/admin/*`
- Config: htpasswd file at `secrets/traefik_usersfile` (mounted as Docker secret)
- Users defined in `ADMIN_ALLOWED_IPS`-gated routes

**Strapi Users-Permissions JWT:**
- Used by: admin dashboard app login (`POST /api/auth/local`)
- JWT secret: `STRAPI_JWT_SECRET`
- Admin JWT secret (Strapi admin panel): `STRAPI_ADMIN_JWT_SECRET`

**n8n Credentials:**
- Encrypted in PostgreSQL `n8n` database using `n8n_encryption_key` file-based secret
- Credential types used: `strapiTokenApi` (API token), `strapiApi` (email+password), `postgresDb`, `redis`

**Webhook Token Auth:**
- Header-based: `x-webhook-token` or `Authorization: Bearer`
- Query token disabled: `LEGACY_SHARED_ALLOWED=false` by default
- Shared token: `WEBHOOK_SHARED_TOKEN` env var

## AI / LLM

**Ollama (local, optional):**
- Service: `ollama` container, profile `ai`
- Endpoint: `http://ollama:11434/api/chat` (internal only)
- Model: llama3.1 (4.9 GB; must be pulled separately after container start)
- Env: `LLM_API_URL`, `LLM_MODEL`
- Fallback: if Ollama unavailable, workflows degrade gracefully

**Whisper ASR (local, optional):**
- Service: `whisper` container, profile `ai`
- Endpoint: `http://whisper:9000` (internal only; actual path TBD from workflow config)
- Env: `STT_API_URL`
- Used by: `project/workflows/W_STT_PIPELINE.json`

**NVIDIA NIM:**
- Referenced in `.planning/` phase docs (phase 07 NemoClaw Telegram bot project)
- Not integrated into the current RESTO BOT production stack
- Separate standalone project (`NemoClaw`) planned in future phases

## Monitoring & Observability

**Health Monitor:**
- GitHub Actions `health-monitor.yml` runs every 6 hours
- Checks: `GET https://api.<domain>/healthz` (HTTP 200 = healthy)
- SSH fallback diagnostics if HTTP unhealthy (checks docker ps, postgres, disk, memory)
- Alert: `ALERT_WEBHOOK_URL` (generic webhook) and `DISCORD_WEBHOOK_URL`

**Performance Baseline:**
- GitHub Actions `perf-baseline.yml` runs after each CD deploy
- Measures p50/p95/p99 for `/healthz`, `/v1/inbound/whatsapp` (GET), `/v1/admin/ping`
- Alerts if p95 > 2x previous baseline

**DORA Metrics:**
- Recorded by `scripts/dora_metrics.sh` after successful deploys
- Logged via GitHub Actions CD pipeline

**SLO Monitoring (in-workflow):**
- `W17_HEALTH_MONITOR.json` — internal SLO checks
- SLO targets: inbound-to-outbox P95 ≤ 2000ms, DLQ rate ≤ 5%, pending age ≤ 600s
- Env vars: `SLO_WINDOW_MIN`, `SLO_INBOUND_TO_OUTBOX_P95_MS`, `SLO_OUTBOX_PENDING_AGE_MAX_SEC`, `SLO_DLQ_RATE_MAX`, `SLO_DLQ_COUNT_MAX`

## CI/CD & Deployment

**GitHub Actions → VPS (SSH):**
- All CD workflows connect to VPS via SSH key secret `VPS_SSH_KEY`
- VPS vars: `VPS_HOST` (72.60.190.192), `VPS_USER` (deploy), `PROJECT_DIR` (/opt/resto), `BACKUP_DIR` (/opt/resto/backups), `HEALTH_URL`
- SSH composite action: `.github/actions/setup-ssh/action.yml`
- Deploy model: release directory model (`/opt/resto/releases/<id>/`), symlink `current` updated atomically

**GitHub Container Registry (GHCR):**
- Custom images pushed to: `ghcr.io/{owner}/resto-bot-{cms|admin|kiosk}`
- Tags: `:latest` + `:${{ github.sha }}`
- Signed with Cosign (private key in `COSIGN_PRIVATE_KEY` secret)
- SBOM: CycloneDX format, attested with Cosign
- SLSA Provenance: L2 attestations via `actions/attest-build-provenance`

**Notifications:**
- `ALERT_WEBHOOK_URL` — generic webhook (Slack/webhook-compatible)
- `DISCORD_WEBHOOK_URL` — Discord channel notifications
- Used by: CD deploy notifications, health monitor alerts

## Certificate Management

**Let's Encrypt (via Traefik ACME):**
- Method: TLS challenge (`--certificatesresolvers.mytlschallenge.acme.tlschallenge=true`)
- Email: `SSL_EMAIL` env var
- Storage: `traefik_data` volume at `/letsencrypt/acme.json`
- Auto-renewal handled by Traefik

## Webhooks & Callbacks

**Incoming (from external systems):**
- `POST https://api.<domain>/v1/inbound/whatsapp` — Meta WhatsApp events
- `POST https://api.<domain>/v1/inbound/instagram` — Meta Instagram events
- `POST https://api.<domain>/v1/inbound/messenger` — Meta Messenger events
- `GET https://api.<domain>/v1/inbound/{channel}` — Meta webhook verification challenges
- `POST https://api.<domain>/v1/...` — payment callbacks (Chargily; exact path in W_PAYMENT_CALLBACK.json)

**Outgoing (to external systems):**
- Meta Graph API — send WhatsApp/Instagram/Messenger messages
- Ollama API — LLM inference (`http://ollama:11434/api/chat`)
- Whisper ASR API — speech-to-text (`STT_API_URL`)
- `ALERT_WEBHOOK_URL` — health/deploy notifications

## Environment Configuration

**Required secrets (GitHub Actions):**
- `VPS_SSH_KEY` — SSH private key for VPS access
- `COSIGN_PRIVATE_KEY` / `COSIGN_PASSWORD` — image signing
- `ALERT_WEBHOOK_URL` — optional alert webhook
- `DISCORD_WEBHOOK_URL` — optional Discord notifications

**Required GitHub repository variables:**
- `VPS_HOST` — VPS IP/hostname (72.60.190.192)
- `VPS_USER` — SSH user (deploy)
- `PROJECT_DIR` — project root on VPS (/opt/resto)
- `BACKUP_DIR` — backup directory (/opt/resto/backups)
- `HEALTH_URL` — health check URL (https://api.<domain>/healthz)
- `DOMAIN` — production domain name

---

*Integration audit: 2026-03-20*
