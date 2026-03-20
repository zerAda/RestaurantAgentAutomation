# n8n Stack

**Analysis Date:** 2026-03-20
**Scope:** n8n queue-mode automation system — RESTO BOT v3.3.0

---

## n8n Version

**Version:** 2.9.4
**Image:** `docker.n8n.io/n8nio/n8n:2.9.4`
**Mode:** Queue (EXECUTIONS_MODE=queue)
**Source:** `project/docker-compose.hostinger.prod.yml`; version pinned in `project/.env` as `N8N_VERSION=2.9.4`

### Version-Specific Quirks (2.9.4)

**1. toolPostgres not available:**
- `@n8n/n8n-nodes-langchain.toolPostgres` does not exist in 2.9.4
- W_ADMIN_AGENT previously broke on this; replaced with `toolHttpRequest` to Strapi REST API
- Any workflow referencing `toolPostgres` will fail silently at execution

**2. PATCH activation returns `active: unknown`:**
- `PATCH /api/v1/workflows/{id}` with `{active: true}` does not reliably set the active flag
- Workaround: direct SQL `UPDATE workflow_entity SET active=true WHERE id='{id}'` on the n8n PostgreSQL database
- API-level activation is unreliable for scripted deployment

**3. N8N_RUNNERS_ENABLED=false does not suppress task-runner:**
- The env var is set to `false` on both n8n-main and n8n-worker
- In 2.9.4 task-runner sub-processes still spawn — the flag is not fully honored
- Impact: extra CPU usage; observed load spikes during startup

**4. n8n CLI `import:workflow` hangs in queue mode:**
- `n8n import:workflow` blocks indefinitely inside a running queue-mode container
- Workaround: use Node.js HTTP request to `http://localhost:5678/api/v1/workflows` from inside the container
- API key: query `user_api_keys` table, column `apiKey` (camelCase)

**5. `webhook_entity` table removed in n8n 2.x:**
- Do not query `webhook_entity` — it does not exist
- Webhook data is now in `workflow_entity`

**6. Login field change:**
- Auth endpoint uses `emailOrLdapLoginId` (not `email`) for the login field

---

## Queue Infrastructure

**Broker:** Redis 7-alpine
**Queue library:** Bull (bundled with n8n)
**Queue config env vars:**
- `QUEUE_BULL_REDIS_HOST=redis`
- `QUEUE_BULL_REDIS_PORT=6379`
- `QUEUE_BULL_REDIS_PASSWORD` — optional, from `REDIS_PASSWORD`
- `QUEUE_BULL_MAX_CONCURRENCY` — default: 2 (worker only)

**Manual execution routing:**
- `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true` — manual runs go through worker, not main

---

## Execution Data Retention

- `EXECUTIONS_DATA_PRUNE=true`
- `EXECUTIONS_DATA_MAX_AGE=336` hours (14 days)
- `EXECUTIONS_DATA_PRUNE_MAX_COUNT=50000`

---

## Resource Limits

| Container | CPU | RAM |
|-----------|-----|-----|
| n8n-main | 1.0 | 1G |
| n8n-worker | 0.75 | 768M |
| Redis | 0.50 | 384M |
| PostgreSQL | 1.00 | 1G |

---

## Node.js Runtime

- Node.js version: 20 (set in CI as `NODE_VERSION: "20"`)
- n8n runs inside the official n8n Docker image; Node.js version is managed by that image
- Worker entrypoint uses `tini` as PID 1: `exec tini -- /docker-entrypoint.sh worker`

---

## PostgreSQL

**Version:** 15-alpine
**Databases:**
- `n8n` — n8n execution data, workflow definitions, credentials, queue state
- `strapi` — Strapi CMS content (separate DB, same PostgreSQL instance)

**Tuning (production):**
- `shared_buffers=256MB`
- `effective_cache_size=768MB`
- `maintenance_work_mem=128MB`
- `checkpoint_completion_target=0.9`
- `wal_buffers=16MB`
- `random_page_cost=1.1`
- `effective_io_concurrency=200`
- `max_connections=100`
- `log_statement=ddl`
- `log_min_duration_statement=1000` (log slow queries > 1s)

**Migrations:** `project/db/migrations/` applied by `db-migrate` init container (postgres:15-alpine image, runs once at startup, tracked in `schema_migrations` table with filename + checksum)

---

## n8n Credentials (known IDs)

Credentials are stored encrypted in the n8n PostgreSQL database. The following are referenced in workflow JSON files:

