---
phase: 4
slug: test-coverage-routing-and-permissions
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-23
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + curl (smoke scripts, zero new dependencies) |
| **Config file** | scripts/smoke-nginx-zones.sh, scripts/smoke-permissions.sh (Wave 0 creates) |
| **Quick run command** | `bash scripts/smoke-nginx-zones.sh` |
| **Full suite command** | `bash scripts/smoke-nginx-zones.sh && bash scripts/smoke-permissions.sh` |
| **Estimated runtime** | ~30 seconds (curl round-trips, no build needed) |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/smoke-nginx-zones.sh`
- **After every plan wave:** Run `bash scripts/smoke-nginx-zones.sh && bash scripts/smoke-permissions.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | TEST-01 | smoke | `bash scripts/smoke-nginx-zones.sh` | ❌ W0 | ⬜ pending |
| 4-01-02 | 01 | 1 | TEST-02 | smoke | `bash scripts/smoke-nginx-zones.sh --cors` | ❌ W0 | ⬜ pending |
| 4-01-03 | 01 | 1 | TEST-03 | smoke | `bash scripts/smoke-nginx-zones.sh --ratelimit` | ❌ W0 | ⬜ pending |
| 4-02-01 | 02 | 1 | TEST-05 | smoke | `bash scripts/smoke-permissions.sh` | ❌ W0 | ⬜ pending |
| 4-02-02 | 02 | 1 | TEST-06 | smoke | `bash scripts/smoke-permissions.sh --authenticated` | ❌ W0 | ⬜ pending |
| 4-03-01 | 03 | 2 | TEST-07 | CI | `gh workflow run` / git push to PR | ❌ W0 | ⬜ pending |
| 4-03-02 | 03 | 2 | TEST-08 | CI | `gh workflow run` / git push to PR | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/smoke-nginx-zones.sh` — 8-zone routing smoke (stubs: return 0 with TODO comments)
- [ ] `scripts/smoke-permissions.sh` — Strapi permission matrix smoke (stubs)
- [ ] `infra/gateway/nginx.smoke.conf` — nginx test config with stubs for all proxy_pass locations

*These must exist before any task in Wave 1 runs, even as stubs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Rate-limit zone state reset | TEST-03 | Redis zone state persists across requests; need fresh zone for reliable count | Wait 2s between test runs, or restart nginx between rate-limit tests |
| Public role permission seeding | TEST-05 | Strapi 5 admin API endpoint format needs first-run verification | If admin API fails, seed via: `docker exec current-postgres-1 psql -U strapi -d strapi -c "INSERT INTO up_permissions..."` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
