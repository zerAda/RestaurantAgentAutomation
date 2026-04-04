# Requirements: RESTO BOT — Platform Hardening & Reliability

**Defined:** 2026-03-18
**Core Value:** Orders placed on any channel reach the kitchen, get paid, and get delivered — reliably and without manual intervention.

## v1 Requirements

### CMS Stability

- [x] **CMS-01**: CMS routes for all 15 APIs (ingredient, system-config, restaurant-brand, delivery-assignment, feedback, supplier, marketing-campaign, loyalty-tier, and 7 others) are defined in TypeScript source files and survive container rebuild
- [x] **CMS-02**: CMS Docker image can be rebuilt (`docker compose build cms`) without losing any API routes
- [x] **CMS-03**: All Strapi API routes return correct HTTP status codes after a fresh container start (no manual injection needed)

### Infrastructure Upgrade

- [x] **INFRA-01**: All frontend Dockerfiles (admin-dashboard, kiosk-app) use `node:20-alpine` base image (was: node:18-alpine, EOL)
- [x] **INFRA-02**: CMS Dockerfile uses `node:20-alpine` (consistent base across all services)
- [ ] **INFRA-03**: Rebuilt images are verified to function correctly (login, product display, CMS health)

### Observability — Structured Logging

- [x] **OBS-01**: n8n workflows emit structured JSON logs with correlation IDs (workflow_id, execution_id, step, timestamp, level)
- [x] **OBS-02**: Strapi CMS uses JSON log format in production (Winston JSON formatter)
- [x] **OBS-03**: Nginx access log includes request_id header for cross-service tracing
- [x] **OBS-04**: A correlation ID is generated at the gateway and propagated to upstream services via `X-Request-ID` header

### Observability — Metrics & Alerting

- [ ] **METR-01**: n8n queue depth (pending executions) is exported as a metric (Prometheus or structured log)
- [ ] **METR-02**: Workflow error rate is tracked and loggable (failures per hour per workflow)
- [x] **METR-03**: Nginx rate limit hit events are logged (zone, IP, endpoint) — currently blind
- [ ] **METR-04**: Alert fires when queue depth > 50 pending executions for > 5 minutes
- [ ] **METR-05**: Alert fires when disk usage > 80% of 119GB (< 24GB free)

### Observability — Audit Trail

- [x] **AUDIT-01**: A `workflow_audit` table exists in PostgreSQL (workflow_id, execution_id, trigger, input_hash, output_hash, status, started_at, completed_at)
- [ ] **AUDIT-02**: All inbound adapter workflows (W_IN_WHATSAPP, W_IN_INSTAGRAM, W_IN_MESSENGER) write an audit entry on execution start and end
- [ ] **AUDIT-03**: Audit log is queryable from the admin dashboard (basic search by date range + workflow name)
- [ ] **AUDIT-04**: Audit entries are retained for 90 days, then archived (not deleted)


### Test Coverage — Nginx Routing

- [x] **TEST-01**: Smoke test verifies each of the 8 nginx routing zones returns the expected HTTP status (not 502/404)
- [x] **TEST-02**: Smoke test verifies `Access-Control-Allow-Origin` header appears exactly once on kiosk endpoints (no duplicates)
- [x] **TEST-03**: Rate limiting smoke test: 25 rapid requests to `/v1/inbound/whatsapp` triggers 429 after burst limit
- [x] **TEST-04**: Smoke tests run automatically in CI on every PR that touches `infra/gateway/nginx.conf`

### Test Coverage — Strapi Permissions

