# Roadmap: RESTO BOT — Platform Hardening & Reliability

## Overview

This milestone transforms RESTO BOT from a platform that works-in-practice into one that is
provably stable. Phase 1 eliminates the P0 CMS runtime-injection hack and upgrades Node.js to a
supported LTS. Phases 2-3 add structured observability so operators can see what the platform is
doing. Phases 4-5 add automated test coverage so regressions are caught before they reach
production. Phase 6 closes out with database indexes, Redis safety, and frontend bundle
optimizations that remove known performance ceilings. Every phase delivers a coherent, verifiable
capability — no horizontal layers, no partial features.

## Phases

- [ ] **Phase 1: CMS Stability & Base Upgrade** - Eliminate the docker-cp runtime hack; bake all 15 Strapi API routes into source; upgrade Node.js 18 -> 20 across all services
- [x] **Phase 2: Structured Logging & Correlation** - Add JSON structured logs with correlation IDs across n8n, Strapi, and Nginx so every request is traceable end-to-end (completed 2026-03-23)
- [ ] **Phase 3: Metrics, Alerting & Audit Trail** - Export queue/error metrics, add disk/memory alerts, and create a queryable workflow audit table
- [ ] **Phase 4: Test Coverage — Routing & Permissions** - Smoke-test all 8 nginx routing zones and validate the Strapi permission matrix with automated integration tests
- [ ] **Phase 5: Test Coverage — n8n Workflow E2E** - End-to-end tests for inbound adapters, outbox retry, and CI integration for workflow smoke tests
- [ ] **Phase 6: Performance Tuning** - Add DB indexes for orders queries, enforce Redis eviction policy, and split the admin dashboard JS bundle
- [ ] **Phase 7: NemoClaw Telegram Bot** - Fix NVIDIA NIM config, async bridge with typing keepalive, error handling with retries, systemd auto-restart

## Phase Details

### Phase 1: CMS Stability & Base Upgrade
**Goal**: The CMS build is self-contained; all 15 Strapi API routes exist in TypeScript source and survive any container rebuild; all frontend Dockerfiles use a supported Node.js LTS
**Depends on**: Nothing (first phase)
**Requirements**: CMS-01, CMS-02, CMS-03, INFRA-01, INFRA-02, INFRA-03
**Success Criteria** (what must be TRUE):
  1. Running `docker compose build cms` from a clean state produces an image where all 15 API routes (ingredient, system-config, restaurant-brand, delivery-assignment, feedback, supplier, marketing-campaign, loyalty-tier, and 7 others) respond correctly — no manual `docker cp` required
  2. A freshly started CMS container returns expected HTTP status codes on all 15 routes without any post-start injection
  3. Admin dashboard and kiosk-app Dockerfiles reference `node:20-alpine`; rebuilt images pass login and product-display smoke checks
  4. CMS Dockerfile references `node:20-alpine`; CMS health endpoint returns 204 after rebuild
**Plans:** 4 plans
Plans:
- [x] 01-01-PLAN.md — Smoke scripts and documentation (PATCHLOG, TEST_REPORT)
- [x] 01-02-PLAN.md — VPS CMS clean rebuild and route verification
- [x] 01-03-PLAN.md — Node.js LTS static verification and INFRA-03 functional check
- [ ] 01-04-PLAN.md — Gap closure: VPS rebuild execution and smoke verification (CMS-02, CMS-03, INFRA-03)

### Phase 2: Structured Logging & Correlation
**Goal**: Every request entering the gateway carries a correlation ID that is propagated to all upstream services; n8n, Strapi, and Nginx all emit structured JSON logs that include this ID
**Depends on**: Phase 1
**Requirements**: OBS-01, OBS-02, OBS-03, OBS-04
**Success Criteria** (what must be TRUE):
  1. Nginx generates an `X-Request-ID` header on every inbound request and includes it in the JSON access log
  2. n8n workflow execution logs contain `workflow_id`, `execution_id`, `step`, `timestamp`, and `level` fields in JSON format
  3. Strapi production logs are in JSON format (Winston JSON formatter); a single request can be traced from nginx access log to Strapi application log using the correlation ID
  4. Nginx access log contains `request_id` for every proxied request, enabling end-to-end trace reconstruction
