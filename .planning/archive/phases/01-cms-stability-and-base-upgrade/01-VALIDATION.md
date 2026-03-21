---
phase: 1
slug: cms-stability-and-base-upgrade
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-18
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + curl (smoke scripts) + vitest 4.0.18 (admin-dashboard unit tests) |
| **Config file** | `project/admin-dashboard/vite.config.ts` |
| **Quick run command** | `cd project/admin-dashboard && npm run test` |
| **Full suite command** | `bash project/scripts/smoke-cms-routes.sh && bash project/scripts/smoke-post-rebuild.sh` |
| **Estimated runtime** | ~10 seconds (unit) / ~2 minutes (smoke after rebuild) |

---

## Sampling Rate

- **After every task commit:** Run `cd project/admin-dashboard && npm run test`
- **After every plan wave:** Run full smoke suite against running CMS container
- **Before `/gsd:verify-work`:** All 15 CMS routes return 200; Dockerfile static checks pass
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | CMS-01 | static check | `ls project/inventory-cms/src/api/*/routes/` | ✅ | ⬜ pending |
| 1-01-02 | 01 | 1 | CMS-01 | manual smoke | `bash project/scripts/smoke-cms-routes.sh` | ❌ W0 | ⬜ pending |
| 1-01-03 | 01 | 1 | CMS-02 | manual smoke | `docker compose build cms --no-cache` + smoke | ❌ W0 | ⬜ pending |
| 1-01-04 | 01 | 1 | CMS-03 | manual smoke | `bash project/scripts/smoke-cms-routes.sh` after restart | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 1 | INFRA-01 | static check | `grep "FROM node:20" project/admin-dashboard/Dockerfile` | ✅ | ⬜ pending |
| 1-02-02 | 02 | 1 | INFRA-02 | static check | `grep "FROM node:20" project/inventory-cms/Dockerfile` | ✅ | ⬜ pending |
| 1-02-03 | 02 | 2 | INFRA-03 | manual smoke | `bash project/scripts/smoke-post-rebuild.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `project/scripts/smoke-cms-routes.sh` — curl all 15 critical routes, check HTTP status; covers CMS-01, CMS-02, CMS-03
- [ ] `project/scripts/smoke-post-rebuild.sh` — admin login check, kiosk product display, CMS health endpoint; covers INFRA-03

*Existing infrastructure (vitest, bash, curl) covers all other requirements — no new framework install needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CMS image clean rebuild succeeds | CMS-02 | Requires VPS SSH + 15-30 min build time | `ssh deploy@72.60.190.192 "cd /opt/resto/current && docker compose build cms --no-cache"` |
| Disk space pre-check | CMS-02 | Must verify > 10GB free before `--no-cache` build | `ssh deploy@72.60.190.192 "df -h /opt/resto"` |
| singleType URLs correct | CMS-03 | Verify `/api/system-config` (not `/api/system-configs`) | `curl https://cms.srv1258231.hstgr.cloud/api/system-config` → 200 |
| control-plane/metric/realtime routes | CMS-03 | Custom non-CRUD handlers; verify they still work post-rebuild | `curl https://api.srv1258231.hstgr.cloud/v1/inbound/whatsapp` → not 502 |
