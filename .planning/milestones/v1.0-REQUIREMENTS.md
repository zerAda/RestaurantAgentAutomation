# Requirements: RESTO BOT — Platform Hardening & Reliability

**Defined:** 2026-03-18
**Core Value:** Orders placed on any channel reach the kitchen, get paid, and get delivered — reliably and without manual intervention.

> **Checkbox status reconciled 2026-06-19** to match the authoritative 2026-04-04 milestone audit
> (`.planning/v1.0-MILESTONE-AUDIT.md`). A checked box means satisfied at code/CI level **and** not
> flagged as broken at VPS runtime by the audit. The 7 audit-confirmed runtime gaps remain unchecked
> with a `(gap → Phase NN)` annotation pointing at the closure phase. See `.planning/REMAINING-WORK.md`.

## v1 Requirements

### CMS Stability

- [x] **CMS-01**: CMS routes for all 15 APIs (ingredient, system-config, restaurant-brand, delivery-assignment, feedback, supplier, marketing-campaign, loyalty-tier, and 7 others) are defined in TypeScript source files and survive container rebuild
- [x] **CMS-02**: CMS Docker image can be rebuilt (`docker compose build cms`) without losing any API routes
- [x] **CMS-03**: All Strapi API routes return correct HTTP status codes after a fresh container start (no manual injection needed)

### Infrastructure Upgrade

- [x] **INFRA-01**: All frontend Dockerfiles (admin-dashboard, kiosk-app) use `node:20-alpine` base image (was: node:18-alpine, EOL)
- [x] **INFRA-02**: CMS Dockerfile uses `node:20-alpine` (consistent base across all services)
- [x] **INFRA-03**: Rebuilt images are verified to function correctly (login, product display, CMS health) — *partial: kiosk/admin gateway 403s are pre-existing and user-accepted*

### Observability — Structured Logging

- [x] **OBS-01**: n8n workflows emit structured JSON logs with correlation IDs (workflow_id, execution_id, step, timestamp, level)
- [x] **OBS-02**: Strapi CMS uses JSON log format in production (Winston JSON formatter)
- [x] **OBS-03**: Nginx access log includes request_id header for cross-service tracing
- [x] **OBS-04**: A correlation ID is generated at the gateway and propagated to upstream services via `X-Request-ID` header

### Observability — Metrics & Alerting

- [ ] **METR-01**: n8n queue depth (pending executions) is exported as a metric — *code complete (`W_QUEUE_METRICS`) but **gap → Phase 12**: PG credential ID is an empty `$env` expression on VPS, node fails at runtime*
- [ ] **METR-02**: Workflow error rate is tracked and loggable (failures per hour per workflow) — *same credential gap as METR-01; **gap → Phase 12***
- [x] **METR-03**: Nginx rate limit hit events are logged (zone, IP, endpoint) — nginx.conf `limit_req_log_level` (2026-03-26)
- [ ] **METR-04**: Alert fires when queue depth > 50 pending executions for > 5 minutes — *cascade from METR-01; **gap → Phase 12***
- [ ] **METR-05**: Alert fires when disk usage > 80% of 119GB (< 24GB free) — ***gap → Phase 12**: disk check regressed to `stat -f -c` (Alpine-incompatible), must restore `df -k /`*

### Observability — Audit Trail

- [x] **AUDIT-01**: A `workflow_audit` table exists in PostgreSQL (workflow_id, execution_id, trigger, input_hash, output_hash, status, started_at, completed_at) — migration `2026-03-23_p3_workflow_audit.sql` + CI schema check (2026-03-26)
- [ ] **AUDIT-02**: All inbound adapter workflows (W_IN_WHATSAPP, W_IN_INSTAGRAM, W_IN_MESSENGER) write an audit entry on execution start and end — *code complete; **gap → Phase 11**: ops.workflow_audit table not applied to VPS, W_AUDIT_WRITE INSERT fails silently*
- [ ] **AUDIT-03**: Audit log is queryable from the admin dashboard (search by date range + workflow name) — *code complete; **gap → Phase 13**: `VITE_API_URL` not in compose build args (URL unrouted) + W_AUDIT_QUERY count/filter defects*
- [ ] **AUDIT-04**: Audit entries are retained for 90 days, then archived (not deleted) — *code complete; **gap → Phase 11**: W_AUDIT_ARCHIVE cron incompatible with n8n 2.x, not re-imported/activated on VPS*

