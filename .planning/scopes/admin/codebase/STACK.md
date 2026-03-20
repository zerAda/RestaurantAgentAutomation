# Admin Dashboard — Technology Stack

**Analysis Date:** 2026-03-20
**Scope:** `project/admin-dashboard/`

---

## Languages

**Primary:**
- TypeScript 5.9 (`~5.9.3`) — all source files in `src/`
- TSX — React components

**Config / Markup:**
- HTML — `index.html` (Vite entry point)
- CSS — `src/index.css` (Tailwind v4 directives + custom CSS variables)

---

## Runtime

**Environment:**
- Build: Node.js 20-alpine (Docker build stage: `FROM node:20-alpine AS build`)
- Serve: `nginxinc/nginx-unprivileged:1.27-alpine` (static file server, no Node at runtime)

**Package Manager:**
- npm (`package-lock.json` present)
- Install command: `npm ci --legacy-peer-deps` (required due to peer dep conflicts)

---

## Frameworks

**Core UI:**
- React 19.2.0 — component model, hooks, Strict Mode
- React DOM 19.2.0 — browser renderer
- React Router DOM 7.13.1 — client-side routing (`BrowserRouter`, `Routes`, `Route`, `useNavigate`, `useLocation`)

**Styling:**
- Tailwind CSS 4.1.18 — utility-first CSS (v4 uses `@tailwindcss/postcss`, no `tailwind.config.js`)
- `tailwind-merge` 2.2.0 — safe class merging in `cn()` helper
- `class-variance-authority` 0.7.0 — variant-based class generation (used in `src/components/ui/`)
- `clsx` 2.1.0 — conditional class names

**Data Fetching / State:**
- `@tanstack/react-query` 5.22.2 — server state management (used only for orders hooks)
- `@tanstack/react-virtual` 3.13.20 — virtualised lists (imported, usage extent unknown)

**Charts:**
- Recharts 3.7.0 — `AreaChart`, `BarChart`, `PieChart` used in dashboard and analytics views

**Animation:**
- Framer Motion 11.0.0 — modal transitions in `AutomationView`, page transitions
- CSS animations — `animate-pulse`, `animate-bounce`, `animate-float` via Tailwind custom utilities

**Icons:**
- Lucide React 0.330.0 — all icons throughout the application

**Markdown:**
- `react-markdown` 10.1.0 — renders AI agent replies in `AIChatBubble`
- `remark-gfm` 4.0.1 — GitHub-Flavored Markdown support (tables, strikethrough)

---

## Build Tooling

**Bundler:** Vite 6.0.0
- Config: `vite.config.ts`
- Path alias: `@` → `./src` (used as `@/components/...`, `@/services/...`)
- No manual chunk splitting configured — single bundle output
- React plugin: `@vitejs/plugin-react` 5.1.1 (Babel-based)

**TypeScript Compilation:**
- `tsc --noEmit` runs before `vite build` (type-check only, no emit)
- Config: `tsconfig.json` (not read in this analysis — assumed strict mode)

**CSS Processing:**
- PostCSS 8.5.6 with `@tailwindcss/postcss` 4.1.18
- Autoprefixer 10.4.24

**Linting:**
- ESLint 9.39.1 — flat config (`eslint.config.js`)
- `typescript-eslint` 8.46.4
- `eslint-plugin-react-hooks` 7.0.1
- `eslint-plugin-react-refresh` 0.4.24

**Testing:**
- Vitest 4.0.18 — test runner (configured in `vite.config.ts`, `environment: 'jsdom'`)
- `@testing-library/react` 16.3.2
- `@testing-library/jest-dom` 6.9.1
- jsdom 28.1.0

---

## Key Dependencies

**Critical (runtime):**

