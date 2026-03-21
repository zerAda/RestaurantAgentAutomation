# Admin Dashboard — Architecture

**Analysis Date:** 2026-03-20
**Scope:** `project/admin-dashboard/` (React 19 + Vite SPA)

---

## Pattern Overview

**Overall:** Single-Page Application (SPA), client-rendered, served as static files from nginx.

**Key Characteristics:**
- No server-side rendering — full client-side routing via React Router v7
- Strapi CMS is the sole backend; all data fetched via `src/services/strapiClient.ts`
- Authentication uses Strapi users-permissions JWT (NOT Strapi admin JWT)
- Polling-based data freshness — no WebSockets, no SSE
- Role-based access control (RBAC) enforced entirely in the browser

---

## Application Bootstrap

**Entry point:** `src/main.tsx`

```
StrictMode
  └── ErrorBoundary          (global crash boundary)
       └── BrowserRouter
            └── App           (auth gate + layout + routes)
```

`App` (`src/App.tsx`) is the root component. It:
1. Calls `authService.isAuthenticated()` on render; if false, shows `<LoginView>`
2. After login: renders the full sidebar + main content with `<Routes>`
3. Reads `authService.getUser()` to gate admin-only nav sections on `isFullAdmin`

---

## Layers

**Auth Layer**
- Location: `src/services/authService.ts`
- Purpose: Login, JWT storage, logout, expiry enforcement
- Storage: `sessionStorage` (tab-isolated, wiped on browser close)
- Keys: `admin_jwt`, `admin_user`, `admin_jwt_expiry`
- Client-side expiry: 24-hour timeout enforced on every `isAuthenticated()` call
- Fallback: `logout()` also clears `localStorage` for old keys from pre-fix sessions

**API Client Layer**
- Location: `src/services/strapiClient.ts`
- Purpose: Typed `fetch()` wrapper; attaches Bearer token; handles 401/5xx centrally
- Token source: `sessionStorage.getItem('admin_jwt')` (falls back to `localStorage`)
- 401 behavior: saves current path to `sessionStorage('redirect_after_login')`, clears auth, redirects to `/`
- 5xx/timeout behavior: fires `strapi-network-error` CustomEvent → `ApiErrorListener` → Toast
- Default request timeout: 10s (AI chat uses 50s, passed via `timeoutMs` option)
- Methods: `find`, `findOne`, `get`, `post`, `put`, `delete`, `rawGet`, `getCortexData`

**Service Layer**
- Location: `src/services/`
- `orders.ts` — TanStack Query hooks: `useOrders` (poll every 10s), `useUpdateOrderStatus` (mutation)
- `stockService.ts` — imperative: `getAll()`, `updateStock()` (calls custom `/api/ingredients/:id/adjust`)
- `authService.ts` — auth lifecycle (login, logout, getUser, getToken)

**View / Page Layer**
- `src/pages/` — true page components: `DashboardHome.tsx`, `ControlPlaneView.tsx`, `KitchenDisplay.tsx`, `GodMode.tsx`
- `src/components/` — views rendered via routing AND reusable UI components (not cleanly separated)
- Most "views" are in `components/` (StockView, KitchenView, AnalyticsView, AutomationView, etc.)

**UI Utility Layer**
- `src/lib/utils.ts` — `cn()` helper (clsx + tailwind-merge)
- `src/utils/i18n.ts` — static EN/FR/AR translation table + `setPageDirection()` for RTL
- `src/utils/pii.ts` — `maskPII()` for phone/name redaction in order display
- `src/components/ui/` — card, badge primitives (used by `KitchenDisplay.tsx`)
- `src/components/SkeletonLoader.tsx` — skeleton loading states
- `src/components/AnimatedNumber.tsx` — animated count-up for KPI cards

---

## Routing

All routes are defined inline in `src/App.tsx` inside a single `<Routes>` block.

| Path | Component | File | Admin-Only |
|------|-----------|------|------------|
| `/dashboard` | `DashboardHome` | `src/pages/DashboardHome.tsx` | No |
| `/stock` | `StockView` | `src/components/StockView.tsx` | No |
| `/alerts` | `QuickAdjust` | `src/components/QuickAdjust.tsx` | No |
| `/kitchen` | `KitchenView` | `src/components/KitchenView.tsx` | No |
| `/support` | `SupportView` | `src/components/SupportView.tsx` | No |
| `/customers` | `CustomerView` | `src/components/CustomerView.tsx` | No |
| `/fleet` | `FleetPlaceholder` | inline in `src/App.tsx` | No |
| `/analytics` | `AnalyticsView` | `src/components/AnalyticsView.tsx` | Yes |
| `/growth` | `GrowthAgentView` | `src/components/GrowthAgentView.tsx` | Yes |
| `/marketing` | `MarketingView` | `src/components/MarketingView.tsx` | Yes |
| `/automation` | `AutomationView` | `src/components/AutomationView.tsx` | Yes |
| `/ai-observatory` | `AiObservatoryView` | `src/components/AiObservatoryView.tsx` | Yes |
| `/control-plane` | `ControlPlaneView` | `src/pages/ControlPlaneView.tsx` | Yes |
| `/brand` | `BrandView` | `src/components/BrandView.tsx` | Yes |
| `*` | Redirect to `/dashboard` | — | — |

**RBAC gate (`src/App.tsx` line 61):**
```typescript
const isFullAdmin = user?.role?.type === 'authenticated'
  || user?.role?.name?.toLowerCase() === 'admin'
  || user?.role?.name?.toLowerCase() === 'super_admin';
```

All routes are wrapped in `<PageTransition>` via `ViewWrapper` for animated transitions.

---

## Component Tree (Authenticated Layout)

