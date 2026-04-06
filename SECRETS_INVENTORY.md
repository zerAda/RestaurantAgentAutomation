# 🔐 Resto Bot: Exhaustive Secrets Inventory

This inventory lists all tokens and keys required to achieve "Diamond-Grade" performance and operational stability. Use this checklist to verify your GitHub Actions Secrets and VPS `.env` configuration.

## 🚀 WhatsApp & Meta (Omnichannel Logic)
Required for n8n workflows (W21, W50, W_WA_ROUTER) to communicate with customers.

- [ ] `WA_API_TOKEN`: Permanent System User Token from Meta Business Suite.
- [ ] `WA_PHONE_NUMBER_ID`: Unique ID for the WhatsApp Business number.
- [ ] `WA_BUSINESS_ACCOUNT_ID`: ID for the associated WABA.
- [ ] `META_APP_SECRET`: For HMAC-SHA256 request signing/validation (Security Hardening).
- [ ] `META_VERIFY_TOKEN`: Random string for webhook verification.

## 🛠️ Strapi CMS (Authentication & Security)
Required for secure API access and data integrity.

- [ ] `STRAPI_ADMIN_JWT_SECRET`: Secret for signing admin dashboard tokens.
- [ ] `STRAPI_API_TOKEN_SALT`: Salt for generating API tokens.
- [ ] `STRAPI_TRANSFER_TOKEN_SALT`: Salt for data transfer operations.
- [ ] `STRAPI_DATABASE_CA`: (Optional) If using managed SSL database.
- [ ] `JWT_SECRET`: General application JWT secret.

## 🤖 n8n Automation (Platform Core)
Required for workflow execution and inter-service communication.

- [ ] `N8N_ENCRYPTION_KEY`: **CRITICAL**. Must be identical to the one used during setup to decrypt existing credentials.
- [ ] `N8N_USER_MANAGEMENT_JWT_SECRET`: For secure user sessions.
- [ ] `OLLAMA_API_BASE`: URL for the LLM engine (e.g., `http://ollama:11434`).
- [ ] `HIVE_MIND_SHARED_SECRET`: For cross-service HMAC auth (W_HIVE_MIND_DISPATCH).

## 📦 CI/CD & DevOps (GitHub Actions)
Required for the "All-Green" pipeline and automatic VPS deployment.

- [ ] `VPS_SSH_KEY`: Private SSH key for `deploy@72.60.190.192`.
- [ ] `DOCKER_USERNAME` / `CR_PAT`: GitHub Container Registry (GHCR) access token.
- [ ] `ALERT_WEBHOOK_URL`: Discord/Slack/Telegram webhook for status alerts (W_REDIS_MONITOR).
- [ ] `POSTGRES_PASSWORD`: For database migrations and integration tests.

## ⚡ Infrastructure & Performance
Required for the Phase 6 performance tuning.

- [ ] `REDIS_PASSWORD`: (If configured) for cache security.
- [ ] `MAX_ORDERS_PER_MINUTE`: (Optional) Throttling limit for surge protection.
- [ ] `CACHE_TTL_MENUS`: Default 300 (5 minutes) for Kiosk performance.

---

### How to set these:
1. **GitHub Secrets**: Repository Settings > Secrets and variables > Actions.
2. **VPS Production**: `/opt/resto/current/.env` (or project root).