### Test Coverage — Nginx Routing

- [x] **TEST-01**: Smoke test verifies each of the 8 nginx routing zones returns the expected HTTP status (not 502/404)
- [x] **TEST-02**: Smoke test verifies `Access-Control-Allow-Origin` header appears exactly once on kiosk endpoints (no duplicates)
- [x] **TEST-03**: Rate limiting smoke test: 25 rapid requests to `/v1/inbound/whatsapp` triggers 429 after burst limit
- [x] **TEST-04**: Smoke tests run automatically in CI on every PR that touches `infra/gateway/nginx.conf`

### Test Coverage — Strapi Permissions

- [x] **TEST-05**: Integration test: unauthenticated request to `GET /api/products` returns 200 with data (public role works)
- [x] **TEST-06**: Integration test: unauthenticated request to `POST /api/orders` returns 403 or 401
- [x] **TEST-07**: Integration test: authenticated admin user can `GET /api/orders` with full data
- [x] **TEST-08**: Permission tests run automatically in CI against a local Strapi instance

### Test Coverage — n8n Workflows

- [x] **TEST-09**: E2E test: POST to `/v1/inbound/whatsapp` with valid Meta payload triggers WA inbound adapter and creates a record in Postgres `inbound_messages` (delivered in Phase 8)
- [x] **TEST-10**: E2E test: failed outbound message is retried with exponential backoff (Redis queue entry exists after first failure) (delivered in Phase 8)
- [x] **TEST-11**: Workflow smoke tests run in CI using a full compose-stack lifecycle (delivered in Phase 8)

### Performance — Database

- [x] **PERF-01**: Migration adds `CREATE INDEX idx_orders_status_created ON orders(status, created_at)` if not exists — `2026-03-26_p6_orders_indexes.sql`
- [x] **PERF-02**: Migration adds `CREATE INDEX idx_orders_customer_status ON orders(customer_id, status)` if not exists — `2026-03-26_p6_orders_indexes.sql`
- [x] **PERF-03**: EXPLAIN ANALYZE on the 3 most common order queries shows index usage — tooling `scripts/verify-orders-indexes.sh` (audit: satisfied)

### Performance — Redis

- [x] **PERF-04**: Redis `maxmemory-policy` is set to `allkeys-lru` (prevents OOM kill) — `infra/redis/entrypoint.sh`
- [x] **PERF-05**: Redis memory usage is logged on a schedule (every 15 minutes) and alert fires if > 200MB used — `W_REDIS_MONITOR` (2026-03-26; PERF-05 connectivity-only scope user-accepted)
- [x] **PERF-06**: Redis configuration is documented in `ENV_REFERENCE.md` — updated 2026-03-26

### Performance — Frontend

- [x] **PERF-07**: Admin dashboard uses React Router `lazy()` for all view components (code splitting) — `admin-dashboard/src/App.tsx` (2026-03-26)
- [x] **PERF-08**: Initial JS bundle size is reduced by at least 30% compared to the monolithic build — lazy loading applied (audit: satisfied)
- [x] **PERF-09**: Kiosk menu data is cached (ETag or 5-min TTL) to reduce Strapi API calls on re-render — `menuService.ts` + VerticalVideoFeed (2026-03-26)

## v2 Requirements

### Backup & Recovery

- **BAK-01**: Automated daily pg_dump to `/opt/resto/backups/` with 7-day retention
- **BAK-02**: Backup sync to S3 or secondary storage
- **BAK-03**: Monthly restore drill documented in RUNBOOK.md

### n8n Upgrade

- **N8N-01**: n8n 2.9.4 → 3.x upgrade (after test coverage exists)
- **N8N-02**: Task-runner properly disabled in n8n 3.x
- **N8N-03**: All 54 workflows verified on n8n 3.x

### Advanced Observability

- **ADVOBS-01**: Grafana dashboard for error rates, latency percentiles, queue depth
- **ADVOBS-02**: ELK/Loki log aggregation
- **ADVOBS-03**: PagerDuty or webhook alerting for P0 events

## Out of Scope

