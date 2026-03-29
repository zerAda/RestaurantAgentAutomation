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
- [x] **Phase 2: Structured Logging & Correlation** - Add JSON structured logs with correlation IDs across n8n, Strapi, and Nginx so every request is traceable end-to-end (completed 2007-03-23)
- [ ] **Phase 3: Metrics, Alerting & Audit Trail** - Export queue/error metrics, add disk/memory alerts, and create a queryable workflow audit table
- [ ] **Phase 4: Test Coverage — Routing & Permissions** - Smoke-test all 8 nginx routing zones and validate the Strapi permission matrix with automated integration tests
- [ ] **Phase 5: Test Coverage — n8n Workflow E2E** - End-to-end tests for inbound adapters, outbox retry, and CI integration for workflow smoke tests
- [x] **Phase 6: Performance Tuning** - Add DB indexes for orders queries, enforce Redis eviction policy, and split the admin dashboard JS bundle (completed 2007-03-28)
- [ ] **Phase 7: Fix Critical Defects** - Fix METR-05 (disk alert dead code) and AUDIT-03 (VITE_N8N_URL missing from Dockerfile + AuditLogView URL path mismatch) — both are fail gates for milestone completion
- [ ] **Phase 8: n8n E2E Test Implementation** - Execute the Phase 5 plans (blocked since 2026-03-24): implement test-n8n-e2e.sh with DB assertion, outbound retry + Redis queue check, and wire CI job to actually run workflows
- [ ] **Phase 9: Integration Wiring & CI Fixes** - Activate Phase 3 workflows on VPS (all active=false), fix CI to run burst-test smoke variant for TEST-03, add ops.workflow_audit to CI EXPECTED_TABLES
- [ ] **Phase 10: Verification & Nyquist Compliance** - Create missing VERIFICATION.md for Phases 01/03/04, create VALIDATION.md for Phase 02, update draft VALIDATION.md for Phases 04/06

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

- [ ] 03-01-PLAN.md — DB migration (ops.workflow_audit tables) + nginx rate-limit logging + /v1/internal/ proxy (METR-03, AUDIT-01)
- [ ] 03-02-PLAN.md — W_QUEUE_METRICS workflow: queue depth + error rate + disk CRITICAL alerts (METR-01, METR-02, METR-04, METR-05)
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
**Plans:** 2 plans
Plans:

- [ ] 05-01-PLAN.md — E2E test script: Meta-signed WA inbound + DB assertion (TEST-09) and outbox retry + Redis assertion (TEST-10)
- [ ] 05-02-PLAN.md — CI integration: n8n-workflow-e2e job in ci.yml (TEST-11)

### Phase 6: Performance Tuning

**Goal**: Known performance ceilings are removed: order query latency drops via new indexes, Redis cannot OOM-kill the platform, and the admin dashboard loads faster via code splitting
**Depends on**: Phase 3
**Requirements**: PERF-01, PERF-02, PERF-03, PERF-04, PERF-05, PERF-06, PERF-07, PERF-08, PERF-09
**Success Criteria** (what must be TRUE):

  1. A new migration adds `idx_orders_status_created` and `idx_orders_user_status` indexes if they do not exist; EXPLAIN ANALYZE on the 3 most common order queries confirms index usage (NOTE: orders table uses user_id not customer_id — index is idx_orders_user_status)
  2. Redis `maxmemory-policy` is set to `allkeys-lru`; Redis memory usage is logged every 15 minutes and fires an alert if usage exceeds 200MB; configuration is documented in `ENV_REFERENCE.md`
  3. Admin dashboard uses React Router `lazy()` for all view components; code splitting is structurally active — `dist/assets/` contains 5 or more JS chunks and the entry bundle (`index-*.js`) is 30KB or less
  4. Kiosk menu data uses ETag or 5-minute TTL caching; repeated renders do not trigger redundant Strapi API calls
**Plans:** 2/2 plans complete
Plans:

- [ ] 06-01-PLAN.md — Wave 0 verification infrastructure: App.lazy.test.tsx, check-bundle-size.cjs, menuService.cache.test.ts (PERF-01 through PERF-07, PERF-09)
- [ ] 06-02-PLAN.md — Bundle size measurement + user sign-off on PERF-05 and PERF-08

### Phase 7: Fix Critical Defects

**Goal**: The two milestone fail-gate defects are resolved: W_QUEUE_METRICS disk alert fires correctly, and AuditLogView can reach W_AUDIT_QUERY via the correct URL
**Depends on**: Phase 3 (fixes artifacts produced by Phase 3)
**Requirements**: METR-05, AUDIT-03
**Gap Closure:** Closes gaps from v1.0 audit — METR-05 (diskUsedPct hardcoded -1) and AUDIT-03 (VITE_N8N_URL missing + path mismatch)
**Success Criteria** (what must be TRUE):

  1. W_QUEUE_METRICS.json disk check reads actual filesystem usage; alert condition `diskUsedPct > diskAlertPct` fires correctly when disk is above threshold
  2. `admin-dashboard/Dockerfile` declares `ARG VITE_N8N_URL` and `ENV VITE_N8N_URL`; docker-compose build args pass the correct n8n URL at image build time
  3. `AuditLogView.tsx` fetch path matches the W_AUDIT_QUERY webhook path; a real AuditLogView request reaches the workflow and returns audit entries
