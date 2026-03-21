# Kiosk App — Architecture

**Analysis Date:** 2026-03-20
**Scope:** `project/kiosk-app/` — React 19 + Vite 6 SPA

---

## Pattern Overview

**Overall:** Single-Page Application (SPA) with client-side routing, a single global Context
store, and a service layer that proxies all CMS calls through the nginx gateway.

**Key Characteristics:**
- No server-side rendering — fully static build served by nginx-unprivileged:1.27-alpine
- All API calls target `VITE_STRAPI_URL` (baked into the bundle at Docker build time)
- State lives entirely in `CartContext` — no external state library
- Kiosk-optimized UI: `touch-none`, `select-none`, `overflow-hidden` on body; designed for
  full-screen tablet/iPad, not a resizable browser window
- Idle auto-reset via `IdleTimer` component with configurable timeout from Strapi system-config

---

## Layers

**Entry Point:**
- Purpose: Mount React root with StrictMode and outer ErrorBoundary
- Location: `project/kiosk-app/src/main.tsx`
- Wraps `<App>` in `<ErrorBoundary>` — auto-reload after 10s on any uncaught crash
- Depends on: `App.tsx`, `components/ErrorBoundary.tsx`

**App Shell:**
- Purpose: Router setup, cart provider, idle timer, global cinematic backdrop
- Location: `project/kiosk-app/src/App.tsx`
- Contains: `<CartProvider>`, `<BrowserRouter>`, `<IdleTimer>`, route declarations, animated gradient backdrop
- Route table:
  - `/` → `VerticalVideoFeed` (product discovery / home screen)
  - `/checkout` → `CheckoutView` (multi-step checkout page)
  - `/wheel` → `FortuneWheelView` (gamification reward wheel)
- `IdleTimer` reads `kiosk_idle_timeout_sec` from `configService`, throttled to once/sec,
  navigates to `/` and calls `clearCart()` after inactivity

**Service Layer:**
- Location: `project/kiosk-app/src/services/`
- `strapiClient.ts`: Base HTTP client. `strapi.get/post/put` for Strapi CMS endpoints.
  `strapi.n8n` for n8n webhook calls (separate base URL from `VITE_N8N_URL`, adds
  `x-kiosk-secret` header). 10s hard timeout via `AbortSignal.timeout(10000)`. No API
  token embedded — relies on Strapi Public role permissions. Parses Strapi error body to
  surface `error.message` rather than a generic HTTP status string.
- `menuService.ts`: Fetches products with `is_kiosk_visible=true` filter and
  `creative_assets,ingredients` populate. LocalStorage cache, 5-min TTL, keyed by
  category. Ingredient-level stock check: marks product out-of-stock if any linked
  ingredient has `current_stock <= min_stock_alert`. Exposes `getProducts(category?)` and
  `getCategories()`.
- `configService.ts`: Fetches `/api/system-config` (Strapi singleType). LocalStorage
  cache, 5-min TTL. Returns `SystemConfig` with `kiosk_idle_timeout_sec`,
  `kiosk_default_service_mode`, `kiosk_enabled`. Falls back to hardcoded defaults
  (`120s`, `kiosk_sur_place`, `true`) on any error — never throws.

**Context / State:**
- Location: `project/kiosk-app/src/context/CartContext.tsx`
- Provides: `items`, `addItem`, `removeItem`, `updateQuantity`, `clearCart`, `total`,
  `cartCount`, `tableNumber`, `orderType`, `submitOrder`, `isSubmitting`,
  `lastOrderResult`, `defaultServiceMode`
- Cart item composite key: `${product.id}-${size.name}-${extrasKey}-${saucesKey}` —
  same product with different options creates distinct line items
- `submitOrder` calls `strapi.post('/api/orders', {...})` directly via the gateway
- `total` is recomputed from items on every render (no memoization)
- Fetches `system-config` on mount to populate `defaultServiceMode`

