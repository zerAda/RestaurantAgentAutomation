# Kiosk App — Production Readiness Findings
**Analysis date:** 2026-03-21
**Analyst:** GSD Explore Agent

## Summary
- **P0 (Critical)**: 6 findings
- **P1 (Important)**: 8 findings
- **P2 (Nice to have)**: 7 findings

---

## P0 — Critical (must fix before prod)

### K-P0-01: Missing VITE_N8N_URL in Kiosk Env Config
- **File**: `kiosk-app/.env.example` line 24 (commented)
- **Root cause**: `VITE_N8N_URL` is referenced in `src/services/strapiClient.ts` line 70 and `src/utils/tracking.ts` line 8, but `.env.example` doesn't list it as required. The fallback hardcodes a VPS URL.
- **Fix**: Add `VITE_N8N_URL=https://api.${DOMAIN_NAME}` to `.env.example`. Update compose to inject `VITE_N8N_URL: https://api.${DOMAIN_NAME}`.

### K-P0-02: VITE_KIOSK_SECRET Exposed in Frontend Build
- **File**: `kiosk-app/src/services/strapiClient.ts` line 76
- **Root cause**: `VITE_KIOSK_SECRET` is baked into the JS bundle at build time — visible in browser devtools. Vite VITE_* vars are always public.
- **Fix**: Move validation to gateway nginx or n8n auth middleware. Document in comments that this is a non-secret rate-limit key.

### K-P0-03: No Content-Type Validation for Image Assets
- **File**: `kiosk-app/src/services/menuService.ts` lines 56–59
- **Root cause**: Images fetched from Strapi with no Content-Type validation. Misconfigured Strapi could return HTML, breaking UI.
- **Fix**: Add `onError` handler to `<img>` elements with inline SVG fallback.

### K-P0-04: Uncaught Promise Rejection in Config Fetch
- **File**: `kiosk-app/src/context/CartContext.tsx` lines 66–76
- **Root cause**: `strapi.get('/api/system-config')` in useEffect has no try-catch. If CMS unreachable, loading spinner hangs forever with no user feedback.
- **Fix**: Wrap in try-catch, set `setConfigError(true)`, show warning badge.

### K-P0-05: No Fallback for Missing Product Image
- **File**: `kiosk-app/src/components/VerticalVideoFeed.tsx` line 216
- **Root cause**: `<img src={feed[index].url}` can 404. No fallback image loads, broken display on kiosk.
- **Fix**: Add `onError` handler with base64 inline SVG placeholder.

### K-P0-06: Order Total Not Recalculated Server-Side
- **File**: `kiosk-app/src/context/CartContext.tsx` lines 148–149 and `src/pages/CheckoutView.tsx` line 61
- **Root cause**: Frontend calculates and sends `total_cents` to Strapi. Comment (SEC-010) acknowledges untrusted but no server-side recalc evidence.
- **Fix**: Ensure n8n OrderFinalizer workflow recalculates line_total from order_items before payment.

---

## P1 — Important

### K-P1-01: Unused VITE_STRAPI_API_TOKEN in Env Config
- **File**: `kiosk-app/.env.example` line 12
- **Root cause**: Token documented but never used; all queries rely on public role. Misleads devs.
- **Fix**: Remove from `.env.example`, add comment explaining public-role approach.

### K-P1-02: Missing Error UI for Menu Fetch Failure
- **File**: `kiosk-app/src/services/menuService.ts` lines 121–123
- **Root cause**: If CMS down, loading spinner stays forever. No user feedback.
- **Fix**: Add try-catch in VerticalVideoFeed useEffect. Show "Menu Unavailable" card with retry button.

### K-P1-03: No Timeout for Checkout Submission
- **File**: `kiosk-app/src/pages/CheckoutView.tsx` line 66
- **Root cause**: n8n webhook call has no timeout. If webhook hangs, spinner never stops.
- **Fix**: Add 15s timeout. On timeout show: "Submission timeout. Please retry or contact staff."

### K-P1-04: Hardcoded n8n Webhook URL Fallback in Tracking
- **File**: `kiosk-app/src/utils/tracking.ts` line 8
- **Root cause**: Fallback `https://n8n.srv1258231.hstgr.cloud` breaks on domain change. Fails silently.
- **Fix**: Use `import.meta.env.VITE_N8N_URL`. If undefined, skip tracking gracefully.

### K-P1-05: No XSS Protection on Product Titles/Descriptions
- **File**: `kiosk-app/src/components/VerticalVideoFeed.tsx` lines 298–302
- **Root cause**: Product title/description rendered directly from Strapi. React escapes by default but test with malicious strings.
- **Fix**: Verify React escaping covers all injection vectors. Add sanitization for any `dangerouslySetInnerHTML` uses.

### K-P1-06: Missing 429 Rate Limit Feedback
- **File**: `kiosk-app/src/services/strapiClient.ts` line 48
- **Root cause**: 429 shows generic error. On shared kiosk, users may restart app.
- **Fix**: Check for 429 and show: "Too many requests. Please wait 30 seconds."

### K-P1-07: No Offline Fallback
- **File**: `kiosk-app/src/components/VerticalVideoFeed.tsx` lines 121–130
- **Root cause**: FALLBACK_FEED shows "Initializing Matrix..." when offline. No user feedback.
- **Fix**: After 5 failures, show offline badge, serve from localStorage cache with "Last updated: X hours ago".

### K-P1-08: CORS Validation for Strapi Requests
- **File**: `kiosk-app/src/services/menuService.ts` line 121
- **Root cause**: Compose injects correct VITE_STRAPI_URL (gateway proxy) but no test validates CORS response.
- **Fix**: Always route through gateway `/v1/strapi/...`. Add smoke test for CORS headers.

---

## P2 — Nice to have

### K-P2-01: Missing Aria Labels (Accessibility)
### K-P2-02: No Bundle Size Monitoring in CI
### K-P2-03: Idle Timeout Countdown Missing
### K-P2-04: No Skeleton Loading States
### K-P2-05: No Analytics Dashboard for Funnel Events
### K-P2-06: Hardcoded Google Review URL in FortuneWheelView
- **File**: `kiosk-app/src/pages/FortuneWheelView.tsx` line 24
- **Root cause**: `https://g.page/r/example/review` placeholder. 404 in prod.
- **Fix**: Load from Strapi system-config `google_review_url` field.

### K-P2-07: No Service Worker for Offline Resilience

---

## Architecture Notes
- React 19 + TypeScript 5.9 strict mode
- Vite 6 + TailwindCSS 4 + Framer Motion
- CartContext (state), Service Layer (API), ErrorBoundary (auto-reload 10s), IdleTimer (120s reset)
- i18n: FR, AR, EN with RTL support
- Build: `node:20-alpine` → `nginxinc/nginx-unprivileged:1.27` (two-stage, good)
- Menu/config cached in localStorage with 5-min TTL
- Compose correctly injects `VITE_STRAPI_URL: https://api.${DOMAIN_NAME}/v1/strapi`
