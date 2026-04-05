---
type: index
updated_at: 2026-04-04T18:00:00+02:00
---

# Index by Docker Service

| Service | Image | Port | Repo Path | Config |
|---------|-------|------|-----------|--------|
| traefik | traefik:3.6.6 | :443, :8080 | `docker-compose.hostinger.prod.yml` | Traefik labels |
| gateway | nginx:1.27-alpine | :8080 | `infra/gateway/nginx.conf` | 8 routing zones |
| n8n-main | n8n:2.9.4 | :5678 | `workflows/`, compose | Queue mode main |
| n8n-worker | n8n:2.9.4 | — | `workflows/`, compose | Queue mode worker |
| postgres | postgres:15-alpine | :5432 | `db/`, compose | shared_buffers, max_connections |
| pgbouncer | edoburu/pgbouncer | :6432 | compose | Transaction mode, pool 50 |
| redis | redis:7-alpine | :6379 | `infra/redis/entrypoint.sh` | 256MB, allkeys-lru |
| cms | strapi 5.37.1 | :1337 | `inventory-cms/` | 40+ content types |
| admin-dashboard | react 19 | :3000 | `admin-dashboard/` | Vite, TailwindCSS |
| kiosk-app | react 19 | :4000 | `kiosk-app/` | Vite, TailwindCSS |
| ollama | ollama:0.6.2 | :11434 | compose | llama3.1 |
| whisper | openai/whisper | :9000 | compose | STT API |

---

> Updated by `/project:mapcodebase` and `/project:docker-doctor`.
