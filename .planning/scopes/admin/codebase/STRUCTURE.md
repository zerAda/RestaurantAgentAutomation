# Admin Dashboard — Codebase Structure

**Analysis Date:** 2026-03-20
**Scope:** `project/admin-dashboard/`

---

## Directory Layout

```
project/admin-dashboard/
├── src/
│   ├── components/          # Views AND reusable UI components (mixed)
│   ├── pages/               # True page components (4 files)
│   ├── services/            # API client + domain services
│   ├── utils/               # Pure utility functions
│   ├── lib/                 # Framework configuration + helpers
│   ├── App.tsx              # Root component: auth gate, layout, routing
│   ├── main.tsx             # React DOM entry point
│   └── index.css            # Tailwind v4 directives + CSS custom properties
├── dist/                    # Built output (committed, used for in-container patching)
│   ├── assets/
│   │   ├── index-C6so2xNl.js   # Single JS bundle (~975KB, uncompressed)
│   │   └── index-CrLCB9yz.css  # Single CSS bundle
│   └── index.html
├── Dockerfile               # Multi-stage: node:20 build → nginx:1.27 serve
├── package.json
├── package-lock.json
├── vite.config.ts
├── eslint.config.js
├── index.html               # Vite HTML entry (references /src/main.tsx)
├── .env.example             # Documents all VITE_* variables
├── .gitignore
└── node_modules/
```

---

## Directory Purposes

**`src/components/`**
- Purpose: The majority of the application's feature views AND reusable UI components live here. No strict separation between "views" and "components".
- Contains:
  - Feature views: `StockView.tsx`, `KitchenView.tsx`, `AnalyticsView.tsx`, `AutomationView.tsx`, `CustomerView.tsx`, `MarketingView.tsx`, `BrandView.tsx`, `SupportView.tsx`, `GrowthAgentView.tsx`, `AiObservatoryView.tsx`, `QuickAdjust.tsx`
  - Global UI: `AIChatBubble.tsx`, `NotificationCenter.tsx`, `ToastProvider.tsx`, `AppSwitcher.tsx`, `PageTransition.tsx`, `ErrorBoundary.tsx`, `ApiErrorListener.tsx`
  - Primitives: `SkeletonLoader.tsx`, `AnimatedNumber.tsx`, `CortexHub.tsx`, `LoginView.tsx`
  - UI library: `ui/card.tsx`, `ui/badge.tsx` (used by KitchenDisplay)
- Key files:
  - `src/components/AIChatBubble.tsx` — floating AI assistant, calls `/api/agent/chat`
  - `src/components/KitchenView.tsx` — live order board with status update controls
  - `src/components/NotificationCenter.tsx` — polling notification dropdown
  - `src/components/ToastProvider.tsx` — global toast Context + display stack
  - `src/components/ErrorBoundary.tsx` — class component, global render crash catcher

**`src/pages/`**
- Purpose: Full-page components that are direct route targets with heavier data-fetch logic.
- Key files:
  - `src/pages/DashboardHome.tsx` — main KPI dashboard, 5 parallel Strapi fetches on mount
  - `src/pages/ControlPlaneView.tsx` — infrastructure telemetry (PostgreSQL, Redis, n8n, memory)
  - `src/pages/KitchenDisplay.tsx` — alternative kitchen view using Card/Badge primitives
  - `src/pages/GodMode.tsx` — kill switch for order acceptance via platform-settings Strapi entry

**`src/services/`**
- Purpose: API interaction — typed Strapi client and domain-specific service modules.
- Key files:
  - `src/services/strapiClient.ts` — **central API client**; all Strapi calls go through here
  - `src/services/authService.ts` — login/logout/token management
  - `src/services/orders.ts` — `useOrders` and `useUpdateOrderStatus` TanStack Query hooks
  - `src/services/stockService.ts` — `getAll()` and `updateStock()` for ingredients

**`src/utils/`**
- Purpose: Pure utility functions with no React dependencies.
- Key files:
  - `src/utils/i18n.ts` — static translation table (EN/FR/AR) + `setPageDirection()`
  - `src/utils/pii.ts` — `maskPII()` function for phone/name redaction

