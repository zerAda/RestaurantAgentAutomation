---
phase: 12-w-queue-metrics-runtime-fix
plan: "01"
subsystem: n8n-workflows
tags: [n8n, metrics, alerting, credentials, alpine, disk]
requires:
  - phase: 03-metrics-alerting-and-audit-trail
    provides: W_QUEUE_METRICS workflow (queue depth, error rate, disk + queue alerts)
provides:
  - W_QUEUE_METRICS PG node uses a valid hardcoded credential ID (METR-01, METR-02)
  - W_QUEUE_METRICS Redis nodes use a valid hardcoded credential ID (METR-04)
  - W_QUEUE_METRICS disk check uses POSIX `df -k /` (METR-05)
affects: [n8n, metrics, alerting]
tech-stack:
  added: []
  patterns:
    - "n8n credential IDs hardcoded in workflow JSON (matches W_AUDIT_ARCHIVE) rather than empty $env expressions"
    - "Disk introspection in n8n Code nodes must use POSIX `df -k`, not GNU `stat -f -c` (Alpine/busybox runtime)"
key-files:
  created: []
  modified:
    - workflows/W_QUEUE_METRICS.json
status: code-complete
requirements_closed_at_code_level: [METR-01, METR-02, METR-04, METR-05]
deferred_to_vps: ["import corrected workflow on VPS", "verify METR-04/05 alerts fire at runtime"]
---

# Phase 12 — Plan 01 Summary: W_QUEUE_METRICS Runtime Fix

## What changed

`workflows/W_QUEUE_METRICS.json` — two runtime defects fixed:

1. **Credential IDs hardcoded** (3 nodes):
   - `PG - Queue Depth` (`query-queue-depth`): `={{$env.N8N_DB_CREDENTIAL_ID || ''}}` → `1mZZJEscADgQ8InR`
   - `redis-get-queue-counter` and `redis-set-queue-counter`: `={{$env.REDIS_CREDENTIAL_ID || ''}}` → `43SDqJYMGa6RvFqW`
2. **Disk check** in `B0 - Compute Metrics` (`compute-metrics`): the `execSync("stat -f -c '%a %s %b' /")` block was replaced with `execSync('df -k /')` parsing (reads the last output line, `1K-blocks` as total and `Used` as used). Removed the unused `fs.statSync`/`clusterSize` dead code.

## Verification (local)

- `jq -e .` confirms the file is valid JSON.
- `grep` confirms 0 remaining `CREDENTIAL_ID` env expressions and exactly one `df -k /` call; no functional `stat -f` call remains (only an explanatory comment references the old form).
- Ran the new disk logic standalone under Node 22: returned `diskUsedGB=7.1`, `diskUsedPct=3` — a sane value in `[0,100]`, so the `diskUsedPct >= diskAlertPct` guard can now fire (it never could with the `-1` sentinel).

## Requirement status

METR-01, METR-02, METR-04, METR-05 are now satisfied **at code level**. Final runtime satisfaction requires importing the corrected workflow on the VPS and confirming the alerts fire — that deploy/verify step is 🔴 **deferred** (no prod SSH from this environment) and is tracked in `.planning/REMAINING-WORK.md` (Phase 12, VPS items).

## Notes

- `43SDqJYMGa6RvFqW` is the Redis credential ID documented in Phase 09's injection plan; it is not yet referenced by any other workflow, so the VPS import step should confirm it matches the live n8n Redis credential. `W_REDIS_MONITOR.json` still uses the `$env.REDIS_CREDENTIAL_ID` form — out of scope for this phase but a candidate for the same treatment.
