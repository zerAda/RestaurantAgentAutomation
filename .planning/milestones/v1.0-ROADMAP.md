# Roadmap: RESTO BOT — Platform Hardening & Reliability

## Overview

This milestone transforms RESTO BOT from a platform that works-in-practice into one that is
provably stable. Phase 1 eliminates the P0 CMS runtime-injection hack and upgrades Node.js to a
supported LTS. Phases 2-3 add structured observability so operators can see what the platform is
doing. Phases 4-5 add automated test coverage so regressions are caught before they reach
production. Phase 6 closes out the original plan with database indexes, Redis safety, and frontend
bundle optimizations.

The 2026-04-04 milestone audit (`status: gaps_found`, 27/34 requirements satisfied) then expanded
the milestone with gap-closure phases 7-14: Phase 7 fixed two fail-gate defects, Phase 8
re-implemented the n8n E2E tests (superseding the original Phase 5), Phase 9 wired CI and attempted
VPS workflow activation, and Phase 10 brought every executed phase up to verification/Nyquist
compliance. Phases 11-14 remain: they close the seven runtime gaps the audit surfaced (W_QUEUE_METRICS
credentials, the VPS DB migration, the admin audit-log view, and documentation/verification cleanup).

> **Reconciliation note (2026-06-19):** This roadmap was re-synced to match the 14 phase
> directories actually on disk. The earlier version described only the original 7 phases and listed
> a draft "Phase 7: NemoClaw Telegram Bot" that was descoped — the post-audit renumbering assigned
> the Phase 7 slot to "Fix Critical Defects". NemoClaw is no longer tracked in this milestone (it was
> always intended to graduate to its own repository). Requirement and phase statuses below reflect
> the audit's authoritative findings, not earlier optimistic SUMMARY claims.

## Phases

- [x] **Phase 1: CMS Stability & Base Upgrade** - Eliminate the docker-cp runtime hack; bake all 15 Strapi API routes into source; upgrade Node.js 18 -> 20 across all services (verified passed 5/6; INFRA-03 partial — pre-existing gateway 403s accepted)
- [x] **Phase 2: Structured Logging & Correlation** - JSON structured logs with correlation IDs across n8n, Strapi, and Nginx (completed 2026-03-23, verified 6/6)
- [x] **Phase 3: Metrics, Alerting & Audit Trail** - Export queue/error metrics, add disk/memory alerts, and create a queryable workflow audit table (verified passed 6/6 at code level; VPS-runtime gaps tracked in Phases 11/12/13)
- [x] **Phase 4: Test Coverage — Routing & Permissions** - Smoke-test all 8 nginx routing zones and validate the Strapi permission matrix (verified passed 5/5)
- [x] **Phase 5: Test Coverage — n8n Workflow E2E** - SUPERSEDED by Phase 8; requirements TEST-09/10/11 are satisfied there
- [x] **Phase 6: Performance Tuning** - DB indexes, Redis eviction policy, admin dashboard code splitting, kiosk caching (completed 2026-03-26, verified 9/9)
- [x] **Phase 7: Fix Critical Defects** - Resolve the two fail-gate defects (W_QUEUE_METRICS disk alert, AuditLogView URL) at code level (verified passed 7/7; live integration deferred to Phase 9)
- [x] **Phase 8: n8n E2E Test Implementation** - `scripts/test-n8n-e2e.sh` + CI compose-stack lifecycle proving WA inbound DB write and outbox Redis retry (verified passed 6/6)
- [ ] **Phase 9: Integration Wiring & CI Fixes** - Activate the five Phase-3 workflows on VPS, inject real credential IDs, fix CI — PARTIAL (plan 02 complete; plan 01 has 3 unresolved VPS blockers; VERIFICATION.md missing → Phase 14)
- [x] **Phase 10: Verification & Nyquist Compliance** - Bring every executed phase to a passing VERIFICATION.md and non-draft VALIDATION.md (verified passed 6/6)
- [ ] **Phase 11: VPS Ops — Apply DB Migration & Activate Audit Chain** - Apply the Phase-3 migration on VPS, recreate the gateway, re-import/activate W_AUDIT_ARCHIVE — researched, NOT executed (VPS-runtime only; DEFERRED to a prod-connected session)
- [x] **Phase 12: W_QUEUE_METRICS Runtime Fix** - Hardcode the PG/Redis credential IDs and restore the `df -k /` disk check so METR-01/02/04/05 fire on VPS — CODE COMPLETE (2026-06-20); VPS import deferred
- [x] **Phase 13: Admin Dashboard Audit-Log Repair** - Add the `VITE_API_URL` build arg and fix W_AUDIT_QUERY count/filter defects so AUDIT-03 works end-to-end — CODE COMPLETE (2026-06-20); VPS rebuild deferred
- [x] **Phase 14: Nyquist Compliance & Documentation Cleanup** - Create the missing Phase 09 VERIFICATION.md and Phase 03 VALIDATION.md, lift draft VALIDATIONs to compliant, and close stale checkboxes — COMPLETE (2026-06-20)