```
App
├── ToastProvider                    (Context: addToast)
│   ├── ApiErrorListener             (listens to strapi-network-error → addToast)
│   ├── <nav> (sidebar)
│   │   ├── NavItem × N              (navigate() calls)
│   │   ├── AppSwitcher
│   │   └── user avatar + LogOut button → authService.logout()
│   └── <main>
│       ├── NotificationCenter       (polls Strapi every 20s)
│       ├── ErrorBoundary
│       │   └── Routes
│       │       ├── DashboardHome
│       │       │   ├── CortexHub    (polls /api/realtime/cortex every 10s)
│       │       │   ├── KPICard × 4  (revenue, orders, prep time, customers)
│       │       │   ├── AreaChart    (recharts, 7-day revenue)
│       │       │   └── Low-stock alert chips
│       │       ├── StockView        (stockService.getAll, no auto-refresh)
│       │       ├── KitchenView      (useOrders, useUpdateOrderStatus)
│       │       ├── ControlPlaneView (rawGet /api/control-plane/status, 15s poll)
│       │       ├── AutomationView   (static workflow list + trigger modal)
│       │       └── ... (remaining views)
│       └── AIChatBubble             (floating, always rendered when authenticated)
```

---

## Data Flow

**Standard Strapi CRUD (most views):**
```
Component useEffect / useQuery
  → strapi.find('orders', { filters, pagination, sort })
  → fetch GET ${VITE_STRAPI_URL}/api/orders?...
  → Authorization: Bearer <jwt> header
  → 200: map StrapiOrder[] → Order[]  → setState
  → 401: clear storage + redirect /
  → 5xx: CustomEvent → Toast
```

**AI Agent Chat:**
```
AIChatBubble.sendMessage(text)
  → fetch POST ${VITE_STRAPI_URL}/api/agent/chat
    body: { data: { message, sessionId: 'admin-dashboard-session', confirm } }
    timeout: 50s
  → Strapi system-config custom controller (agent-chat.ts)
  → POST https://n8n-main:5678/webhook/admin/chat  (internal Docker network)
  → W_ADMIN_AGENT workflow: 17 RAG slices from Strapi → Ollama llama3.1 → reply
  → { reply, actions[], ragSlices[], needsConfirmation }
  → Rendered in chat panel with markdown (react-markdown + remark-gfm)
```

**Order Status Update:**
```
KitchenView / OrdersKanban
  → useUpdateOrderStatus().mutate({ documentId, status })
  → strapi.put('/api/orders/${documentId}', { status })  [uses documentId, not id]
  → onSuccess: queryClient.invalidateQueries(['orders'])
```

**Control Plane Telemetry:**
```
ControlPlaneView (every 15s)
  → strapi.rawGet('/api/control-plane/status')   [raw response, no data wrapper]
  → Strapi controller checks: pg health, redis connections, n8n executions, system memory
  → SystemStatus { services, system } displayed as StatusCard grid
```

**Notification Polling:**
```
NotificationCenter (every 20s)
  → Promise.allSettled([
      strapi.find('orders', last 1h),
      strapi.find('ingredients', all),
      strapi.find('workflow-errors', last 1h)
    ])
  → Diff against knownIds ref → new items fire addToast
```

**n8n Workflow Trigger:**
```
AutomationView.handleTrigger()
  → strapi.post('/api/automation/trigger', { webhookUrl, payload })
  → Strapi custom controller proxies to n8n webhook URL
```

---

## State Management

**TanStack Query v5** (`@tanstack/react-query`)
- Used only for `useOrders` and `useUpdateOrderStatus` hooks in `src/services/orders.ts`
- `QueryClient` instance: `src/lib/queryClient.ts` (default config — no `staleTime`, no retry config)
- `Providers.tsx` exists but is NOT used in `main.tsx` — `QueryClientProvider` is missing from the tree

**Local component state**
- All other views use `useState` + `useEffect` + `setInterval` polling
- No global data store (no Zustand, Redux, or data Context)

**sessionStorage** (auth tokens)
- `admin_jwt`, `admin_user`, `admin_jwt_expiry` — managed by `authService.ts`

**localStorage** (chat history)
- `ralphe_agent_history` — last 50 AI chat messages, persists across sessions

---

## Error Handling Strategy

| Layer | Mechanism | Effect |
|-------|-----------|--------|
| Render crash | `ErrorBoundary` class component (`src/components/ErrorBoundary.tsx`) | Full-section fallback UI with reload button |
| 401 Unauthorized | `strapiClient` catches 401, fires `authService.logout()` after saving redirect path | Full redirect to `/` |
| 5xx / timeout | `strapiClient` fires `strapi-network-error` CustomEvent | Toast notification via `ApiErrorListener` |
| View fetch error | `try/catch` in `useEffect`/`useCallback` | Silently sets local error state or logs to console |
| AI chat error | `catch` in `sendMessage` | Inline "Communication Link Severed" agent message |
| Error reporting | `console.error` with bracketed tags | Local only — no remote error tracking |

---

## Cross-Cutting Concerns

**Logging:** `console.error` with prefixed tags (`[AuthService]`, `[DashboardHome]`, etc.). No structured logging, no remote tracking (Sentry, etc.).

**Validation:** No client-side form validation beyond empty-check on login. Input sanitization is absent — relies on Strapi's API validation.

**Authentication:** All routes are protected by a single `isAuthenticated()` check at the `App` render level. No per-route guards, no lazy protection.

**Internationalization:** Static translation table (`src/utils/i18n.ts`) covers EN/FR/AR for sidebar labels only. Page titles and most UI strings are hardcoded French/English in `App.tsx` and individual components.

**PII Masking:** `maskPII()` in `src/utils/pii.ts` applied selectively in `OrdersKanban` customer field display.

---

*Architecture analysis: 2026-03-20*
