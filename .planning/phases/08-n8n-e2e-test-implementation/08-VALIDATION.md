---
phase: 8
slug: n8n-e2e-test-implementation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-28
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + curl + psql + redis-cli (same as test_harness.sh) |
| **Config file** | docker/docker-compose.test.yml (existing, already complete) |
| **Quick run command** | `bash -n scripts/test-n8n-e2e.sh` |
| **Full suite command** | `bash scripts/test-n8n-e2e.sh` |
| **Estimated runtime** | ~90 seconds (excluding stack startup) |

---

## Sampling Rate

- **After every task commit:** Run `bash -n scripts/test-n8n-e2e.sh` (syntax check, no Docker required)
- **After every plan wave:** Run full suite (`bash scripts/test-n8n-e2e.sh` — requires running compose stack)
- **Before `/gsd:verify-work`:** Full suite must be green (`test_harness.sh` AND `test-n8n-e2e.sh`)
- **Max feedback latency:** ~90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 8-01-01 | 01 | 1 | TEST-09, TEST-10 | structural | `bash -n scripts/test-n8n-e2e.sh` | ❌ W0 | ⬜ pending |
| 8-01-02 | 01 | 1 | TEST-09, TEST-10 | integration | `bash scripts/test-n8n-e2e.sh` | ❌ W0 | ⬜ pending |
| 8-02-01 | 02 | 2 | TEST-11 | structural | `grep "n8n-workflow-e2e" .github/workflows/ci.yml` | ✅ | ⬜ pending |
| 8-02-02 | 02 | 2 | TEST-11 | structural | `grep "test-n8n-e2e.sh" .github/workflows/ci.yml` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/test-n8n-e2e.sh` — covers TEST-09 (Meta-signed WA inbound + Postgres DB assertion) and TEST-10 (outbox retry seeding + Redis re-queue verification)
- [ ] `.github/workflows/ci.yml` — new `n8n-workflow-e2e` job with inline full compose lifecycle (covers TEST-11); update ci-summary `needs` and summary table

*(docker/docker-compose.test.yml already has all required env vars — no Wave 0 gap there)*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full E2E smoke against live VPS | TEST-09 | Requires VPS access, live n8n, Strapi, and real Meta HMAC | Run `bash scripts/smoke-n8n-e2e.sh` from local with VPS SSH tunnel or directly on VPS |
| Redis Bull queue exponential backoff verified at runtime | TEST-10 | Requires a running n8n queue with real Bull job scheduling | 1. Seed failing outbox entry. 2. Wait 35s for W15 cron. 3. Run `redis-cli LRANGE bull:n8n:wait 0 -1` — verify job has `attempts+1` and future `nextRetryAt` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
