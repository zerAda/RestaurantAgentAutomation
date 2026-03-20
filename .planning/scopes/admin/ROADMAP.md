# Admin Dashboard — Phase Roadmap

**Scope:** `project/admin-dashboard/` (React 19 + Vite SPA)
**Last updated:** 2026-03-20

---

## Priority Order

1. Critical runtime bugs — app is broken or showing wrong data without these
2. Security hardening — RBAC, token hygiene, credential hygiene
3. Performance — bundle splitting, polling optimization
4. Features — enhancements once the foundation is solid
5. Testing — coverage to prevent regression

---

## Phase 1: Critical Runtime Fixes

**Goal:** The app works correctly. No crashed components, no wrong prices, kitchen display filters real status.

**Requirements:** T-01, T-05, T-06, T-07, T-09

**Plans:** 2 plans

**Success Criteria:**
- `KitchenView` and `KitchenDisplay` mount without "No QueryClient set" error (T-01 fixed)
- Notification center shows order totals in DA without dividing by 100 (T-05 fixed; e.g. a 1200 DA order shows "1200 DA" not "12 DA")
- `KitchenDisplay` hides orders with status `'done'` and `'cancelled'` (T-06 fixed; lowercase filter matches Strapi enum)
- `QueryClient` configured with `staleTime: 5000, retry: 1` (T-07 fixed)
- `GodMode` kill switch uses `documentId` not numeric `id` (T-09 fixed)

**Rollback:** All changes are isolated TypeScript edits. Revert individual file changes via git. No DB migration, no API contract change.

---

## Phase 2: Security Hardening

**Goal:** No authenticated user automatically gets admin privileges. JWT is not accessible to XSS. No hardcoded credentials.

**Requirements:** S-01, S-02, S-03, S-04

**Plans:** 2 plans

**Success Criteria:**
- A user whose Strapi role `type` is `'authenticated'` but role `name` is not `'admin'` or `'super_admin'` cannot navigate to `/analytics`, `/control-plane`, or other admin-only routes (S-02 fixed)
- Chat history stored in `sessionStorage` not `localStorage` — cleared on tab close (S-01 fixed)
- `AIChatBubble` calls `authService.getToken()` instead of reading `admin_jwt` from storage directly (S-03 fixed)
- Portainer dead link removed or gated behind `VITE_PORTAINER_URL` env var (S-04 fixed)

**Rollback:** Pure TypeScript changes. No infra change. Revert individual files via git.

---

## Phase 3: Performance — Bundle Splitting & Polling Consolidation

**Goal:** Initial load parses a small core bundle. Admin-only views are lazy-loaded. Polling does not hammer Strapi with redundant calls every 10 seconds.

**Requirements:** T-02, T-03, T-04, P-01

**Plans:** 2 plans

**Success Criteria:**
- Vite build produces at minimum 4 separate chunks: `vendor` (react + react-dom + react-router), `charts` (recharts), `animation` (framer-motion), `markdown` (react-markdown + remark-gfm)
- All admin-only routes (`/analytics`, `/growth`, `/marketing`, `/automation`, `/ai-observatory`, `/control-plane`, `/brand`) use `React.lazy` + `Suspense`
- `dist/` removed from git tracking (added to `.gitignore`) so committed bundle no longer diverges from source
- `DashboardHome` previous-period queries use `staleTime: 5 * 60 * 1000` (do not re-fetch on every 30s tick)

**Rollback:** Vite config and import changes. No API or DB impact. Revert via git.

---

## Phase 4: Feature Completeness

**Goal:** AutomationView shows real workflow data. GrowthAgentView and AiObservatoryView are not dead stubs. AI chat session is isolated per user.

**Requirements:** T-08, M-01, M-02

**Plans:** 3 plans

**Success Criteria:**
- `AutomationView` fetches workflow list and status from Strapi `platform-settings` collection (not hardcoded)
- "Session expiring" warning shown 5 minutes before 24-hour JWT expiry; user can re-authenticate in a modal without losing the current view
- All auto-refreshing views show a "last updated" timestamp so users can see when data is stale
- AI chat `sessionId` includes the Strapi user `id` (e.g. `admin-dashboard-session-1`) so multiple admin users do not share agent memory

**Rollback:** All changes are additive UI/service layer. Revert individual files via git.

---

## Phase 5: Test Coverage

**Goal:** CI catches the class of bugs found in this audit. `authService`, `strapiClient` 401 handling, and `mapOrder` status normalization are unit-tested. A smoke Playwright test confirms login → dashboard renders.

**Requirements:** TC-01

**Plans:** 3 plans

**Success Criteria:**
- `npm test` passes (no placeholder truthiness test — real assertions)
- `authService.isAuthenticated()` tested: valid token returns true, expired token returns false and clears storage
- `strapiClient` 401 behavior tested: saves redirect path, calls logout
- `mapOrder()` tested: uppercase status input is normalized to lowercase OrderStatus
- `NotificationCenter` tested: renders zero-state when no notifications
- Playwright E2E: login flow succeeds with valid credentials, shows `/dashboard` with KPI cards

**Rollback:** Test files are additive. No production code changed. Revert test files via git.

---

## Phase 6: Observability & Long-Term Hygiene

**Goal:** Errors are tracked remotely (not just `console.error`). i18n covers more than sidebar labels. PII masking is consistent across all order-displaying views.

**Requirements:** None currently tracked (future enhancements)

**Plans:** 2 plans

**Success Criteria:**
- Runtime errors forwarded to a structured log endpoint (or Sentry if configured via `VITE_SENTRY_DSN`)
- Page titles, headers, and primary UI strings translated in EN/FR/AR (not just sidebar items)
- `maskPII()` applied consistently in `CustomerView`, `SupportView`, `NotificationCenter` alongside `OrdersKanban`

**Rollback:** All changes are additive. Revert via git.

---

## Dependency Order

```
Phase 1 (runtime bugs)
  └── Phase 2 (security) — depends on Phase 1: RBAC fix needs QueryClient working
        └── Phase 3 (performance) — can begin in parallel after Phase 1
              └── Phase 4 (features) — depends on Phase 2 + 3 complete
                    └── Phase 5 (testing) — tests the fixed codebase
                          └── Phase 6 (hygiene) — long-term polish
```

Phases 2 and 3 can run in parallel after Phase 1. Phase 4 needs both.
