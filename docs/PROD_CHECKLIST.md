# PROD_CHECKLIST (v3.3.0)

> Updated 2026-02-27 from CI/CD infrastructure audit.
> Previous version: v3.0. All original items retained and expanded.

---

## 1. Environment Variables (.env) - CRITICAL

These settings **must** be changed from their dev defaults before production deployment.

### 1.1 Meta / WhatsApp Integration

| Variable | Dev Default | Production Requirement |
| -------- | ----------- | ---------------------- |
| `META_SIGNATURE_REQUIRED` | `off` | Set to `warn` initially, then `enforce` after validation |
| `META_APP_SECRET` | *(empty)* | Copy from Meta Developer Portal > App Settings > App Secret |
| `META_VERIFY_TOKEN` | `REPLACE_ME_META_VERIFY_TOKEN` | Generate a strong random string (`openssl rand -hex 32`) |

### 1.2 Network / Access Control

| Variable | Dev Default | Production Requirement |
| -------- | ----------- | ---------------------- |
| `ADMIN_ALLOWED_IPS` | `127.0.0.1/32` | Add your actual admin IPs (comma-separated CIDR blocks) |
| `TRAEFIK_TRUSTED_IPS` | `127.0.0.1/32` | Add your reverse proxy / CDN IPs for X-Forwarded-For trust |
| `WEBHOOK_URL` | `http://localhost:5678` | Set to `https://api.${DOMAIN_NAME}/` |

### 1.3 Tenant / Restaurant IDs

| Variable | Dev Default | Production Requirement |
| -------- | ----------- | ---------------------- |
| `DEFAULT_TENANT_ID` | *(empty)* | UUID of your primary tenant from `tenants` table |
| `DEFAULT_RESTAURANT_ID` | *(empty)* | UUID of your primary restaurant from `restaurants` table |

### 1.4 Workflow IDs

| Variable | Dev Default | Production Requirement |
| -------- | ----------- | ---------------------- |
| `CORE_WORKFLOW_ID` | *(empty)* | n8n workflow ID for W4_CORE after import |
| `ADMIN_WA_CONSOLE_WORKFLOW_ID` | *(empty)* | n8n workflow ID for W14_ADMIN_WA_SUPPORT_CONSOLE |
| `REDIS_HELPER_WORKFLOW_ID` | *(empty)* | n8n workflow ID for W_REDIS_HELPER |

To populate workflow IDs after importing workflows into n8n:

```bash
# List all workflows and their IDs
curl -s -H "Authorization: Bearer $N8N_API_KEY" \
  http://localhost:5678/api/v1/workflows | jq '.data[] | {id, name}'
```

### 1.5 Secrets (use Docker secrets, not .env)

| Variable | Dev Default | Production Requirement |
| -------- | ----------- | ---------------------- |
| `N8N_BASIC_AUTH_PASSWORD` | `dev_local_password_not_for_prod_32c` | Generate strong password, store in Docker secret |
| `N8N_ENCRYPTION_KEY` | `dev_local_encryption_key_32_chars_minimum_abcdef123456` | Generate with `openssl rand -hex 32`, store in Docker secret |
| `POSTGRES_PASSWORD` | *(dev placeholder)* | Generate strong password, store in `secrets/postgres_password` |

Production compose already reads from Docker secrets files:

- `secrets/postgres_password`
- `secrets/n8n_encryption_key`
- `secrets/traefik_usersfile`

---

## 2. Pre-deploy Checklist

### 2.1 DNS

- [ ] `api.${DOMAIN_NAME}` resolves to VPS IP
- [ ] `console.${DOMAIN_NAME}` resolves to VPS IP
- [ ] `admin.${DOMAIN_NAME}` resolves to VPS IP
- [ ] `cms.${DOMAIN_NAME}` resolves to VPS IP
- [ ] `kiosk.${DOMAIN_NAME}` resolves to VPS IP

### 2.2 Secrets Files