| Credential Type | Placeholder ID in JSON | Notes |
|----------------|------------------------|-------|
| Redis | `REDIS_CREDENTIAL_ID` (static string in most files) | Should be real UUID from n8n DB; dynamic `$env.REDIS_CREDENTIAL_ID` in some files |
| Postgres | `POSTGRES_CREDENTIAL_ID` (static string) | Same issue — static placeholder |
| Redis (VPS actual) | `43SDqJYMGa6RvFqW` | Real credential ID on VPS |
| Postgres (VPS actual) | `1mZZJEscADgQ8InR` | Real credential ID on VPS |
| Strapi Token API (VPS actual) | `sT8kApXwN2mFqUvR` | Real credential ID on VPS |

**Credential type mappings:**
- `strapiApi` — uses email + password + url + apiVersion (content API user, NOT admin)
- `strapiTokenApi` — uses apiToken + url + apiVersion — use this for API tokens
- Strapi node v1 auth: `'password'` mode uses `strapiApi`; `'token'` mode uses `strapiTokenApi`

---

## Security Configuration

**Encryption:**
- `N8N_ENCRYPTION_KEY_FILE=/run/secrets/n8n_encryption_key` (main)
- Worker reads key via `project/scripts/n8n-worker-entrypoint.sh` (file → env var at startup)
- Key file: `project/secrets/n8n_encryption_key` (Docker secret, not in git)

**Cookie security:** `N8N_SECURE_COOKIE=true`

**Diagnostics/Telemetry disabled:**
- `N8N_DIAGNOSTICS_ENABLED=false`
- `N8N_PERSONALIZATION_ENABLED=false`

**Proxy hops:** `N8N_PROXY_HOPS=2` (Traefik + nginx in front)

**Webhook base URL:** `WEBHOOK_URL=https://{API_SUBDOMAIN}.{DOMAIN_NAME}/` — all webhook paths are relative to this

---

## LangChain / AI Nodes

**Version:** Bundled with n8n 2.9.4 as `@n8n/n8n-nodes-langchain`

**Used node types:**
- `@n8n/n8n-nodes-langchain.agent` — AI agent (W_ADMIN_AGENT, W_ADMIN_AI_AGENT)
- `@n8n/n8n-nodes-langchain.lmChatOllama` — Ollama chat model
- `@n8n/n8n-nodes-langchain.memoryBufferWindow` — in-memory conversation window

**NOT available in 2.9.4:**
- `@n8n/n8n-nodes-langchain.toolPostgres` — absent; use `toolHttpRequest` instead

---

## Key Environment Variables (n8n-specific)

| Variable | Default | Purpose |
|----------|---------|---------|
| `N8N_VERSION` | 2.9.4 | Image tag; must match in ci.yml and security-scan.yml |
| `EXECUTIONS_MODE` | queue | Must be `queue` for worker mode |
| `QUEUE_BULL_MAX_CONCURRENCY` | 2 | Worker job parallelism |
| `N8N_RUNNERS_ENABLED` | false | Supposed to disable task-runner; ineffective in 2.9.4 |
| `OUTBOX_MAX_ATTEMPTS` | 7 | Max retry attempts for outbound messages |
| `OUTBOX_BASE_DELAY_SEC` | 30 | Base delay for exponential backoff |
| `OUTBOX_MAX_DELAY_SEC` | 3600 | Max delay cap (1 hour) |
| `META_SIGNATURE_REQUIRED` | enforce | X-Hub-Signature-256 enforcement: off / warn / enforce |
| `MENU_CACHE_TTL_SEC` | 300 | Strapi config cache TTL in Redis |
| `FRAUD_FLOOD_LIMIT_30S` | 6 | Messages per 30s before quarantine |
| `TENANT_CONTEXT_SECRET` | (required) | HMAC key for cross-workflow tenant context sealing |
| `CORE_WORKFLOW_ID` | (empty) | Workflow ID for W4_CORE; used by adapters to call executeWorkflow |
| `SCHEMAS_ROOT` | /opt/resto/schemas | Mount point for inbound envelope JSON schemas |
| `LLM_API_URL` | http://ollama:11434/api/chat | Ollama endpoint |
| `LLM_MODEL` | llama3.1 | Default model for all LLM calls |
| `STRAPI_URL` | http://cms:1337 (implicit) | Strapi internal URL used by workflows |
| `STRAPI_API_TOKEN` | (required) | Strapi API token for config reads |

---

## CI/CD Version Consistency Requirement

`N8N_VERSION` must match in three places or CI fails:
1. `project/.env` — `N8N_VERSION=2.9.4`
2. `project/.github/workflows/ci.yml` — `N8N_VERSION: "2.9.4"`
3. `project/.github/workflows/security-scan.yml` — version reference

---

*Stack analysis: 2026-03-20*
