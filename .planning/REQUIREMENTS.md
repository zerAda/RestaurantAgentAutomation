# Requirements: RESTO BOT — Platform Hardening & Reliability

**Defined:** 2026-03-18
**Core Value:** Orders placed on any channel reach the kitchen, get paid, and get delivered — reliably and without manual intervention.

## v1 Requirements

### CMS Stability

- [ ] **CMS-01**: CMS routes for all 15 APIs (ingredient, system-config, restaurant-brand, delivery-assignment, feedback, supplier, marketing-campaign, loyalty-tier, and 7 others) are defined in TypeScript source files and survive container rebuild
- [ ] **CMS-02**: CMS Docker image can be rebuilt (`docker compose build cms`) without losing any API routes
- [ ] **CMS-03**: All Strapi API routes return correct HTTP status codes after a fresh container start (no manual injection needed)

### Infrastructure Upgrade

- [ ] **INFRA-01**: All frontend Dockerfiles (admin-dashboard, kiosk-app) use `node:20-alpine` base image (was: node:18-alpine, EOL)
- [ ] **INFRA-02**: CMS Dockerfile uses `node:20-alpine` (consistent base across all services)
- [ ] **INFRA-03**: Rebuilt images are verified to function correctly (login, product display, CMS health)

### Observability — Structured Logging

- [x] **OBS-01**: n8n workflows emit structured JSON logs with correlation IDs (workflow_id, execution_id, step, timestamp, level)
- [x] **OBS-02**: Strapi CMS uses JSON log format in production (Winston JSON formatter)
- [x] **OBS-03**: Nginx access log includes request_id header for cross-service tracing
- [x] **OBS-04**: A correlation ID is generated at the gateway and propagated to upstream services via `X-Request-ID` header

### Observability — Metrics & Alerting

- [ ] **METR-01**: n8n queue depth (pending executions) is exported as a metric (Prometheus or structured log)
- [ ] **METR-02**: Workflow error rate is tracked and loggable (failures per hour per workflow)
- [ ] **METR-03**: Nginx rate limit hit events are logged (zone, IP, endpoint) — currently blind
- [ ] **METR-04**: Alert fires when queue depth > 50 pending executions for > 5 minutes
- [ ] **METR-05**: Alert fires when disk usage > 80% of 119GB (< 24GB free)

### Observability — Audit Trail

- [ ] **AUDIT-01**: A `workflow_audit` table exists in PostgreSQL (workflow_id, execution_id, trigger, input_hash, output_hash, status, started_at, completed_at)
- [ ] **AUDIT-02**: All inbound adapter workflows (W_IN_WHATSAPP, W_IN_INSTAGRAM, W_IN_MESSENGER) write an audit entry on execution start and end
- [ ] **AUDIT-03**: Audit log is queryable from the admin dashboard (basic search by date range + workflow name)
- [ ] **AUDIT-04**: Audit entries are retained for 90 days, then archived (not deleted)

### Test Coverage — Nginx Routing

- [ ] **TEST-01**: Smoke test verifies each of the 8 nginx routing zones returns the expected HTTP status (not 502/404)
- [ ] **TEST-02**: Smoke test verifies `Access-Control-Allow-Origin` header appears exactly once on kiosk endpoints (no duplicates)
- [ ] **TEST-03**: Rate limiting smoke test: 25 rapid requests to `/v1/inbound/whatsapp` triggers 429 after burst limit
- [ ] **TEST-04**: Smoke tests run automatically in CI on every PR that touches `infra/gateway/nginx.conf`

### Test Coverage — Strapi Permissions

