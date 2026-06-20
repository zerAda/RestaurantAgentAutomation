# External Integrations

**Analysis Date:** 2026-06-20

> Integration topology: external messaging channels enter through **Traefik → nginx gateway →
> n8n webhooks**. n8n is the orchestrator and the only service that holds channel/LLM credentials.
> Strapi is the system-of-record for menu, orders, config, and the **SaaS product-module /
> tenant-entitlement** model that the `W0_MODULE_GUARD` workflow enforces. All secret values
> referenced below live in env vars, file-mounted secrets, or n8n's encrypted credential store —
> never in source.

## APIs & External Services

### Messaging Channels (omnichannel — the product's core)
Each channel is a **SaaS `channel_pack` module** (`config/product_modules.json`) gated by `W0_MODULE_GUARD` before inbound processing.

- **WhatsApp Business (Meta Graph API)** — module `channel_whatsapp`.
  - Inbound: `W1_IN_WA.json`; Outbound: `W5_OUT_WA.json`; Admin console: `W14_ADMIN_WA_SUPPORT_CONSOLE.json`.
  - Integration: `n8n-nodes-base.httpRequest` to Graph API (`WA_SEND_URL` + `GRAPH_API_VERSION`).
  - Auth: `WA_API_TOKEN`, `WA_PHONE_NUMBER_ID` (env, read in workflow code). Webhook signature: `META_APP_SECRET`.
  - Most-referenced channel: `WA_API_TOKEN` appears 31× across workflows, `WA_PHONE_NUMBER_ID` 27×.
- **Instagram DM (Meta Graph API)** — module `channel_instagram`.
  - Inbound: `W2_IN_IG.json`; Outbound: `W6_OUT_IG.json`.
  - Auth: `IG_API_TOKEN`, `IG_PAGE_ID`; send via `IG_SEND_URL`.
- **Facebook Messenger (Meta Graph API)** — module `channel_messenger`.
  - Inbound: `W3_IN_MSG.json`; Outbound: `W7_OUT_MSG.json`.
  - Auth: `MSG_API_TOKEN`, `MSG_PAGE_ID`; send via `MSG_SEND_URL`.
- **TikTok** — module `channel_tiktok` (rollout `disabled_by_default`).
  - Inbound DM: `W1_IN_TIKTOK.json`; Outbound: `W5_OUT_TIKTOK.json`; publishing: `W_TIKTOK_PUBLISHER`.
  - Auth: `TIKTOK_API_TOKEN`, `TIKTOK_CLIENT_KEY` / `TIKTOK_ACCESS_TOKEN`; analytics `TIKTOK_PIXEL_ID`.
- **Telegram** — driver/ops bot surface (`W_DRIVER_BOT.json` and related driver workflows under module `delivery_dispatch`). Minimal references; the README-mentioned "NemoClaw Telegram bot" is an in-progress roadmap item (Phase 7), not a fully wired channel.

All three Meta channels share one unified webhook verifier workflow: **`W0_META_VERIFY_UNIFIED.json`** (handshake + HMAC signature validation via `META_APP_SECRET`, gated by `META_SIGNATURE_REQUIRED` = `off|warn|enforce`).

### AI / LLM Services
- **Ollama (self-hosted, `ollama:0.6.2`)** — primary LLM inference. 6 `n8n-nodes-base.ollamaChat` nodes; reached via `LLM_API_URL` with `LLM_MODEL`. Used by router/FAQ/admin-AI workflows (`W4.1_ROUTER`, `W4.3_FAQ_AGENT`, `W_ADMIN_AI_AGENT`, etc.).
- **Whisper ASR (`openai-whisper-asr-webservice:v1.2.0`)** — speech-to-text for the `voice` module (`W_STT_PIPELINE`, `W30_VOICE_CALL_INIT`).
- **OpenAI / OpenRouter** — optional cloud LLM fallback. Auth via `OPENAI_API_KEY`, `OPENROUTER_API_KEY` (`.env.example`); a few direct `api.openai`/`chat/completions` references.
- **ElevenLabs** — text-to-speech (`ELEVENLABS_API_KEY`); part of the voice/TTS pipeline (`W_TTS_PIPELINE`).
- **Replicate** — image/asset generation (`REPLICATE_API_TOKEN`); used by content/asset workflows (`W20_ASSET_ENHANCER`, growth/content modules).
- **Vapi** — voice agent platform (`VAPI_TOKEN`); voice call module.