**Pages:**
- Location: `project/kiosk-app/src/pages/`
- `CheckoutView.tsx`: Multi-step checkout (review → mode → confirm → done). Dynamically
  imports `configService` on mount to set default service mode. Order submission calls
  `strapi.n8n('/kiosk-order', payload)` — routes to `VITE_N8N_URL` webhook, NOT to
  Strapi directly. This is a second, separate submission path from `CartContext.submitOrder`
  and the two are not coordinated. See CONCERNS.md for details.
- `FortuneWheelView.tsx`: Gamification reward wheel. Six hardcoded reward strings. Google
  review gate is a 2-second `setTimeout` — not cryptographically verified. No Strapi
  integration. Reward promo codes are static strings.

**Components:**
- Location: `project/kiosk-app/src/components/`
- `VerticalVideoFeed.tsx`: Home screen. Fetches products via raw `fetch()` (bypasses
  `strapiClient` and its unified error handling). Also polls
  `STRAPI_URL/api/realtime/cortex?keys=KITCHEN_LOAD` every 15s for a kitchen load
  indicator in the top bar. Manages language state locally (not in context). When adding
  a product constructs a partial `Product` object with hardcoded `category: 'specials'`,
  `inStock: true`, empty `extras/sauces`, and `sizes: [{name:'Normal', price_modifier:0}]`
  — ignores per-product extras/sauces/sizes data from Strapi.
- `Cart.tsx`: Slide-in cart drawer. Calls `CartContext.submitOrder()`. Shows an animated
  receipt screen on success.
- `MenuGrid.tsx`: 2-column product card grid. Accepts `products: Product[]` as props.
  Not wired to any route — exists as a component but is not rendered anywhere in production.
- `CustomizerModal.tsx`: Size / extras / sauces / quantity modal. Free sauce slot logic:
  first N sauces are marked `is_free: true` based on `product.sauces[0].included_count`.
- `ErrorBoundary.tsx`: Class component. Shows "terminal restarting" screen and calls
  `window.location.reload()` after 10 seconds.
- `LanguageSelector.tsx`: Modal for fr/ar/en selection. Calls `setPageDirection()` to
  update `document.documentElement.dir` and `lang`.
- `AppSwitcher.tsx`: Dev utility dropdown linking to all platform URLs including the CMS
  admin panel (`cms.${DOMAIN}/admin`). Not imported or rendered by any route — dead code.

**Utilities:**
- Location: `project/kiosk-app/src/utils/`, `project/kiosk-app/src/lib/`
- `i18n.ts`: Static dictionary, 8 translation keys, 3 languages (fr/ar/en). `getTranslation(key,
  lang)` returns the key string as fallback when missing. `setPageDirection(lang)` sets
  `dir` and `lang` on `<html>`.
- `SoundManager.ts`: Web Audio API synthesized sounds. Creates a new `AudioContext` per
  `playSound()` call — not pooled (memory leak risk on rapid interaction).
- `tracking.ts`: Fire-and-forget `POST` to `VITE_N8N_URL/webhook/track`. Stores a
  `kiosk_session` UUID in localStorage. Silent on failure.
- `lib/utils.ts`: `cn()` helper combining `clsx` + `tailwind-merge`.

---

## Data Flow

**Product Discovery (Home Screen):**

1. `VerticalVideoFeed` mounts — raw `fetch()` calls `STRAPI_URL/api/products?populate=creative_assets&filters[is_kiosk_visible][$eq]=true&pagination[pageSize]=10&sort=createdAt:desc`
2. Gateway at `api.srv1258231.hstgr.cloud/v1/strapi/api/products` (GET-only, `kiosk_menu` rate zone at 30r/s) proxies to CMS
3. `mapStrapiToFeed()` normalises Strapi v4 and v5 media payload shapes → fullscreen image slides
4. Concurrent `fetchCortex()` polls `STRAPI_URL/api/realtime/cortex?keys=KITCHEN_LOAD` every 15s — sets kitchen load indicator in top bar
5. User taps "Pre-Order" → `CustomizerModal` opens with partial product object (hardcoded defaults, not full Strapi product)
6. User confirms → `CartContext.addItem()` called

**Cart Checkout (Cart Drawer — primary path):**