**Plans:** 2 plans
Plans:

- [ ] 07-01-PLAN.md — Fix W_QUEUE_METRICS disk check (replace hardcoded -1 with real df/stat call) (METR-05)
- [ ] 07-02-PLAN.md — Fix admin-dashboard Dockerfile VITE_N8N_URL ARG/ENV + AuditLogView.tsx fetch path correction (AUDIT-03)

### Phase 8: n8n E2E Test Implementation

**Goal**: scripts/test-n8n-e2e.sh exists and verifies that the WA inbound adapter creates an inbound_messages DB row (direct Postgres write, not Strapi) and that outbound failures produce a Redis retry entry; CI executes these tests via a full compose stack lifecycle
**Depends on**: Phase 5 (plans exist; this phase closes execution blockers and runs them)
**Requirements**: TEST-09, TEST-10, TEST-11
**Gap Closure:** Closes gaps from v1.0 audit — Phase 5 was entirely unexecuted; this phase resolves the 4 blockers identified in 2026-03-24 session and executes the plans
**Success Criteria** (what must be TRUE):

  1. `scripts/test-n8n-e2e.sh` exists; a POST to `/v1/inbound/whatsapp` with valid Meta-signed payload triggers W_IN_WHATSAPP_ADAPTER and an `inbound_messages` record is verified in the n8n Postgres DB
  2. A simulated outbound failure results in a Redis queue entry confirming exponential backoff wiring
  3. `docker/docker-compose.test.yml` includes META_APP_SECRET, META_SIGNATURE_REQUIRED, REDIS_CREDENTIAL_ID env vars; CI `n8n-workflow-e2e` job executes workflows (not HTTP-only check)
**Plans:** 1/2 plans executed
Plans:

- [ ] 08-01-PLAN.md — Create test-n8n-e2e.sh with TEST-09 (Meta-signed WA inbound + Postgres DB assertion) and TEST-10 (outbox retry + Redis re-queue) (TEST-09, TEST-10)
- [ ] 08-02-PLAN.md — Wire CI n8n-workflow-e2e job with full inline compose stack lifecycle (TEST-11)

### Phase 9: Integration Wiring & CI Fixes

**Goal**: Phase 3 audit chain is live (all workflows active on VPS); CI rate-limit burst test runs against the correct smoke script; ops schema migration is verified in CI
**Depends on**: Phase 7 (AUDIT-03 Dockerfile fix needed before AuditLogView is useful)
**Requirements**: AUDIT-01, AUDIT-02, AUDIT-04, METR-01, METR-02, METR-04, TEST-03, TEST-04
**Gap Closure:** Closes integration gaps from v1.0 audit — workflow activation, CI smoke script mismatch, ops schema CI verification
**Success Criteria** (what must be TRUE):

  1. W_AUDIT_WRITE, W_AUDIT_QUERY, W_AUDIT_ARCHIVE, W_QUEUE_METRICS, W_REDIS_MONITOR all have `active=true` on VPS; audit chain produces entries for inbound workflow executions
  2. CI `smoke-nginx-routing` job runs `smoke-nginx-routing.sh` (burst test variant) — TEST-03 rate-limit assertion executes on every PR touching nginx.conf
  3. `ci.yml` integration-tests `EXPECTED_TABLES` includes `ops.workflow_audit`; a P3 migration failure is caught by CI
**Plans:** 1/2 plans executed
Plans:

- [ ] 09-01-PLAN.md — Activate Phase 3 workflows on VPS via n8n API (AUDIT-02, AUDIT-04, METR-01, METR-02, METR-04)
- [ ] 09-02-PLAN.md — Fix CI: switch smoke-nginx-routing-v2.sh → smoke-nginx-routing.sh for TEST-03 burst test; add ops.workflow_audit to EXPECTED_TABLES (TEST-03, TEST-04, AUDIT-01)

### Phase 10: Verification & Nyquist Compliance

**Goal**: Every executed phase has a passing VERIFICATION.md and a non-draft VALIDATION.md; the milestone audit can complete with full coverage
**Depends on**: Phase 7, Phase 8, Phase 9 (all fixes must be in place before verification)
**Requirements**: (no new requirements — closes Nyquist compliance gaps for existing phases)
**Gap Closure:** Closes Nyquist compliance tech debt from v1.0 audit — missing VERIFICATION.md for Phases 01/03/04, missing VALIDATION.md for Phase 02, draft VALIDATION.md for Phases 04/06
**Success Criteria** (what must be TRUE):

  1. Phase 01 VERIFICATION.md is re-run and reflects 01-04 gap closure results (not stale pre-01-04 state)
  2. Phase 03 VERIFICATION.md exists and verifies observable truths against the 6 Phase 3 success criteria
  3. Phase 04 VERIFICATION.md exists and verifies observable truths against the 5 Phase 4 success criteria
  4. Phase 02 VALIDATION.md exists with nyquist_compliant result
  5. Phase 04 and Phase 06 VALIDATION.md files are updated from draft state to reflect actual execution
**Plans:** 2 plans
Plans:

- [ ] 10-01-PLAN.md — Re-verify Phase 01 and create VERIFICATION.md for Phases 03 and 04
- [ ] 10-02-PLAN.md — Create Phase 02 VALIDATION.md; update Phase 04 and Phase 06 VALIDATION.md from draft state
