# Admin Dashboard — Codebase Concerns

**Analysis Date:** 2026-03-20
**Scope:** `project/admin-dashboard/`

---

## Security Considerations

### S-01 — AI Chat History in localStorage (XSS-accessible)

**Risk:** High
**Files:** `src/components/AIChatBubble.tsx` lines 44–56
**Problem:**
```typescript
const STORAGE_KEY = 'ralphe_agent_history';
localStorage.setItem(STORAGE_KEY, JSON.stringify(messages.slice(-50)));
```
The auth JWT is correctly stored in `sessionStorage` (XSS-resistant, tab-isolated). However, the AI chat history is in `localStorage`. Any XSS attack can read the full conversation history, which may contain sensitive business data (revenue figures, customer counts, inventory levels) as the agent replies include RAG data from Strapi.

**Current mitigation:** None.
**Recommendation:** Move to `sessionStorage` or IndexedDB with origin isolation. If persistence across sessions is required, strip sensitive RAG slice content before saving.

---

### S-02 — RBAC Gate Is Too Broad (All Authenticated Users Are Admins)

**Risk:** High
**Files:** `src/App.tsx` lines 60–62
**Problem:**
```typescript
const isFullAdmin = user?.role?.type === 'authenticated'
  || user?.role?.name?.toLowerCase() === 'admin'
  || user?.role?.name?.toLowerCase() === 'super_admin';
```
The first condition (`role.type === 'authenticated'`) matches every user created by Strapi's users-permissions plugin — the `authenticated` type is the default type for all non-public roles. This means any user who can log in at all gets full access to admin-only routes: `/analytics`, `/growth`, `/control-plane`, `/ai-observatory`, `/brand`, `/marketing`, `/automation`.

**Current mitigation:** Strapi IP-allowlists the CMS, so only users who can reach the admin dashboard URL at all can log in. This is a network-layer control, not an application-layer one.
**Recommendation:** Change the gate to check `role.name === 'admin' || role.name === 'super_admin'` only. Remove the `role.type === 'authenticated'` check entirely.

---

### S-03 — AIChatBubble Reads JWT Directly From Storage

**Risk:** Medium
**Files:** `src/components/AIChatBubble.tsx` lines 115, 177
**Problem:**
```typescript
const token = sessionStorage.getItem('admin_jwt') || localStorage.getItem('admin_jwt');
```
`AIChatBubble` bypasses `authService.getToken()` and reads `admin_jwt` from storage directly by string key. If the storage key name is ever changed in `authService.ts`, the AI chat will silently fail authentication without any error surfaced to the developer.
**Recommendation:** Always call `authService.getToken()`. Replace both direct storage reads in `AIChatBubble.tsx`.

---

### S-04 — Portainer Link Is a Dead Anchor

**Risk:** Low (information disclosure)
**Files:** `src/pages/ControlPlaneView.tsx` line 135
**Problem:**
```html
<a href="#">Open Orchestrator</a>
```
The "Open Orchestrator" link in `ControlPlaneView` points to `#` (no-op). It suggests Portainer integration but provides no actual URL. If a real Portainer URL is added in the future without IP allowlisting, it would expose container management to any logged-in user.
**Recommendation:** Either remove the link or populate `VITE_PORTAINER_URL` and add a note that it requires VPN/allowlist.

---

## Tech Debt

### T-01 — `Providers.tsx` Is Defined But Never Mounted

**Risk:** Medium (silent data-fetching bugs)
**Files:** `src/components/Providers.tsx`, `src/main.tsx`
**Problem:**
```typescript
// Providers.tsx wraps with QueryClientProvider
export function Providers({ children }) {
  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
}
```
`Providers.tsx` is never imported or used. `main.tsx` renders `<App>` directly without `QueryClientProvider`. Yet `useOrders` and `useUpdateOrderStatus` in `src/services/orders.ts` call `useQuery` and `useMutation`. This means if `KitchenView` or `OrdersKanban` uses these hooks, they will throw a runtime error: _"No QueryClient set, use QueryClientProvider to set one"_.

Either: (a) these hooks work because a `QueryClientProvider` exists somewhere not found in this analysis, or (b) the `KitchenView` and `OrdersKanban` components that use them crash on mount and the error is swallowed by the `ErrorBoundary`.
**Fix:** Add `<Providers>` to the tree in `src/main.tsx`, wrapping `<App>`.

---

### T-02 — Committed `dist/` Diverges From Source

