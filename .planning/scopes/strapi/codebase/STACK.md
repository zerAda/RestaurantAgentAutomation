# Strapi CMS Technology Stack

**Analysis Date:** 2026-03-20

## Languages

**Primary:**
- TypeScript 5.x — All source files in `src/`, `config/`, `types/`

**Config:**
- JSON — Content type schemas (`schema.json` in each `content-types/` directory)

## Runtime

**Environment:**
- Node.js 20.20.0 (pinned in `FROM node:20.20.0-alpine` in `project/inventory-cms/Dockerfile`)
- Engines constraint in `package.json`: `"node": ">=20.0.0 <=24.x.x"`
- Alpine Linux base image

**Package Manager:**
- npm (lockfile: `package-lock.json`, present)
- Install command: `npm ci --legacy-peer-deps --omit=dev` in production stage

## Frameworks

**Core:**
- `@strapi/strapi` 5.37.1 — headless CMS framework
- `@strapi/plugin-users-permissions` 5.37.1 — roles, JWT auth, user management
- `@strapi/plugin-cloud` 5.37.1 — Strapi Cloud plugin (present but not actively used; platform is self-hosted)

**Frontend (Admin Panel):**
- React 18 — Admin panel UI
- `react-router-dom` 6 — Admin panel routing
- `styled-components` 6 — Admin panel styling
- Custom plugin: `src/plugins/json-form/` — JSON form editor widget in admin UI

**Build/Dev:**
- `strapi build` — Compiles TS + bundles admin panel (`dist/` output)
- `strapi develop` — Dev server with hot-reload
- `strapi start` — Production server (reads from `dist/`)

## Key Dependencies

**Critical:**
- `@strapi/strapi` 5.37.1 — Core framework. All content type APIs, routing, auth, middleware pipeline
- `pg` ^8.18.0 — PostgreSQL client (Knex under the hood in Strapi 5)
- `ioredis` ^5.10.0 — Redis client. Used directly in three places: realtime service (SSE pub/sub), system-config agent-chat controller (RAG cache, rate limit), auth-ratelimit middleware
- `zod` ^4.3.6 — Validation library (imported but usage scope limited to custom code)

**Infrastructure:**
- `react` ^18.0.0 + `react-dom` + `react-router-dom` ^6 — Required for Strapi 5 admin panel compilation

**DevDependencies:**
- `typescript` ^5
- `@types/node` ^20
- `@types/react` ^18
- `@types/react-dom` ^18

## Configuration

**Environment:**
- All secrets injected at runtime via environment variables or Docker secrets
- `docker-entrypoint.sh` reads `DATABASE_PASSWORD` and `STRAPI_SUPER_ADMIN_PASSWORD` from Docker secret files (if `_FILE` path vars are set)
- Build-time placeholders used for env vars that Strapi reads during `npm run build` (see `ENV` lines in Dockerfile — no real values)

**Required env vars at runtime:**
- `APP_KEYS` — Strapi session encryption keys (array)
- `ADMIN_JWT_SECRET` — Admin panel JWT signing secret
- `JWT_SECRET` — Users-Permissions plugin JWT signing secret
- `API_TOKEN_SALT` — API token hashing salt
- `TRANSFER_TOKEN_SALT` — Data transfer token salt
- `ENCRYPTION_KEY` — Field-level encryption key
- `DATABASE_CLIENT` — `postgres` in production
- `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USERNAME`
- `DATABASE_PASSWORD` or `DATABASE_PASSWORD_FILE` — Password or Docker secret path
- `REDIS_HOST`, `REDIS_PORT` — For ioredis connections in agent-chat and realtime service
- `N8N_WEBHOOK_BASE` or `N8N_WEBHOOK_BASE_URL` — n8n internal URL for agent chat forwarding
- `CORS_ORIGINS` — Comma-separated allowed origins (kiosk and admin subdomains)
- `VPS_HOSTNAME` — Used in CORS defaults fallback
- `STRAPI_SUPER_ADMIN_EMAIL` — Super admin account email (provisioned at bootstrap)
- `STRAPI_SUPER_ADMIN_PASSWORD` — Super admin password (file path or value)
- `N8N_INTERNAL_IPS` — Comma-separated IPs exempt from rate limiting

**Optional env vars:**
- `N8N_WEBHOOK_AUTH` — Basic auth credentials for n8n webhook calls (agent-chat)
- `PORT` — Override listen port (default 1337)
- `HOST` — Override listen host (default 0.0.0.0)
- `PROXY` — Enable proxy headers trust (default true)

**Build:**
- `tsconfig.json`: `target: ES2022`, `module: ESNext`, `moduleResolution: Bundler`, `strict: true`, `noImplicitAny: true`
- `outDir: dist`, `rootDir: .`
- `src/admin/` and `src/plugins/` excluded from server compilation (separate admin panel build)

## Plugins In Use

| Plugin | Version | Purpose |
|---|---|---|
| `@strapi/plugin-users-permissions` | 5.37.1 | User auth (JWT), roles (Public/Authenticated), social auth base |
| `@strapi/plugin-cloud` | 5.37.1 | Present but not used (self-hosted deployment) |
| `src/plugins/json-form/` | custom | JSON form widget for admin UI |

**Not used (not installed):**
- `@strapi/plugin-i18n` — No internationalization plugin; multilang handled via `description_multilang` JSON fields
- `@strapi/plugin-upload` — No media upload plugin configured beyond defaults
- `strapi-plugin-redis` — Not installed; direct ioredis used instead

## Docker Build

**Multi-stage:**
1. `build` stage (`node:20.20.0-alpine`): installs all deps including devDeps, runs `npm run build`
2. Production stage (`node:20.20.0-alpine`): installs prod deps only (`--omit=dev`), copies `dist/` from build stage
3. Non-root user: `strapi` (UID 1001, GID 1001) — created in production stage
4. Build tooling (`python3 make g++`) installed for native module compilation (`pg`) then removed
5. `vips-dev` kept in production stage (required by `sharp` for image processing)

**Image naming (CI/CD):**
- GHCR path: `ghcr.io/{owner}/resto-bot-cms:{sha}`
- Signed with Cosign at build time (`sigstore/cosign-installer@v3.7.0`)
- SBOM generated with CycloneDX format and attested

## Platform Requirements

**Development:**
- Node 20+, npm 6+
- SQLite supported for local dev (set `DATABASE_CLIENT=sqlite`)
- PostgreSQL 15 for full feature testing

**Production:**
- Docker (multi-stage build, Alpine)
- PostgreSQL 15 (separate `strapi` database on shared postgres container)
- Redis 7 (shared with n8n queue; used for CMS pub/sub and rate limit)
- 2+ CPU cores recommended (npm ci takes 15-30 min on 2 CPU VPS; first Strapi bootstrap ~8 min)
- ~500MB Docker image size

---

*Stack analysis: 2026-03-20*