**`src/lib/`**
- Purpose: Framework-level configuration and shared helpers.
- Key files:
  - `src/lib/utils.ts` — `cn()` helper (`clsx` + `tailwind-merge`)
  - `src/lib/queryClient.ts` — TanStack Query `QueryClient` instance (default config)

**`dist/`**
- Purpose: Pre-built production output committed to the repo.
- Generated: Yes (by `npm run build`)
- Committed: Yes — the dist was patched in-container (sed on minified JS) during the 2026-03-14 emergency fix session. This means the committed `dist/` may diverge from the source.
- Used by: Docker build copies `dist/` as the nginx serve root

---

## Key File Locations

**Entry Points:**
- `src/main.tsx` — React DOM root, wraps in `StrictMode` + `ErrorBoundary` + `BrowserRouter`
- `index.html` — Vite HTML entry, references `<script type="module" src="/src/main.tsx">`

**Root Component:**
- `src/App.tsx` — auth gate, sidebar layout, route definitions, NavItem, FleetPlaceholder

**Configuration:**
- `vite.config.ts` — Vite + Vitest config, `@` alias
- `eslint.config.js` — ESLint flat config
- `Dockerfile` — multi-stage Docker build
- `project/admin-dashboard/.env.example` — VITE_* variable documentation

**Core Logic:**
- `src/services/strapiClient.ts` — all API calls, auth headers, 401/5xx handling
- `src/services/authService.ts` — JWT lifecycle, sessionStorage
- `src/App.tsx` — RBAC gate, routing, language toggle

**Testing:**
- `src/setup.test.ts` — single placeholder test (truthiness assertion)

---

## Naming Conventions

**Files:**
- React components: PascalCase (`DashboardHome.tsx`, `KitchenView.tsx`, `AIChatBubble.tsx`)
- Services/utilities: camelCase (`strapiClient.ts`, `stockService.ts`, `authService.ts`)
- Hooks (in service files): camelCase prefixed with `use` (`useOrders`, `useUpdateOrderStatus`)
- Config files: lowercase with extension (`vite.config.ts`, `eslint.config.js`)

**Directories:**
- All lowercase: `components/`, `pages/`, `services/`, `utils/`, `lib/`

**Exports:**
- Named exports for components: `export function StockView()`, `export const authService = {}`
- Default exports for pages: `export default function DashboardHome()`
- No barrel `index.ts` files — all imports use direct file paths

---

## Where to Add New Code

**New Feature View (full page):**
- Implementation: `src/pages/NewView.tsx`
- Add route in `src/App.tsx` `<Routes>` block
- Add nav item in `src/App.tsx` sidebar section

**New Feature Component (sub-view or widget):**
- Implementation: `src/components/NewWidget.tsx`

**New Strapi Data Hook:**
- Implementation: `src/services/newEntity.ts`
- Follow pattern in `src/services/orders.ts`: define `StrapiType`, `DomainType`, map function, export `useEntityName` with `useQuery`

**New Strapi Imperative Service:**
- Implementation: `src/services/newService.ts`
- Follow pattern in `src/services/stockService.ts`: export a `const service = { getAll, update }` object

**New Utility Function:**
- Pure function with no React: `src/utils/newUtil.ts`
- React-dependent helper: `src/lib/newHelper.ts`

**New UI Primitive:**
- Implementation: `src/components/ui/new-primitive.tsx`
- Follow Card/Badge pattern — use `cn()` for class composition

---

## Special Directories

**`dist/`**
- Purpose: Production build output served by nginx
- Generated: Yes (by `npm run build` / Docker build stage)
- Committed: Yes — anomalous for a typical SPA project; exists due to in-container emergency patching during 2026-03-14 session
- Risk: Committed `dist/` may not match source; a clean rebuild will replace it

**`node_modules/`**
- Purpose: npm dependencies
- Generated: Yes
- Committed: No (in `.gitignore`)

---

*Structure analysis: 2026-03-20*