## Phase Details

### Phase 1: CMS Stability & Base Upgrade
**Goal**: The CMS build is self-contained; all 15 Strapi API routes exist in TypeScript source and survive any container rebuild; all frontend Dockerfiles use a supported Node.js LTS
**Depends on**: Nothing (first phase)
**Requirements**: CMS-01, CMS-02, CMS-03, INFRA-01, INFRA-02, INFRA-03
**Status**: Complete — VERIFICATION.md `passed`, 5/6 must-haves (INFRA-03 partial: kiosk/admin gateway 403s pre-existing and accepted)
**Success Criteria** (what must be TRUE):
  1. Running `docker compose build cms` from a clean state produces an image where all 15 API routes respond correctly — no manual `docker cp` required
  2. A freshly started CMS container returns expected HTTP status codes on all 15 routes without any post-start injection
  3. Admin dashboard and kiosk-app Dockerfiles reference `node:20-alpine`; rebuilt images pass login and product-display smoke checks
  4. CMS Dockerfile references `node:20-alpine`; CMS health endpoint returns 204 after rebuild
**Plans:** 4 plans
Plans:
- [x] 01-01-PLAN.md — Smoke scripts and documentation (PATCHLOG, TEST_REPORT)
- [x] 01-02-PLAN.md — VPS CMS clean rebuild and route verification
- [x] 01-03-PLAN.md — Node.js LTS static verification and INFRA-03 functional check
- [x] 01-04-PLAN.md — Gap closure: VPS rebuild execution and smoke verification (CMS-02, CMS-03, INFRA-03)

### Phase 2: Structured Logging & Correlation
**Goal**: Every request entering the gateway carries a correlation ID that is propagated to all upstream services; n8n, Strapi, and Nginx all emit structured JSON logs that include this ID
**Depends on**: Phase 1
**Requirements**: OBS-01, OBS-02, OBS-03, OBS-04
**Status**: Complete (2026-03-23) — VERIFICATION.md `passed`, 6/6; VALIDATION.md `compliant`
**Success Criteria** (what must be TRUE):
  1. Nginx generates an `X-Request-ID` header on every inbound request and includes it in the JSON access log
  2. n8n workflow execution logs contain `workflow_id`, `execution_id`, `step`, `timestamp`, and `level` fields in JSON format
  3. Strapi production logs are in JSON format; a single request can be traced from nginx access log to Strapi application log using the correlation ID
  4. Nginx access log contains `request_id` for every proxied request, enabling end-to-end trace reconstruction
**Plans:** 5/5 plans complete
Plans:
- [x] 02-01-PLAN.md — Nginx: $request_id JSON log + X-Request-ID propagation (OBS-03, OBS-04)
- [x] 02-02-PLAN.md — n8n: N8N_LOG_FORMAT=json (OBS-01)
- [x] 02-03-PLAN.md — Strapi: Pino JSON logger + request-id middleware (OBS-02, OBS-04)
- [x] 02-04-PLAN.md — End-to-end correlation smoke test (OBS-01..04)
- [x] 02-05-PLAN.md — Gap closure: document OBS-01 limitation, mark OBS-02 complete

### Phase 3: Metrics, Alerting & Audit Trail
**Goal**: Operators can observe queue health and disk pressure in near-real-time; all inbound workflow executions are recorded in a queryable audit table with 90-day retention
**Depends on**: Phase 2
**Requirements**: METR-01, METR-02, METR-03, METR-04, METR-05, AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04
**Status**: Complete at code level — VERIFICATION.md `passed`, 6/6. **VPS-runtime gaps remain** (METR-01/02/04/05, AUDIT-02/03/04) and are closed by Phases 11, 12, 13. VALIDATION.md was MISSING (→ Phase 14).
**Success Criteria** (what must be TRUE):
  1. n8n queue depth and workflow error rate are exported as structured log metrics
  2. Nginx rate-limit hit events are logged with zone, IP, and endpoint
  3. An alert fires when queue depth exceeds 50 pending executions for 5+ minutes, and when disk usage crosses 80% of 119GB
  4. A `workflow_audit` table exists in PostgreSQL; inbound adapters write audit entries on start and completion
  5. The admin dashboard has an audit log view searchable by date range and workflow name
  6. Audit entries older than 90 days are archived (not deleted) automatically
