# n8n Queue-Mode Architecture

**Analysis Date:** 2026-03-20
**Scope:** n8n automation system — RESTO BOT v3.3.0

---

## Pattern Overview

**Overall:** Event-driven queue-mode automation with inbound adapter pattern, outbox pattern for outbound reliability, and sub-workflow composition.

**Key Characteristics:**
- Queue mode (Bull + Redis): n8n-main handles webhooks/triggers; n8n-worker executes jobs
- Inbound adapters normalize multi-channel payloads into a canonical envelope before business logic
- Outbox pattern ensures outbound messages survive failures (Redis list + exponential backoff retry)
- Sub-workflow composition: `W0_CONFIG_READER` and `W0_REDIS_HELPER` are shared library workflows called by many others via `executeWorkflow`
- Tenant context is HMAC-sealed between workflows to prevent privilege escalation across sub-workflow calls

---

## Queue Mode Setup

**n8n-main (port 5678):**
- Registers all webhooks, handles all scheduling triggers (ScheduleTrigger cron nodes)
- Delegates job execution to workers via Bull/Redis queue
- `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true` — manual runs also go through the worker
- Resource limits: 1.0 CPU, 1G RAM
- Networks: `proxy` (Traefik-exposed) + `internal` (database/Redis)

**n8n-worker:**
- Pulls and executes jobs from the Bull queue
- Concurrency: `QUEUE_BULL_MAX_CONCURRENCY` (default: 2)
- Custom entrypoint: `project/scripts/n8n-worker-entrypoint.sh` — reads `N8N_ENCRYPTION_KEY` from `/run/secrets/n8n_encryption_key` and exports it as an env var before calling `exec tini -- /docker-entrypoint.sh worker`. This workaround is required because n8n worker does not natively support `N8N_ENCRYPTION_KEY_FILE`.
- Resource limits: 0.75 CPU, 768M RAM
- Networks: `internal` only — no Traefik/proxy exposure
- Health check: `pgrep -f 'n8n worker'`

**Redis (queue broker + cache + outbox):**
- Image: `redis:7-alpine`, memory limit: 384M
- Key namespaces in use:
  - `ralphe:outbox:pending` — Redis list; outbox retry queue (RPOP/LPUSH for FIFO)
  - `ralphe:outbox:wa:{id}`, `ralphe:outbox:ig:{id}`, `ralphe:outbox:msg:{id}` — per-message outbox entries (TTL: 7 days via `OUTBOX_REDIS_TTL_SEC`)
  - `ralphe:outbox:sent:{id}` — dedupe keys for sent messages (TTL: configurable)
  - `ralphe:outbox:pending:count` — pending count gauge
  - `config:platform` — cached Strapi system-config (TTL: `MENU_CACHE_TTL_SEC`, default 300s)
  - `ralphe:error:burst_count` — error burst counter in `W_ERROR_HANDLER`
  - `paid:{checkout_id}` — payment idempotency keys in `W_PAYMENT_CALLBACK`
- AOF persistence enabled via `project/infra/redis/entrypoint.sh`
- Optional auth via `REDIS_PASSWORD` env var

**Known quirk — `N8N_RUNNERS_ENABLED=false` does not suppress task-runner processes:**
- Set to `false` on both n8n-main (compose line 377) and n8n-worker (compose line 518)
- In n8n 2.9.4 task-runner sub-processes still spawn — the flag is not fully honored in this version
- Impact: extra CPU consumption; observed load spikes (peak ~28, normalizes to ~10 over time)
- No fix available without upgrading n8n

---

## Workflow Categories

### Category 1 — Meta Webhook Verification

**`project/workflows/W0_META_VERIFY_UNIFIED.json`** (active: false in JSON):
- Handles `GET /webhook/v1/inbound/whatsapp`, `.../instagram`, `.../messenger`
- Three separate webhook trigger nodes all fan into one shared Code node (`B0 - Verify Challenge`)
- Verifies `hub.mode=subscribe` + `hub.verify_token` using a timing-safe character-by-character XOR comparison
- Success: returns `hub.challenge` as `text/plain` with `Cache-Control: no-store`
- Failures: 400 (bad mode or missing challenge), 403 (token mismatch), 500 (token not configured), 404 (feature disabled)
- Config: `META_VERIFY_ENABLED`, `META_VERIFY_TOKEN`

### Category 2 — Inbound Adapters

All inbound adapters share an identical processing pipeline:

```
POST Webhook (rawBody: true)
  → B0 Parse & Canonicalize  (Meta native format → canonical envelope v1 or v2)
  → B0 Signature OK?         (X-Hub-Signature-256 HMAC; modes: off / warn / enforce)
  → RESP 200 ACK             (immediate — fast ACK before further processing)
  → B0 Contract Valid?       (ajv or basic validator against /opt/resto/schemas/inbound/{version}.json)
  → B0 Resolve Client        (DB: api_clients table lookup by SHA-256(token))
  → B0 Apply Auth Context    (authMode: api_client | meta_signature | legacy_shared | deny)
  → B0 Seal Tenant Context   (HMAC-SHA256 of tenant_context with TENANT_CONTEXT_SECRET)
  → B0 Token OK?
  → B0 Dedupe Check          (W0_REDIS_HELPER sub-workflow: SET NX on msg_id)
  → executeWorkflow → W4.1_ROUTER
```

**`project/workflows/W1_IN_WA.json`** — WhatsApp (active: false in JSON, enabled on VPS):
- Path: `POST /webhook/v1/inbound/whatsapp`
- Parses Meta native format (`object: 'whatsapp_business_account'`) and legacy passthrough format
- Silently drops WhatsApp status events (delivered/read receipts) — returns 200 with no downstream action
- Signature enforcement controlled by `META_SIGNATURE_REQUIRED` (default: `enforce`)
- Replay window: `META_REPLAY_WINDOW_SEC` (default: 600s)

**`project/workflows/W2_IN_IG.json`** — Instagram (active: true), path: `POST /webhook/v1/inbound/instagram`

**`project/workflows/W3_IN_MSG.json`** — Messenger (active: true), path: `POST /webhook/v1/inbound/messenger`

**`project/workflows/W1_IN_TIKTOK.json`** — TikTok (active: true), separate adapter for TikTok channel

### Category 3 — Canonical Inbound Schemas

Defined in `project/schemas/inbound/`, validated at runtime in adapters:

**`project/schemas/inbound/v1.json`:**
- Required: `contract_version:"v1"`, `provider:"wa"|"ig"|"msg"`, `msg_id`, `from`, `text`, `timestamp`
- Optional: `attachments[]` (type: audio|image, max 10), `meta`, `tenant_context`
- `additionalProperties: false` on all objects

**`project/schemas/inbound/v2.json`:**
- Required: `contract_version:"v2"`, `provider`, `msg_id`, `sender.id`, `message`, `timestamp`
- `message` must contain at least `text` or `attachments[]`
- Adds `meta.idempotency_key` field
- Attachment mime pattern restricted to `^(audio|image)/`
- `additionalProperties: false` on all objects

`tenant_context` in both versions is marked as never-trusted from payload without proof (`source: untrusted_payload | auth_db | legacy_shared`).

### Category 4 — Core Business Logic

**`project/workflows/W4_CORE.json`** (active: false in JSON):
- Main conversation orchestrator; entry point for all canonical messages from inbound adapters

**`project/workflows/W4.1_ROUTER.json`** (active: false in JSON):
- Entry: `executeWorkflowTrigger` (called by adapters via executeWorkflow)
- Re-verifies tenant context HMAC seal (throws `TENANT_CONTEXT_TAMPERED` on mismatch)
- Upserts customer into `restaurant_users` (tenant_id, restaurant_id, channel, user_id, role='customer') with `ON CONFLICT DO NOTHING`
- Single SQL query loads: `conversation_state`, `carts`, `customer_preferences` (locale), `system_configs`, all `message_templates` for tenant + `_GLOBAL` in both `fr` and `ar` locales

**`project/workflows/W4_CORE_MENU_GROUNDED.json`:**
- LLM-grounded variant with AI input guardrails
- Prompt injection detection: 16 patterns (instruction overrides, role manipulation, system prompt leakage, jailbreaks, encoding tricks, delimiter injection, sudo/execute commands)
- Input sanitization: strips control chars (0x00–0x1F, 0x7F–0x9F), collapses whitespace, hard-caps at `AI_INPUT_MAX_LENGTH` (default 500 chars)
- Blocked inputs return a friendly rejection message without reaching the LLM

**`project/workflows/W4.2_CART_MANAGER.json`** (active: false) — Cart CRUD operations sub-workflow

**`project/workflows/W4.3_FAQ_AGENT.json`** (active: false) — FAQ routing sub-workflow

### Category 5 — Outbound Senders

All output workflows use `executeWorkflowTrigger` and implement the outbox pattern before calling external APIs.

