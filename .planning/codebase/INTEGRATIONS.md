# External Integrations

**Analysis Date:** 2026-03-18

## APIs & External Services

**Communication Channels:**
- **WhatsApp** - Multi-user bot via Meta Cloud API
  - Configuration: WHATSAPP_TOKEN in .env
  - Webhook route: POST /v1/inbound/whatsapp (Nginx gateway)
  - Signature validation: META_SIGNATURE_REQUIRED=enforce (production)
  - n8n workflows: 54 JSON files handling WhatsApp events

- **Instagram** - Messenger/Direct Messages
  - Configuration: META_APP_ID, META_APP_SECRET in .env
  - Webhook route: POST /v1/inbound/instagram
  - Uses Meta Business Platform

- **Messenger** - Facebook Messenger integration
  - Handled via Meta Business Platform
  - Endpoint: POST /v1/inbound/messenger

**Payment Processing:**
- **Chargily** - Algerian payment gateway
  - Configuration: CHARGILY_API_KEY (secret, Docker secrets)
  - Used in n8n workflows for payment collection
  - Webhook route: POST /v1/inbound/chargily

- **EDAHABIA** - Bank transfer/payment method
  - Referenced in workflow logic

- **Cash on Delivery (COD)** - Direct payment at delivery
  - Implemented in order workflows

**Voice & Speech:**
- **OpenAI API** - LLM for agent responses
  - Configuration: OPENAI_API_KEY (secret)
  - Used in: W_ADMIN_AGENT.json workflow
  - Alternative: Ollama local LLM when ai profile enabled

- **Elevenlabs** - Text-to-speech
  - Configuration: ELEVENLABS_API_KEY (secret)
  - Optional voice output for bot responses

- **Twilio** - SMS & Voice
  - Configuration: TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN (secrets)
  - Optional channel for order notifications

**AI/LLM:**
- **Ollama** - Local LLM runtime (self-hosted, optional ai profile)
  - Model: llama3.1 (4.9 GB)
  - Service: ollama container in docker-compose
  - Used via: n8n-nodes-base.ollamaChat
  - Health: http://ollama:11434/api/tags

- **OpenAI Whisper** - Speech-to-text (optional ai profile)
  - Service: whisper container (onerahmet/openai-whisper-asr-webservice:v1.2.0)
  - Endpoint: Speech audio processing

**Video & Media:**
- **TikTok Pixel** - Analytics tracking
  - Configuration: TIKTOK_PIXEL_ID in .env
  - Tracks user events (kiosk orders, funnel metrics)

**Other Services:**
- **Replicate** - AI model inference
  - Configuration: REPLICATE_API_TOKEN (secret)
  - Optional image/video generation

- **Supabase** - Backend-as-a-Service
  - Configuration: SUPABASE_URL, SUPABASE_ANON_KEY
  - Optional, not currently active

- **VAPI** - Voice agent API
  - Configuration: VAPI_TOKEN (secret)
  - For voice-first interactions

## Data Storage

**Databases:**
- **PostgreSQL 15-alpine** (Primary)
  - Connection: postgres:5432 (Docker internal)
  - Client: pg npm package (8.18.0)
  - Two databases:
    - n8n: workflows, executions, credentials, API keys
    - strapi: CMS content, users, roles, permissions
  - Connection pooling: PgBouncer middleware
  - Tuning: shared_buffers=256MB, max_connections=100, effective_cache_size=768MB

**Cache/Queue:**
- **Redis 7-alpine** (In-memory store)
  - Connection: redis:6379 (Docker internal)
  - Client: ioredis npm package (5.10.0)
  - Usage:
    - Bull job queue (n8n queue mode)
    - Session storage
    - API response cache
  - Config: Optional password auth (REDIS_PASSWORD in .env)
  - Persistence: AOF enabled

**File Storage:**
- **Local filesystem only** - No cloud storage
  - Strapi files: cms_data:/opt/resto/media
  - Nginx static: admin_data:, kiosk_data:
  - n8n files: n8n_data:/home/node/.n8n

## Authentication & Identity

**Auth Provider:**
- **Strapi Users-Permissions Plugin** - Custom user/role management
  - Login: POST /api/auth/local (email/password)
  - Creates JWT token
  - RBAC: Authenticated, Public roles
  - Permissions per role per content type

- **n8n Native** - Workflow execution
  - API keys stored in n8n database (user_api_keys table)
  - Pattern: Authorization: Bearer <n8n-api-key>