**Plans:** 5 plans
Plans:
- [x] 03-01-PLAN.md — DB migration + nginx rate-limit logging + /v1/internal/ proxy (METR-03, AUDIT-01)
- [x] 03-02-PLAN.md — W_QUEUE_METRICS workflow (METR-01, METR-02, METR-04, METR-05) — code complete; runtime fix in Phase 12
- [x] 03-03-PLAN.md — W_AUDIT_WRITE/QUERY/ARCHIVE workflows (AUDIT-01..04) — code complete; runtime in Phases 11/13
- [x] 03-04-PLAN.md — Patch inbound adapters with audit hooks (AUDIT-02)
- [x] 03-05-PLAN.md — Admin dashboard AuditLogView page (AUDIT-03) — bugs fixed in Phase 13

### Phase 4: Test Coverage — Routing & Permissions
**Goal**: Automated tests guard the two most fragile, zero-coverage surfaces: nginx routing and Strapi permission matrix; both run in CI on relevant PRs
**Depends on**: Phase 1
**Requirements**: TEST-01..08
**Status**: Complete — VERIFICATION.md `passed`, 5/5; VALIDATION.md `compliant`. CI smoke-script mismatch resolved in Phase 9 (09-02).
**Success Criteria** (what must be TRUE):
  1. A smoke test verifies each of the 8 nginx routing zones returns the expected HTTP status
  2. `Access-Control-Allow-Origin` appears exactly once on kiosk endpoints
  3. 25 rapid requests to `/v1/inbound/whatsapp` confirm 429 fires after the burst limit
  4. Strapi permission matrix (public GET products 200, unauth POST orders 401/403, admin GET orders 200)
  5. Both suites run in CI on relevant PRs
**Plans:** 3 plans
Plans:
- [x] 04-01-PLAN.md — nginx.smoke.conf + smoke-nginx-routing.sh (TEST-01, TEST-02, TEST-03)
- [x] 04-02-PLAN.md — smoke-strapi-permissions.sh (TEST-05, TEST-06, TEST-07)
- [x] 04-03-PLAN.md — CI integration (TEST-04, TEST-08)

### Phase 5: Test Coverage — n8n Workflow E2E
**Goal**: (Original) End-to-end tests for inbound adapters and outbox retry, run in CI
**Depends on**: Phase 4
**Requirements**: TEST-09, TEST-10, TEST-11
**Status**: SUPERSEDED by Phase 8 (`08-n8n-e2e-test-implementation`). Two plans (05-01, 05-02) were written but never executed; the work was redesigned and delivered in Phase 8, where TEST-09/10/11 are verified satisfied. This phase directory is retained for history only.
**Plans:** 2 plans (not executed — superseded)
Plans:
- [ ] 05-01-PLAN.md — (superseded by 08-01)
- [ ] 05-02-PLAN.md — (superseded by 08-02)

### Phase 6: Performance Tuning
**Goal**: Known performance ceilings are removed: order query latency drops via new indexes, Redis cannot OOM-kill the platform, and the admin dashboard loads faster via code splitting
**Depends on**: Phase 3
**Requirements**: PERF-01..09
**Status**: Complete (2026-03-26) — VERIFICATION.md `passed`, 9/9; VALIDATION.md `compliant`
**Success Criteria** (what must be TRUE):
  1. New migration adds `idx_orders_status_created` and `idx_orders_customer_status`; EXPLAIN ANALYZE confirms index usage
  2. Redis `maxmemory-policy` = `allkeys-lru`; memory logged every 15 min with a 200MB alert; documented in ENV_REFERENCE.md
  3. Admin dashboard uses React Router `lazy()` for all views; initial bundle ≥30% smaller
  4. Kiosk menu data uses ETag/5-min TTL caching
**Plans:** 2 plans
Plans:
- [x] 06-01-PLAN.md — DB indexes migration + Redis monitor + ENV_REFERENCE update (PERF-01/02/04/05/06)
- [x] 06-02-PLAN.md — Admin dashboard React lazy loading + kiosk menu caching (PERF-07, PERF-09)