### Payments
- **Chargily** — payment initiation + callback (module `payment`).
  - Workflows: `W_PAYMENT_CHARGILY.json` (initiate), `W_PAYMENT_CALLBACK.json` (incoming callback), `W_ORDER_FINALIZER.json` (finalize on success).
  - CMS side: `inventory-cms/src/api/payment/` (schema + `lifecycles.ts`).
  - Auth: `CHARGILY_API_KEY` (`.env.example`). Cash-on-delivery toggled via `PAYMENT_COD_ENABLED`.
- **Twilio** — SMS/voice telephony (`TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`); used by OTP/voice paths.

### Other external
- **Supabase** — referenced for auxiliary storage/auth (`SUPABASE_URL`, `SUPABASE_ANON_KEY`); used by a handful of workflows, not the primary datastore.

## Data Storage

**Databases — one Postgres 15 instance, TWO logically isolated databases (important):**
- **`n8n` database** — owned by user `n8n`. Holds n8n's own execution/workflow data **and** the platform's business tables (orders, audit trail, metrics, dedupe, outbox, `tenant_entitlements`/`product_modules` constraints from `db/migrations/2026-04-06_saas_modules_entitlements.sql`). Bootstrapped by `db/bootstrap.sql`, evolved by `db/migrations/*.sql`.
- **`strapi` database** — owned by a **dedicated `strapi` user** with its own password, created/isolated by `db/init/02_create_strapi_db.sh` (P0-SEC-05 user isolation: revokes public schema, grants only to `strapi`). Strapi auto-creates its content-type tables here on boot.
- **Connection path:** every service connects through **pgBouncer** (`pgbouncer:5432`, transaction pooling), not Postgres directly. Strapi config in `inventory-cms/config/database.ts` (`DATABASE_HOST=pgbouncer`, `DATABASE_CLIENT=postgres`, pool 2–10). n8n uses `DB_POSTGRESDB_HOST=pgbouncer`.
- **n8n DB access from workflows:** 165 `n8n-nodes-base.postgres` nodes; credential referenced as `postgres-main` (fixed ID) or via `N8N_DB_CREDENTIAL_ID` env.
- **Migrations:** idempotent SQL in `db/migrations/` (16 files) applied by the `db-migrate` compose service (waits on pgBouncer, records into `schema_migrations`). Strapi-managed constraints layered on top via the SaaS migration.

**File Storage:**
- **Local volume** `cms_uploads` mounted at `/app/public/uploads` in the CMS container (Strapi default upload provider). No S3/cloud object store wired in.

**Caching / Queue / Pub-Sub (Redis 7):**
- **n8n Bull queue** — `QUEUE_BULL_REDIS_HOST=redis:6379`, `EXECUTIONS_MODE=queue` (drives `n8n-main` ↔ `n8n-worker`).
- **App cache / dedupe / outbox / rate-limit** — 60 `n8n-nodes-base.redis` nodes; credential via `REDIS_CREDENTIAL_ID` (env-indirected). Used for message dedupe (`DEDUPE_*`), outbox (`OUTBOX_*`), Meta replay guard (`REPLAY_*`), per-channel rate limits.
- **Strapi realtime SSE** — `ioredis` subscriber on channel `order_updates`, re-emitted to clients via Strapi eventHub (`inventory-cms/src/index.ts`).
- Auth: `REDIS_PASSWORD` (optional; no-auth fallback for backward compat).

## Authentication & Identity