- **Basic Auth (Traefik)** - Admin UI protection
  - Endpoints: console.*, cms.*, admin.*
  - Credentials: traefik_usersfile (Docker secret)
  - IP allowlist: ADMIN_ALLOWED_IPS env var

- **Custom Header Token** - API gateway
  - Header: X-Api-Token
  - Rate limited per token in Nginx
  - Query string tokens: DISABLED by default

**No Third-Party Auth:**
- No OAuth2, SAML, or external identity providers
- All authentication self-hosted

## Monitoring & Observability

**Error Tracking:**
- Not configured - No Sentry, Rollbar, or external service
- Logging: Docker json-file driver
  - Max file: 10m per container
  - Max files: 3-5 rotation

**Logs:**
- Container stdout/stderr captured by Docker daemon
- Nginx JSON format: infra/gateway/nginx.conf
- n8n execution logs: PostgreSQL database
- Strapi logs: Node.js console (json-file rotates)
- Query logging: PostgreSQL DDL statements (log_statement=ddl)

**Health Checks:**
- All services: 30s intervals, 3 retries
- PostgreSQL: pg_isready -U n8n -d n8n
- Redis: redis-cli ping
- Strapi: GET /_health
- Nginx/Admin/Kiosk: HTTP wget to root

## CI/CD & Deployment

**Hosting:**
- Hostinger VPS (72.60.190.192)
- SSH user: deploy (key auth only)
- Path: /opt/resto/current/ (symlink to active release)
- Release strategy: Immutable in /opt/resto/releases/

**CI Pipeline:**
- GitHub Actions (13 workflows)
- Trigger: push to main, scheduled, or manual
- Stages: Lint → Security scan → Build → Push → Test
- Image repo: ghcr.io/resto-bot/* (SHA-pinned)

**CD Pipeline:**
- Validation → Preflight → Security gate → Staging → Smoke → Approval → Backup → Deploy → Smoke → DORA → Cleanup
- Rollback via release versioning

## Environment Configuration

**Required env vars:**
- Domain: DOMAIN_NAME, API_SUBDOMAIN, CONSOLE_SUBDOMAIN
- TLS: SSL_EMAIL (Let's Encrypt)
- n8n: N8N_VERSION, N8N_BASIC_AUTH_USER, N8N_BASIC_AUTH_PASSWORD, N8N_ENCRYPTION_KEY, WEBHOOK_URL
- Strapi: STRAPI_API_TOKEN, STRAPI_ADMIN_JWT_SECRET, STRAPI_APP_KEYS, STRAPI_JWT_SECRET, STRAPI_API_TOKEN_SALT
- Meta: META_APP_ID, META_APP_SECRET, META_SIGNATURE_REQUIRED=enforce
- External: OPENAI_API_KEY, CHARGILY_API_KEY, TWILIO_*, WHATSAPP_TOKEN, etc.

**Secrets location:**
- Docker secrets: /run/secrets/ (mounted at runtime)
  - postgres_password: Database auth
  - n8n_encryption_key: Workflow encryption
  - traefik_usersfile: BasicAuth credentials
- .env file (git-ignored)
- .env.production for production overrides

## Webhooks & Callbacks

**Incoming Webhooks (Public):**
- POST /v1/inbound/whatsapp: Meta WhatsApp events
- POST /v1/inbound/instagram: Meta Messenger/DMs
- POST /v1/inbound/messenger: Facebook Messenger
- POST /v1/inbound/chargily: Payment confirmations
- Rate limiting: 10 req/s per IP (Meta), 20 req/s (tokens)

**Outgoing Webhooks (n8n):**
- **Meta Cloud API**: Send messages (WhatsApp, Messenger, Instagram)
  - Endpoint: https://graph.instagram.com/*/messages
  - Auth: WHATSAPP_TOKEN in URL

- **Chargily**: Initiate payments
  - Endpoint: https://api.chargily.dz/invoices

- **Twilio**: SMS/Voice delivery
  - Auth: TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN

- **Ollama**: LLM inference
  - Endpoint: http://ollama:11434/api/chat (internal)

- **Strapi Content API**: Fetch/update content
  - Endpoint: http://cms:1337/api/* (internal)

**Retries & Reliability:**
- n8n outbox pattern: Exponential backoff, max 7 attempts
- Dead-letter queue: Workflow errors stored
- Idempotency: Inbound event deduplication

---

*Integration audit: 2026-03-18*
