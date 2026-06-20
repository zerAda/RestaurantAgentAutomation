---
phase: 09-integration-wiring-and-ci-fixes
verified: 2026-06-20T00:00:00Z
status: partial
score: 3/5 observable truths verified (2 deferred to VPS)
gaps:
  - "ops.workflow_audit table not applied to VPS (→ Phase 11)"
  - "W_AUDIT_ARCHIVE cron incompatible with n8n 2.x, not activated on VPS (→ Phase 11)"
created_by: "Phase 14 — Nyquist Compliance & Documentation Cleanup (backfill of the audit-flagged missing VERIFICATION.md, INT-04)"
---

# Phase 9: Integration Wiring & CI Fixes — Verification Report

**Phase Goal:** Activate all five Phase-3 workflows on VPS n8n so the audit chain, queue metrics, and Redis monitoring are live; inject real VPS credential IDs; fix CI smoke wiring.
**Verified:** 2026-06-20 (backfilled during Phase 14)
**Status:** partial — CI goals verified; VPS activation partially achieved, remainder deferred to Phase 11.

> This VERIFICATION.md was missing at the time of the 2026-04-04 milestone audit (gap INT-04).
> It is created here to record the achieved-vs-deferred state honestly rather than retroactively
> claim completion.

---

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | CI runs a `smoke-nginx-routing` job (burst test) on PRs touching the gateway | VERIFIED | `09-02-SUMMARY.md`; `.github/workflows/ci.yml` smoke-nginx-routing job (TEST-03, TEST-04) |
| 2 | CI verifies the `ops.workflow_audit` table in both PG15 and PG16 schema checks | VERIFIED | `09-02-SUMMARY.md`; ci.yml ops-schema check using `table_schema='ops'` (AUDIT-01) |
| 3 | Phase-3 workflow credential placeholders replaced with the real n8n credential ID and 4/5 workflows activated on VPS | VERIFIED | `09-01-SUMMARY.md`: `CREDENTIAL_ID_PLACEHOLDER → 1mZZJEscADgQ8InR`; W_AUDIT_WRITE/QUERY, W_QUEUE_METRICS, W_REDIS_MONITOR show "Activated" |
| 4 | The `ops.workflow_audit` table exists on the VPS n8n database so W_AUDIT_WRITE INSERTs succeed | DEFERRED | `09-01-SUMMARY.md` blocker 1: Phase-3 migration never run on VPS → relation-not-found. Closure: **Phase 11** |
| 5 | W_AUDIT_ARCHIVE is activated on VPS (90-day archival live) | DEFERRED | `09-01-SUMMARY.md`: cron node `propertyValues[itemName] is not iterable` on n8n 2.x; not activated. Closure: **Phase 11** |

## Goal Achievement

- **CI integration (plan 02):** fully achieved — the nginx routing smoke job and the ops-schema
  check run in CI and gate PRs. TEST-03, TEST-04, AUDIT-01 (CI-schema basis) are satisfied.
- **VPS activation (plan 01):** partially achieved — credential injection and activation of 4 of 5
  workflows succeeded; two runtime items (ops table application, W_AUDIT_ARCHIVE cron activation)
  remain blocked on prod access and are carried into Phase 11.

## Deferred / Follow-up

Both deferred truths require live VPS SSH and are tracked in `.planning/REMAINING-WORK.md` (Phase 11).
Related code-level fixes that the same audit surfaced were since closed:
- METR-01/02/04/05 credential + disk-check regression → **Phase 12** (code complete).
- AUDIT-03 admin audit-log path + W_AUDIT_QUERY defects → **Phase 13** (code complete).

## Verdict

`partial` — no regression; the phase achieved its CI objectives and the achievable portion of its
VPS objectives. The remainder is a VPS-runtime deployment task, not unfinished code.
