---
phase: 20-redis-cached-fail-closed-guard-and-internal-token-provisioning
plan: 03
subsystem: infra
tags: [alerting, classifier, security-events, w8-ops, node-test, ci, fail-closed]

# Dependency graph
requires:
  - phase: 20-redis-cached-fail-closed-guard-and-internal-token-provisioning
    provides: "20-01's guard emits the stable reason prefixes (GUARD_ERROR_FAILCLOSED / NO_ENTITLEMENT / MODULE_NOT_FOUND / EXPIRED) the classifier keys off; 20-01 created phase-20-assertions.yml this plan appends to"
provides:
  - "scripts/guard/classify-deny.mjs — pure reason->{class,severity,pageable,alertKey} classifier (downstream-only, O-3)"
  - "scripts/guard/__tests__/classify-deny.test.mjs — node --test (11 tests)"
  - "docs/guard-alert-split.md — severity contract + downstream wiring into security_events.severity + W8_OPS ALERT_WEBHOOK_URL"
  - "guard-alert-classifier CI job appended to phase-20-assertions.yml"
affects: [alerting, ops, on-call, vps-workflow-import]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure downstream reason-classifier keyed off stable prefixes; unknown->safe-default pageable HIGH (never swallow a new failure mode)"
    - "Disjoint ownership: classification lives downstream so 20-03 never edits the guard topology (O-3)"

key-files:
  created:
    - scripts/guard/classify-deny.mjs
    - scripts/guard/__tests__/classify-deny.test.mjs
    - docs/guard-alert-split.md
  modified:
    - .github/workflows/phase-20-assertions.yml

key-decisions:
  - "Downstream-only classification (O-3): classify() is consumed in the caller deny-branch / W8_OPS path, so 20-03 never touches W0_MODULE_GUARD.json — clean disjoint ownership from 20-01"
  - "FAILCLOSED matched before the generic GUARD_ERROR: prefix so the pageable outage case is never shadowed by the non-paged caller-bug case; unknown reason defaults to pageable HIGH"

patterns-established:
  - "classify(reason) safe-default: an unrecognized reason pages (GUARD_UNKNOWN) rather than being silently swallowed"

requirements-completed: [GRD-01]

# Metrics
duration: 2min
completed: 2026-06-20
---

# Phase 20 Plan 03: Guard Alert Split Summary

**A `GUARD_ERROR_FAILCLOSED` outage is now distinguishable from a legitimate `NO_ENTITLEMENT` denial in alerting — the pure `classify(reason)` seam maps the cannot-determine prefix to pageable HIGH `GUARD_FAILCLOSED` while routine denials are non-pageable LOW (unknown reason defaults to pageable HIGH), documented to wire into the existing `security_events.severity` + `W8_OPS` `ALERT_WEBHOOK_URL` plane WITHOUT editing the guard topology (O-3).**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-20T18:44:49Z
- **Completed:** 2026-06-20T18:47:15Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Pure `scripts/guard/classify-deny.mjs` `classify(reason)` keyed off the guard's stable prefixes: `GUARD_ERROR_FAILCLOSED*`->pageable HIGH `GUARD_FAILCLOSED`; `NO_ENTITLEMENT*`/`MODULE_NOT_FOUND*`/`EXPIRED*`->non-pageable LOW; `GUARD_ERROR:`->MEDIUM caller-bug; `_CACHED`/positive->allow; unknown/empty/null->safe-default pageable HIGH `GUARD_UNKNOWN`. 11/11 node --test green.
- `docs/guard-alert-split.md` documents the severity contract + EXACTLY how `classify()` plugs into the EXISTING alert plane (the caller deny-branch `security_events.severity` from `W1_IN_WA.json:240` + the `W8_OPS` `E4 - Optional Alert Webhook` `ALERT_WEBHOOK_URL` path) with the guard topology UNCHANGED.
- `guard-alert-classifier` CI job appended to `phase-20-assertions.yml` (node --test + a READ-ONLY grep that the guard still emits the prefixes); 20-01 + 20-02 jobs intact; guard JSON not modified.

## Task Commits

1. **Task 1: Pure reason-classifier seam + node --test** - `b3985f3` (feat)
2. **Task 2: Alert-split doc + append classifier CI job** - `7d546f6` (docs)

## Files Created/Modified
- `scripts/guard/classify-deny.mjs` - Pure reason->{class,severity,pageable,alertKey} classifier
- `scripts/guard/__tests__/classify-deny.test.mjs` - node --test (11 tests): every prefix + FAILCLOSED-pages/NO_ENTITLEMENT-doesn't + unknown->HIGH
- `docs/guard-alert-split.md` - severity contract + downstream wiring + contract-stability note
- `.github/workflows/phase-20-assertions.yml` - appended guard-alert-classifier job + extended paths

## Decisions Made
- O-3: downstream-only classifier — the guard keeps emitting stable prefixes; classification lives in the caller/W8_OPS path so 20-03 never edits `W0_MODULE_GUARD.json`.
- FAILCLOSED before generic `GUARD_ERROR:`; unknown->pageable HIGH safe default.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
🔴 VPS-deferred (tracked, not attempted): the live edit to the caller deny-branch (`security_events.severity` from `classify()`) + the `W8_OPS` `pageable` fan-out + importing the updated workflows on prod n8n. Documented in `docs/guard-alert-split.md`; executed in a prod-connected session.

## Next Phase Readiness
- All three Phase-20 plans complete (code/CI). The phase-20-assertions.yml gate has all 4 jobs. Phase not marked verified — awaiting `/gsd:verify-work` + the 🔴 VPS deferrals.

## Self-Check: PASSED

- FOUND: scripts/guard/classify-deny.mjs, scripts/guard/__tests__/classify-deny.test.mjs, docs/guard-alert-split.md, .github/workflows/phase-20-assertions.yml
- FOUND commits: b3985f3, 7d546f6

---
*Phase: 20-redis-cached-fail-closed-guard-and-internal-token-provisioning*
*Completed: 2026-06-20*