**Plans:** 5/5 plans complete
Plans:
- [x] 02-01-PLAN.md — Nginx: add $request_id to JSON log format and propagate X-Request-ID header to all upstream services (OBS-03, OBS-04)
- [x] 02-02-PLAN.md — n8n: configure N8N_LOG_FORMAT=json for structured NDJSON output on main and worker (OBS-01)
- [x] 02-03-PLAN.md — Strapi: Pino JSON logger config + request-id Koa middleware for correlation ID capture (OBS-02, OBS-04)
- [x] 02-04-PLAN.md — End-to-end correlation smoke test verifying all four OBS requirements on live VPS (OBS-01, OBS-02, OBS-03, OBS-04)
- [ ] 02-05-PLAN.md — Gap closure: document OBS-01 known limitation and mark OBS-02 complete in REQUIREMENTS.md (OBS-01, OBS-02)

### Phase 3: Metrics, Alerting & Audit Trail
**Goal**: Operators can observe queue health and disk pressure in near-real-time; all inbound workflow executions are recorded in a queryable audit table with 90-day retention
**Depends on**: Phase 2
**Requirements**: METR-01, METR-02, METR-03, METR-04, METR-05, AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04
**Success Criteria** (what must be TRUE):
  1. n8n queue depth (pending executions) and workflow error rate are exported as structured log metrics queryable without manual DB inspection
  2. Nginx rate-limit hit events are logged with zone, IP, and endpoint — operators can see which IPs are being throttled
  3. An alert fires (log-level CRITICAL or equivalent) when queue depth exceeds 50 pending executions for more than 5 minutes, and when disk usage crosses 80% of 119GB
  4. A `workflow_audit` table exists in PostgreSQL; W_IN_WHATSAPP, W_IN_INSTAGRAM, and W_IN_MESSENGER write audit entries on execution start and completion
  5. The admin dashboard has a basic audit log view where operators can search by date range and workflow name
  6. Audit entries older than 90 days are archived (not deleted) by an automated process
**Plans:** 5 plans
Plans:
- [ ] 03-01-PLAN.md — DB migration (ops.workflow_audit tables) + nginx rate-limit logging (METR-02, AUDIT-01)
- [ ] 03-02-PLAN.md — W_QUEUE_METRICS workflow: queue depth + error rate + disk CRITICAL alerts (METR-01, METR-03)
- [ ] 03-03-PLAN.md — W_AUDIT_WRITE, W_AUDIT_QUERY, W_AUDIT_ARCHIVE workflows (AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04)
- [ ] 03-04-PLAN.md — Patch W1_IN_WA, W2_IN_IG, W3_IN_MSG with fire-and-forget audit hooks (AUDIT-02)
- [ ] 03-05-PLAN.md — Admin dashboard AuditLogView page with date range filter and pagination (AUDIT-03)

### Phase 4: Test Coverage — Routing & Permissions
**Goal**: Automated tests guard the two most fragile, zero-coverage surfaces: nginx routing and Strapi permission matrix; both run in CI on relevant PRs
**Depends on**: Phase 1
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04, TEST-05, TEST-06, TEST-07, TEST-08
**Success Criteria** (what must be TRUE):
  1. A smoke test script verifies that each of the 8 nginx routing zones returns the expected HTTP status (not 502 or 404)
  2. The smoke test verifies `Access-Control-Allow-Origin` appears exactly once on kiosk endpoints (no header duplication regression)
  3. The rate-limit smoke test sends 25 rapid requests to `/v1/inbound/whatsapp` and confirms 429 fires after the burst limit
  4. An unauthenticated `GET /api/products` returns 200 with product data; an unauthenticated `POST /api/orders` returns 403/401; an authenticated admin `GET /api/orders` returns full order data
  5. Nginx smoke tests run automatically in CI on every PR that touches `infra/gateway/nginx.conf`; Strapi permission tests run in CI against a local Strapi instance
**Plans:** 3 plans
Plans:
- [ ] 04-01-PLAN.md — nginx.smoke.conf (CI-safe stub config) + smoke-nginx-routing.sh (8 zones + CORS + rate-limit) (TEST-01, TEST-02, TEST-03)
- [ ] 04-02-PLAN.md — smoke-strapi-permissions.sh (Public + Authenticated role matrix) (TEST-05, TEST-06, TEST-07)
- [ ] 04-03-PLAN.md — CI integration: nginx-smoke + strapi-permissions jobs in ci.yml (TEST-04, TEST-08)