| Package | Version | Purpose |
|---------|---------|---------|
| `react` | 19.2.0 | UI framework |
| `react-router-dom` | 7.13.1 | Client-side routing |
| `@tanstack/react-query` | 5.22.2 | Orders data hooks, cache invalidation |
| `recharts` | 3.7.0 | Revenue area chart, analytics bar/pie charts |
| `framer-motion` | 11.0.0 | AutomationView modal animation |
| `react-markdown` | 10.1.0 | AI chat reply rendering |
| `lucide-react` | 0.330.0 | All icons |

**Infrastructure (build/dev):**

| Package | Version | Purpose |
|---------|---------|---------|
| `vite` | 6.0.0 | Dev server + production bundler |
| `typescript` | ~5.9.3 | Type checking |
| `tailwindcss` | 4.1.18 | Utility CSS (v4) |
| `vitest` | 4.0.18 | Unit test runner |

---

## Configuration

**Environment Variables (build-time, baked into bundle):**

| Variable | Required | Example Value | Purpose |
|----------|----------|---------------|---------|
| `VITE_STRAPI_URL` | Yes | `https://cms.srv1258231.hstgr.cloud` | Base URL for all Strapi API calls |
| `VITE_DOMAIN` | Yes | `srv1258231.hstgr.cloud` | Domain for URL construction fallback |
| `VITE_N8N_WEBHOOK_BASE` | Optional | `https://api.srv1258231.hstgr.cloud/v1` | n8n webhook base (used in AutomationView) |
| `VITE_API_GATEWAY_URL` | Optional | `https://api.srv1258231.hstgr.cloud` | Gateway URL reference |
| `VITE_STRAPI_API_TOKEN` | Optional | — | Documented in `.env.example` but not used in source |
| `VITE_RESTAURANT_ID` | Optional | — | Documented in `.env.example` but not used in source |

Documented in: `project/admin-dashboard/.env.example`

**Important:** `VITE_STRAPI_URL` is baked in at Docker build time as a build ARG. The compose file passes `https://cms.${DOMAIN_NAME}` — this points to the CMS directly, NOT through the gateway. The SPA therefore cannot reach CMS from a browser without IP allowlist exception or gateway proxy.

**Build Config:**
- `project/admin-dashboard/vite.config.ts` — Vite config
- `project/admin-dashboard/eslint.config.js` — ESLint flat config
- No `tailwind.config.js` (Tailwind v4 is configured via CSS directives in `src/index.css`)

---

## Docker Image

**Build process (`project/admin-dashboard/Dockerfile`):**
```
Stage 1: node:20-alpine AS build
  - WORKDIR /app
  - ARG VITE_STRAPI_URL, VITE_DOMAIN (baked into bundle at build time)
  - COPY package.json + package-lock.json → npm ci --legacy-peer-deps
  - COPY source → npm run build (tsc + vite build)

Stage 2: nginxinc/nginx-unprivileged:1.27-alpine
  - COPY infra/nginx/spa-default.conf → /etc/nginx/conf.d/default.conf
  - COPY dist/ → /usr/share/nginx/html
  - Runs as nginx user (non-root)
  - EXPOSE 80
```

**Build context:** `.` (project root), not `admin-dashboard/` — required because Dockerfile also copies `infra/nginx/spa-default.conf`.

**Nginx SPA config:** `project/infra/nginx/spa-default.conf` — serves `index.html` for all 404s (SPA fallback routing).

**Compose service:**
- Service name: `admin-dashboard`
- CPU limit: 0.25 cores, memory limit: 128MB
- Exposed on port 80 (internal Docker network only)
- Traefik label: `Host(admin.${DOMAIN_NAME})`, entrypoint `websecure`
- Networks: `proxy` only (no `internal` network access)

---

## Platform Requirements

**Development:**
- Node.js 20+
- npm (with `--legacy-peer-deps` flag required)
- Strapi CMS running and reachable for API calls

**Production:**
- Docker with BuildKit
- `VITE_STRAPI_URL` and `VITE_DOMAIN` build args must be set
- nginx-unprivileged:1.27-alpine compatible host
- Traefik v3 for TLS termination and routing

---

*Stack analysis: 2026-03-20*