**`project/workflows/W5_OUT_WA.json`** — WhatsApp (active: false in JSON):
- Generates a unique `outboxMsgId`, stores an outbox entry in Redis key `ralphe:outbox:wa:{id}` (TTL 7 days)
- Pushes entry to `ralphe:outbox:pending` list for async retry (if `OUTBOX_ASYNC_ENABLED=true`; default: false = synchronous)
- Propagates `correlation_id` from `_timing` for end-to-end tracing
- Meta Cloud API URL auto-constructed: `https://graph.facebook.com/{GRAPH_API_VERSION}/{WA_PHONE_NUMBER_ID}/messages`
- Supports: plain text, interactive buttons (max 3; titles max 20 chars), template messages (locale: `ar` or `fr`)
- Built-in retry loop: up to `OUTBOX_MAX_ATTEMPTS` with exponential backoff; 429 respects `retry-after` header; 4xx client errors are not retried

**`project/workflows/W6_OUT_IG.json`** — Instagram sender (active: true)

**`project/workflows/W7_OUT_MSG.json`** — Messenger sender (active: true)

**`project/workflows/W5_OUT_TIKTOK.json`** — TikTok sender

### Category 6 — Outbox Worker

**`project/workflows/W15_OUTBOX_WORKER.json`** (active: false in JSON):
- Trigger: ScheduleTrigger every 30 seconds
- Config: `OUTBOX_WORKER_ENABLED` (default true), `OUTBOX_WORKER_BATCH_SIZE` (default 10), `OUTBOX_MAX_ATTEMPTS` (7), `OUTBOX_BASE_DELAY_SEC` (30), `OUTBOX_MAX_DELAY_SEC` (3600)
- RPOP from `ralphe:outbox:pending` (tail=true → FIFO order)
- Integrity: verifies `_seal` HMAC on messages that carry it; discards tampered messages as invalid
- Exponential backoff formula: `delay = min(baseDelaySec * 2^(attempts-1), maxDelaySec)` seconds
- Not-ready messages (where `nextRetryAt` is in the future) are LPUSH'd back onto the queue
- Dedupe: checks `ralphe:outbox:sent:{outboxMsgId}` before each send attempt
- **Known limitation:** The batch loop is currently a stub — only 1 message is processed per 30s execution. Comment in code says "simplified version"; batch LRANGE+LTRIM not yet implemented. See CONCERNS.md.

### Category 7 — DLQ Handler and Replay

**`project/workflows/W8_DLQ_HANDLER.json`** (active: true):
- Trigger: ScheduleTrigger every 5 minutes
- SQL: `SELECT ... FROM outbound_messages WHERE status='DLQ' AND last_retry_at < NOW()-INTERVAL '1 hour' ORDER BY created_at ASC LIMIT 50`
- Alert threshold: `DLQ_ALERT_THRESHOLD` (default 10)
- On alert: INSERT into `security_events` (`DLQ_THRESHOLD_EXCEEDED`, severity `HIGH`), POST to `ALERT_WEBHOOK_URL` if configured and `ALERT_SLO_ENABLED=true`
- Credential: `"id": "POSTGRES_CREDENTIAL_ID"` static placeholder — must be replaced with real n8n credential ID

**`project/workflows/W8_DLQ_REPLAY.json`** (active: false — manual trigger only):
- Path: `POST /webhook/v1/admin/dlq/replay`
- Admin token: SHA-256 hash validated against `api_clients` table with `scopes` check
- Options: `{msg_ids[], channel, max_messages (hard cap 100), dry_run, replay_all}`

### Category 8 — Shared Sub-Workflows

**`project/workflows/W0_CONFIG_READER.json`** (active: true):
- Called via `executeWorkflow` from most other workflows; `callerPolicy: workflowsFromSameOwner`
- Cache-first: GET Redis `config:platform`; if valid JSON, return immediately
- Cache miss: `GET {STRAPI_URL}/api/system-config` with `Authorization: Bearer {STRAPI_API_TOKEN}`
- Writes response to Redis with `MENU_CACHE_TTL_SEC` TTL (default 300s)
- Callers must handle null/empty config and fall back to env vars

**`project/workflows/W0_REDIS_HELPER.json`** (active: true):
- Dedupe primitive: `SET NX` with caller-supplied `dedupeKey` and `dedupeTtl` (default 86400s)
- Returns `{_redis: {available, isNew, error, dedupeKey, checkedAt}}`
- Fails open: Redis error → `available=false`, `isNew=true` — messages are never dropped due to Redis unavailability

### Category 9 — Admin AI Agents

