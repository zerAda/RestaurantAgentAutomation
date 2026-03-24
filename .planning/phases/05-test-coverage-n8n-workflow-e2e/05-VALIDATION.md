---
phase: 5
slug: test-coverage-n8n-workflow-e2e
status: active
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-24
updated: 2026-03-24
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + docker compose + curl + psql + redis-cli |
| **Config file** | docker/docker-compose.test.yml |
| **Quick run command** | `bash -n scripts/test-n8n-e2e.sh` (syntax check, no Docker) |
| **Full suite command** | `bash scripts/test-n8n-e2e.sh` (requires running compose stack) |
| **Estimated runtime** | ~90 seconds (excluding stack startup) |

---

## Sampling Rate

- **After every task commit:** Run the task's `<automated>` verify command (see map below)
- **After every plan wave:** Run `bash scripts/test-n8n-e2e.sh` against running compose stack
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-T1 | 01 | 1 | TEST-09, TEST-10 | config | `grep -c "META_APP_SECRET" docker/docker-compose.test.yml \| grep -q "1" && grep -c "META_SIGNATURE_REQUIRED" docker/docker-compose.test.yml \| grep -q "1" && grep -c "REDIS_CREDENTIAL_ID" docker/docker-compose.test.yml \| grep -q "1" && echo "PASS" \|\| echo "FAIL"` | Yes (modify existing) | pending |
| 05-01-T2 | 01 | 1 | TEST-09, TEST-10 | syntax | `bash -n scripts/test-n8n-e2e.sh && echo "SYNTAX OK" \|\| echo "SYNTAX FAIL"` | No (Wave 0) | pending |
| 05-02-T1 | 02 | 2 | TEST-11 | CI config | `grep -c "n8n-workflow-e2e" .github/workflows/ci.yml \| grep -qE "^[4-9]\|^[1-9][0-9]" && grep -A80 "n8n-workflow-e2e:" .github/workflows/ci.yml \| grep -q "docker compose.*up -d" && grep -A80 "n8n-workflow-e2e:" .github/workflows/ci.yml \| grep -q "docker compose.*down" && echo "PASS" \|\| echo "FAIL"` | Yes (modify existing) | pending |

*Status: pending -> green -> red -> flaky*

---

## Wave 0 Requirements

- [x] `docker/docker-compose.test.yml` already exists -- Task 05-01-T1 adds env vars
- [ ] `scripts/test-n8n-e2e.sh` -- Task 05-01-T2 creates this file (Wave 0 artifact)
- [x] `.github/workflows/ci.yml` already exists -- Task 05-02-T1 adds job

*All Wave 0 gaps are covered by plan tasks. No external dependencies.*

---

## Requirement Traceability

| Req ID | Behavior | Verified By | Automated Command |
|--------|----------|-------------|-------------------|
| TEST-09 | POST Meta-signed payload -> W1_IN_WA -> inbound_messages row (direct Postgres, NOT Strapi) | 05-01-T2 (test-n8n-e2e.sh TEST-09 section) | `bash scripts/test-n8n-e2e.sh` |
| TEST-10 | Failing outbox entry -> W15 processes -> re-queued with attempts+1 | 05-01-T2 (test-n8n-e2e.sh TEST-10 section) | `bash scripts/test-n8n-e2e.sh` |
| TEST-11 | Workflow E2E tests run in CI without live VPS | 05-02-T1 (n8n-workflow-e2e CI job) | CI pipeline pass on main/release |

---

## Manual-Only Verifications

None. All phase behaviors have automated verification.

Meta HMAC signature validation is automated within test-n8n-e2e.sh using `openssl dgst -sha256 -hmac` with the test secret `test_meta_app_secret_for_e2e` matching the docker-compose.test.yml env var.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify commands
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (test-n8n-e2e.sh created by 05-01-T2)
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready for execution
