# ⚠️ SECRETS ROTATION REQUIRED

All secrets in `.env.production` were previously committed to git history.
**ALL of these must be rotated on production immediately.**

## Secrets to Rotate

| Secret | Where | Priority |
|--------|-------|----------|
| `N8N_ENCRYPTION_KEY` | n8n env | P0 |
| `APP_SECRET` (Strapi) | Strapi env | P0 |
| `ADMIN_JWT_SECRET` | Strapi env | P0 |
| `API_TOKEN_SALT` | Strapi env | P0 |
| `JWT_SECRET` | Strapi env | P0 |
| `TRANSFER_TOKEN_SALT` | Strapi env | P0 |
| `DATABASE_PASSWORD` | Postgres | P0 |
| `META_APP_SECRET` | Meta Dev Portal | P0 |
| `WA_API_TOKEN` | Meta Business Manager | P0 |
| `WA_VERIFY_TOKEN` | Meta Webhook Config | P0 |
| `OPENAI_API_KEY` | OpenAI Dashboard | P1 |
| `REDIS_PASSWORD` | Redis config | P1 |
| `N8N_BASIC_AUTH_PASSWORD` | n8n env | P1 |
| `STRAPI_API_TOKEN_INTERNAL` | Strapi admin (internal API token for W0_MODULE_GUARD) | P1 |

> **`STRAPI_API_TOKEN_INTERNAL`** is read by `W0_MODULE_GUARD` to call Strapi
> (`product-modules` + `tenant-entitlements`). If unset the guard fails closed and
> denies every inbound message + operator action (total lockout). `docker compose up`
> (prod) hard-fails via `${STRAPI_API_TOKEN_INTERNAL:?…}` and `scripts/preflight.sh`
> exits non-zero with a clear message when it is missing.

## How to Rotate

1. Generate new secrets: `openssl rand -hex 32` for each
2. Update in your deployment environment (VPS, Docker secrets, etc.)
3. **Do NOT commit new secrets to the repo**
4. Use environment variables or Docker secrets mount

## After Rotation

- Verify all services start correctly
- Test WhatsApp webhook delivery
- Test admin dashboard login
- Test n8n → Strapi API communication
