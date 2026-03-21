# Kiosk App — Codebase Structure

**Analysis Date:** 2026-03-20
**Scope:** `project/kiosk-app/`

---

## Directory Layout

```
project/kiosk-app/
├── src/
│   ├── main.tsx                   # React root mount + outer ErrorBoundary
│   ├── App.tsx                    # App shell: router, CartProvider, IdleTimer, backdrop
│   ├── App.css                    # Empty / unused (all styles in index.css)
│   ├── index.css                  # Global styles: Tailwind import, @theme tokens, component classes
│   ├── assets/
│   │   └── react.svg              # Default Vite placeholder asset (not used in production)
│   ├── components/
│   │   ├── VerticalVideoFeed.tsx  # Home screen: product slides, add-to-cart, language selector
│   │   ├── Cart.tsx               # Cart drawer overlay + order submission + receipt
│   │   ├── CustomizerModal.tsx    # Size / extras / sauces / quantity modal
│   │   ├── ErrorBoundary.tsx      # Class-based error boundary + 10s auto-reload
│   │   ├── LanguageSelector.tsx   # Language picker modal (fr / ar / en)
│   │   ├── MenuGrid.tsx           # 2-col product grid (not currently routed — dead code)
│   │   └── AppSwitcher.tsx        # Dev utility: platform URL switcher (dead code, not rendered)
│   ├── context/
│   │   └── CartContext.tsx        # Global cart state + order submission (CartProvider, useCart)
│   ├── pages/
│   │   ├── CheckoutView.tsx       # Multi-step checkout page (/checkout route)
│   │   └── FortuneWheelView.tsx   # Gamification reward wheel (/wheel route)
│   ├── services/
│   │   ├── strapiClient.ts        # HTTP client: strapi.get / post / put / n8n
│   │   ├── menuService.ts         # Product fetch + LocalStorage cache + stock check
│   │   └── configService.ts       # system-config fetch + LocalStorage cache + fallback defaults
│   ├── utils/
│   │   ├── i18n.ts                # Translation dictionary (8 keys, 3 langs) + setPageDirection
│   │   ├── SoundManager.ts        # Web Audio API synthesized sounds (swipe / select / ambient)
│   │   └── tracking.ts            # Fire-and-forget analytics POST to n8n webhook
│   ├── lib/
│   │   └── utils.ts               # cn() = clsx + tailwind-merge
│   └── setup.test.ts              # Placeholder test (single truthiness assertion — no real coverage)
├── dist/                          # Vite build output (COMMITTED — should be gitignored)
│   ├── index.html
│   ├── vite.svg
│   └── assets/
│       ├── index-B9kjNePO.js      # Full bundled JS
│       └── index-Z3FW72MA.css     # Full bundled CSS
├── Dockerfile                     # Multi-stage: node:20-alpine build + nginx-unprivileged serve
├── index.html                     # Vite HTML entry (Google Fonts preconnect, #root div)
├── vite.config.ts                 # Vite + Vitest config (@ alias, jsdom environment)
├── tailwind.config.js             # Tailwind 4 content paths
├── postcss.config.js              # PostCSS (required by Tailwind 4)
├── eslint.config.js               # ESLint flat config (TS + React Hooks + React Refresh)
├── package.json                   # Dependencies and scripts
├── package-lock.json              # npm lockfile
├── tsconfig.json                  # TypeScript root config
├── tsconfig.app.json              # App-specific TS config (src/ files)
├── tsconfig.node.json             # Node TS config (vite.config.ts)
├── .env.example                   # Environment variable template
├── .gitignore                     # Git ignore rules
└── build_error.txt                # Captured Windows build error output (should NOT be committed)
```

**Infrastructure files referenced by Dockerfile (outside `kiosk-app/`):**
- `project/infra/nginx/spa-default.conf` — nginx server block for SPA (copied into image at build time)

---

## Directory Purposes

**`src/components/`:**
- Purpose: Reusable UI components — both full-screen overlays and embedded sub-views
- All components are default or named exports from single `.tsx` files
- No component sub-directories — flat structure
- Key files: `VerticalVideoFeed.tsx` (home screen), `Cart.tsx` (checkout overlay), `CustomizerModal.tsx`

**`src/context/`:**
- Purpose: React Context providers for global state
- Only one context exists: `CartContext.tsx`
- Exports: `CartProvider` (wrap app), `useCart` (hook), `CartItem` type

**`src/pages/`:**
- Purpose: Route-level page components rendered directly by `<Route>` in `App.tsx`
- Each page manages its own local step state and async operations

**`src/services/`:**
- Purpose: All external API communication — HTTP calls to Strapi CMS and n8n
- No React imports — pure TypeScript modules
- `strapiClient.ts` is the base HTTP layer; `menuService` and `configService` build on top of it

**`src/utils/`:**
- Purpose: Pure utility functions with no React dependency
- Each file is a standalone module: `i18n.ts`, `SoundManager.ts`, `tracking.ts`

**`src/lib/`:**
- Purpose: Shared helper utilities (shadcn/ui convention)
- Currently only `utils.ts` with the `cn()` function

---

## Key File Locations

**Entry Points:**
- `project/kiosk-app/src/main.tsx` — React root mount point
- `project/kiosk-app/index.html` — HTML shell loaded by browser

