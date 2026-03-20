# Technology Stack

**Analysis Date:** 2026-03-18

## Languages

**Primary:**
- TypeScript 5.x - Used in admin-dashboard, kiosk-app, inventory-cms, and workflow logic
- JavaScript (Node.js) - n8n workflows, runtime execution
- SQL - PostgreSQL database, migrations, bootstrap scripts

**Build Time:**
- Shell scripting - Database migrations, entrypoints, CI/CD workflows

## Runtime

**Environment:**
- Node.js 20-alpine (LTS) - All frontend and backend services
- Docker (containerized deployment) - 12 production services

**Package Manager:**
- npm 6.0.0+ - Lockfiles present for all packages
- Lockfile: `package-lock.json` (present and committed)

## Frameworks

**Core Services:**
- **n8n** 2.9.4 - Workflow automation engine (multi-channel bot orchestration)
  - Queue mode: n8n-main + n8n-worker + Bull/Redis for job distribution
  - 91 workflow JSON files defining business logic across WhatsApp, Instagram, Messenger
- **Strapi** 5.37.1 - Headless CMS (central configuration hub)
  - Users-Permissions plugin for role-based access control
  - Multi-database support (PostgreSQL primary)
  - Cloud plugin included (`@strapi/plugin-cloud`)
- **React** 19.2.0 - Frontend framework for admin-dashboard and kiosk-app
- **Vite** 6.0.0 - Frontend build tooling and dev server
- **React Router** 7.13.1 - Client-side routing (admin-dashboard, kiosk-app)

**Testing:**
- vitest 4.0.18 - Unit and integration tests
- @testing-library/react 16.3.2 - React component testing
- @testing-library/jest-dom 6.9.1 - DOM assertion helpers

**Build/Dev:**
- TypeScript compiler (tsc) - Type checking (tsconfig.json pattern)
- ESLint 9.39.1 - Linting JavaScript/TypeScript
- Tailwind CSS 4.1.18 - Utility-first CSS framework
- PostCSS 8.5.6 - CSS transformations

**Infrastructure:**
- Traefik 3.6.6 - Reverse proxy, TLS termination, routing (Let's Encrypt auto-certs)
- Nginx 1.27-alpine - Hardened API gateway and static file serving
- PostgreSQL 15-alpine - Primary database (two schemas: n8n, strapi)
- Redis 7-alpine - Message queue (Bull), session/cache storage, AOF persistence
- Ollama 0.6.2 - Local LLM runtime (optional ai profile)
- openai-whisper-asr 1.2.0 - Speech-to-text (optional ai profile)

## Key Dependencies

**Critical:**
- `@strapi/strapi` 5.37.1 - CMS engine, content APIs
- `ioredis` 5.10.0 - Redis client for Bull queue management
- `pg` 8.18.0 - PostgreSQL driver
- `zod` 4.3.6 - Schema validation (Strapi models)
- `react-router-dom` 7.13.1 - Routing for web UIs
- `framer-motion` 11.0.0 - Animation library (dashboard, kiosk)

**UI/UX:**
- `@tanstack/react-query` 5.22.2 - Async state management (admin-dashboard)
- `@tanstack/react-virtual` 3.13.20 - Virtual scrolling
- `recharts` 3.7.0 - Data visualization (dashboard metrics)
- `react-markdown` 10.1.0 - Markdown rendering (agent responses)
- `tailwind-merge` 2.2.0 - Tailwind class merging
- `lucide-react` 0.330.0 - Icon library
- `class-variance-authority` 0.7.0 - Variant pattern for components
- `clsx` 2.1.0 - Conditional CSS class names

**AI/LLM:**
- `@n8n/n8n-nodes-langchain` - LangChain integration for agent orchestration
- `ollama-chat` node - Local LLM integration (llama3.1 model: 4.9 GB)

**n8n Nodes (Workflow Integrations):**
- `n8n-nodes-base.postgres` - Direct PostgreSQL queries
- `n8n-nodes-base.code` - JavaScript/TypeScript code execution
- `n8n-nodes-base.httpRequest` - REST API calls
- `n8n-nodes-base.redis` - Redis pub/sub and operations
- `n8n-nodes-base.webhook` - Incoming webhook triggers
- `n8n-nodes-base.strapi` - Strapi content API integration
- `n8n-nodes-base.scheduleTrigger` - Cron-like scheduling
- `n8n-nodes-base.ollamaChat` - Local LLM calls

## Configuration

**Environment:**
- Environment file: `.env` with 580+ configuration variables
- Secrets managed via Docker secrets (not in git):
  - `postgres_password` - Strapi + n8n DB auth
  - `n8n_encryption_key` - Workflow encryption
  - `traefik_usersfile` - Basic auth credentials
- Configuration per deployment profile:
  - `docker-compose.hostinger.prod.yml` - Production on Hostinger VPS
  - `docker-compose.dev.yml` - Local development
  - `docker-compose.ghcr.yml` - GitHub Container Registry images
  - `docker-compose.base.yml` - Shared base service definitions

**Build:**
- Dockerfiles multi-stage builds for all frontend services:
  - `admin-dashboard/Dockerfile` - Node build → Nginx serving
  - `kiosk-app/Dockerfile` - Node build → Nginx serving
  - `inventory-cms/Dockerfile` - Strapi Node build
- Build-time environment variables passed via `docker-compose` build args
- TypeScript compilation in build stage (`tsc --noEmit && vite build`)

**Database Initialization:**
- `db/bootstrap.sql` - Schema bootstrap (88KB, applied on first run)
- `db/migrations/` - Idempotent PostgreSQL migrations
- `db/init/` - Init scripts (db creation, migration runner)
- Two separate databases on same PostgreSQL instance:
  - `n8n` - n8n workflows, executions, credentials
  - `strapi` - CMS content, users, roles, permissions

## Platform Requirements

**Development:**
- Node.js 20.x
- npm 6.0.0+
- Docker + Docker Compose 2.0+
- PostgreSQL 15+ (can run in container)
- Redis 7+ (can run in container)
- 8GB+ RAM recommended

**Production:**
- Deployment target: Hostinger VPS (72.60.190.192)
- 12 container services in orchestrated deployment
- TLS termination via Traefik (Let's Encrypt)
- Rate limiting at Nginx gateway layer
- Health checks for all services (30s intervals)
- Resource limits enforced per service (CPU, memory)

## Version Matrix

| Component | Version | Source |
|-----------|---------|--------|
| RESTO BOT | 3.4.0 | `project/VERSION` |
| n8n | 2.9.4 | `.env N8N_VERSION` |
| Strapi | 5.37.1 | `inventory-cms/package.json` |
| PostgreSQL | 15-alpine | Docker image |
| Redis | 7-alpine | Docker image |
| Traefik | v3.6.6 | Docker Compose |
| Nginx | 1.27-alpine | Docker Compose |
| Node.js | 20-alpine | Frontend Dockerfiles |
| TypeScript | ~5.9.3 | package.json engines |
| React | 19.2.0 | Admin dashboard, kiosk-app |
| Vite | 6.0.0 | Frontend build tool |
| Ollama | 0.6.2 | Optional ai profile |
| Whisper | 1.2.0 | Optional ai profile |

## Dependencies Note

Production dependency lock: Both Strapi and frontend projects use `--legacy-peer-deps` during npm installation to accommodate React 18/19 ecosystem peer dependencies. This is documented in Dockerfiles and development docs.

---

*Stack analysis: 2026-03-18*
