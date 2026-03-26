# Environment Variable Reference — Resto Bot Platform

> **Last updated:** 2026-03-26
> **Maintainer:** Platform Engineering

---

## Redis Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_PASSWORD` | *(empty — no auth)* | Redis authentication password. Set in `.env` to enable `requirepass`. Leave empty for backward-compatible no-auth mode. |
| `REDIS_CREDENTIAL_ID` | *(n8n credential)* | n8n credential ID for Redis connections. Referenced by all workflow nodes via `$env.REDIS_CREDENTIAL_ID`. |

### Redis Runtime Configuration (set in `infra/redis/entrypoint.sh`)

| Setting | Value | Source |
|---------|-------|--------|
| `appendonly` | `yes` | `infra/redis/entrypoint.sh` line 7 |
| `maxmemory` | `256mb` | `infra/redis/entrypoint.sh` line 7 |
| `maxmemory-policy` | `allkeys-lru` | `infra/redis/entrypoint.sh` line 7 |

> **⚠️ Important:** Redis CLI args in `entrypoint.sh` take precedence over any `redis.conf` file. Do NOT add a `redis.conf` that conflicts with the entrypoint settings.

### Redis Memory Monitoring

| Metric | Threshold | Action |
|--------|-----------|--------|
| `used_memory` | > 200 MB | CRITICAL alert via `W_REDIS_MONITOR` workflow |
| Redis unreachable | Connection refused | CRITICAL alert + structured log |
| Health check interval | 15 minutes | `W_REDIS_MONITOR` scheduled trigger |

**Verify current config:**
```bash
docker exec current-redis-1 redis-cli CONFIG GET maxmemory-policy
# Expected: allkeys-lru

docker exec current-redis-1 redis-cli INFO memory | grep -E 'used_memory_human|maxmemory_human'
```

---

## PostgreSQL Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_USER` | `n8n` | PostgreSQL superuser name |
| `POSTGRES_PASSWORD` | *(from .env)* | PostgreSQL password — **never commit** |
| `POSTGRES_DB` | `n8n` | Primary database name |
| `PGPASSWORD` | *(from .env)* | Used by `psql` CLI tools and migration scripts |
| `STRAPI_DATABASE_NAME` | `strapi` | Strapi CMS database (separate from n8n) |
| `DATABASE_URL` | *(constructed)* | Full connection string: `postgres://$POSTGRES_USER:$PGPASSWORD@postgres:5432/$POSTGRES_DB` |

### Database Indexes (Performance)

| Index Name | Table | Columns | Purpose |
|------------|-------|---------|---------|
| `idx_orders_status_created` | `orders` | `(status, created_at DESC)` | Kitchen display, admin order list |
| `idx_orders_user_status` | `orders` | `(user_id, status)` | Customer order history |
| `idx_orders_restaurant_created` | `orders` | `(restaurant_id, created_at DESC)` | Per-restaurant filtering |
| `idx_orders_active` | `orders` | `(created_at DESC) WHERE status IN (...)` | Active order queries (partial) |
| `idx_orders_restaurant_status` | `orders` | `(restaurant_id, status)` | Phase 1 migration |
| `idx_orders_created` | `orders` | `(created_at)` | Phase 1 migration |

---

## n8n Workflow Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `N8N_VERSION` | `2.9.4` | n8n container version |
| `WEBHOOK_SHARED_TOKEN` | *(from .env)* | Shared secret for webhook authentication |
| `META_APP_SECRET` | *(from .env)* | Meta (Facebook/Instagram) app secret for signature verification |
| `WA_SEND_URL` | *(from .env)* | WhatsApp Cloud API send endpoint |
| `WA_API_TOKEN` | *(from .env)* | WhatsApp API bearer token |
| `IG_SEND_URL` | *(from .env)* | Instagram Send API endpoint |
| `IG_API_TOKEN` | *(from .env)* | Instagram API bearer token |
| `MSG_SEND_URL` | *(from .env)* | Messenger Send API endpoint |
| `MSG_API_TOKEN` | *(from .env)* | Messenger API bearer token |
| `ALERT_WEBHOOK_URL` | *(from .env)* | Webhook URL for critical alerts (Slack, Discord, etc.) |

### n8n Credential References (used in workflows via `$env`)

| Environment Variable | Used By | Description |
|---------------------|---------|-------------|
| `REDIS_CREDENTIAL_ID` | All Redis-connected workflows | n8n Redis credential ID |
| `POSTGRES_CREDENTIAL_ID` | DB query workflows | n8n PostgreSQL credential ID |
| `STRAPI_API_CREDENTIAL_ID` | Admin Agent, CMS queries | n8n Strapi API token credential |

---

## Strapi CMS Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `STRAPI_ADMIN_JWT_SECRET` | *(from .env)* | Admin panel JWT signing secret (32+ chars) |
| `STRAPI_JWT_SECRET` | *(from .env)* | API JWT signing secret (32+ chars) |
| `STRAPI_API_TOKEN_SALT` | *(from .env)* | Salt for API token generation |
| `STRAPI_TRANSFER_TOKEN_SALT` | *(from .env)* | Salt for transfer token generation |
| `STRAPI_ENCRYPTION_KEY` | *(from .env)* | Encryption key for sensitive fields |
| `STRAPI_APP_KEYS` | *(from .env)* | Comma-separated app keys (session signing) |

---

## Frontend Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_STRAPI_URL` | `https://cms.$DOMAIN` | Strapi CMS URL for API calls |
| `VITE_DOMAIN` | *(from .env)* | Base domain name |
| `VITE_N8N_WEBHOOK_URL` | *(from .env)* | n8n webhook base URL |

### Frontend Caching

| Cache | TTL | Storage | Notes |
|-------|-----|---------|-------|
| Menu products (Kiosk) | 5 minutes | `localStorage` | `menuService.ts` — key pattern: `menu_cache_{category}` |
| Kiosk feed | Uses menuService | `localStorage` | PERF-09: VerticalVideoFeed now uses cached menuService |

---

## Infrastructure

| Variable | Default | Description |
|----------|---------|-------------|
| `DOMAIN_NAME` | *(from .env)* | Primary domain name |
| `CONSOLE_SUBDOMAIN` | `console` | n8n admin subdomain |
| `API_SUBDOMAIN` | `api` | API gateway subdomain |
| `SSL_EMAIL` | *(from .env)* | Let's Encrypt certificate email |
| `TZ` | `UTC` | Container timezone |
| `TRAEFIK_TRUSTED_IPS` | *(from .env)* | Trusted proxy IPs for Traefik |
| `ADMIN_ALLOWED_IPS` | *(from .env)* | IP allowlist for admin panel |

---

## Docker Images

| Variable | Default | Description |
|----------|---------|-------------|
| `CMS_IMAGE` | `ghcr.io/zerada/resto-bot-cms:latest` | Strapi CMS image |
| `ADMIN_IMAGE` | `ghcr.io/zerada/resto-bot-admin:latest` | Admin dashboard image |
| `KIOSK_IMAGE` | `ghcr.io/zerada/resto-bot-kiosk:latest` | Kiosk frontend image |