1. User opens cart → `Cart.tsx` renders as full-screen overlay
2. User enters table number (optional integer), selects dine-in or takeaway
3. Taps "Order Now" → `CartContext.submitOrder()` → `strapi.post('/api/orders', payload)` via gateway `/v1/strapi/api/orders` (POST-only nginx location block)
4. On success: receipt overlay shown with order ID, cart cleared

**Checkout Page (alternate path — `/checkout` route):**

1. `CheckoutView` mounts → dynamic import of `configService` sets default service mode
2. User steps through: review items → mode selection → confirm
3. Taps "Deploy Order Matrix" → `handleSubmitOrder()` → `strapi.n8n('/kiosk-order', payload)` → `VITE_N8N_URL/kiosk-order` (n8n webhook)
4. On success: random orderId displayed, cart cleared, step = `done`

**Idle Reset:**

1. `IdleTimer` registers throttled global event listeners (`mousemove`, `keydown`, `touchstart`, `click`) — 1s throttle
2. No interaction for `kiosk_idle_timeout_sec` seconds (fetched from Strapi, default 120)
3. `clearCart()` + `navigate('/')` executed

**State Management:**
- React Context API only (`CartContext`) — no Redux, Zustand, or Jotai
- Language state is local to `VerticalVideoFeed` — lost when navigating to `/checkout`
- LocalStorage keys used:
  - `menu_cache_all`, `menu_cache_{category}` — product list, 5-min TTL (written by `menuService`)
  - `kiosk_system_config` — system config, 5-min TTL (written by `configService`)
  - `kiosk_session` — session ID for tracking (written by `tracking.ts`, persists indefinitely)
- Cart state is in-memory React state only — lost on page reload

---

## Entry Points

**`src/main.tsx`:**
- Location: `project/kiosk-app/src/main.tsx`
- Triggers: Browser loads `index.html`, Vite module script tag
- Responsibilities: Mount React root, outer error boundary

**`src/App.tsx`:**
- Location: `project/kiosk-app/src/App.tsx`
- Triggers: Rendered by `main.tsx`
- Responsibilities: Cart state initialization, routing, idle timer, visual backdrop

---

## Error Handling

**Strategy:** Fail-soft / graceful degradation. Errors do not propagate destructively to the user.

| Location | Strategy |
|---|---|
| `strapiClient.ts` | Parses Strapi error body, throws `Error` with Strapi message |
| `configService.ts` | Returns hardcoded defaults on any error — never throws |
| `menuService.ts` | Does not catch — callers must handle network errors |
| `VerticalVideoFeed.tsx` | Catches fetch errors silently, keeps `FALLBACK_FEED` (single placeholder item) |
| `tracking.ts` | `console.debug` only on failure — never affects UX |
| `ErrorBoundary.tsx` | Class boundary wraps full app; shows spinner + reloads in 10s |
| `CheckoutView.tsx` | Sets `error` string state, renders inline `AlertTriangle` message |
| `Cart.tsx` | Uses `lastOrderResult.error` from context for inline error display |

---

## Cross-Cutting Concerns

**Logging:** `console.error/warn/debug` only. No structured logging, no correlation IDs,
no log shipping.

**Validation:** None client-side. Table number input accepts any integer with no range
check. No cart item or quantity maximum enforced in the UI. Order `total_cents` is
computed client-side and sent as-is — a code comment (`SEC-010`) in `CartContext.tsx`
line 147 explicitly acknowledges it is untrusted and must be re-validated server-side.

**Authentication:** No auth on kiosk. Strapi Public role is used for all reads and order
creation. `setStrapiToken()` exists in `strapiClient.ts` but is never called from any
component. The `x-kiosk-secret` header is sent on n8n calls but the value is `''` (empty
string) in production because `VITE_KIOSK_SECRET` is not passed as a Docker build ARG.

**CORS:** Managed entirely at the nginx gateway. Strapi's own CORS headers are stripped via
`proxy_hide_header` and replaced by nginx with a hardcoded
`Access-Control-Allow-Origin: https://kiosk.srv1258231.hstgr.cloud` on all `/v1/strapi/`
routes.

---

*Architecture analysis: 2026-03-20*
