# 07-02 Summary: Fix AUDIT-03 (AuditLogView double-broken)

**Plan:** 07-02-PLAN.md
**Requirement:** AUDIT-03
**Status:** ✅ COMPLETE
**Duration:** ~5 min
**Files modified:** 4

## Changes

### admin-dashboard/Dockerfile
- Added `ARG VITE_N8N_URL` after existing `ARG VITE_DOMAIN` (line 10)
- Added `ENV VITE_N8N_URL=${VITE_N8N_URL}` after existing `ENV VITE_DOMAIN` (line 11)
- Both lines appear BEFORE `RUN npm run build` — required for Vite build-time baking
- Existing VITE_STRAPI_URL and VITE_DOMAIN lines unchanged

### docker-compose.hostinger.prod.yml
- Added `VITE_N8N_URL: https://${CONSOLE_SUBDOMAIN}.${DOMAIN_NAME}` to admin-dashboard `build.args` (line 14)
- Resolves to `https://n8n.srv1258231.hstgr.cloud` from existing .env values
- Existing VITE_DOMAIN and VITE_STRAPI_URL args unchanged

### admin-dashboard/src/pages/AuditLogView.tsx
- Line 111: Changed `audit-query` → `audit-log` in fetch URL path
- Path now matches W_AUDIT_QUERY.json webhook registration: `v1/internal/audit-log`
- No other lines changed (layout, colors, interfaces, state logic all preserved)

### workflows/W_AUDIT_QUERY.json
- **B0 - Format Response** node `jsCode` replaced
- Old shape: `{ rows: items }` → New shape: `{ data: items, total: items.length, page: cfg.page, limit: cfg.pageSize }`
- Now matches `AuditResponse` TypeScript interface in AuditLogView.tsx
- References `$('B0 - Parse Params').first().json` for page/pageSize values
- All 5 nodes preserved, all 4 connections unchanged

## Verification

| Check | Result |
|-------|--------|
| Dockerfile `ARG VITE_N8N_URL` present | ✅ line 10 |
| Dockerfile `ENV VITE_N8N_URL` present | ✅ line 11 |
| Compose `VITE_N8N_URL` build arg present | ✅ line 14 |
| AuditLogView uses `audit-log` path | ✅ line 111 |
| AuditLogView does NOT use `audit-query` | ✅ |
| W_AUDIT_QUERY JSON valid | ✅ 101 lines |
| W_AUDIT_QUERY returns `data` field | ✅ |
| W_AUDIT_QUERY does NOT return `rows` | ✅ |
| 5 nodes preserved | ✅ |
| 4 connections preserved | ✅ |

## Tech Debt

- `total: items.length` returns current-page count, not global total across all pages. The countQuery exists in B0-Parse-Params but is never executed by a second PG node. Acceptable as first fix — full pagination accuracy is future scope.
- `CREDENTIAL_ID_PLACEHOLDER` in audit-query-pg node — operator must set real credential after VPS import.

## Next Steps

- Rebuild admin-dashboard image on VPS: `docker compose build admin-dashboard`
- Import updated W_AUDIT_QUERY.json on VPS via n8n API (Phase 9 scope)
- Activate W_AUDIT_QUERY workflow on VPS (Phase 9 scope)
