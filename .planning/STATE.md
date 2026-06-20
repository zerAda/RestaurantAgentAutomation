---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: SaaS Multi-Tenant Hardening
status: complete
stopped_at: v2.0 COMPLETE — all 7 phases (15-21) verified passed (code/CI); milestone integration audit verdict COMPLETE (8/8 cross-phase seams connect); 13/13 requirements satisfied. Archived to .planning/milestones/v2.0-{ROADMAP,REQUIREMENTS,AUDIT}.md. Pushed to claude/milestone-v2-saas-hardening (PR #29, awaiting merge). 🔴 VPS cutover checklist in v2.0-AUDIT.md.
last_updated: "2026-06-20T20:05:00.000Z"
progress:
  total_phases: 7
  completed_phases: 7
  total_plans: 22
  completed_plans: 22
---

# Project State

## Project Reference

See: .planning/PROJECT.md

**Core value:** Orders placed on any channel reach the kitchen, get paid, and get delivered — reliably and without manual intervention.
**Current focus:** v2.0 — SaaS Multi-Tenant Hardening is **COMPLETE** (all 7 phases verified, audit verdict COMPLETE, 13/13 requirements). Archived in `.planning/milestones/v2.0-*.md`. Remaining work is the 🔴 VPS production cutover (see `.planning/milestones/v2.0-AUDIT.md`) + merging PR #29 to main. No next milestone defined yet — run `/gsd:new-milestone` to start one.

## Current Position

Milestone: v2.0 — SaaS Multi-Tenant Hardening — **COMPLETE & AUDITED** (2026-06-20).
All 7 phases (15-21) executed via research→plan→check→execute→verify and verified `passed` at code/CI level; milestone integration audit verdict **COMPLETE** (8/8 cross-phase seams connect end-to-end). 13/13 requirements satisfied (TEN-01..05, ENT-01..03, GRD-01, AUD-01/02, DB-01, TYP-01). Phase 21 additionally turned the long-standing Frontend Lint (admin-dashboard) + CMS TypeScript Compilation CI baselines green (lint 0, build exit 0, CMS tsc 0). All seven `phase-1X/2X-assertions.yml` gates + gitleaks + integrity gate green on the branch. Snapshotted to `.planning/milestones/v2.0-{ROADMAP,REQUIREMENTS,AUDIT}.md`.
Next: (1) merge PR #29 to main (user/MCP — not done autonomously); (2) execute the 🔴 VPS production cutover checklist in `.planning/milestones/v2.0-AUDIT.md` (migrations apply → backfill → channel_identities seed → STRAPI_API_TOKEN_INTERNAL provision → CMS rebuild → workflow import → Redis identity/eviction → live alert wiring); (3) optional `/gsd:cleanup` to archive the 15-21 phase dirs (post-merge hygiene); (4) `/gsd:new-milestone` when ready. Follow-up surfaced by the audit: kiosk O-3 (device→tenant resolution) — kiosk order-create fails closed until implemented.

### Phase 19 VPS-deferred (NOT attempted — prod-connected session required)

- Apply `db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql` to the live strapi DB using the LIVE tenant UUID discovered on prod (ADR 0001 — never hardcode `…0001`).
- Rebuild the CMS so the new `tenant-entitlement`/`product-module` `lifecycles.ts` + `audit-hook.ts` take effect.
- Confirm the prod Redis the hook's `DEL` targets is the SAME Redis the Phase-20 guard reads.
- 🔴 manual-only: admin-panel entitlement edit → audit row's `changed_by` is the real admin actor (the node-test, no Strapi boot, can't cover the `requestContext` actor path) — see 19-VALIDATION.md.

### Phase 18 VPS-deferred (NOT attempted — prod-connected session required)

- Apply `db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql` to the live strapi DB (column add + backfill + NOT NULL + `CREATE UNIQUE INDEX CONCURRENTLY (tenant_id, phone)` direct to postgres:5432, not pgbouncer:6432).
- Rebuild the CMS so the new order/customer `tenant_id` attributes + lifecycles take effect.
- Import the updated scoped workflows (W_ORDER_FINALIZER, W51, W53, W_THE_USUAL, W_ADMIN_PROACTIVE, W14, W4_CORE) on prod n8n.