- [ ] `secrets/postgres_password` exists (file, not directory) with strong password
- [ ] `secrets/n8n_encryption_key` exists with 32+ char key
- [ ] `secrets/traefik_usersfile` exists with htpasswd entry
- [ ] `secrets/redis_password` exists (file, not directory) with password
- [ ] `secrets/strapi_db_password` exists (file, not directory) with password
- [ ] All secret files have mode `644` (n8n runs as `node` UID, needs read access)

### 2.3 .env Configuration

- [ ] All Section 1 variables above set to production values
- [ ] `DOMAIN_NAME` set to actual domain
- [ ] `SSL_EMAIL` set to valid email for Let's Encrypt
- [ ] `N8N_VERSION=1.80.0` (matches CI/CD pipeline)
- [ ] `ALLOWED_AUDIO_DOMAINS` is non-empty (required for STT)

### 2.4 Compose Validation

```bash
docker compose -f docker-compose.hostinger.prod.yml config --quiet
# Must exit 0 with no errors
```

---

## 3. Deploy Verification

### 3.1 Service Health

- [ ] `docker compose ps` shows all 10 services UP
- [ ] `curl https://api.${DOMAIN_NAME}/healthz` returns 200
- [ ] `curl -k https://console.${DOMAIN_NAME}/` returns 401 (BasicAuth)
- [ ] `curl -k https://admin.${DOMAIN_NAME}/` returns 401 (BasicAuth)
- [ ] `curl https://cms.${DOMAIN_NAME}/` returns 302 (Strapi)
- [ ] `curl https://kiosk.${DOMAIN_NAME}/` returns 200
- [ ] Console accessible only from allowlisted IPs

### 3.2 Internal Health

- [ ] PostgreSQL: `pg_isready -U n8n` accepting connections
- [ ] Redis: `redis-cli ping` returns PONG
- [ ] n8n: `/healthz` returns `{"status":"ok"}`
- [ ] n8n-worker: running and connected to Redis queue

### 3.3 Webhook Verification

- [ ] Meta webhook verification: GET `/v1/inbound/whatsapp?hub.mode=subscribe&hub.verify_token=<token>&hub.challenge=test` returns `test`
- [ ] Inbound WhatsApp: POST `/v1/inbound/whatsapp` with valid signature returns 200
- [ ] Inbound Instagram: POST `/v1/inbound/instagram` returns 200
- [ ] Inbound Messenger: POST `/v1/inbound/messenger` returns 200

---

## 4. Post-deploy Operations

### 4.1 Backup

- [ ] Daily PostgreSQL backup via `./scripts/backup_postgres.sh` (cron)
- [ ] Restore drill validated via `./scripts/restore_postgres.sh`
- [ ] Backup covers both `n8n` and `strapi` databases

### 4.2 Monitoring

- [ ] `outbound_messages` PENDING/RETRY/SENT/DLQ monitored
- [ ] Traefik dashboard accessible at `localhost:8080` (SSH tunnel only)
- [ ] Log rotation configured on all containers
- [ ] Disk usage monitored (alert at 80%)

### 4.3 Security

- [ ] `api_clients` table has at least 1 token per tenant
- [ ] `WEBHOOK_SHARED_TOKEN` removed or kept only as temporary fallback
- [ ] `META_SIGNATURE_REQUIRED` set to `enforce` after initial validation
- [ ] Gitleaks scan clean (no secrets in repo)
- [ ] `.env` is in `.gitignore` and not tracked

---

## 5. Version Alignment

Ensure these versions match across all environments:

| Component | Expected | Check Location |
| --------- | -------- | -------------- |
| n8n | 1.80.0 | `.env:N8N_VERSION`, `ci.yml:44`, `security-scan.yml:110` |
| PostgreSQL | 15-alpine | `docker-compose.hostinger.prod.yml`, `ci.yml` matrix |
| Redis | 7-alpine | `docker-compose.hostinger.prod.yml` |
| Traefik | v3.6.6 | `docker-compose.hostinger.prod.yml` |
| Nginx | 1.27-alpine | Gateway Dockerfile |
| VERSION file | 3.3.0 | `project/VERSION` |
