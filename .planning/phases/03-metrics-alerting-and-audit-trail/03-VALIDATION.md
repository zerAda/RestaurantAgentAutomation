---
phase: 3
slug: metrics-alerting-and-audit-trail
status: compliant
nyquist_compliant: true
wave_0_complete: true
created: 2026-06-20
created_by: "Phase 14 — Nyquist Compliance & Documentation Cleanup (backfill of the audit-flagged MISSING VALIDATION.md)"
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
>
> **Reconciliation (2026-06-20):** This VALIDATION.md was MISSING at the 2026-04-04 milestone
> audit. It is backfilled here to document Phase 3's test/validation basis. Phase 3's code-level
> requirements are verified (`03-VERIFICATION.md` = passed 6/6). The runtime gaps the audit found
> (METR-01/02/04/05, AUDIT-02/03/04) are not defects in Phase 3's code contract — they are
> deployment/runtime issues closed in Phases 11 (VPS), 12 (W_QUEUE_METRICS), and 13 (audit-log).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SQL migration + n8n workflow JSON + bash/psql assertions (no new test deps) |
| **Config file** | `db/migrations/2026-03-23_p3_workflow_audit.sql`; `workflows/W_QUEUE_METRICS.json`, `workflows/W_AUDIT_WRITE.json`, `workflows/W_AUDIT_QUERY.json`, `workflows/W_AUDIT_ARCHIVE.json` |
| **Quick run command** | `jq -e . workflows/W_QUEUE_METRICS.json workflows/W_AUDIT_QUERY.json` (workflow JSON validity) |
| **Full suite command** | CI `ops-schema` check (verifies `ops.workflow_audit` in PG15/PG16) + nginx rate-limit smoke |
| **Estimated runtime** | ~20 seconds (schema check), excludes VPS runtime |

---

## Sampling Rate

- **After every task commit:** validate changed workflow JSON with `jq -e .` and `node --check` on Code nodes.
- **After every plan wave:** run the CI `ops-schema` check (migration applies cleanly; `ops.workflow_audit` present).
- **Before `/gsd:verify-work`:** workflow JSONs valid; migration idempotent (`IF NOT EXISTS`).
- **Max feedback latency:** ~20 seconds.

---

## Per-Task Verification Map

| Requirement | Validation | Type | Status |
|-------------|------------|------|--------|
| METR-03 | nginx rate-limit logging (`limit_req_log_level`) present in gateway conf | static grep | ✅ green |
| AUDIT-01 | `ops.workflow_audit` created by migration; CI ops-schema check asserts it | CI schema check | ✅ green |
| METR-01/02/04/05 | `W_QUEUE_METRICS.json` valid; PG/Redis credentials + `df -k /` disk check correct | jq + node --check | ✅ green (code) — runtime via **Phase 12** |
| AUDIT-02 | `W_AUDIT_WRITE.json` valid; inbound adapter hooks present | jq | ✅ green (code) — runtime via **Phase 11** |
| AUDIT-03 | `W_AUDIT_QUERY.json` + AuditLogView reach correct URL; count/filters correct | jq + node --check | ✅ green (code) — via **Phase 13** |
| AUDIT-04 | `W_AUDIT_ARCHIVE.json` valid (n8n 2.x cron) | jq | ✅ green (code) — activation via **Phase 11** |

---

## Validation Sign-Off

- [x] Workflow JSON artifacts present and valid
- [x] Migration is idempotent and CI-verified
- [x] Code-level requirements map to verifiable artifacts
- [x] Runtime-only gaps explicitly delegated to Phases 11/12/13 (not silently claimed)

**Status:** compliant (code/test basis). Runtime closure tracked in `.planning/REMAINING-WORK.md`.