- [ ] **TEST-05**: Integration test: unauthenticated request to `GET /api/products` returns 200 with data (public role works)
- [ ] **TEST-06**: Integration test: unauthenticated request to `POST /api/orders` returns 403 or 401 (kiosk can't create orders without auth... or verify intended behavior)
- [ ] **TEST-07**: Integration test: authenticated admin user can `GET /api/orders` with full data
- [ ] **TEST-08**: Permission tests run automatically in CI against a local Strapi instance

### Test Coverage — n8n Workflows

- [ ] **TEST-09**: E2E test: POST to `/v1/inbound/whatsapp` with valid Meta payload triggers W_IN_WHATSAPP_ADAPTER and creates a record in Strapi `inbound-message`
- [ ] **TEST-10**: E2E test: failed outbound message is retried with exponential backoff (verify Redis queue entry exists after first failure)
- [ ] **TEST-11**: Workflow smoke tests run in CI using n8n test mode or mock webhook triggers

### Performance — Database

- [ ] **PERF-01**: Migration adds `CREATE INDEX idx_orders_status_created ON orders(status, created_at)` if not exists
- [ ] **PERF-02**: Migration adds `CREATE INDEX idx_orders_customer_status ON orders(customer_id, status)` if not exists
- [ ] **PERF-03**: EXPLAIN ANALYZE on the 3 most common order queries shows index usage

### Performance — Redis

- [ ] **PERF-04**: Redis `maxmemory-policy` is set to `allkeys-lru` (prevents OOM kill)
- [ ] **PERF-05**: Redis memory usage is logged on a schedule (every 15 minutes) and alert fires if > 200MB used
- [ ] **PERF-06**: Redis configuration is documented in `ENV_REFERENCE.md`

### Performance — Frontend

- [ ] **PERF-07**: Admin dashboard uses React Router `lazy()` for all view components (code splitting)
- [ ] **PERF-08**: Initial JS bundle size is reduced by at least 30% compared to current monolithic build
- [ ] **PERF-09**: Kiosk menu data is cached (ETag or 5-min TTL) to reduce Strapi API calls on re-render

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
| CMS-01 | Phase 1 | In progress (smoke scripts added; rebuild in plan 02) |
| CMS-02 | Phase 1 | In progress (smoke scripts added; rebuild in plan 02) |
| CMS-03 | Phase 1 | In progress (smoke scripts added; rebuild in plan 02) |
| INFRA-01 | Phase 1 | Pending |
| INFRA-02 | Phase 1 | Pending |
| INFRA-03 | Phase 1 | In progress (smoke-post-rebuild.sh added; verification runs in plan 02) |
| OBS-01 | Phase 2 | Complete |
| OBS-02 | Phase 2 | Complete |
| OBS-03 | Phase 2 | Complete |
| OBS-04 | Phase 2 | Complete |
| METR-01 | Phase 3 | Pending |
| METR-02 | Phase 3 | Pending |
| METR-03 | Phase 3 | Pending |
| METR-04 | Phase 3 | Pending |
| METR-05 | Phase 3 | Pending |
| AUDIT-01 | Phase 3 | Pending |
| AUDIT-02 | Phase 3 | Pending |
| AUDIT-03 | Phase 3 | Pending |
| AUDIT-04 | Phase 3 | Pending |
| TEST-01 | Phase 4 | Pending |
| TEST-02 | Phase 4 | Pending |
| TEST-03 | Phase 4 | Pending |
| TEST-04 | Phase 4 | Pending |
| TEST-05 | Phase 4 | Pending |
| TEST-06 | Phase 4 | Pending |
| TEST-07 | Phase 4 | Pending |
| TEST-08 | Phase 4 | Pending |
| TEST-09 | Phase 5 | Pending |
| TEST-10 | Phase 5 | Pending |
| TEST-11 | Phase 5 | Pending |
| PERF-01 | Phase 6 | Pending |
| PERF-02 | Phase 6 | Pending |
| PERF-03 | Phase 6 | Pending |
| PERF-04 | Phase 6 | Pending |
| PERF-05 | Phase 6 | Pending |
| PERF-06 | Phase 6 | Pending |
| PERF-07 | Phase 6 | Pending |
| PERF-08 | Phase 6 | Pending |
| PERF-09 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 34 total
- Mapped to phases: 34
- Unmapped: 0

---
*Requirements defined: 2026-03-18*
*Last updated: 2026-03-23 — OBS-01 marked complete after n8n upgrade to 2.9.4 on VPS; OBS-02, OBS-03, OBS-04 complete — all Phase 02 observability requirements satisfied*
