---
phase: 4
slug: test-coverage-routing-and-permissions
status: compliant
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-23
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + curl (smoke scripts, zero new dependencies) |
| **Config file** | `scripts/smoke-nginx-routing.sh`, `scripts/smoke-strapi-permissions.sh` |
| **Quick run command** | `bash scripts/smoke-nginx-routing.sh` |
| **Full suite command** | `bash scripts/smoke-nginx-routing.sh && bash scripts/smoke-strapi-permissions.sh` |
| **Estimated runtime** | ~30 seconds (curl round-trips, no build needed) |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/smoke-nginx-routing.sh`
- **After every plan wave:** Run `bash scripts/smoke-nginx-routing.sh && bash scripts/smoke-strapi-permissions.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | TEST-01 | smoke | `bash scripts/smoke-nginx-routing.sh` | ✅ | ✅ green |
| 4-01-02 | 01 | 1 | TEST-02 | smoke | `bash scripts/smoke-nginx-routing.sh` (CORS check included) | ✅ | ✅ green |
| 4-01-03 | 01 | 1 | TEST-03 | smoke | `bash scripts/smoke-nginx-routing.sh` (burst test at lines 260-279) | ✅ | ✅ green |
| 4-02-01 | 02 | 1 | TEST-05 | smoke | `bash scripts/smoke-strapi-permissions.sh` | ✅ | ✅ green |
| 4-02-02 | 02 | 1 | TEST-06 | smoke | `bash scripts/smoke-strapi-permissions.sh` | ✅ | ✅ green |
| 4-03-01 | 03 | 2 | TEST-04 | CI | CI smoke-nginx-routing job (ci.yml) | ✅ | ✅ green |
| 4-03-02 | 03 | 2 | TEST-08 | CI | CI smoke-strapi-permissions job (ci.yml) | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `scripts/smoke-nginx-routing.sh` — 8-zone routing smoke with CORS + rate-limit burst test (TEST-01, TEST-02, TEST-03)
- [x] `scripts/smoke-strapi-permissions.sh` — Strapi permission matrix smoke (TEST-05, TEST-06)
- [x] `infra/gateway/nginx.smoke.conf` — nginx test config with stubs for all proxy_pass locations

*All wave 0 scripts created during Phase 04 execution and confirmed present.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Rate-limit zone state reset | TEST-03 | Redis zone state persists across requests; need fresh zone for reliable count | Wait 2s between test runs, or restart nginx between rate-limit tests |
| Public role permission seeding | TEST-05 | Strapi 5 admin API endpoint format needs first-run verification | If admin API fails, seed via: `docker exec current-postgres-1 psql -U strapi -d strapi -c "INSERT INTO up_permissions..."` |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-03-29
