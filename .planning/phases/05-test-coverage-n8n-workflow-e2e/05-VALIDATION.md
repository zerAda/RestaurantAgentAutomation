---
phase: 5
slug: test-coverage-n8n-workflow-e2e
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-24
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + docker compose (scripts/test_harness.sh) |
| **Config file** | docker/docker-compose.test.yml |
| **Quick run command** | `bash scripts/test_harness.sh --smoke` |
| **Full suite command** | `bash scripts/test_harness.sh` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/test_harness.sh --smoke`
- **After every plan wave:** Run `bash scripts/test_harness.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 5-01-01 | 01 | 1 | TEST-09 | integration | `bash scripts/test_harness.sh --test whatsapp-inbound` | ❌ W0 | ⬜ pending |
| 5-01-02 | 01 | 1 | TEST-09 | integration | `bash scripts/test_harness.sh --test whatsapp-inbound` | ❌ W0 | ⬜ pending |
| 5-02-01 | 02 | 2 | TEST-10 | integration | `bash scripts/test_harness.sh --test outbox-retry` | ❌ W0 | ⬜ pending |
| 5-02-02 | 02 | 2 | TEST-10 | integration | `bash scripts/test_harness.sh --test outbox-retry` | ❌ W0 | ⬜ pending |
| 5-03-01 | 03 | 3 | TEST-11 | CI | `act -j integration-tests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/test_harness.sh --test whatsapp-inbound` subcommand — stub for TEST-09
- [ ] `scripts/test_harness.sh --test outbox-retry` subcommand — stub for TEST-10
- [ ] `docker/docker-compose.test.yml` extended with Redis credential env vars for W15

*Existing test_harness.sh infrastructure covers the base stack — Wave 0 adds test-specific subcommands.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Meta HMAC signature validation | TEST-09 | Requires live webhook secret | Use generate_signature() from test_e2e.sh with real payload |

*All other phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