**Public API (webhooks) — token auth:**
- Shared-token model: `x-webhook-token: <WEBHOOK_SHARED_TOKEN>` or `Authorization: Bearer <WEBHOOK_SHARED_TOKEN>`. Legacy `?token=` only if `ALLOW_QUERY_TOKEN=true` (off by default).
- Meta inbound routes are token-exempt (Meta doesn't send custom headers) — protected instead by HMAC signature (`META_APP_SECRET`) + IP-keyed rate limiting at the gateway.

**Strapi (CMS) auth:**
- Admin panel: Strapi admin users (super-admin auto-provisioned from `STRAPI_SUPER_ADMIN_EMAIL` / `STRAPI_SUPER_ADMIN_PASSWORD`, fail-closed in production — see `inventory-cms/src/index.ts`).
- API: `@strapi/plugin-users-permissions` JWT + Strapi **API tokens** (`STRAPI_API_TOKEN`, salted by `STRAPI_API_TOKEN_SALT`). The bootstrap also syncs a matching Users-Permissions API user for the dashboard.
- n8n → Strapi: 82 references to `STRAPI_API_TOKEN` + 75 to `STRAPI_URL`; module guard uses `STRAPI_API_TOKEN_INTERNAL` against `STRAPI_API_URL`/`STRAPI_INTERNAL_URL`.

**Admin dashboard auth:**
- `admin-dashboard/src/services/authService.ts` authenticates against Strapi (`VITE_STRAPI_URL`), JWT-based.

**SaaS multi-tenant entitlement model (the recent layer):**
- **`product-module`** (`inventory-cms/src/api/product-module/`) — catalog of features with `key`, `tier` (`shared_core | product_core | channel_pack | addon | experimental`), `enabled_globally`, `rollout_policy`, `required_env_vars`, `required_workflows`, `depends_on`.
- **`tenant-entitlement`** (`inventory-cms/src/api/tenant-entitlement/`) — per-tenant `(tenant_id, module_key, enabled, expires_at, config_overrides)`; DB-unique on `(tenant_id, module_key)` via `db/migrations/2026-04-06_saas_modules_entitlements.sql` (+ `entitlement_audit_log`).
- **`W0_MODULE_GUARD.json`** — shared gate called by workflow entrypoints. Queries Strapi `/api/product-modules` then `/api/tenant-entitlements`, checks global-enable / entitlement / expiry, returns `config_overrides`. **Fails closed** on error. Tenant resolved from input `tenant_id` or `DEFAULT_TENANT_ID` (default `'default'`).
- **Seeder:** `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` (invoked from `inventory-cms/src/index.ts` `bootstrap()`) seeds the 15 modules and auto-entitles the default tenant on first boot. Canonical module list mirrors `config/product_modules.json` (keys must match exactly or the guard denies).

## Monitoring & Observability

- **Error tracking:** internal — DLQ workflows (`W8_DLQ_HANDLER`, `W8_DLQ_REPLAY`), `W_ERROR_HANDLER`, and `workflow_error` CMS content type. No Sentry/Datadog wired.
- **Health:** `W16_HEALTHZ` / `W17_HEALTH_MONITOR` workflows; gateway `/healthz` + `/healthz/deep`; container healthchecks on every service. External cron via `.github/workflows/health-monitor.yml`.
- **Metrics/audit:** `W_QUEUE_METRICS`, `W_REDIS_MONITOR`, `W_AUDIT_WRITE/QUERY/ARCHIVE`; CMS `metric`, `admin-audit-log`, `llm-usage-log` content types.
- **Logs:** Docker json-file driver (rotated, `max-size`/`max-file` per service). Structured logging + correlation IDs injected at the gateway (`X-Correlation-Id`).

## CI/CD & Deployment

**Hosting:**
- Production: Docker Compose on Hostinger VPS (`docker-compose.hostinger.prod.yml`), edge by Traefik v3.6.6 (TLS via Let's Encrypt `mytlschallenge`).
- Image distribution: GitHub Container Registry (`ghcr.io/<owner>/resto-bot-<service>`) consumed by `docker-compose.ghcr.yml`.

**CI Pipeline (GitHub Actions, `.github/workflows/`):**
- `ci.yml` — integrity gate, lint/validate, `python-tests` (3.11), integration tests (spins Postgres + creates `strapi` DB), `cms-ts-compile`, `docker-build`, `frontend-lint`. Node `20.20.0`.
- `workflow-validate.yml` / `migration-validate.yml` — validate n8n workflow JSON and DB migration idempotency.
- `build-push-artifacts.yml`, `cd-deploy.yml` / `ralphe-cd-deploy.yml`, `release.yml`, `rollback.yml` — build/push images and deploy/rollback.
- `secret-scan.yml` / `security-scan.yml` — gitleaks (`.gitleaks.toml`) + security scanning.
- `scheduled-backup.yml`, `perf-baseline.yml`, `health-monitor.yml`, `env-sync.yml`, `debug-vps.yml`.
- A parallel `.gitlab-ci.yml` mirrors CI for GitLab.

## Environment Configuration

**Development:**
- Required: `DOMAIN_NAME`, `STRAPI_*` secrets, `WEBHOOK_SHARED_TOKEN`, channel tokens as needed, `DEFAULT_TENANT_ID`.
- Templates: `.env.example` (root), `config/.env.example`. References: `ENV_REFERENCE.md`, `SECRETS_INVENTORY.md`, `SECRETS_ACTION_PLAN.md`.
- Mock/stub: `mock-api/` service stands in for external HTTP dependencies in tests.

**Production:**
- Secrets management: **file-based Docker secrets** mounted from `./secrets/*` to `/run/secrets/*` (postgres password, strapi db password, n8n encryption key, strapi admin password, traefik usersfile). Strapi build uses throwaway placeholder secrets; real values injected at runtime.
- `META_SIGNATURE_REQUIRED=enforce` and `REDIS_PASSWORD` are required for a hardened prod posture.

## Webhooks & Callbacks

**Incoming (via nginx gateway `infra/gateway/nginx.conf` → n8n):**
- `POST /v1/inbound/whatsapp` → `/webhook/v1/inbound/whatsapp` (`W1_IN_WA`). `GET` handles Meta verify handshake.
- `POST /v1/inbound/instagram` → `W2_IN_IG`; `POST /v1/inbound/messenger` → `W3_IN_MSG`.
- Legacy aliases: `/v1/inbound/{wa,ig,msg}-incoming-v16` rewrite to the canonical webhook paths.
- `/v1/customer/*` (internal-token zone) → `/webhook/v1/customer/*`; `/v1/strapi/api/orders` and read-only kiosk menu routes proxy to `cms:1337`.
- Verification: Meta HMAC signature in `W0_META_VERIFY_UNIFIED` (`META_APP_SECRET`); replay protection via Redis (`REPLAY_*`, `db/migrations/2026-01-23_p0_sec02_meta_replay.sql`).
- Rate limiting zones at gateway: `meta_inbound` (10r/s by IP), `internal_token` (20r/s by `X-Api-Token`), `kiosk_menu` (30r/s by IP).
- Payment callback: `W_PAYMENT_CALLBACK.json` (Chargily → finalize order).

**Outgoing:**
- Channel sends to Meta Graph / TikTok APIs (`*_SEND_URL`), Chargily payment API, LLM endpoints (Ollama/OpenAI/OpenRouter), Whisper/ElevenLabs/Replicate.
- Internal alerts via `ALERT_WEBHOOK_URL`; kitchen print via `KITCHEN_PRINTER_IP`; ops/driver notifications to configured Telegram/group IDs (`LOGISTICS_DRIVERS_GROUP_ID`, `REVENUE_ALERTS_CHANNEL_ID`).
- Outbox pattern (`W15_OUTBOX_WORKER`, `OUTBOX_*`) provides retrying, async delivery of outbound messages.

## Service-to-Service Communication (summary)

- **Edge → app:** Traefik (TLS, per-subdomain routing + IP allowlist/BasicAuth) → nginx `gateway` (path normalization, rate limiting, correlation IDs) → `n8n-main` webhooks (`n8n-main:5678`) or `cms:1337`.
- **n8n ↔ Strapi:** HTTP REST over the `internal`/`proxy` networks (`STRAPI_URL` / `STRAPI_INTERNAL_URL`) with API token; the module guard is the hottest path.
- **n8n main ↔ worker:** Redis Bull queue (`redis:6379`).
- **All DB clients → pgBouncer → Postgres** (`pgbouncer:5432`); `n8n` user → `n8n` DB, `strapi` user → `strapi` DB (isolated).
- **Strapi → clients:** SSE pushed from Redis `order_updates` channel; SPAs poll/fetch Strapi REST (`VITE_STRAPI_URL`) and hit n8n webhooks (`VITE_N8N_URL` / `VITE_API_URL`).

---

*Integration audit: 2026-06-20*
*Update when adding/removing channels, external APIs, or changing the tenant-entitlement / credential model.*
