# Technology Stack

**Analysis Date:** 2026-03-14

## Languages

**Primary:**
- TypeScript 5.x - Backend (Strapi CMS), frontend (admin-dashboard, kiosk-app)
- Node.js 20+ - Runtime for all backend services, CLI tools
- JavaScript (ES2020+) - n8n workflow expressions, browser runtime

**Secondary:**
- SQL - PostgreSQL migrations and queries (90 workflow files, db/migrations/)
- Bash - Docker entrypoints, deployment scripts (scripts/)
- YAML - GitHub Actions CI/CD (13 workflows), Docker Compose, configuration

## Runtime

**Environment:**
- Node.js: >=20.0.0 <=24.x.x (specified in `inventory-cms/package.json` engines field)
- Platform: Linux (Docker Alpine base), Windows 10 Pro (development)

**Package Manager:**
- npm 6.0.0+ (specified in `inventory-cms/package.json`)
- Lockfile: `package-lock.json` present in all subdirectories

## Frameworks

**Core:**
- **Strapi 5.37.1** - CMS backend (`inventory-cms/package.json`), central configuration hub
  - Location: `inventory-cms/`
  - Plugins: @strapi/plugin-cloud, @strapi/plugin-users-permissions
  - Database: PostgreSQL 15 (strapi database)
  - Exports: REST API at `/api/` endpoints

- **n8n 2.9.4** - Workflow orchestration and automation (`docker-compose.hostinger.prod.yml`)
  - Location: Container image `docker.n8n.io/n8nio/n8n:2.9.4`
  - Mode: Queue-based (Bull + Redis) with worker scaling
  - 90 workflow JSON files in `workflows/`

- **React 19.2.0** - Frontend framework
  - Used in: `admin-dashboard/package.json`, `kiosk-app/package.json`
  - React DOM: 19.2.0

- **React Router 7.13.1** - Client-side routing
  - admin-dashboard: 7.13.1
  - kiosk-app: 7.13.1

**Testing:**
- Vitest 4.0.18 - Unit test runner (admin-dashboard, kiosk-app)
- @testing-library/react 16.3.2 - React component testing
- @testing-library/jest-dom 6.9.1 - DOM matchers
- jest.config or vitest.config in frontend apps

**Build/Dev:**
- **Vite 6.0.0** - Frontend build tool (admin-dashboard, kiosk-app)
- TypeScript Compiler (tsc) - Type checking (admin-dashboard, kiosk-app build scripts)
- ESLint 9.39.1 - Code linting (admin-dashboard, kiosk-app: eslint.config.js)
- PostCSS 8.5.6 - CSS processing
- TailwindCSS 4.1.18 - Utility CSS framework (admin-dashboard, kiosk-app)

## Key Dependencies

**Critical:**
- **pg 8.18.0** - PostgreSQL client (inventory-cms)
- **ioredis 5.10.0** - Redis client (inventory-cms, n8n uses Bull Redis)
- **react 19.2.0** - Core UI framework (both web frontends)
- **@tanstack/react-query 5.22.2** - Data fetching + caching (admin-dashboard)
- **react-router-dom 7.13.1** - Navigation (both frontends)

**UI/UX:**
- **TailwindCSS 4.1.18** - Styling utility framework
- **Framer Motion 11.0.0** - Animations (admin-dashboard, kiosk-app)
- **Lucide React 0.330.0** - Icon library
- **Recharts 3.7.0** - Charts/graphs (admin-dashboard analytics)
- **React Markdown 10.1.0** - Markdown rendering (admin-dashboard)

**Form/Validation:**
- **zod 4.3.6** - Schema validation (inventory-cms)
- **class-variance-authority 0.7.0** - Component variants (admin-dashboard)

**Styling:**
- **styled-components 6.0.0** - CSS-in-JS (inventory-cms admin panel)
- **clsx 2.1.0** - Conditional CSS class merging
- **tailwind-merge 2.2.0** - Smart Tailwind class resolution

**Infrastructure:**
- **Bull** (via Redis) - Job queue for n8n workers (internal, not in package.json)
- **PostgreSQL 15-alpine** - Primary database (docker-compose.hostinger.prod.yml)
- **Redis 7-alpine** - Cache + job queue (docker-compose.hostinger.prod.yml)
- **Traefik v3.6.6** - Reverse proxy, TLS termination (docker-compose.hostinger.prod.yml)
- **nginx 1.27-alpine** - API gateway (docker-compose.hostinger.prod.yml)
- **Ollama 0.6.2** - LLM service for AI features (profile: ai)
- **Whisper** (onerahmet/openai-whisper-asr-webservice:v1.2.0) - STT service (profile: ai)

## Configuration

**Environment:**
- `.env` file (not tracked): 580+ configuration variables
- `.env.example`: Template with required/optional vars
- Secrets mounted via Docker secrets: `postgres_password`, `n8n_encryption_key`, `strapi_admin_password`, `traefik_usersfile`
- Environment variables injected at container start

**Build:**
- `docker-compose.hostinger.prod.yml` - Production compose (12 services)
- `docker-compose.base.yml` - Base service definitions
- `docker-compose.dev.yml` - Development profile with mock-api
- `docker-compose.ghcr.yml` - GHCR registry variant
- Dockerfile locations:
  - `admin-dashboard/Dockerfile` - React + Vite build
  - `inventory-cms/Dockerfile` - Strapi production build
  - `kiosk-app/Dockerfile` - React + Vite build
  - `mock-api/Dockerfile` - Test endpoint server

## Platform Requirements

**Development:**
- Node.js 20+
- Docker + Docker Compose 2.x+
- Git with LFS support
- Bash shell (scripts/)

**Production:**
- Linux VPS (Hostinger: 72.60.190.192)
- Docker + Docker Compose
- 12 containers with resource limits:
  - Traefik: 0.5 CPU, 256MB RAM
  - n8n-main: 1.0 CPU, 1GB RAM
  - n8n-worker: 0.75 CPU, 768MB RAM
  - PostgreSQL: 1.0 CPU, 1GB RAM
  - Redis: 0.5 CPU, 384MB RAM
  - nginx gateway: 0.25 CPU, 128MB RAM
  - admin-dashboard: 0.25 CPU, 128MB RAM
  - kiosk-app: 0.25 CPU, 128MB RAM
  - Strapi CMS: 0.5 CPU, 512MB RAM
  - Ollama: 1.5 CPU, 3GB RAM (optional ai profile)
  - Whisper: included in ai profile

**Storage:**
- PostgreSQL two databases: `n8n` (main), `strapi` (CMS)
- Redis 256MB max memory (AOF persistence)
- External Docker volumes: `postgres_data`, `redis_data`, `n8n_data`, `cms_uploads`, `ollama_data`, `traefik_data`
- ~119GB VPS disk (fills fast - disk full breaks everything)

**Deployment:**
- GitHub Actions for CI/CD (13 workflows)
- Images tagged with git SHA (supply-chain security)
- Cosign for Docker image signing

---

*Stack analysis: 2026-03-14*