### Phase 5: Test Coverage — n8n Workflow E2E
**Goal**: The three inbound adapter workflows and the outbox retry mechanism have automated E2E tests that prove orders reach Strapi and retries fire correctly; tests run in CI
**Depends on**: Phase 4
**Requirements**: TEST-09, TEST-10, TEST-11
**Success Criteria** (what must be TRUE):
  1. A POST to `/v1/inbound/whatsapp` with a valid Meta-signed payload triggers W_IN_WHATSAPP_ADAPTER and creates a record in Strapi `inbound-message` — verifiable by querying the DB after the test
  2. A simulated outbound failure results in a Redis queue entry for the retry, confirming exponential backoff is wired up correctly
  3. Workflow smoke tests execute in CI using n8n test mode or mock webhook triggers without requiring a live VPS
**Plans**: TBD

### Phase 6: Performance Tuning
**Goal**: Known performance ceilings are removed: order query latency drops via new indexes, Redis cannot OOM-kill the platform, and the admin dashboard loads faster via code splitting
**Depends on**: Phase 3
**Requirements**: PERF-01, PERF-02, PERF-03, PERF-04, PERF-05, PERF-06, PERF-07, PERF-08, PERF-09
**Success Criteria** (what must be TRUE):
  1. A new migration adds `idx_orders_status_created` and `idx_orders_customer_status` indexes if they do not exist; EXPLAIN ANALYZE on the 3 most common order queries confirms index usage
  2. Redis `maxmemory-policy` is set to `allkeys-lru`; Redis memory usage is logged every 15 minutes and fires an alert if usage exceeds 200MB; configuration is documented in `ENV_REFERENCE.md`
  3. Admin dashboard uses React Router `lazy()` for all view components; initial JS bundle size is at least 30% smaller than the pre-split baseline
  4. Kiosk menu data uses ETag or 5-minute TTL caching; repeated renders do not trigger redundant Strapi API calls
**Plans**: TBD

### Phase 7: NemoClaw Telegram Bot NVIDIA NIM integration and reliability improvements
**Goal**: The NemoClaw Telegram bot (@AdelClaw_Nemobot) responds to messages using NVIDIA NIM LLM inference, with async non-blocking processing, typing indicators, retry logic for transient errors, and auto-restart via systemd
**Depends on**: Nothing (independent of main platform phases)
**Requirements**: NIM-01, NIM-02, BOT-01, BOT-02, BOT-03, SVC-01, SVC-02
**Success Criteria** (what must be TRUE):
  1. NVIDIA NIM API returns HTTP 200 for model `meta/llama-3.3-70b-instruct` with the configured API key
  2. `openclaw agent` responds to a test message end-to-end without 404 or auth errors
  3. Telegram bot responds to messages within 30 seconds with AI-generated text
  4. Typing indicator appears during processing and clears after response
  5. Rate-limited (429) and server errors produce user-friendly messages, not raw errors
  6. systemd service restarts automatically after process kill (Restart=always)
  7. Service survives SSH disconnect and VPS reboot (loginctl linger enabled)
**Plans:** 1/4 plans executed
Plans:
- [ ] 07-01-PLAN.md — Fix NVIDIA NIM model config and API key auth
- [ ] 07-02-PLAN.md — Patch Telegram bridge for async spawn, typing keepalive, retries, and error handling
- [ ] 07-03-PLAN.md — Fix systemd service and E2E Telegram verification
- [ ] 07-04-PLAN.md — Create dedicated GitHub repo for NemoClaw (separate project from RESTO BOT)

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. CMS Stability & Base Upgrade | 3/4 | In progress (gap closure) | - |
| 2. Structured Logging & Correlation | 5/5 | Complete   | 2026-03-23 |
| 3. Metrics, Alerting & Audit Trail | 0/5 | Not started | - |
| 4. Test Coverage — Routing & Permissions | 0/3 | Not started | - |
| 5. Test Coverage — n8n Workflow E2E | 0/TBD | Not started | - |
| 6. Performance Tuning | 0/TBD | Not started | - |
| 7. NemoClaw Telegram Bot | 1/4 | In Progress|  |
