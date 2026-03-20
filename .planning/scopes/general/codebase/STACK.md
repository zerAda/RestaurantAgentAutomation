# Technology Stack

**Analysis Date:** 2026-03-20

## Languages

**Primary:**
- JavaScript/TypeScript — n8n workflow code, Strapi CMS source (`project/inventory-cms/src/`), admin dashboard (`project/admin-dashboard/src/`), kiosk app (`project/kiosk-app/src/`), CI scripts
- Python 3.11 — CI test scripts: `scripts/validate_contracts.py`, `scripts/test_darja_intents.py`, `scripts/test_template_render.py`, `scripts/test_l10n_script_detection.py`, `scripts/patch_workflows.py`
- Bash — Ops scripts, CI shell steps, preflight, smoke, backup/restore scripts (`scripts/*.sh`)
- SQL — DB schema (`db/bootstrap.sql`), migrations (`db/migrations/*.sql`), seed files

**Secondary:**
- HCL-equivalent — Docker Compose YAML (infrastructure-as-code)

## Runtime

**Environment:**
- Node.js 20 (set in CI `NODE_VERSION: "20"` in `.github/workflows/ci.yml`; n8n 2.9.4 bundles its own Node internally)
- Python 3.11 (CI test runner)

**Package Manager:**
- npm (admin-dashboard, kiosk-app, inventory-cms)
- pip (CI scripts; requirements: `scripts/requirements-ci.txt`)
- Lockfiles: `package-lock.json` present per sub-project

## Frameworks

**Core:**
- n8n 2.9.4 — workflow automation engine (queue mode: main + worker + Redis Bull)
  - Source image: `docker.n8n.io/n8nio/n8n:${N8N_VERSION}`
  - 91 workflow JSON files in `project/workflows/`
- Strapi 5 (5.37.1 on VPS) — headless CMS, central config hub
  - Source: `project/inventory-cms/` (custom Docker build)
- React/Vite — admin dashboard (`project/admin-dashboard/`) and kiosk app (`project/kiosk-app/`)

**Infrastructure:**
- Traefik v3.6.6 — TLS termination, Let's Encrypt ACME, middleware chains, service discovery via Docker labels
- nginx 1.27-alpine — API gateway, reverse proxy, rate limiting, security hardening
- PostgreSQL 15-alpine — primary data store (two databases: `n8n`, `strapi`)
- Redis 7-alpine — Bull queue broker for n8n execution queue
- Docker Compose — container orchestration (`project/docker-compose.hostinger.prod.yml`)

**AI (optional `ai` profile):**
- Ollama 0.6.2 — local LLM inference (`ollama/ollama:0.6.2`); llama3.1 model (4.9 GB)
- Whisper ASR v1.2.0 — speech-to-text (`onerahmet/openai-whisper-asr-webservice:v1.2.0`)

**Testing:**
- pytest + Python unittest — CI integration tests
- Gitleaks v8.24.3 — secret detection
- Trivy — container and dependency vulnerability scanning
- Anchore SBOM action — CycloneDX SBOM generation per image

**Build:**
- Docker Buildx — multi-stage image builds with GitHub Actions cache
- Cosign (Sigstore) — image signing (`sigstore/cosign-installer v3.7.0`)
- SLSA Provenance — L2 attestations (`actions/attest-build-provenance v2.2.3`)

## Key Dependencies

**Critical Infrastructure:**
- `docker.n8n.io/n8nio/n8n:2.9.4` — workflow engine; pinned version, no SHA in compose (pinned in CI)
- `postgres:15-alpine` — database; tuned via command flags in compose
- `redis:7-alpine` — queue broker; AOF persistence enabled
- `traefik:v3.6.6` — ingress; pinned version
- `nginx:1.27-alpine` — gateway; pinned version
- `ollama/ollama:0.6.2` — LLM; pinned version (ai profile only)
- `onerahmet/openai-whisper-asr-webservice:v1.2.0` — STT; pinned version (ai profile only)

