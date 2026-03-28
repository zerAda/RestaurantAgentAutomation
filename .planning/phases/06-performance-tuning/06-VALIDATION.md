---
phase: 6
slug: performance-tuning
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-28
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Vitest 4.0.18 |
| **Config file** | `admin-dashboard/vite.config.ts` (test section present) |
| **Quick run command** | `cd admin-dashboard && npm test` |
| **Full suite command** | `cd admin-dashboard && npm test && cd ../kiosk-app && npm test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd admin-dashboard && npm test`
- **After every plan wave:** Run `cd admin-dashboard && npm test && cd ../kiosk-app && npm test`
- **Before `/gsd:verify-work`:** Full suite must be green + DB smoke checks + bundle size delta
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-00 | 01 | 1 | PERF-01..06 | smoke/shell | `grep -c 'idx_orders_status_created' db/migrations/2026-03-26_p6_orders_indexes.sql && grep -c 'idx_orders_user_status' db/migrations/2026-03-26_p6_orders_indexes.sql && test -f scripts/verify-orders-indexes.sh && grep -q 'allkeys-lru' infra/redis/entrypoint.sh && test -f workflows/W_REDIS_MONITOR.json && grep -q 'maxmemory-policy' ENV_REFERENCE.md && echo ALL_PASS` | ✅ existing | ⬜ pending |
| 06-01-01 | 01 | 1 | PERF-07 | unit | `cd admin-dashboard && npx vitest run src/App.lazy.test.tsx` | ❌ W0 | ⬜ pending |
| 06-01-02 | 01 | 1 | PERF-08 | smoke/build | `cd admin-dashboard && npm run build && node scripts/check-bundle-size.cjs` | ❌ W0 | ⬜ pending |
| 06-01-03 | 01 | 1 | PERF-09 | unit | `cd kiosk-app && npx vitest run src/menuService.cache.test.ts` | ❌ W0 | ⬜ pending |
| 06-02-01 | 02 | 2 | PERF-08 | smoke/build | `cd admin-dashboard && npm run build 2>&1 \| tail -3 && node scripts/check-bundle-size.cjs` | ❌ W0 | ⬜ pending |
| 06-02-02 | 02 | 2 | PERF-05, PERF-08 | manual-checkpoint | User sign-off — requires human review of bundle ratio and W_REDIS_MONITOR.json | manual-only | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `admin-dashboard/src/App.lazy.test.tsx` — asserts lazy() used for all 14 route components (PERF-07)
- [ ] `admin-dashboard/scripts/check-bundle-size.cjs` — measures current build vs baseline via BUNDLE_BASELINE_KB env var (PERF-08)
- [ ] `kiosk-app/src/menuService.cache.test.ts` — asserts getProducts() returns cached result on 2nd call (PERF-09)

Pre-existing (no Wave 0 needed):
- [x] `db/migrations/2026-03-26_p6_orders_indexes.sql` — creates idx_orders_status_created + idx_orders_user_status (PERF-01, PERF-02)
- [x] `scripts/verify-orders-indexes.sh` — EXPLAIN ANALYZE script (PERF-03)
- [x] `infra/redis/entrypoint.sh` — allkeys-lru eviction policy (PERF-04)
- [x] `workflows/W_REDIS_MONITOR.json` — 15-min schedule, 200MB threshold (PERF-05)
- [x] `ENV_REFERENCE.md` — maxmemory-policy documented (PERF-06)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Redis memory logged every 15 min; alert fires at >200MB | PERF-05 | Requires live n8n execution over 15-minute interval; cannot be mocked in unit test | 1. Import W_REDIS_MONITOR workflow to n8n; 2. Wait 15 min; 3. Check structured logs for `redis_memory_mb` field; 4. Temporarily set threshold to 1MB, confirm alert fires |
| Initial JS bundle is 30% smaller than pre-split baseline | PERF-08 | Monolithic baseline no longer in codebase; entry/total ratio is a proxy only | Review entry/total chunk ratio from check-bundle-size.cjs output; for exact measurement revert App.tsx lazy imports temporarily, build, record baseline, restore |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
