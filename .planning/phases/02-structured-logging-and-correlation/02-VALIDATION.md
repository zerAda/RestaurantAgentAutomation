---
phase: 2
slug: structured-logging-and-correlation
status: compliant
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-29
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + curl + python3 json.loads (in-shell JSON validation) |
| **Config file** | `scripts/smoke-correlation.sh` |
| **Quick run command** | `bash scripts/smoke-correlation.sh` |
| **Full suite command** | `bash scripts/smoke-correlation.sh` |
| **Estimated runtime** | ~30 seconds (VPS-dependent) |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/smoke-correlation.sh`
- **After every plan wave:** Run `bash scripts/smoke-correlation.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | OBS-03 | smoke | `bash scripts/smoke-correlation.sh` (OBS-03 section) | ✅ | ✅ green |
| 2-02-01 | 02 | 1 | OBS-01 | smoke | `bash scripts/smoke-correlation.sh` (OBS-01 section) | ✅ | ✅ green |
| 2-03-01 | 03 | 1 | OBS-02 | smoke | `bash scripts/smoke-correlation.sh` (OBS-02 section) | ✅ | ✅ green |
| 2-04-01 | 04 | 2 | OBS-04 | smoke | `bash scripts/smoke-correlation.sh` (OBS-04 section) | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

- [x] `scripts/smoke-correlation.sh` — OBS-01 through OBS-04 checks using bash + curl + python3 json.loads; confirmed present and covers all 4 requirements

*All wave 0 scripts existed at execution time. `scripts/smoke-correlation.sh` was created in Plan 02 (OBS-01 stub) and expanded through Plans 01-04.*

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-03-29