**Custom Images (GHCR):**
- `ghcr.io/{owner}/resto-bot-cms:latest` and `:${{ github.sha }}` — Strapi CMS build
- `ghcr.io/{owner}/resto-bot-admin:latest` and `:${{ github.sha }}` — Admin dashboard build
- `ghcr.io/{owner}/resto-bot-kiosk:latest` and `:${{ github.sha }}` — Kiosk app build

**Python CI Dependencies (`scripts/requirements-ci.txt`):**
- jsonschema — contract validation
- pyyaml — YAML parsing
- safety, pip-audit — dependency vulnerability scanning

## Configuration

**Environment:**
- All runtime config via `project/.env` (580+ variables; gitignored)
- Template: `project/config/.env.example`
- VPS shared env: `/opt/resto/shared/.env` (managed separately)
- Key required variables: `DOMAIN_NAME`, `SSL_EMAIL`, `CONSOLE_SUBDOMAIN`, `API_SUBDOMAIN`, `ADMIN_ALLOWED_IPS`, `TRAEFIK_TRUSTED_IPS`, `N8N_VERSION`, `META_APP_SECRET`, `WEBHOOK_SHARED_TOKEN`, all Strapi JWT secrets

**Build-time (baked into Docker images):**
- `VITE_DOMAIN` — kiosk and admin dashboard
- `VITE_STRAPI_URL` — kiosk uses `https://api.<domain>/v1/strapi`; admin uses `https://cms.<domain>`

**Secrets (file-based, not in .env):**
- `project/secrets/postgres_password` — PostgreSQL password
- `project/secrets/n8n_encryption_key` — n8n credential encryption
- `project/secrets/traefik_usersfile` — BasicAuth users (htpasswd format)
- `project/secrets/strapi_db_password` — Strapi DB password
- `project/secrets/` directory is gitignored; not committed

**Build Config:**
- `project/docker-compose.hostinger.prod.yml` — 12-service production stack
- `project/docker/docker-compose.yml` — local dev stack
- `project/docker/docker-compose.test.yml` — CI test harness
- `project/.github/workflows/` — 13 GitHub Actions CI/CD workflows
- `project/.github/actions/` — 4 composite actions

## Platform Requirements

**Development:**
- Docker + Docker Compose v2
- Node.js 20
- Python 3.11
- Bash (for ops scripts)

**Production:**
- Hostinger VPS: 72.60.190.192 (2 vCPU, ~4 GB RAM implied by resource limits)
- OS: Linux (deploy user with docker group membership)
- 119 GB disk (fills up; disk pressure is a documented concern — see CONCERNS.md)
- SSH key auth only (`deploy` user, no password)
- External Docker networks pre-created: `proxy`, `internal`
- External Docker volumes pre-created: `postgres_data`, `n8n_data`, `redis_data`, `traefik_data`, `cms_uploads`, `ollama_data`
- Project path: `/opt/resto/current/` (symlink managed by CD pipeline)
- Releases stored in: `/opt/resto/releases/`
- Backups stored in: `/opt/resto/backups/`

## Version Matrix

| Component | Version | Source |
|-----------|---------|--------|
| RESTO BOT | 3.4.0 | `project/VERSION` |
| n8n | 2.9.4 | `N8N_VERSION` env var |
| PostgreSQL | 15-alpine | compose image pin |
| Redis | 7-alpine | compose image pin |
| Traefik | v3.6.6 | compose image pin |
| Nginx | 1.27-alpine | compose image pin |
| Ollama | 0.6.2 | compose image pin (ai profile) |
| Whisper ASR | v1.2.0 | compose image pin (ai profile) |
| Node.js (CI) | 20 | ci.yml `NODE_VERSION` |
| Python (CI) | 3.11 | ci.yml `PYTHON_VERSION` |

---

*Stack analysis: 2026-03-20*
