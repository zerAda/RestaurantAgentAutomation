---
name: secrets_data_protection
description: Prevent secret leakage, manage rotation, protect PII, enforce data retention.
when_to_use:
  - Adding integrations or API keys
  - Debugging auth issues
  - Preparing for audit
  - Reviewing data handling
  - Token rotation
---

# Secrets and Data Protection (RESTO BOT)

## Current secrets inventory

| Secret | File | Used by |
| --- | --- | --- |
| postgres_password | project/secrets/postgres_password | postgres, n8n-main, n8n-worker, cms, db-migrate |
| n8n_encryption_key | project/secrets/n8n_encryption_key | n8n-main, n8n-worker |
| redis_password | project/secrets/redis_password | redis (if configured) |
| strapi_db_password | project/secrets/strapi_db_password | cms (shares postgres_password) |
| traefik_usersfile | project/secrets/traefik_usersfile | traefik, console/admin BasicAuth |

## Env-based secrets (in .env, NOT in git)

- STRAPI_ADMIN_JWT_SECRET, STRAPI_JWT_SECRET, STRAPI_API_TOKEN_SALT
- STRAPI_TRANSFER_TOKEN_SALT, STRAPI_ENCRYPTION_KEY, STRAPI_APP_KEYS
- WEBHOOK_SHARED_TOKEN, META_APP_SECRET
- WA_API_TOKEN, IG_API_TOKEN, MSG_API_TOKEN
- COSIGN_PASSWORD, COSIGN_PRIVATE_KEY (CI/CD)
- LOG_MASK_PATTERNS=token,password,secret,api_key,authorization,x-api-token,x-webhook-token,bearer

## Rules

- No secrets in git (ever)
- No secrets in logs (LOG_MASK_PATTERNS enforced)
- No secrets in screenshots or patches
- Prefer secret files mounted into containers over env vars
- Redact Authorization, x-webhook-token, and any API keys in all outputs

## Rotation procedure

1. Generate new secret
2. Deploy dual-accept window (optional, for zero-downtime)
3. Cutover to new secret
4. Revoke old secret
5. Verify all services healthy

## PII protection

- Identify where phone numbers, names, addresses, order details are stored
- Ensure logs do not contain PII unnecessarily
- Define retention and deletion timeline
- Audit logging for admin actions, workflow changes, token rotations

## Key files

- `project/secrets/` (all secret files)
- `project/.env` (secret values marked with [SECRET] comments)
- `project/.github/workflows/` (COSIGN_*, GHCR_* secrets)
- `project/infra/gateway/nginx.conf` (token redaction in access logs)

## Required output

- ENV_REFERENCE updates with secret flags
- Redaction audit (where logging occurs)
- Secret scanning in CI (fail builds on leaks)
- PII inventory table (if audit-relevant)