### Previous milestone — v1.0 Platform Hardening & Reliability (archived)

13/14 phases complete; ROADMAP/REQUIREMENTS archived to `.planning/milestones/v1.0-*.md`. Phases 12/13/14 code-complete (merged to main via PRs #26/#27/#28). Only VPS-runtime deploy steps remain (Phase 11 + 12/13 deploy), tracked in `.planning/REMAINING-WORK.md`.

**v1.0 status by remaining phase:**

- Phase 09 — PARTIAL: CI goals verified; 2 VPS activation items deferred to Phase 11. 09-VERIFICATION.md now exists (status: partial).

**Status by remaining phase:**

- Phase 09 — PARTIAL: CI goals verified; 2 VPS activation items deferred to Phase 11. 09-VERIFICATION.md now exists (status: partial).
- Phase 11 — Researched only; VPS runtime ops; DEFERRED to a prod-connected session.
- Phase 12 — CODE COMPLETE (2026-06-20): W_QUEUE_METRICS.json fixed. VPS import deferred.
- Phase 13 — CODE COMPLETE (2026-06-20): compose VITE_API_URL + W_AUDIT_QUERY + AuditLogView fixed. VPS rebuild deferred.
- Phase 14 — COMPLETE (2026-06-20): 09-VERIFICATION.md + 03-VALIDATION.md created; 01/07/09/10 VALIDATIONs lifted to compliant.

## Performance Metrics

**Velocity:**

- Plans executed: 30 of 32 (Phase 5's 2 plans were superseded by Phase 8)
- Phases with passing/partial VERIFICATION.md: 9 (1,2,3,4,6,7,8,10 passed; 9 partial)
- Branch: gap-closure work on `claude/gap-closure-phases-12-14`; docs reconciliation on `claude/intelligent-galileo-w170kg` (PR #26)

**By Phase:**

| Phase | Plans | Status |
|-------|-------|--------|
| 01-cms-stability-and-base-upgrade | 4/4 | Complete (5/6, INFRA-03 partial) |
| 02-structured-logging-and-correlation | 5/5 | Complete |
| 03-metrics-alerting-and-audit-trail | 5/5 | Complete at code (VPS gaps → 11/12/13) |
| 04-test-coverage-routing-and-permissions | 3/3 | Complete |
| 05-test-coverage-n8n-workflow-e2e | 0/2 | Superseded by Phase 8 |
| 06-performance-tuning | 2/2 | Complete |
| 07-fix-critical-defects | 2/2 | Complete at code |
| 08-n8n-e2e-test-implementation | 2/2 | Complete |
| 09-integration-wiring-and-ci-fixes | 2/2 | Partial (VPS blockers; VERIFICATION now partial) |
| 10-verification-and-nyquist-compliance | 2/2 | Complete |
| 11-vps-ops-db-migration-and-audit-chain | 0/0 | Researched, deferred (VPS-only) |
| 12-w-queue-metrics-runtime-fix | 1/1 | Code complete (VPS import deferred) |
| 13-admin-dashboard-audit-log-repair | 1/1 | Code complete (VPS rebuild deferred) |
| 14-nyquist-compliance-and-documentation-cleanup | 1/1 | Complete |
| Phase 19 Pall | ~70m | 8 tasks | 10 files |
| Phase 20 P01 | 5min | 3 tasks | 5 files |
| Phase 20 P02 | 3min | 3 tasks | 7 files |
| Phase 20 P03 | 2min | 2 tasks | 4 files |
| Phase 21 P02 | 4 | 3 tasks | 7 files |
| Phase 21 P03 | 2 | 2 tasks | 2 files |
| Phase 21 P04 | 2 | 2 tasks | 6 files |
| Phase 21 P01 | 4 | 3 tasks | 5 files |

## Accumulated Context

### Decisions

- Phase 19 (ADR 0003): `entitlement_audit_log` stays in the strapi DB; writer is raw Knex `strapi.db.connection` (the table is NOT a Strapi content type, so `strapi.db.query('api::…')` is impossible) — no cross-DB connection, no table move
- Phase 19: cache key LOCKED `ralphe:entitlement:{tenant_id}:{module_key}` (ROADMAP:147; exact-key DEL must match the Phase-20 GRD-01 GET byte-for-byte); product-module = audit-only (O-1, TTL-bounded, no global flush); single-row only (O-2, bulk *Many out of scope)
- Phase 19 (Blocker B correction): `entitlement_audit_log.tenant_id` is `uuid NULL` + nullable FK (parity with `admin_audit_log`); global product-module audit rows carry `tenant_id = NULL` — the all-zero sentinel is NOT used
- Phase 19 (Blocker A correction): `phase-19-assertions.yml` pins `actions/setup-node@v4.1.0` node-version 22 before every node step (the phase-18 mirror has no setup-node → would default to Node 20; `node --test --experimental-strip-types` of the `.ts` helper needs Node ≥22.18)
- Phase 19: `validateTenantId` uses `z.string().guid()` not `.uuid()` — zod 4's `.uuid()` enforces RFC-9562 variant bits and rejects the all-zero canonical/sentinel UUIDs the Postgres `uuid` column accepts
- Milestone scope: Fix-first; no new features this milestone (stabilize before extending)
- CMS routes: Fix by adding TS source files to inventory-cms/src/api/ — never runtime injection
- Node.js: Upgrade all Dockerfiles 18-alpine -> 20-alpine (EOL security fix)
- The 2026-04-04 milestone audit restructured the milestone into 14 phases (gap-closure 7-14)
- Phase 5 (n8n E2E) was superseded by Phase 8
- W_QUEUE_METRICS uses hardcoded PG credential ID `1mZZJEscADgQ8InR` (n8n DB) and Redis credential ID `43SDqJYMGa6RvFqW` — the `$env.*` expression form evaluated to empty on VPS (root cause of METR-01/02/04/05)
- n8n Code nodes must use POSIX `df -k /` for disk introspection (GNU `stat -f -c` fails on Alpine/busybox)
- Vite build args must be passed through docker-compose (not just declared as ARG in Dockerfile) — root cause of AUDIT-03 URL bug
- ops.workflow_audit migration targets the n8n database (user=n8n, db=n8n), NOT strapi
- NemoClaw Telegram Bot descoped from v1.0 (intended for its own repository)
- [Phase 20]: 20-01: W0_MODULE_GUARD restructured into Redis cache-aside (GET/SET nodes around pure .mjs seam); HIT skips both Strapi fetches (graph-proven); cache stores RAW row (expiry re-eval on read); transient GUARD_ERROR_FAILCLOSED never cached
- [Phase 20]: 20-02: STRAPI_API_TOKEN_INTERNAL first-class secret — HARD ${VAR:?} prod / SOFT base + .env.example + secrets inventory + preflight.sh REQ_VARS fail-fast (ENT-03)
- [Phase 20]: 20-03: pure downstream classify-deny.mjs maps GUARD_ERROR_FAILCLOSED->pageable HIGH vs NO_ENTITLEMENT->non-pageable LOW (unknown->safe-default HIGH); wiring documented into security_events.severity + W8_OPS ALERT_WEBHOOK_URL; guard topology unchanged (O-3, GRD-01 crit 4)
- [Phase 21]: 21-01 (ENT-01): useEntitlements fail-closed — SHARED_CORE allowlist (platform_runtime, order_bot_core) visible in every state (no admin lockout), non-core false while loading/error; explicit error/status + EntitlementErrorBanner; DTO-typed (6 any cleared); fallback #5 KEPT-but-fail-closed-on-result (no tenant UUID in UI)
- [Phase 21]: 21-02 (ENT-02): 6 ghost module_keys reconciled (3 App.tsx + 3 workflows); W_ORDER_FINALIZER->order_bot_core deliberately (NOT payment, so COD not denied); scripts/check-module-keys.mjs one-directional check + manifest==seeder guard; phase-21-assertions.yml created (admin lint/vitest Node 20, module-key Node 22)
- [Phase 21]: 21-03 (TYP-01): shared v4/v5-tolerant DTOs (ProductModuleRaw/TenantEntitlementRaw/unwrap) in src/types/entitlements.ts; AIChatBubble as-any+disable retired via AgentChatResponse; 4 already-clean components untouched
- [Phase 21]: 21-04 (TYP-01): CMS TS fully green (0 errors) — 4 @ts-ignore UID lines + static ioredis import (realtime.ts pattern); cms-ts-compile job appended Node 20

### Reconciliation & gap-closure (2026-06-19 → 2026-06-20)

- 2026-06-19: ROADMAP/REQUIREMENTS/STATE reconciled to 14-phase disk reality (PR #26, branch claude/intelligent-galileo-w170kg) — docs-only.
- 2026-06-20: local gap-closure executed on branch claude/gap-closure-phases-12-14:
  - Phase 12 — `workflows/W_QUEUE_METRICS.json`: hardcoded PG/Redis credential IDs + `df -k /` disk check.
  - Phase 13 — `docker-compose.{hostinger.prod,base}.yml` VITE_API_URL build arg; `AuditLogView.tsx` dead-var removal; `workflows/W_AUDIT_QUERY.json` count node + limit alias + status/channel filters.
  - Phase 14 — created 09-VERIFICATION.md (partial) + 03-VALIDATION.md; lifted 01/07/09/10 VALIDATIONs to compliant.
- All VPS deploy/import/verify steps remain deferred (no prod SSH).

### Roadmap Evolution

- Original 7-phase plan (phase 7 = NemoClaw) replaced after the 2026-04-04 audit
- Gap-closure phases added: 07 fix-critical-defects, 08 n8n-e2e, 09 integration-wiring, 10 verification-nyquist, 11 vps-ops, 12 w-queue-metrics-fix, 13 admin-audit-log-repair, 14 nyquist-doc-cleanup

### Pending Todos

None.

### Blockers/Concerns

- **VPS access required** for Phase 11 and the deploy steps of Phases 12-13 (SSH `deploy@72.60.190.192`) — unavailable from this environment; deferred (see REMAINING-WORK.md)
- CI baseline on the repo is red for reasons unrelated to these changes (gitleaks full-history scan; pre-existing `no-explicit-any` lint in `useEntitlements.ts`; integration/CMS jobs) — accepted as pre-existing debt
- No automated DB backup — deferred to v2 (BAK-01..03 out of scope)
- Disk risk: 119GB VPS; ENOSPC corrupts files — monitor during image rebuilds
- Pending security actions (historical): rotate Telegram Bot Token exposed in commit cd133f19; rotate n8n encryption key / API keys exposed in historical commits

## Session Continuity

Last session: 2026-06-20T19:38:42.514Z
Stopped at: Completed 21-02/21-03/21-04/21-01-PLAN.md (all 4 plans; code/CI complete; awaiting verifier). Lint 0 / vitest 11 / CMS tsc 0 / module-key exit 0 / integrity exit 0. NOT pushed.
Resume file: None

### To finish v1.0 (VPS-connected session required)

- Phase 11: apply `db/migrations/2026-03-23_p3_workflow_audit.sql` to the n8n DB, `docker compose up -d gateway`, re-import + activate W_AUDIT_ARCHIVE.
- Phase 12 deploy: import the fixed `W_QUEUE_METRICS.json` on VPS; verify METR-04/05 alerts fire.
- Phase 13 deploy: rebuild + redeploy admin-dashboard image; verify AuditLogView end-to-end against `ops.workflow_audit`.
- Then: `/gsd:audit-milestone` (expect 34/34) → `/gsd:complete-milestone v1.0`.
