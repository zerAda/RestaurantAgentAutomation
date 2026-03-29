---
phase: 9
slug: integration-wiring-and-ci-fixes
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-29
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash smoke scripts + psql assertions |
| **Config file** | `.github/workflows/ci.yml` |
| **Quick run command** | `bash scripts/smoke-nginx-routing.sh` |
| **Full suite command** | CI pipeline (GitHub Actions) |
| **Estimated runtime** | ~60 seconds (smoke) / ~10 min (full CI) |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/smoke-nginx-routing.sh` for CI-related tasks; SSH verification query for VPS activation tasks
- **After every plan wave:** Full CI pipeline passes
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 9-01-01 | 01 | 1 | AUDIT-02, AUDIT-04, METR-01, METR-02, METR-04 | VPS SQL | `ssh deploy@72.60.190.192 "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \"SELECT name, active FROM workflow_entity WHERE name LIKE 'W_AUDIT%' OR name LIKE 'W_QUEUE%' OR name LIKE 'W_REDIS%' ORDER BY name;\""` | ✅ | ⬜ pending |
| 9-01-02 | 01 | 1 | AUDIT-02 | VPS smoke | `ssh deploy@72.60.190.192 "curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:5678/webhook/v1/internal/audit-write -H 'Content-Type: application/json' -d '{}'"`  | ❌ W0 | ⬜ pending |
| 9-02-01 | 02 | 2 | TEST-03, TEST-04 | CI smoke | `bash scripts/smoke-nginx-routing.sh` | ✅ | ⬜ pending |
| 9-02-02 | 02 | 2 | AUDIT-01 | CI integration | `psql -h localhost -U n8n -d n8n -t -c "SELECT 1 FROM information_schema.tables WHERE table_schema='ops' AND table_name='workflow_audit';"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `ci.yml` smoke-nginx-routing job: remove `services: nginx:` block, switch to `smoke-nginx-routing.sh`, remove warning suppression
- [ ] `ci.yml` integration-tests `Verify schema integrity` step: add `OPS_EXPECTED_TABLES="workflow_audit"` loop
- [ ] `ci.yml` integration-tests-pg16 `Verify schema integrity` step: same addition
- [ ] `ci.yml` `on: pull_request:` trigger: add `paths:` entry for `infra/gateway/nginx.conf`
- [ ] VPS workflow import/activation script: check existence → import if missing → patch credentials → SQL activate → restart n8n-main → verify

*Existing infrastructure covers the nginx burst smoke test (smoke-nginx-routing.sh already has the TEST-03 burst logic); Wave 0 wires it into CI and verifies VPS activation.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| W_AUDIT_ARCHIVE 90-day cron fires | AUDIT-04 | Cron schedule cannot be triggered on-demand | Verify `active=true` in `workflow_entity` and cron expression `0 2 * * *` is set; manual trigger or wait for next execution window |
| Queue alert threshold fires (>50 depth) | METR-04 | Requires real queue backlog to test threshold logic | Verify W_QUEUE_METRICS is active and has correct alert threshold expression; functional test deferred to load test phase |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