- [x] **TEST-05**: Integration test: unauthenticated request to `GET /api/products` returns 200 with data (public role works)
- [x] **TEST-06**: Integration test: unauthenticated request to `POST /api/orders` returns 403 or 401 (kiosk can't create orders without auth... or verify intended behavior)
- [x] **TEST-07**: Integration test: authenticated admin user can `GET /api/orders` with full data
- [x] **TEST-08**: Permission tests run automatically in CI against a local Strapi instance

### Test Coverage — n8n Workflows

- [x] **TEST-09**: E2E test: POST to `/v1/inbound/whatsapp` with valid Meta payload triggers W_IN_WHATSAPP_ADAPTER and creates a record in Strapi `inbound-message`
- [x] **TEST-10**: E2E test: failed outbound message is retried with exponential backoff (verify Redis queue entry exists after first failure)
- [x] **TEST-11**: Workflow smoke tests run in CI using n8n test mode or mock webhook triggers

### Performance — Database

- [x] **PERF-01**: Migration adds `CREATE INDEX idx_orders_status_created ON orders(status, created_at)` if not exists
- [x] **PERF-02**: Migration adds `CREATE INDEX idx_orders_user_status ON orders(user_id, status)` if not exists (NOTE: orders table has no customer_id column; the actual column is user_id — canonical index name is idx_orders_user_status)
- [x] **PERF-03**: EXPLAIN ANALYZE on the 3 most common order queries shows index usage

### Performance — Redis

- [x] **PERF-04**: Redis `maxmemory-policy` is set to `allkeys-lru` (prevents OOM kill)
- [x] **PERF-05**: Redis memory usage is logged on a schedule (every 15 minutes) and alert fires if > 200MB used
- [x] **PERF-06**: Redis configuration is documented in `ENV_REFERENCE.md`

### Performance — Frontend

- [x] **PERF-07**: Admin dashboard uses React Router `lazy()` for all view components (code splitting)
- [x] **PERF-08**: Code splitting is structurally active: `dist/assets/` contains 5 or more JS chunks AND the entry bundle (`index-*.js`) is 30KB or less (monolithic baseline no longer exists in git; entry-bundle size is the measurable proxy for the 30% reduction intent)
- [x] **PERF-09**: Kiosk menu data is cached (ETag or 5-min TTL) to reduce Strapi API calls on re-render

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
| Multi-tenant support | Single restaurant scope for now |
| Mobile app | Web kiosk covers current use case |
| Real-time WebSocket dashboard | Polling sufficient for current ops volume |
| mTLS for admin services | Defense-in-depth; current triple-auth layer is sufficient |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CMS-01 | Phase 1 | Complete |
| CMS-02 | Phase 1 | Complete |
| CMS-03 | Phase 1 | Complete |
| INFRA-01 | Phase 1 | Complete |
| INFRA-02 | Phase 1 | Complete |
| INFRA-03 | Phase 1 | Partial (gateway 403s pre-existing, accepted) |
| OBS-01 | Phase 2 | Complete |
| OBS-02 | Phase 2 | Complete |
| OBS-03 | Phase 2 | Complete |
| OBS-04 | Phase 2 | Complete |
| METR-01 | Phase 12 (gap closure from Phase 3) | Pending |
| METR-02 | Phase 12 (gap closure from Phase 3) | Pending |
| METR-03 | Phase 3 | Complete |
| METR-04 | Phase 12 (gap closure from Phase 3) | Pending |
| METR-05 | Phase 12 (gap closure from Phase 7) | Pending |
| AUDIT-01 | Phase 9 (gap closure from Phase 3) | Complete |
| AUDIT-02 | Phase 11 (gap closure from Phase 9) | Pending |
| AUDIT-03 | Phase 13 (gap closure from Phase 7) | Pending |
| AUDIT-04 | Phase 11 (gap closure from Phase 9) | Pending |
| TEST-01 | Phase 4 | Complete |
| TEST-02 | Phase 4 | Complete |
| TEST-03 | Phase 9 (gap closure from Phase 4) | Complete |
| TEST-04 | Phase 9 (gap closure from Phase 4) | Complete |
| TEST-05 | Phase 4 | Complete |
| TEST-06 | Phase 4 | Complete |
| TEST-07 | Phase 4 | Complete |
| TEST-08 | Phase 4 | Complete |
| TEST-09 | Phase 8 (gap closure from Phase 5) | Complete |
| TEST-10 | Phase 8 (gap closure from Phase 5) | Complete |
| TEST-11 | Phase 8 (gap closure from Phase 5) | Complete |
| PERF-01 | Phase 6 | Complete |
| PERF-02 | Phase 6 | Complete |
| PERF-03 | Phase 6 | Complete |
| PERF-04 | Phase 6 | Complete |
| PERF-05 | Phase 6 | Complete |
| PERF-06 | Phase 6 | Complete |
| PERF-07 | Phase 6 | Complete |
| PERF-08 | Phase 6 | Complete |
| PERF-09 | Phase 6 | Complete |

**Coverage:**
- v1 requirements: 34 total
- Mapped to phases: 34
- Unmapped: 0
- Satisfied: 27 | Unsatisfied (runtime): 7 (METR-01, METR-02, METR-04, METR-05, AUDIT-02, AUDIT-03, AUDIT-04)
- Gap closure phases: METR-01/02/04/05 → Phase 12, AUDIT-02/04 → Phase 11, AUDIT-03 → Phase 13, METR-05/AUDIT-03 → previously Phase 7 (re-assigned), AUDIT-01/TEST-03/04 → Phase 9, TEST-09/10/11 → Phase 8

---
*Requirements defined: 2026-03-18*
*Last updated: 2026-03-28 — PERF-02 index name corrected to idx_orders_user_status (orders table has user_id, not customer_id); PERF-08 acceptance criteria updated to entry-bundle proxy measurement (monolithic baseline no longer in git history)*
*2026-03-28 — Gap closure phases 7-10 added from v1.0 milestone audit; METR-05/AUDIT-03/TEST-09/TEST-10/TEST-11 reassigned to gap closure phases; AUDIT-01/AUDIT-02/AUDIT-04/TEST-03/TEST-04 also reassigned to Phase 9*