### Phase 7: Fix Critical Defects
**Goal**: The two milestone fail-gate defects are resolved: W_QUEUE_METRICS disk alert fires correctly, and AuditLogView can reach W_AUDIT_QUERY via the correct URL
**Depends on**: Phase 3
**Requirements**: METR-05 (disk alert), AUDIT-03 (audit-log URL)
**Status**: Complete at code level — VERIFICATION.md `passed`, 7/7. Live integration deferred to Phase 9; subsequent audit found a regression (disk check reverted to `stat -f -c`) and residual AuditLogView defects, now tracked in Phases 12 and 13. VALIDATION.md was draft (→ Phase 14).
**Plans:** 2 plans
Plans:
- [x] 07-01-PLAN.md — W_QUEUE_METRICS disk-alert fix (METR-05)
- [x] 07-02-PLAN.md — AuditLogView URL fix (AUDIT-03)

### Phase 8: n8n E2E Test Implementation
**Goal**: `scripts/test-n8n-e2e.sh` verifies the WA inbound adapter creates an `inbound_messages` DB row (direct Postgres write) and that outbound failures produce a Redis retry entry; CI executes these tests via a full compose-stack lifecycle
**Depends on**: Phase 4
**Requirements**: TEST-09, TEST-10, TEST-11
**Status**: Complete — VERIFICATION.md `passed`, 6/6; VALIDATION.md `complete`. (Supersedes Phase 5.)
**Plans:** 2 plans
Plans:
- [x] 08-01-PLAN.md — test-n8n-e2e.sh: WA inbound DB assertion + outbox Redis retry (TEST-09, TEST-10)
- [x] 08-02-PLAN.md — CI n8n-workflow-e2e job via compose stack (TEST-11)

### Phase 9: Integration Wiring & CI Fixes
**Goal**: Activate all five Phase-3 workflows on VPS n8n so the audit chain, queue metrics, and Redis monitoring are live; inject real VPS credential IDs; fix CI smoke wiring
**Depends on**: Phases 3, 4, 7, 8
**Requirements**: AUDIT-01 (CI schema check), TEST-03, TEST-04 (CI wiring); attempted AUDIT-02/04, METR-01/02/04
**Status**: PARTIAL. Plan 02 (CI fixes) complete. Plan 01 (VPS workflow activation) `status: partial` with 3 unresolved blockers: (1) ops.workflow_audit table not applied to VPS, (2) W_AUDIT_ARCHIVE cron incompatible with n8n 2.x, (3) credential injection unverified at runtime. VERIFICATION.md is MISSING and VALIDATION.md is draft — both addressed by Phase 14. Runtime activation moves to Phase 11.
**Plans:** 2 plans
Plans:
- [x] 09-01-PLAN.md — Activate 5 Phase-3 workflows on VPS + credential injection (PARTIAL — 3 VPS blockers)
- [x] 09-02-PLAN.md — CI: smoke-nginx-routing job + ops.workflow_audit schema check (TEST-03, TEST-04, AUDIT-01)

### Phase 10: Verification & Nyquist Compliance
**Goal**: Every executed phase has a passing VERIFICATION.md and a non-draft VALIDATION.md so the milestone audit can complete with full coverage
**Depends on**: Phases 1-9
**Requirements**: (process/quality — no new product requirements)
**Status**: Complete (2026-03-30) — VERIFICATION.md `passed`, 6/6. Note: this phase backfilled VERIFICATION.md for phases 01/03/04 and VALIDATION.md for 02/04/06; the later milestone audit identified that Phase 09 VERIFICATION.md and Phase 03 VALIDATION.md still need to be created (→ Phase 14).
**Plans:** 2 plans
Plans:
- [x] 10-01-PLAN.md — Backfill VERIFICATION.md for executed phases
- [x] 10-02-PLAN.md — Lift VALIDATION.md drafts toward compliance

### Phase 11: VPS Ops — Apply DB Migration & Activate Audit Chain
**Goal**: Close the three runtime integration gaps that require live VPS access: apply the Phase-3 DB migration (`2026-03-23_p3_workflow_audit.sql`) into the n8n Postgres database, recreate the gateway container to pick up the `/v1/internal/` nginx route, and re-import + activate W_AUDIT_ARCHIVE with the n8n 2.x-compatible cron node
**Depends on**: Phase 9
**Requirements**: AUDIT-02, AUDIT-04 (and unblocks AUDIT-03 alongside Phase 13)
**Status**: RESEARCHED, NOT EXECUTED. RESEARCH.md exists; no PLAN.md. **DEFERRED** — every step requires SSH to the production VPS (`deploy@72.60.190.192`), which is unavailable from the planning/sandbox environment. See `.planning/REMAINING-WORK.md` for the runtime checklist.
**Plans:** 0 plans (deferred)

