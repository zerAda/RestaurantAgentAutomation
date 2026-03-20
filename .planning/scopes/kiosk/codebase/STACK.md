# Kiosk App — Technology Stack

**Analysis Date:** 2026-03-20
**Scope:** `project/kiosk-app/`

---

## Languages

**Primary:**
- TypeScript 5.9.x — all source files under `src/`

**Templates / Markup:**
- TSX (React JSX in TypeScript) — all components and pages
- CSS via Tailwind 4 utility classes + custom `@layer` blocks in `src/index.css`

---

## Runtime

**Environment:**
- Browser (SPA) — no Node.js at runtime
- Target: full-screen tablet/touchscreen kiosk (`select-none`, `touch-none`, `overflow-hidden` on body)

**Served By:**
- `nginxinc/nginx-unprivileged:1.27-alpine` — serves pre-built `/dist` as static files
- SPA fallback: `try_files $uri $uri/ /index.html` (all routes return `index.html`)
- Static asset cache: `expires 30d; Cache-Control: public, immutable` for CSS/JS/fonts

---

## Package Manager

- npm
- Lockfile: `project/kiosk-app/package-lock.json` — present
- Install flags: `npm ci --legacy-peer-deps` (required — peer dependency conflicts exist
  between React 19 and testing-library versions)

---

## Frameworks

**Core:**
- React 19.2.x — UI rendering
- react-router-dom 7.13.x — client-side routing (`BrowserRouter`, `Routes`, `Route`,
  `useNavigate`, `useParams`)
- Vite 6.x — build tool and dev server

**Styling:**
- Tailwind CSS 4.1.x — utility classes, configured via `@import "tailwindcss"` in
  `src/index.css` (Tailwind 4 CSS-first config, not JS-first)
- Custom `@theme` block in `src/index.css` defines design tokens:
  - `--color-brand-primary`: `oklch(0.65 0.24 350)` — #FF3366 (primary pink/red)
  - `--color-brand-accent`: `oklch(0.75 0.15 250)`
  - `--color-success`: `oklch(0.72 0.16 154)`
  - `--color-warning`: `oklch(0.84 0.18 77)`
  - `--color-error`: `oklch(0.62 0.22 28)`
- Custom component classes defined in `@layer components`:
  `.quantum-card`, `.quantum-glass`, `.btn-quantum`, `.btn-quantum-outline`,
  `.cinematic-mesh`, `.grain-overlay`, `.scrim-top`, `.scrim-bottom`
- Font: `Outfit` (primary weight 100–900) + `Inter` (fallback) — loaded from Google Fonts
  CDN via `<link>` preconnect in `index.html`

**Animation:**
- framer-motion 11.x — `motion.div`, `AnimatePresence` for slide transitions, modal
  entrances, cart item add/remove animations, cart-fly sprites

**Icons:**
- lucide-react 0.330.x — all UI icons

**Utility:**
- clsx 2.1.x — conditional class name construction
- tailwind-merge 2.2.x — safe Tailwind class merging (used via `cn()` in `src/lib/utils.ts`)

**Testing:**
- vitest 4.x — test runner (configured in `vite.config.ts` with `environment: 'jsdom'`,
  `globals: true`)
- jsdom 28.x — browser DOM environment for tests
- `@testing-library/react` 16.x — present in devDependencies but not yet used
- `@testing-library/jest-dom` 6.x — present in devDependencies but not yet used

---

## Build Tooling

**Vite Configuration:** `project/kiosk-app/vite.config.ts`
```typescript
plugins: [react()]
resolve.alias: { "@": path.resolve(__dirname, "./src") }
test: { environment: 'jsdom', globals: true }
```

**Build command:** `tsc --noEmit && vite build`
- TypeScript check runs first (strict, will fail on type errors)
- Then Vite bundles with Rollup

**Tailwind Configuration:** `project/kiosk-app/tailwind.config.js`
- Content: `./index.html`, `./src/**/*.{js,ts,jsx,tsx}`
- No custom theme extensions (all design tokens live in `@theme` in CSS)

**PostCSS:** `project/kiosk-app/postcss.config.js` — present (required by Tailwind 4)

**ESLint:** `project/kiosk-app/eslint.config.js` (flat config format)
- `@eslint/js` recommended
- `typescript-eslint` recommended
- `eslint-plugin-react-hooks` flat recommended
- `eslint-plugin-react-refresh` vite preset

---

## Docker Image

**Build Stage:** `node:20-alpine`
- `WORKDIR /app`
- Copies `kiosk-app/package.json` + `package-lock.json`, runs `npm ci --legacy-peer-deps`
- Copies full `kiosk-app/` source, runs `npm run build` (`tsc --noEmit && vite build`)
- Build ARGs baked into bundle at build time:
  - `VITE_STRAPI_URL` — set to `https://api.${DOMAIN_NAME}/v1/strapi` in compose
  - `VITE_DOMAIN` — set to `${DOMAIN_NAME}` in compose