**`project/workflows/W_ADMIN_AGENT.json`** (active: true):
- Path: `POST /webhook/admin/chat` with header auth
- Fetches `system-config` from Strapi for `llm_model` and `llm_temperature`
- Uses `@n8n/n8n-nodes-langchain.agent` + `lmChatOllama` (model from config or `LLM_MODEL` env var, default `llama3.1`) + `memoryBufferWindow`
- Tool: `Strapi_Manager` (HTTP REST calls to Strapi) — replaces removed `toolPostgres` (not available in n8n 2.9.4)
- `errorWorkflow: "W_ERROR_HANDLER"` configured

**`project/workflows/W_ADMIN_AI_AGENT.json`** (active: true):
- Second admin agent implementation (distinct workflow, different path)
- Path: `POST /webhook/admin-agent`
- Input hard-capped at 2000 chars; session ID hard-capped at 128 chars

### Category 10 — Payment Flows

**`project/workflows/W_PAYMENT_CHARGILY.json`** (`active` field absent from JSON — treated as inactive):
- Path: `POST /webhook/create-payment`
- Fetches order from Strapi with `restaurant_id` filter (tenant-isolated — prevents price spoofing, documented as SEC-006)
- Creates Chargily checkout session via Chargily Pay API

**`project/workflows/W_PAYMENT_CALLBACK.json`** (`active` field absent from JSON):
- Path: `POST /webhook/chargily-callback`
- Signature verification: `crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))` using `CHARGILY_SECRET_KEY`
- Idempotency: Redis GET `paid:{checkout_id}` before any state update
- Payment methods: COD (`PAYMENT_COD_ENABLED=true`), Deposit (`PAYMENT_DEPOSIT_ENABLED=true`), CIB (default off), Edahabia (default off)

### Category 11 — Global Error Handler

**`project/workflows/W_ERROR_HANDLER.json`:**
- Global error workflow; configured via `settings.errorWorkflow: "W_ERROR_HANDLER"` in other workflows
- Redis `INCR ralphe:error:burst_count` on each trigger
- PII masking before persistence: E.164 phones → `[PHONE_REDACTED]`, emails, Algerian address patterns, sensitive IDs/keys
- Persists sanitized record to `workflow_errors` table (workflow_name, node_name, error_message, stack, execution_id)
- Fires `ALERT_WEBHOOK_URL`; burst-throttled when `burstCount > 10`

### Category 12 — Health / SLO / Monitoring

**`project/workflows/W16_HEALTHZ.json`** (active: false):
- Exposes `GET /webhook/readyz` (readiness probe) and `GET /webhook/livez` (liveness probe)

**`project/workflows/W17_HEALTH_MONITOR.json`** (active: false):
- Trigger: ScheduleTrigger every 1 minute; polls `WEBHOOK_URL/webhook/readyz`; fires `ALERT_WEBHOOK_URL` on failure
- SLO thresholds: `SLO_INBOUND_TO_OUTBOX_P95_MS=2000`, `SLO_OUTBOX_PENDING_AGE_MAX_SEC=600`, `SLO_DLQ_RATE_MAX=0.05`, `SLO_DLQ_COUNT_MAX=5`

**`project/workflows/W8_OPS.json`** (active: false) — operations utilities

**`project/workflows/W18_MEDIA_FETCH_WORKER.json`** (active: false) — media download worker

**`project/workflows/W9_ADMIN_PING.json`** (active: false) — admin ping utility

---

## Execution Flow — Inbound Message Happy Path

```
Meta Platform
    │  POST /v1/inbound/whatsapp  +  X-Hub-Signature-256
    ▼
Traefik :443  (TLS termination; rate limit: 20r/s avg / 40 burst on api-public-chain)
    ▼
Gateway nginx :8080  (upstream n8n-main:5678; resolver 127.0.0.11 valid=10s)
    ▼
n8n-main  (webhook receiver — enqueues Bull job to Redis)
    ▼
n8n-worker  (dequeues; executes W1_IN_WA / W2_IN_IG / W3_IN_MSG)
    ├── Parse & canonicalize Meta format → canonical envelope
    ├── Verify X-Hub-Signature-256  (enforce mode by default)
    ├── ACK 200 immediately
    ├── Validate envelope against JSON schema (v1/v2)
    ├── Resolve client from api_clients table
    ├── Apply auth context + seal tenant_context (HMAC)
    └── Dedupe check via W0_REDIS_HELPER (SET NX on msg_id)
    ▼
W4.1_ROUTER  (executeWorkflow sub-workflow)
    ├── Re-verify tenant context seal
    ├── Upsert restaurant_users
    └── Load state + cart + prefs + templates (1 SQL query)
    ▼
W4_CORE  (intent detection, cart state machine, LLM if needed)
    ▼
W5_OUT_WA / W6_OUT_IG / W7_OUT_MSG  (outbound sender)
    ├── Prepare outbox entry (outboxMsgId, envelope JSON)
    ├── Store in Redis  (ralphe:outbox:wa:{id}, TTL 7d)
    └── Send to external API with built-in retry loop
    ▼
outbound_messages.status = SENT  |  FAILED → DLQ (after max attempts exhausted)
```