**Risk:** High (build reproducibility, confusion)
**Files:** `project/admin-dashboard/dist/`
**Problem:**
The `dist/` directory is committed to git. During the 2026-03-14 session, the running container's minified JS bundle was patched in-place with `sed` (changing `authService` to call the correct endpoint). That patched bundle was then committed. The committed `dist/` therefore contains changes that are NOT reflected in the TypeScript source — a `git build` from clean source will differ from what is committed.
**Impact:** Anyone doing a clean `docker compose build` will get the correct built image (from source). But the committed dist misleads code readers into thinking the bundle matches the source.
**Fix:** Remove `dist/` from git tracking (add to `.gitignore`) and treat it as a generated artifact.

---

### T-03 — Monolithic JS Bundle (No Code Splitting)

**Risk:** Medium (performance)
**Files:** `vite.config.ts`, `project/admin-dashboard/dist/assets/index-C6so2xNl.js`
**Problem:**
`vite.config.ts` has no `build.rollupOptions.output.manualChunks` configuration. The entire application — including Recharts, Framer Motion, react-markdown, TanStack Query, and all views — is bundled into a single JS file. The committed bundle is `dist/assets/index-C6so2xNl.js`. Framer Motion alone is ~140KB gzipped; Recharts adds ~70KB.

Initial page load requires parsing the full bundle before any UI appears. On a 4G mobile connection (~5Mbps), this is ~200–500ms parse time.
**Fix approach:** Add `manualChunks` to `vite.config.ts` splitting at minimum: vendor (react, react-dom, react-router), charts (recharts), animation (framer-motion), markdown (react-markdown + remark-gfm). Lazy-load admin-only routes with `React.lazy` + `Suspense`.

---

### T-04 — DashboardHome Makes 5 Strapi Calls on Every 30s Tick (No Stale-While-Revalidate)

**Risk:** Medium (backend load, UX)
**Files:** `src/pages/DashboardHome.tsx` lines 119–140
**Problem:**
```typescript
const [ordersRes, prevOrdersRes, customersRes, prevCustomersRes, ingredientsRes] = await Promise.all([
  strapi.find('orders', { pagination: { limit: 500 } }),
  strapi.find('orders', { pagination: { limit: 500 } }),  // prev week
  strapi.find('customers', { pagination: { limit: 500 } }),
  strapi.find('customers', { pagination: { limit: 500 } }),  // prev period
  strapi.find('ingredients', { pagination: { limit: 200 } }),
]);
```
Five concurrent `fetch()` calls every 30 seconds, each requesting up to 500 records. Two of these are for "previous period" comparison (the week before), which changes at most once a day. These are not cached — every 30s tick re-fetches all 5.
**Fix approach:** Use TanStack Query's `staleTime` and `gcTime` options for previous-period data (stale after 5 minutes). Or move to a dedicated dashboard summary endpoint in Strapi that returns pre-aggregated data in a single call.

---

### T-05 — NotificationCenter Field Mismatch (`total_cents` vs `total_amount`)