**Serve Stage:** `nginxinc/nginx-unprivileged:1.27-alpine`
- Copies `project/infra/nginx/spa-default.conf` → `/etc/nginx/conf.d/default.conf`
- Copies `/app/dist` → `/usr/share/nginx/html`
- Ownership fix: `chown -R nginx:nginx` on html dir, cache dir, and nginx.pid
- Runs as `nginx` user (non-root)
- Exposes port 80

**Dockerfile location:** `project/kiosk-app/Dockerfile`
**Build context:** repository root (`.`) — required because Dockerfile copies from `infra/nginx/`

---

## Docker Compose Service

**Service name:** `kiosk-app`
**Defined in:** `project/docker-compose.hostinger.prod.yml` lines 268–319
**Image tag in CI:** `ghcr.io/zerada/resto-bot-kiosk`
**Resource limits:** 0.25 CPU, 128MB RAM
**Network:** `proxy` only (no `internal` network — kiosk does not talk to postgres or redis directly)
**Restart policy:** `unless-stopped`
**Healthcheck:** `wget -qO- http://127.0.0.1:80/` every 30s, 3 retries, 15s start period
**Security:** `cap_drop: [ALL]`, `no-new-privileges: true`, `tmpfs` on `/tmp /var/cache/nginx /run`

**Traefik labels applied:**
- Router: `kiosk.${DOMAIN_NAME}`, entrypoint `websecure`, TLS via Let's Encrypt (`mytlschallenge`)
- Middleware chain: `kiosk-ratelimit` (30 avg / 60 burst) + `kiosk-headers`
- Security headers: `browserXSSFilter`, `contentTypeNosniff`, `frameDeny`, `forceSTSHeader`
  (1 year, includeSubdomains, preload), `referrerPolicy: strict-origin-when-cross-origin`

**Nginx security headers (inside container):** `project/infra/nginx/spa-default.conf`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: SAMEORIGIN`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()`
- `Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https:; font-src 'self'; connect-src 'self' https:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'`

---

## Key Dependencies

| Package | Version | Purpose |
|---|---|---|
| `react` | ^19.2.0 | UI framework |
| `react-dom` | ^19.2.0 | DOM renderer |
| `react-router-dom` | ^7.13.1 | Client-side routing |
| `framer-motion` | ^11.0.0 | Animation library |
| `lucide-react` | ^0.330.0 | Icon set |
| `clsx` | ^2.1.0 | Conditional classnames |
| `tailwind-merge` | ^2.2.0 | Safe Tailwind class merging |
| `tailwindcss` | ^4.1.18 | Utility CSS (devDep) |
| `typescript` | ~5.9.3 | Type checking |
| `vite` | ^6.0.0 | Build tool + dev server |
| `@vitejs/plugin-react` | ^5.1.1 | React Fast Refresh + JSX |
| `vitest` | ^4.0.18 | Test runner |
| `@testing-library/react` | ^16.3.2 | Component testing (installed, unused) |

---

## Configuration

**Environment Variables (baked at build time via Docker ARG):**

| Variable | Declared in Dockerfile | Default if missing | Used In |
|---|---|---|---|
| `VITE_STRAPI_URL` | Yes (`ARG` + `ENV`) | `''` | `strapiClient.ts`, `VerticalVideoFeed.tsx`, `menuService.ts` |
| `VITE_DOMAIN` | Yes (`ARG` + `ENV`) | `''` | `VerticalVideoFeed.tsx` fallback URL construction |
| `VITE_N8N_URL` | **No** (not in Dockerfile) | `'https://n8n.srv1258231.hstgr.cloud'` | `strapiClient.ts` `.n8n()`, `tracking.ts` |
| `VITE_KIOSK_SECRET` | **No** (not in Dockerfile) | `''` (empty string) | `strapiClient.ts` `.n8n()` `x-kiosk-secret` header |
| `VITE_RESTAURANT_ID` | **No** (not in Dockerfile) | `'default'` | `CheckoutView.tsx` order payload `restaurant_id` |

**Important:** `VITE_N8N_URL`, `VITE_KIOSK_SECRET`, and `VITE_RESTAURANT_ID` are
referenced in source code but are NOT declared as build ARGs in the Dockerfile or set in
`docker-compose.hostinger.prod.yml`. They silently fall back to hardcoded defaults at
build time.

**Example file:** `project/kiosk-app/.env.example` — present

---

## Platform Requirements

**Development:**
- Node.js 20
- `npm ci --legacy-peer-deps` (peer dep conflicts require this flag)
- `vite.config.ts` `@` alias must be configured for local builds (it is)

**Production:**
- Docker multi-stage build
- `VITE_STRAPI_URL` and `VITE_DOMAIN` must be set as Docker build ARGs
- Image pushed to GHCR: `ghcr.io/zerada/resto-bot-kiosk`
- Traefik on `proxy` network handles TLS termination

---

*Stack analysis: 2026-03-20*