---

## Tenant Context Security

**Sealing mechanism:**
After resolving auth, each inbound adapter computes `HMAC-SHA256(JSON.stringify(tenant_context), TENANT_CONTEXT_SECRET)` and attaches it as `tenant_context_seal`. Every downstream sub-workflow re-verifies the seal before trusting `tenantId`/`restaurantId`. A mismatch throws `TENANT_CONTEXT_TAMPERED` and halts execution immediately.

**Auth mode priority (inbound adapters):**
1. `api_client` — SHA-256 token hash matches `api_clients` table; tenant/restaurant from DB record
2. `meta_signature` — valid X-Hub-Signature-256; uses `DEFAULT_TENANT_ID` / `DEFAULT_RESTAURANT_ID` env vars
3. `legacy_shared` — matches `WEBHOOK_SHARED_TOKEN`; only active when `LEGACY_SHARED_ALLOWED=true`
4. `deny` — event is dropped

---

## Workflow Activation Status in JSON Files

The `active` field in JSON reflects the state at last export from n8n. Actual live state is stored in the `workflow_entity` table in PostgreSQL. To check or set live state use `SELECT id, name, active FROM workflow_entity` — do not rely on the JSON field alone.

**Note:** `PATCH /api/v1/workflows/{id}/activate` returns `active: unknown` in n8n 2.9.4. Use `UPDATE workflow_entity SET active=true WHERE id='{id}'` as a reliable workaround.

**active: true in JSON (30+ workflows):**
`W0_CONFIG_READER`, `W0_REDIS_HELPER`, `W2_IN_IG`, `W3_IN_MSG`, `W1_IN_TIKTOK`, `W8_DLQ_HANDLER`, `W51_VIP_WIN_BACK`, `W50_CART_ABANDONMENT`, `W31_VOICE_ORDER_CONFIRM`, `W30_VOICE_CALL_INIT`, `W53_DYNAMIC_KITCHEN_LOAD`, `W6_OUT_IG`, `W7_OUT_MSG`, `W_ADMIN_AGENT`, `W_ADMIN_AI_AGENT`, `W_STT_PIPELINE`, `W_UPSELL_ENGINE`, `W_TRACKING_FUNNEL`, `W58_DYNAMIC_SURGE`, `W60_KITCHEN_CLOUD_PRINT`, `W61_REVIEW_CATCHER`, `W_BOT_FUNNEL_HOOK`, `W_AI_FUNNEL_LEARNER`, `W_TIKTOK_PUBLISHER`, `W_AD_MANAGER`, `W_ADMIN_PROACTIVE_AGENT`, `W_OMNICHANNEL_CONTENT_GEN`, `W_GROWTH_AGENT`, `W_LOYALTY_ENGINE`, `W_KIOSK_ORDER`, `W_CONTENT_SCHEDULER`, `W_REVENUE_INTELLIGENCE`, `W_CORTEX_REGISTRY`, `W_RALPHE_OMNISCIENT`

**active: false in JSON (critical path — must be verified active on VPS):**
`W0_META_VERIFY_UNIFIED`, `W1_IN_WA`, `W4_CORE`, `W4.1_ROUTER`, `W4.2_CART_MANAGER`, `W4.3_FAQ_AGENT`, `W15_OUTBOX_WORKER`, `W5_OUT_WA`, `W16_HEALTHZ`, `W17_HEALTH_MONITOR`, `W18_MEDIA_FETCH_WORKER`, `W8_DLQ_REPLAY`, `W14_ADMIN_WA_SUPPORT_CONSOLE`, `W9_ADMIN_PING`, `W12_ADMIN_ORDERS`

**`active` field absent (treated as inactive by n8n):**
`W_PAYMENT_CHARGILY`, `W_PAYMENT_CALLBACK`, `W_ORDER_FINALIZER`, `W_INVENTORY_SYNC`, `W_CMS_SYNC`, `W_DRIVER_DISPATCH`, `W_DRIVER_BOT`, `W_DRIVER_ROUTER`, `W_DRIVER_ACTIONS`, `W_DRIVER_ONBOARDING`, `W_DRIVER_GAMIFICATION`, `W_DRIVER_AVAILABLE_LIST`, `W_DRIVER_HISTORY`, `W_DRIVER_OTP_VERIFY`

---

*Architecture analysis: 2026-03-20*