**Risk:** High (broken UI data)
**Files:** `src/components/NotificationCenter.tsx` line 8, 75
**Problem:**
```typescript
interface StrapiOrder { id: number; total_cents: number; ... }
// line 75:
message: `#${...} — ${(o.total_cents / 100).toFixed(0)} DA Linked`,
```
`NotificationCenter` uses `total_cents` and divides by 100. However, `src/services/orders.ts` (comment on line 25) explicitly documents:
> `total_amount` is already in DA — no division needed.

The Strapi orders schema field is `total_amount` (in DA), NOT `total_cents`. This means notification messages display order totals that are 100x too small (or display `NaN` if the field is actually undefined).
**Fix:** Change `NotificationCenter` to use `total_amount` (no division) matching the pattern in `orders.ts`.

---

### T-06 — KitchenDisplay Uses Uppercase Status Strings That Don't Match Strapi Enum

**Risk:** Medium (stale/broken kitchen display)
**Files:** `src/pages/KitchenDisplay.tsx` lines 34, 49
**Problem:**
```typescript
const activeOrders = orders.filter(o => !['DONE', 'CANCELLED'].includes(o.status));
// ...
status: order.status === 'PREPARING' ? 'COOKING' : 'PENDING',
```
`src/services/orders.ts` comment (line 4) documents the fix for this exact issue:
> Strapi order schema status enum is LOWERCASE ('pending', 'confirmed', 'preparing', 'ready', 'delivered', 'cancelled')

`KitchenDisplay.tsx` filters on uppercase `'DONE'` and `'CANCELLED'` which will never match the lowercase Strapi values. All orders will show as "active" regardless of their real status, and no order will ever be classified as `'COOKING'` (it checks `'PREPARING'` not `'preparing'`).
**Fix:** Replace all uppercase status literals in `KitchenDisplay.tsx` with lowercase equivalents, matching the Strapi enum values documented in `orders.ts`.

---

### T-07 — `queryClient` Has No Configuration (No Retry, No StaleTime)

**Risk:** Low (unnecessary refetches, no resilience)
**Files:** `src/lib/queryClient.ts`
**Problem:**
```typescript
export const queryClient = new QueryClient();
```
The `QueryClient` uses all defaults: 3 retries on failure, no `staleTime` (data is immediately stale), no `gcTime` configuration. For a polling dashboard this means: (a) every background refetch on the 10s interval is treated as "data is stale" so no caching benefit, and (b) transient network errors cause 3 retry attempts before failing, potentially leaving the UI in a loading state for ~4s.
**Fix:** Configure at minimum `defaultOptions: { queries: { staleTime: 5000, retry: 1 } }`.

---

### T-08 — Hardcoded Workflow URLs in AutomationView

**Risk:** Low (maintenance burden)
**Files:** `src/components/AutomationView.tsx` lines 22–71
**Problem:**
The 4 workflow definitions (webhook URLs, descriptions, status, success rates) are hardcoded static objects in the component. Success rates and "last run" are static strings like `'99.8%'` and `'2 mins ago'` — not real data. This means the Automation view shows false metrics that never update.
**Fix approach:** Fetch workflow list from Strapi `platform-settings` or a dedicated `workflows` collection. The `VITE_N8N_WEBHOOK_BASE` env var already provides the base URL.

---

### T-09 — GodMode Kill Switch Uses Numeric `id` Not `documentId`

**Risk:** Medium (kill switch fails silently after Strapi data migration)
**Files:** `src/pages/GodMode.tsx` lines 42, 72
**Problem:**
```typescript
const setting = res.data[0] as unknown as { id: number; key: string; value: string };
setSettingId(setting.id);
// later:
await strapi.put(`/api/platform-settings/${settingId}`, { value: ... });
```
Strapi v5 uses `documentId` (stable string) for PUT/DELETE operations, not the numeric `id`. Using the numeric `id` in the URL path will cause a 404 or incorrect record update after any Strapi content migration that changes the numeric ID (which can happen on re-import or DB restore).
**Fix:** Extract `setting.documentId` instead of `setting.id` and use it in the PUT URL.

---

## Test Coverage Gaps

### TC-01 — Effectively Zero Test Coverage

**Risk:** High
**Files:** `src/setup.test.ts`
**Problem:**
The only test file is:
```typescript
describe('Admin Dashboard Basic Setup', () => {
  it('should pass a basic truthiness test', () => {
    expect(true).toBe(true);
  });
});
```
There are no tests for: `authService` (login, logout, token expiry), `strapiClient` (401 handling, timeout, retry), `orders.ts` (status mapping, field mapping), `stockService` (delta calculation), any React component rendering, or RBAC gate logic.
**Impact:** All bugs described in this document exist undetected by CI. The `frontend-lint` CI job runs `eslint` only — no test execution.
**Priority:** High. Minimum viable: test `authService.isAuthenticated()` expiry logic, `strapiClient` 401 redirect path, and the `mapOrder` function status normalization.

---

## Performance Bottlenecks

### P-01 — Simultaneous Polling Intervals from Multiple Mounted Components

**Problem:** When the dashboard is open on `/dashboard`, the following intervals are active simultaneously:
- `DashboardHome`: 30s × 5 calls = 5 Strapi requests every 30s
- `CortexHub` (child of DashboardHome): 10s × 1 call
- `NotificationCenter` (always visible in header): 20s × 3 calls
- `AIChatBubble` (always rendered): no polling

At peak, this generates ~11 Strapi API calls per 10-second window from a single browser tab.

**Files:** `src/pages/DashboardHome.tsx`, `src/components/CortexHub.tsx`, `src/components/NotificationCenter.tsx`
**Fix approach:** Coordinate polling via a shared React Query cache or a single WebSocket/SSE connection from Strapi.

---

## Missing Critical Features

### M-01 — No Token Refresh Mechanism

**Problem:** The 24-hour token expiry is enforced client-side only (checking `admin_jwt_expiry` in `isAuthenticated()`). There is no token refresh call to Strapi. When the token expires, the user is silently logged out on the next `isAuthenticated()` check or on the next 401 from Strapi. If a user is mid-workflow (e.g., editing a form), unsaved work is lost.
**Files:** `src/services/authService.ts` — `_scheduleRefresh` is a no-op stub.
**Recommendation:** Implement a token refresh before expiry, or show a "session expiring" warning with an option to re-authenticate in a modal without losing the current view.

---

### M-02 — No Offline / Network Error Recovery

**Problem:** When Strapi is unreachable, components show their last-known data (if any) or empty states silently. The `strapi-network-error` Toast fires once but does not retry or indicate which views are stale. There is no "last updated" timestamp visible to the user on most views.
**Recommendation:** Add visible staleness indicators to auto-refreshing views (timestamp of last successful fetch).

---

*Concerns audit: 2026-03-20*