| Feature | Reason |
|---------|--------|
| n8n 2.x → 3.x upgrade | High blast radius; defer until test coverage shields the migration |
| DB backup automation | Important but not blocking prod; deferred to v2 |
| Multi-tenant support | (Note: a SaaS/multi-tenant track has since landed in the codebase outside this milestone's planning scope) |
| Mobile app | Web kiosk covers current use case |
| Real-time WebSocket dashboard | Polling sufficient for current ops volume |
| mTLS for admin services | Defense-in-depth; current triple-auth layer is sufficient |
| NemoClaw Telegram Bot | Descoped from v1.0 (was a draft Phase 7); intended for its own repository |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CMS-01 | Phase 1 | Satisfied |
| CMS-02 | Phase 1 | Satisfied |
| CMS-03 | Phase 1 | Satisfied |
| INFRA-01 | Phase 1 | Satisfied |
| INFRA-02 | Phase 1 | Satisfied |
| INFRA-03 | Phase 1 | Partial (gateway 403s pre-existing, accepted) |
| OBS-01 | Phase 2 | Satisfied |
| OBS-02 | Phase 2 | Satisfied |
| OBS-03 | Phase 2 | Satisfied |
| OBS-04 | Phase 2 | Satisfied |
| METR-01 | Phase 3 → **12** | Unsatisfied (W_QUEUE_METRICS credential gap) |
| METR-02 | Phase 3 → **12** | Unsatisfied (cascade from METR-01) |
| METR-03 | Phase 3 | Satisfied (nginx rate-limit logging) |
| METR-04 | Phase 3 → **12** | Unsatisfied (cascade from METR-01) |
| METR-05 | Phase 7 → **12** | Unsatisfied (disk check `stat -f -c` Alpine-incompatible regression) |
| AUDIT-01 | Phase 3/9 | Satisfied (table + CI schema check) |
| AUDIT-02 | Phase 3 → **11** | Unsatisfied (ops table not on VPS) |
| AUDIT-03 | Phase 7 → **13** | Unsatisfied (VITE_API_URL + W_AUDIT_QUERY defects) |
| AUDIT-04 | Phase 3 → **11** | Unsatisfied (W_AUDIT_ARCHIVE cron not activated) |
| TEST-01 | Phase 4 | Satisfied |
| TEST-02 | Phase 4 | Satisfied |
| TEST-03 | Phase 4/9 | Satisfied |
| TEST-04 | Phase 4/9 | Satisfied |
| TEST-05 | Phase 4 | Satisfied |
| TEST-06 | Phase 4 | Satisfied |
| TEST-07 | Phase 4 | Satisfied |
| TEST-08 | Phase 4 | Satisfied |
| TEST-09 | Phase 8 | Satisfied |
| TEST-10 | Phase 8 | Satisfied |
| TEST-11 | Phase 8 | Satisfied |
| PERF-01 | Phase 6 | Satisfied |
| PERF-02 | Phase 6 | Satisfied |
| PERF-03 | Phase 6 | Satisfied |
| PERF-04 | Phase 6 | Satisfied |
| PERF-05 | Phase 6 | Satisfied (user-accepted scope) |
| PERF-06 | Phase 6 | Satisfied |
| PERF-07 | Phase 6 | Satisfied |
| PERF-08 | Phase 6 | Satisfied |
| PERF-09 | Phase 6 | Satisfied |

**Coverage (per 2026-04-04 milestone audit):**
- v1 requirements satisfied: **27/34**
- Unsatisfied (runtime gaps): **7** — METR-01, METR-02, METR-04, METR-05, AUDIT-02, AUDIT-03, AUDIT-04
- Closure phases for the gaps: Phase 11 (AUDIT-02/04, VPS), Phase 12 (METR-01/02/04/05), Phase 13 (AUDIT-03)
- Unmapped: 0

> Note: the requirement list enumerates 39 IDs; the audit's headline "27/34" preserves the
> milestone's original 34-requirement framing. The 7 unsatisfied IDs above are the authoritative
> remaining set regardless of which denominator is used.

---
*Requirements defined: 2026-03-18*
*Last updated: 2026-06-19 — checkbox status reconciled to the 2026-04-04 milestone audit; 7 runtime gaps annotated with closure phases (11/12/13); NemoClaw descoped*