**Routing:**
- `project/kiosk-app/src/App.tsx` — all three route definitions live here

**Global State:**
- `project/kiosk-app/src/context/CartContext.tsx` — the only global store

**HTTP Client:**
- `project/kiosk-app/src/services/strapiClient.ts` — all fetch calls should go through here
  (exception: `VerticalVideoFeed.tsx` uses raw `fetch()` directly)

**Styles and Design Tokens:**
- `project/kiosk-app/src/index.css` — `@theme` design tokens, component classes, utility animations
- `project/kiosk-app/tailwind.config.js` — content path config only

**Build:**
- `project/kiosk-app/vite.config.ts` — Vite + Vitest config, `@` alias definition
- `project/kiosk-app/Dockerfile` — multi-stage Docker build
- `project/infra/nginx/spa-default.conf` — nginx config copied into Docker image

**CI/CD References:**
- `project/.github/workflows/ci.yml` — kiosk built in `docker-build` matrix (name: `kiosk`, dockerfile: `./kiosk-app/Dockerfile`) and linted in `frontend-lint` matrix
- `project/.github/workflows/build-push-artifacts.yml` — kiosk image built and pushed to GHCR
- `project/.github/workflows/cd-deploy.yml` — Cosign signature verified for `resto-bot-kiosk` before deploy

---

## Naming Conventions

**Files:**
- Components: PascalCase `.tsx` — `VerticalVideoFeed.tsx`, `CartContext.tsx`, `CheckoutView.tsx`
- Utilities/Services: camelCase `.ts` — `strapiClient.ts`, `configService.ts`, `i18n.ts`
- Config files: camelCase `.js/.ts` — `vite.config.ts`, `eslint.config.js`
- Test files: `*.test.ts` suffix — `setup.test.ts`

**Exports:**
- Pages: `export default` — `export default function VerticalVideoFeed()`
- Components: mixed — `export default` for modals, named `export function` for `Cart`, `ErrorBoundary`
- Services: named exports of objects — `export const strapi`, `export const configService`, `export const menuService`
- Types/Interfaces: named exports — `export interface CartItem`, `export type Language`
- Context: named exports — `export function CartProvider`, `export function useCart`

**CSS Classes:**
- Custom components use kebab-case prefixed with design system: `.quantum-card`, `.btn-quantum`, `.cinematic-mesh`
- Tailwind utilities used inline via `cn()` for conditional logic

**Import Path Alias:**
- `@` maps to `src/` — e.g. `import { cn } from "@/lib/utils"`, `import { Cart } from "@/components/Cart"`
- Relative imports used within the same directory tier

---

## Where to Add New Code

**New Page / Route:**
1. Create `project/kiosk-app/src/pages/MyNewPage.tsx`
2. Add `<Route path="/my-route" element={<MyNewPage />} />` in `project/kiosk-app/src/App.tsx`
3. The nginx SPA fallback in `project/infra/nginx/spa-default.conf` already handles any path via `try_files`

**New Reusable Component:**
- Create `project/kiosk-app/src/components/MyComponent.tsx`
- Import via `@/components/MyComponent`

**New API Call (Strapi):**
- Use `strapi.get<T>(path)`, `strapi.post<T>(path, data)`, or `strapi.put<T>(path, data)` from `project/kiosk-app/src/services/strapiClient.ts`
- For a new domain area, create a new service file in `src/services/` that imports `strapi`

**New API Call (n8n webhook):**
- Use `strapi.n8n<T>(path, data, headers?)` from `project/kiosk-app/src/services/strapiClient.ts`
- Path is appended to `VITE_N8N_URL`

**New Translation Key:**
- Add entry to `translations` object in `project/kiosk-app/src/utils/i18n.ts`
- Provide all three values: `en`, `fr`, `ar`
- Call with `getTranslation('my_key', lang)`

**New Design Token:**
- Add CSS custom property to `@theme { }` block in `project/kiosk-app/src/index.css`
- Reference in Tailwind utility classes as `bg-my-token-name` (Tailwind 4 reads `@theme` automatically)

**New Global State:**
- Add field to `CartContextType` interface in `project/kiosk-app/src/context/CartContext.tsx`
- Add state + handlers in `CartProvider`
- Add to context value object at the bottom of `CartProvider`

**New Environment Variable:**
- Add `ARG MY_VAR` and `ENV MY_VAR=${MY_VAR}` in `project/kiosk-app/Dockerfile`
- Add `MY_VAR: ${SOME_VALUE}` under `kiosk-app.build.args` in `project/docker-compose.hostinger.prod.yml`
- Reference in source as `import.meta.env.MY_VAR`
- Document in `project/kiosk-app/.env.example`

---

## Special Directories

**`dist/`:**
- Purpose: Vite production build output
- Generated: Yes (by `npm run build`)
- Committed: Yes — currently tracked in git (should be gitignored)
- Note: The committed `dist/` is a local Windows build that failed partially (see `build_error.txt`). It does not reflect a clean CI build.

**`node_modules/`:**
- Purpose: npm dependency tree
- Generated: Yes (by `npm ci`)
- Committed: No (gitignored)

---

*Structure analysis: 2026-03-20*