### Phase 12: W_QUEUE_METRICS Runtime Fix
**Goal**: Make METR-01, METR-02, METR-04, and METR-05 fire on VPS by replacing the empty `$env.*` credential-ID expressions in `W_QUEUE_METRICS.json` with the real hardcoded ID (`1mZZJEscADgQ8InR`) and restoring the `df -k /` disk check (Alpine-compatible) in place of the regressed `stat -f -c`
**Depends on**: Phase 3
**Requirements**: METR-01, METR-02, METR-04, METR-05
**Status**: CODE COMPLETE (2026-06-20, plan 12-01). W_QUEUE_METRICS.json PG/Redis credential IDs hardcoded and disk check switched to `df -k /`. VPS import + live alert verification deferred per `.planning/REMAINING-WORK.md`.
**Plans:** 0 plans

### Phase 13: Admin Dashboard Audit-Log Repair
**Goal**: Make AUDIT-03 work end-to-end by adding `VITE_API_URL: https://api.${DOMAIN_NAME}` to the admin-dashboard compose build args, and fixing the W_AUDIT_QUERY defects (count query never executes, `limit` vs `page_size` mismatch, status/channel filters ignored in SQL)
**Depends on**: Phases 3, 7, 11 (ops.workflow_audit table)
**Requirements**: AUDIT-03
**Status**: CODE COMPLETE (2026-06-20, plan 13-01). VITE_API_URL build arg added (prod+base); AuditLogView dead var removed; W_AUDIT_QUERY count/limit/filter defects fixed. VPS rebuild + e2e verification deferred per `.planning/REMAINING-WORK.md`.
**Plans:** 0 plans

### Phase 14: Nyquist Compliance & Documentation Cleanup
**Goal**: Bring the planning artifacts to full audit coverage: create the missing Phase 09 VERIFICATION.md and Phase 03 VALIDATION.md, lift Phases 01/07/09/10 VALIDATION.md from draft to compliant, and close stale ROADMAP/REQUIREMENTS checkboxes
**Depends on**: Phases 9, 11, 12, 13 (so verification reflects the real runtime state)
**Requirements**: (process/quality)
**Status**: COMPLETE (2026-06-20, plan 14-01). Created 09-VERIFICATION.md (partial) and 03-VALIDATION.md; lifted 01/07/09/10 VALIDATIONs to compliant. ROADMAP/REQUIREMENTS/STATE reconciled 2026-06-19.
**Plans:** 0 plans

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. CMS Stability & Base Upgrade | 4/4 | Complete (5/6, INFRA-03 partial) | - |
| 2. Structured Logging & Correlation | 5/5 | Complete | 2026-03-23 |
| 3. Metrics, Alerting & Audit Trail | 5/5 | Complete at code (VPS gaps → 11/12/13) | 2026-03-26 |
| 4. Test Coverage — Routing & Permissions | 3/3 | Complete | - |
| 5. Test Coverage — n8n Workflow E2E | 0/2 | Superseded by Phase 8 | - |
| 6. Performance Tuning | 2/2 | Complete | 2026-03-26 |
| 7. Fix Critical Defects | 2/2 | Complete at code (regression → 12/13) | - |
| 8. n8n E2E Test Implementation | 2/2 | Complete | - |
| 9. Integration Wiring & CI Fixes | 2/2 | Partial (VPS blockers; no VERIFICATION) | - |
| 10. Verification & Nyquist Compliance | 2/2 | Complete | 2026-03-30 |
| 11. VPS Ops — Migration & Audit Chain | 0/0 | Researched, deferred (VPS-only) | - |
| 12. W_QUEUE_METRICS Runtime Fix | 1/1 | Code complete (VPS import deferred) | 2026-06-20 |
| 13. Admin Dashboard Audit-Log Repair | 1/1 | Code complete (VPS rebuild deferred) | 2026-06-20 |
| 14. Nyquist Compliance & Doc Cleanup | 1/1 | Complete | 2026-06-20 |

**Milestone status:** 27/34 requirements satisfied at code level (per 2026-04-04 audit). The 7 runtime
requirements (METR-01/02/04/05, AUDIT-02/03/04) are now **code-complete** via Phases 12 (METR) and 13
(AUDIT-03), with Phase 14 closing the documentation/verification debt. What remains is purely VPS
deployment: Phase 11 (apply migration, recreate gateway, activate W_AUDIT_ARCHIVE) and the import/
rebuild/verify steps of Phases 12-13. See `.planning/REMAINING-WORK.md` for the deploy-aware checklist.
