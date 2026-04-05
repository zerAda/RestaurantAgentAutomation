---
type: index
updated_at: 2026-04-04T18:00:00+02:00
---

# Repo Map — RESTO BOT v3.5.0

## Functional Surfaces

| Surface | Path | Key Files | Risk Level |
|---------|------|-----------|------------|
| Admin Dashboard | `admin-dashboard/` | `src/App.tsx` (lazy), `src/pages/` | Low |
| Kiosk App | `kiosk-app/` | `src/services/menuService.ts`, `src/components/` | Low |
| Strapi CMS | `inventory-cms/` | `src/api/` (40+ types), `config/logger.ts` | Medium |
| n8n Workflows | `workflows/` | 100+ W*.json files | High |
| Database | `db/` | `bootstrap.sql`, `migrations/` (16 files) | High |
| Nginx Gateway | `infra/gateway/` | `nginx.conf` (8 zones) | Medium |
| Docker Infra | `docker-compose*.yml` | 5 compose files, 12 services | Medium |
| CI/CD | `.github/workflows/` | 13 workflow files | Medium |
| Scripts | `scripts/` | 20+ automation scripts | Low |
| Documentation | `docs/` | 60+ .md files | Low |
| Planning | `.planning/` | ROADMAP.md, REQUIREMENTS.md, STATE.md | Low |

## Trust Boundaries

1. **Public**: `api.<domain>/v1/inbound/*` (rate limited, signature verified)
2. **Gateway**: Nginx blocks `/v1/admin`, `/v1/internal`, query tokens
3. **Internal**: Docker `internal` network (postgres, redis, n8n, cms)
4. **Admin**: BasicAuth + IP allowlist (Traefik)

## High-Risk Areas

- `workflows/` — 100+ files, zero automated tests, complex coupling
- `db/bootstrap.sql` — single-file schema, no automated backup
- `infra/gateway/nginx.conf` — 8 rate-limit zones, manual testing only
- VPS disk: 119GB, ENOSPC risk during builds

---

> Maintained by `/project:mapcodebase`. Run periodically to refresh.
