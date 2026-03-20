# Codebase Concerns

**Analysis Date:** 2026-03-16

## Tech Debt

**CMS Route Files (P0-4 Runtime Hack)**
- Issue: Previously missing route/controller/service files for `ingredient`, `system-config`, `restaurant-brand`, `delivery-assignment`, `feedback`, `supplier`, `marketing-campaign`, `loyalty-tier` injected at runtime via `docker cp` with world-readable permissions (644)
- Files: `/app/dist/src/api/*/routes/*.js`, `/app/dist/src/api/*/controllers/*.js`, `/app/dist/src/api/*/services/*.js` in CMS container (not persisted in source)
- Impact: Files lost on container recreation; admin dashboard shows empty data until routes are re-injected; any CMS rebuild breaks Strapi until manual fix applied
- Fix approach: Create TS source files in `./project/inventory-cms/src/api/` for all missing routes, rebuild CMS image with `docker compose build cms`, and test route availability via `GET /api/system-config` (singleType)

**Kiosk/Admin Dashboard Build Configuration**
- Issue: Build-time environment variables `VITE_STRAPI_URL` and `VITE_DOMAIN` are baked into container images; if `https://cms.srv1258231.hstgr.cloud` ever changes, both images must be rebuilt
- Files: `project/admin-dashboard/Dockerfile`, `project/kiosk-app/Dockerfile` (build args), `docker-compose.hostinger.prod.yml` (lines 13, 272)
- Impact: Domain/infrastructure changes require full rebuild; current hardcoding is production-critical for the admin dashboard (`/v1/portal` proxy trick doesn't work without correct CORS origin)
- Fix approach: Inject env vars at runtime via nginx rewrite or server-side template; alternatively, document and automate the rebuild pipeline for infrastructure changes

**Admin Dashboard Session Storage (F-02 Partial Fix)**
- Issue: `authService.ts` stores JWT in `sessionStorage` but also checks `localStorage` as fallback; no cleanup mechanism if user logs out of one tab and continues using another
- Files: `project/admin-dashboard/src/services/authService.ts` (lines 8-12, 31, 83-85)
- Impact: Low — sessionStorage is tab-isolated by design; fallback to localStorage is for legacy browsers only
- Fix approach: Remove localStorage fallback if legacy browser support is not required; document session isolation behavior

**n8n Task-Runner Still Spawning**
- Issue: `N8N_RUNNERS_ENABLED=false` set in `docker-compose.hostinger.prod.yml` (lines 377, 518) but n8n 2.9.4 still spawns task-runner subprocesses
- Files: `project/docker-compose.hostinger.prod.yml` (lines 377, 518)
- Impact: CPU load was 28% peak, now normalized to 9.6%; env var may have no effect in n8n 2.x or runners are spawned before env loaded
- Fix approach: Investigate if env var is actually being passed to n8n process; consider upgrading to n8n 3.x where task-runner was redesigned; monitor load over time to confirm it's stable

**Nginx DNS Cache (Fixed but Not Permanent)**
- Issue: After CMS container restart, nginx cached the old DNS IP (172.19.0.4) for `cms:1337`; all requests returned 502 until manual reload
- Files: `project/infra/gateway/nginx.conf` (lines 71-72) — permanent fix applied
- Impact: Medium — any CMS restart can cause 5-minute API outage until someone notices and reloads nginx
- Fix approach: Confirmed — `resolver 127.0.0.11 valid=10s; set $cms_upstream http://cms:1337;` now in place; adds DNS refresh every 10 seconds

**91 n8n Workflow Files (77 Active on VPS)**
- Issue: 91 workflow JSON files exist in `./project/workflows/` but only 76-77 are active on production VPS as of 2026-03-07; unclear which are dead code, duplicates, or backups
- Files: `project/workflows/` (91 JSON files)
- Impact: Maintenance burden; unknown workflows may shadow production workflows if naming conflicts exist; no audit trail for workflow lifecycle
- Fix approach: Document each workflow's purpose, active status, and last update date; remove confirmed dead code; implement workflow versioning in n8n

---

## Known Bugs

**Admin Dashboard Auto-Logout (Fixed in v3.4.3)**
- Symptoms: User logs into admin dashboard, immediately redirected to login screen on any API call
- Root cause: `authService.ts` was calling `/admin/login` (Strapi admin API) which returns admin JWT, but that JWT doesn't work on `/api/*` content endpoints (users-permissions API) → all requests returned 401 → auto-logout
- Files: `project/admin-dashboard/src/services/authService.ts` (lines 19-43) — FIXED
- Current status: RESOLVED — changed to `/api/auth/local` endpoint (users-permissions) with correct payload parsing
- Workaround: None needed; fixed in commit `65e84d7`

**Kiosk No Products Display (Fixed in v3.4.5)**
- Symptoms: Kiosk app shows empty menu; no products visible even though 6 are seeded in Strapi
- Root cause 1: Browser CORS blocked by duplicate `Access-Control-Allow-Origin` headers from Strapi + nginx
- Root cause 2: Strapi sends `Cross-Origin-Resource-Policy: same-origin` → blocks cross-subdomain fetch from `kiosk.*` to `cms.*`
- Files: `project/infra/gateway/nginx.conf` (lines 340-404) — FIXED
- Current status: RESOLVED — nginx now strips Strapi's CORS headers and replaces with single correct header + `Cross-Origin-Resource-Policy: cross-origin`
- Test result: `GET /v1/strapi/api/products` returns 6 products with correct CORS headers ✓

**Strapi `published_at` Collision**
- Symptoms: `content_library` collection fails to create — SQL error `column "published_at" specified more than once`
- Root cause: Strapi 5 automatically adds `published_at` as a system column even with `draftAndPublish: false`; schema also defined a custom `published_at` field → collision
- Files: `project/inventory-cms/src/api/content-library/content-library.ts` (schema definition) — FIXED
- Current status: RESOLVED — custom field renamed to `content_published_at`
- Workaround: None needed; schema fixed in migration

**Gateway 502 on CMS Restart**
- Symptoms: After CMS container restart, all `/v1/strapi/*` requests return 502 `connect() failed (111: Connection refused)`
- Root cause: nginx cached DNS IP of `cms:1337` at startup (172.19.0.4); CMS got new IP (172.19.0.6) → nginx kept sending traffic to old IP
- Files: `project/infra/gateway/nginx.conf` (lines 71-72) — FIXED
- Current status: RESOLVED — DNS resolver with 10s TTL now forces refresh
- Immediate fix: `docker exec current-gateway-1 nginx -s reload` (no longer needed with permanent fix)

---

## Security Considerations

**Query String Token Leakage (Fixed in v3.4.2 / P0-SEC-01)**
- Risk: Tokens passed as query params (`?token=...`) leak to server logs, referrer headers, browser history, and bookmarks
- Files: `project/infra/gateway/nginx.conf` (lines 106-118) — ACTIVE
- Current mitigation: Nginx explicitly blocks requests with `?token=`, `?access_token=`, `?api_token=`, `?webhook_token=` query params; returns 401 with message "Tokens must be sent via Authorization header"
- Recommendations: Enforce Authorization header in all client SDKs; periodically audit logs for any token= usage

**Cortex Data Token Exposure (Fixed in v3.4.2 / C4-TOKEN_LEAK)**
- Risk: `strapiClient.getCortexData()` was passing JWT as `?token=` query param → leaked in logs and browser history
- Files: `project/admin-dashboard/src/services/strapiClient.ts` (line 174) — FIXED
- Current mitigation: Token now sent via `Authorization: Bearer` header only (OWASP A07 / Sensitive Data Exposure fixed)
- Recommendations: Audit all fetch calls in admin-dashboard to confirm headers-only auth

**Control Plane Dashboard Unauthenticated (Fixed in v3.4.2 / C5-CTRL_PLANE_AUTH)**
- Risk: `ControlPlaneView.tsx` was making raw unauthenticated `fetch()` to `/api/control-plane/status` → any network observer could read system metrics
- Files: `project/admin-dashboard/src/pages/ControlPlaneView.tsx` (lines 29-32) — FIXED
- Current mitigation: Now uses `strapi.rawGet()` which includes `Authorization: Bearer` header automatically
- Recommendations: Verify no other components use raw fetch; audit all `/api/*` calls to use `strapiClient` methods

**Meta Signature Enforcement (Fixed in v3.4.2 / C2-META_SIG_ENFORCE)**
- Risk: Unenforced Meta webhook signature validation means anyone can forge webhook events (order messages, delivery updates, etc.)
- Files: `.env.example`, `docker-compose.hostinger.prod.yml` (n8n-main/worker env) — ACTIVE
- Current mitigation: `META_SIGNATURE_REQUIRED=enforce` now default; nginx rejects unsigned requests at `POST /v1/inbound/*`
- Recommendations: Verify n8n W0/W1/W2/W3 workflows actually validate signatures; document signature key rotation procedure

**Redis Authentication (Partially Implemented in v3.4.2 / C3-REDIS_AUTH)**
- Risk: Redis exposed internally on `internal` network without password; any container could flush data or inject commands
- Files: `infra/redis/entrypoint.sh` (optional password support), `docker-compose.hostinger.prod.yml` (REDIS_PASSWORD env)
- Current mitigation: Optional Redis password via `REDIS_PASSWORD` env var; passed to n8n-main, n8n-worker, cms, control-plane controller
- Recommendations: REQUIRE Redis password in .env; generate strong password (32 char); rotate quarterly

**Strapi Admin Password in Secrets File (Fixed in v3.4.2 / W3-STRAPI_PASSWORD)**
- Risk: `docker-entrypoint.sh` reads `STRAPI_SUPER_ADMIN_PASSWORD` from env var; if env var contains file path (e.g., `/run/secrets/strapi_admin_password`), must read the file not use the path as literal password
- Files: `project/inventory-cms/docker-entrypoint.sh` — FIXED
- Current mitigation: Entrypoint checks if env var points to a file and reads it; prevents secret file paths from being set as literal password
- Recommendations: Document secret injection in deployment runbook

**Traefik IP Allowlist Coverage**
- Risk: `console.*` (n8n) and `cms.*` (Strapi) protected by IP allowlist via Traefik, but admin dashboard CORS is handled by browser; if admin origin is compromised, attacker can bypass BasicAuth and read data via fetch
- Files: `docker-compose.hostinger.prod.yml` (Traefik labels for admin-dash, cms, n8n-main)
- Current mitigation: Triple auth layer for admin-dash: Traefik IP allowlist → Traefik BasicAuth → Strapi JWT (but JWT now sent via `/v1/portal` proxy which requires no extra auth since proxy is internal-only)
- Recommendations: Consider re-introducing client certificate auth (mTLS) for extra defense-in-depth

---

## Performance Bottlenecks

**Strapi CMS 8-Minute Cold Start (Strapi 5 Overhead)**
- Problem: First CMS container boot takes ~8 minutes; 81 tables created from scratch; npm ci takes 15-30 minutes on 2-core VPS
- Files: `project/inventory-cms/` (Strapi 5 full suite)
- Cause: Strapi 5 schema introspection, database initialization, and node_modules install all run sequentially on startup; no caching or optimization
- Improvement path:
  1. Pre-build CMS image with installed node_modules (saves 15-30 min)
  2. Cache DB schema introspection if migrations haven't changed
  3. Lazy-load unused plugins (strapi-plugin-menus, media, etc. may not all be needed)
  4. Monitor: `docker compose logs cms | grep -i "starting\|error\|took"` to track startup time

**n8n Webhook Verification Latency (No Real-Time Verification)**
- Problem: Meta webhooks (WhatsApp, Instagram, Messenger) must verify in < 5 seconds; current n8n latency ~2-3 seconds leaves little buffer; if queue backs up, verification might timeout and Meta retries 5 times → platform suspension
- Files: `project/workflows/W0_META_VERIFY_WA.json` and variants (n8n webhook nodes)
- Cause: n8n 2.x in queue mode has variable latency depending on worker availability and Redis queue depth; verification node must run synchronously
- Improvement path:
  1. Monitor webhook verification P95 latency via Prometheus/DataDog
  2. Implement dedicated `high-priority` n8n queue for verification workflows
  3. Cache Meta webhook validation key in Redis (30-min TTL) to skip N8N API calls
  4. Alert if P95 > 3 seconds

**PostgreSQL Query Performance on Order Workflows**
- Problem: `enqueue_wa_order_status` (W26) updates `orders` table with new status; if 1000+ orders pending, UPDATE can lock table briefly → subsequent orders queued behind lock
- Files: `project/workflows/` (order-related workflows W11, W26, W37, etc.)
- Cause: Likely missing index on `orders (status, created_at)` or `orders (customer_id, status)`
- Improvement path:
  1. Add migration: `CREATE INDEX idx_orders_status_created ON orders(status, created_at);`
  2. Profile slow queries: `EXPLAIN ANALYZE SELECT ... FROM orders WHERE ...`
  3. Consider denormalizing order count to `customers.pending_order_count` if dashboard queries it frequently

**Admin Dashboard React Bundle Size**
- Problem: Admin dashboard build contains full feature set (15+ views) as single bundle; kiosk loads CMS menus on every render
- Files: `project/admin-dashboard/src/` (45+ component files)
- Cause: No code splitting; all views bundled together; kiosk API calls on mount + re-render
- Improvement path:
  1. Enable React Router lazy() code splitting for each view (`GrowthAgentView`, `KitchenView`, etc.)
  2. Cache kiosk menu fetch in Redis (5-min TTL) with ETag validation
  3. Profile bundle: `npm run build && npm run analyze` to identify large dependencies

---

## Fragile Areas

**Strapi CMS Route Injection (P0-4 Workaround)**
- Files: `project/inventory-cms/src/api/*/routes/*.js`, `/controllers/*.js`, `/services/*.js`
- Why fragile: Routes for `ingredient`, `system-config`, `restaurant-brand`, etc. were missing from source and manually injected via `docker cp` at runtime; any CMS rebuild reverts changes; no migration ensures routes exist
- Safe modification:
  1. Add TS source files to `./project/inventory-cms/src/api/[name]/` for each missing route
  2. Run `docker compose build cms` to bake routes into image
  3. Test: `curl -H "Authorization: Bearer $TOKEN" http://localhost:1337/api/system-config` should return singleType data
  4. Rebuild admin-dashboard and kiosk to use new routes
- Test coverage: No tests verify route existence; integration tests should check all 15+ API routes return 200/data

**Admin Dashboard `strapiClient` Token Fallback (F-02 Partial)**
- Files: `project/admin-dashboard/src/services/strapiClient.ts` (lines 29-31)
- Why fragile: `getToken()` checks `sessionStorage` first, then `localStorage` fallback; if legacy browser fails, fallback may read stale token
- Safe modification:
  1. Confirm legacy browser requirements; if not needed, remove localStorage fallback
  2. Add logs: `console.log('Token source:', _token ? 'injected' : 'session' : 'fallback')` to track usage
  3. Test: Open DevTools, clear localStorage, verify app still works
- Test coverage: No unit tests for token retrieval; add test case `getToken() returns null if storage empty`

**n8n Queue Mode Worker Scaling (Implicit Concurrency)**
- Files: `project/docker-compose.hostinger.prod.yml` (lines 525-550, env `QUEUE_BULL_MAX_CONCURRENCY`)
- Why fragile: Single `n8n-worker` container with `QUEUE_BULL_MAX_CONCURRENCY` (default 2) handles all background jobs; if workflow processing is slow, queue builds up; no auto-scaling
- Safe modification:
  1. Monitor queue depth: `docker exec current-n8n-main-1 n8n list:executions | wc -l`
  2. If queue_depth > 50, increase worker concurrency: `QUEUE_BULL_MAX_CONCURRENCY=4` and rebuild
  3. Consider adding second `n8n-worker` container with same config if single worker can't catch up
  4. Set alerts: if `pending_execution_count > 100 for 5min`, page on-call
- Test coverage: No load tests for queue depth; add: "submit 500 orders in 30s, verify all process within 5min"

**Gateway Nginx Configuration (Complex Routing)**
- Files: `project/infra/gateway/nginx.conf` (445 lines)
- Why fragile:
  1. 8 rate-limit zones with different keys (IP, token, per-endpoint)
  2. Error page tricks (`error_page 418 = @whatsapp_get`) to work around "if is evil" pattern
  3. Multiple named locations (@whatsapp_get, @instagram_post, etc.) — any location rule change could break routing
  4. CORS headers added at multiple points (kiosk, admin, default) with potential for duplicates
- Safe modification:
  1. Never change rate limits without testing: `ab -n 100 -c 10 https://api.srv1258231.hstgr.cloud/v1/inbound/whatsapp`
  2. Test all 8 locations individually: curl each endpoint and verify it reaches correct upstream
  3. Verify CORS headers are single (no duplicates): `curl -I -H "Origin: https://kiosk.*" ... | grep Access-Control`
  4. Document the error_page trick: add comment explaining why error_page 418/419 is used
- Test coverage: No tests for nginx routing; add smoke test for each location

**Ollama + Whisper Optional Dependency (AI Profile)**
- Files: `project/docker-compose.hostinger.prod.yml` (profiles: ai, lines 558-595)
- Why fragile: If `--profile ai` not used on start, Ollama/Whisper don't run; any workflow that depends on `$LLM_API_URL` will silently fail if Ollama is down
- Safe modification:
  1. Make Ollama health check mandatory in n8n: wrap all LLM calls in try/catch with fallback
  2. Document: "AI profile is optional; without it, LLM features disabled but platform still works"
  3. Test: `docker compose --profile ai up` and verify `GET http://ollama:11434/api/models` returns 200
  4. In workflows: check Ollama health before LLM calls; return user-friendly message if Ollama unreachable
- Test coverage: No tests verify fallback behavior if Ollama down

---

## Scaling Limits

**PostgreSQL Connection Pool (n8n + Strapi)**
- Current capacity: Default 20 connections per client (n8n, cms); max 100 total on VPS
- Limit: When n8n queue depth > 50, worker threads may exhaust connections → "too many connections" errors → new workflows queue indefinitely
- Scaling path:
  1. Monitor: `SELECT count(*) FROM pg_stat_activity;` (target: < 80)
  2. If hitting limits, increase `PGMAXCONNECTIONS` in PostgreSQL config (default 100)
  3. Scale by adding second n8n-worker container (adds ~20 new connections)
  4. Consider PgBouncer for connection pooling if > 5 services need database access

**Redis Memory (Outbox Queue + Cache)**
- Current capacity: 256MB allocated; no eviction policy set (LRU recommended)
- Limit: If daily outbound messages > 100k, Redis queue can exceed 256MB → eviction or OOM kill
- Scaling path:
  1. Monitor: `docker exec current-redis-1 redis-cli INFO memory` (target: < 200MB used)
  2. Set eviction policy: `LATENCY LATEST; CONFIG SET maxmemory-policy allkeys-lru`
  3. If queue > 90% capacity, implement message batching: write 10 messages per Redis key instead of 1
  4. Scale by upgrading to 512MB if daily volume > 50k messages/day

**n8n Queue Processing Latency (Bull + Redis)**
- Current capacity: 2 concurrent workflows per worker; P95 workflow completion ~ 30 seconds
- Limit: If workflow arrival rate > 2/30sec = ~0.067/sec (4 per minute), queue builds indefinitely
- Scaling path:
  1. Monitor: n8n UI → Executions tab, check "Queued" count (target: < 10)
  2. If queued > 50, profile slowest workflows: add timers to identify bottleneck steps
  3. Scale by:
     - Increase `QUEUE_BULL_MAX_CONCURRENCY` to 4-6 per worker
     - Add second `n8n-worker` container (doubles throughput)
     - Optimize slow nodes: batch Strapi calls, cache responses
  4. If concurrency > 10, consider separate queue server (Redis Cluster)

**Disk Space (119GB VPS Drive)**
- Current usage: ~700MB code, ~4GB node_modules, ~2GB database, logs fill rest
- Limit: Once < 5GB free, ENOSPC errors corrupt JSON files (workflows, config) to 0 bytes; system becomes unrecoverable
- Scaling path:
  1. Monitor: `df -h /opt/resto` (alert if < 10GB free)
  2. Regular cleanup: `npm cache clean --force` (frees ~5GB), remove old releases: `rm -rf /opt/resto/releases/0-50`
  3. Log rotation: Set up `logrotate` to compress logs > 30 days old
  4. Backup: Before disk hits 50%, backup `/opt/resto/` to S3 or secondary storage
  5. If near limit, upgrade VPS to 250GB disk (Hostinger upgrade)

---

## Dependencies at Risk

**n8n 2.9.4 → 3.x Migration Debt**
- Risk: n8n 2.x is in maintenance mode; 3.x has major breaking changes (task-runner redesign, workflow schema, credential types)
- Impact: Task-runner env var `N8N_RUNNERS_ENABLED` may be ignored in 2.9.4; upgrading to 3.x required for full fix
- Migration plan:
  1. Create branch: `git checkout -b upgrade/n8n-3.x`
  2. Update `.env` N8N_VERSION from 2.9.4 → 3.0.0
  3. Run integration tests: all 54 workflows must execute without 500 errors
  4. Verify webhook paths unchanged (n8n 3.x changed webhook structure)
  5. Test queue mode: n8n-main + n8n-worker + Redis must still work
  6. Rollback plan: Revert N8N_VERSION, restart containers; old images cached in GHCR

**Strapi 5.37.1 → 5.x Latest**
- Risk: Strapi 5 rapidly evolving; minor updates may introduce schema changes or plugin incompatibilities
- Impact: `npm ci` in Strapi may fail if dependencies have breaking changes in patch versions
- Migration plan:
  1. Update `package-lock.json` in `inventory-cms/`: `npm update --save` in local dev, test, commit
  2. Rebuild CMS image: `docker compose build cms`
  3. Test schema: `curl http://localhost:1337/_health` must return 200
  4. Verify all routes still exist: `curl http://localhost:1337/api/products`, `/api/orders`, etc.
  5. No rollback needed; CMS image rebuild is atomic

**Node.js 18.x LTS → 20.x (In node_modules)**
- Risk: Node 18 reached EOL 2024-04-30; security vulnerabilities may not be patched
- Impact: Admin-dashboard and kiosk Dockerfile use `node:18-alpine` as base
- Migration plan:
  1. Update both Dockerfile base images: `node:18-alpine` → `node:20-alpine`
  2. Rebuild: `docker compose build admin-dashboard kiosk-app`
  3. Test: Admin dashboard login, kiosk product display must work
  4. Verify npm ci still works with newer npm version in Node 20
  5. No code changes needed; Node 20 is backward compatible with 18

**React 18 + React Query (admin-dashboard)**
- Risk: React 18 has strict mode issues with effects running twice; React Query (TanStack) has version incompatibilities
- Impact: Admin dashboard may have race conditions or memory leaks if React Query version drifts
- Migration plan:
  1. Update package-lock.json: `npm update --save` in admin-dashboard/
  2. Check for deprecated APIs: `grep -r "useQuery\|useMutation" src/ | grep -v "useQuery\|useMutation\|QueryClient"`
  3. Test: All dashboard views (AnalyticsView, KitchenView, etc.) must render without console errors
  4. Rollback: `git checkout admin-dashboard/package-lock.json && npm ci`

---

## Missing Critical Features

**Workflow Audit Trail (Not Logged)**
- Problem: When n8n workflows execute, no audit log records who triggered it, what data was processed, or what actions were taken
- Blocks: Compliance (GDPR requires data processing logs), debugging (can't trace which workflow created an order), rollback (no history)
- Estimated effort:
  1. Add `workflow_executions_audit` table (workflow_id, executor, inputs_hash, outputs_hash, timestamp)
  2. Middleware in n8n to log execution start/end
  3. Admin dashboard view to search audit log
  4. Retention policy: keep 90 days, then archive

**Database Backup Automation (Manual)**
- Problem: No documented, automated backup of PostgreSQL; data loss would be catastrophic
- Blocks: RTO/RPO requirements (if DB corrupted, no way to recover), disaster recovery planning
- Estimated effort:
  1. Create `scripts/backup.sh`: `pg_dump` to `/opt/resto/backups/` with date suffix
  2. Add cron job on VPS: `0 2 * * * /opt/resto/scripts/backup.sh` (daily at 2 AM)
  3. Add restore test: monthly restore backup to test instance
  4. Sync backups to S3: `aws s3 sync /opt/resto/backups/ s3://resto-backups/`

**Observability: Structured Logging (Not Implemented)**
- Problem: Logs are unstructured text (grep-able but not queryable); no correlation IDs across services; no log aggregation
- Blocks: Debugging production issues, SLO monitoring, performance analysis
- Estimated effort:
  1. Add JSON logging to n8n workflows: wrap all `console.log()` with structured format `{level, timestamp, workflow_id, message, data}`
  2. Stream logs to ELK stack or Loki (open-source)
  3. Add Grafana dashboard for error rates, latency percentiles, queue depth
  4. Set up alerts: error_rate > 5%, workflow_latency_p95 > 30s

**Rate Limit Analytics (Current: Blind)**
- Problem: Current nginx rate limiting blocks requests but logs no metrics; unknown if legitimate traffic is being blocked
- Blocks: Capacity planning, DDoS detection, tuning rate limits
- Estimated effort:
  1. Add Prometheus metrics export from nginx: `prometheus-nginx-module`
  2. Track: requests_blocked_by_zone, burst_events, top_ips
  3. Grafana dashboard to visualize rate limit hits by endpoint
  4. Tune limits based on data (currently hardcoded: 10r/s for Meta, 30r/s for kiosk)

---

## Test Coverage Gaps

**Nginx Routing (Zero Test Coverage)**
- What's not tested: Whether all 8 nginx locations (whatsapp, instagram, messenger, strapi, portal, customer, internal, admin) actually route to correct upstreams; CORS headers are not duplicated; rate limits are enforced
- Files: `project/infra/gateway/nginx.conf` (445 lines of routing logic)
- Risk: High — routing bug could break entire public API; CORS bug blocks kiosk; rate limit bypass allows DDoS
- Priority: High — add smoke test suite:
  ```bash
  # Test each location
  curl -X POST https://api.srv1258231.hstgr.cloud/v1/inbound/whatsapp -d '{}' -H "Content-Type: application/json"
  curl https://api.srv1258231.hstgr.cloud/v1/strapi/api/products
  curl -X POST https://api.srv1258231.hstgr.cloud/v1/strapi/api/orders -d '{}' -H "Content-Type: application/json"

  # Test CORS headers (no duplicates)
  curl -I -H "Origin: https://kiosk.srv1258231.hstgr.cloud" https://api.srv1258231.hstgr.cloud/v1/strapi/api/products | grep -c "Access-Control-Allow-Origin"  # Should be 1

  # Test rate limiting (burst = 20, should allow first 20, block 21st)
  for i in {1..25}; do curl -s https://api.srv1258231.hstgr.cloud/v1/inbound/whatsapp -d '{}' 2>&1 | grep -q "400\|200" && echo "Request $i"; done
  ```

**Strapi Permission Matrix (Zero Test Coverage)**
- What's not tested: Whether public role can view products, authenticated role can CRUD orders, admin role can do everything
- Files: `project/inventory-cms/` (no permission tests; permissions set manually in DB)
- Risk: High — any manual permission change could break kiosk or admin dashboard silently
- Priority: High — add integration test:
  ```typescript
  // test: kiosk anon user can view products
  const products = await fetch('https://api.srv1258231.hstgr.cloud/v1/strapi/api/products');
  expect(products.status).toBe(200);
  expect(products.data.length).toBeGreaterThan(0);

  // test: admin user can CRUD orders
  const orderRes = await fetch('https://api.srv1258231.hstgr.cloud/v1/portal/api/orders', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${adminJwt}` },
    body: JSON.stringify({ data: {...} })
  });
  expect(orderRes.status).toBe(201);
  ```

**n8n Workflow Execution (1 of 54 Workflows Has Tests)**
- What's not tested: Whether inbound workflows (W1-W3, W26) actually execute without errors; whether outbound messages are queued to Redis correctly; whether retry logic with exponential backoff works
- Files: `project/workflows/` (91 JSON files); `project/tests/` (minimal test harness)
- Risk: High — silent workflow failures could mean orders aren't being processed; customers see no order confirmation
- Priority: Critical — add end-to-end test:
  ```bash
  # Test: Webhook → W1 (WhatsApp inbound) → order created in DB
  curl -X POST https://api.srv1258231.hstgr.cloud/v1/inbound/whatsapp \
    -H "X-Hub-Signature-256: sha256=..." \
    -d '{...meta webhook payload...}' \
    && sleep 5 \
    && psql -c "SELECT count(*) FROM orders WHERE created_at > now() - interval 10s" | grep -E "1|[0-9]+" && echo "Order created ✓"
  ```

**Admin Dashboard Component Integration (Unmocked Strapi)**
- What's not tested: Whether admin dashboard components (AnalyticsView, KitchenView, GrowthAgentView, etc.) render without crashing when Strapi is down; whether error boundaries catch and display errors
- Files: `project/admin-dashboard/src/components/` (30+ components); `project/admin-dashboard/src/setup.test.ts` (minimal)
- Risk: Medium — if Strapi returns 500, admin dashboard crashes or shows blank screen instead of error message
- Priority: Medium — add integration tests:
  ```typescript
  // test: AnalyticsView shows error state if Strapi returns 500
  jest.mock('../services/strapiClient', () => ({
    strapi: { find: jest.fn().mockRejectedValue(new Error('500')) }
  }));

  render(<AnalyticsView />);
  expect(screen.getByText(/error|unavailable/i)).toBeInTheDocument();
  ```

**Strapi CMS Route Injection (No Verification)**
- What's not tested: Whether routes for ingredient, system-config, restaurant-brand, etc. actually exist and return data; whether missing routes would be detected
- Files: `project/inventory-cms/src/api/*/` (15+ routes)
- Risk: High — if routes are missing after rebuild, admin dashboard shows empty data and error is silent
- Priority: High — add smoke test:
  ```bash
  # Verify all critical routes exist (return 200, not 404)
  for route in products orders customers ingredients payment delivery-assignment funnel-event feedback supplier loyalty-tier system-config restaurant-brand driver; do
    status=$(curl -s -o /dev/null -w "%{http_code}" https://cms.srv1258231.hstgr.cloud/api/$route)
    [ "$status" = "200" ] && echo "✓ $route" || echo "✗ $route ($status)"
  done
  ```

---

*Concerns audit: 2026-03-16*
