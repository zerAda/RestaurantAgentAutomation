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
| 06-01-01 | 01 | 1 | PERF-01 | smoke/shell | `psql $DATABASE_URL -c "\d orders" \| grep idx_orders_status_created` | ❌ W0 | ⬜ pending |
| 06-01-02 | 01 | 1 | PERF-02 | smoke/shell | `psql $DATABASE_URL -c "\d orders" \| grep idx_orders_customer_status` | ❌ W0 | ⬜ pending |
| 06-01-03 | 01 | 1 | PERF-03 | smoke/shell | `DATABASE_URL=... bash scripts/verify-orders-indexes.sh` | ❌ W0 | ⬜ pending |
| 06-02-01 | 02 | 1 | PERF-04 | smoke/shell | `docker exec current-redis-1 redis-cli CONFIG GET maxmemory-policy \| grep allkeys-lru` | ❌ W0 | ⬜ pending |
| 06-02-02 | 02 | 1 | PERF-05 | manual-only | N/A — requires live n8n execution over time | manual-only | ⬜ pending |
| 06-02-03 | 02 | 1 | PERF-06 | unit (file existence) | `test -f ENV_REFERENCE.md && grep -q maxmemory-policy ENV_REFERENCE.md` | ❌ W0 | ⬜ pending |
| 06-03-01 | 03 | 2 | PERF-07 | unit | `cd admin-dashboard && npm test -- --run src/App.lazy.test.tsx` | ❌ W0 | ⬜ pending |
| 06-03-02 | 03 | 2 | PERF-08 | smoke/build | `cd admin-dashboard && npm run build && node scripts/check-bundle-size.js` | ❌ W0 | ⬜ pending |
| 06-04-01 | 04 | 2 | PERF-09 | unit | `cd kiosk-app && npm test -- --run src/menuService.cache.test.ts` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/verify-orders-indexes.sh` — EXPLAIN ANALYZE script for PERF-01, PERF-02, PERF-03
- [ ] `admin-dashboard/src/App.lazy.test.tsx` — asserts lazy() used for all route components (PERF-07)
- [ ] `admin-dashboard/scripts/check-bundle-size.js` — compares current build vs baseline (PERF-08)
- [ ] `kiosk-app/src/menuService.cache.test.ts` — asserts getProducts() returns cached result on 2nd call (PERF-09)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Redis memory logged every 15 min; alert fires at >200MB | PERF-05 | Requires live n8n execution over 15-minute interval; cannot be mocked in unit test | 1. Import W_REDIS_MONITOR workflow to n8n; 2. Wait 15 min; 3. Check structured logs for `redis_memory_mb` field; 4. Temporarily set threshold to 1MB, confirm alert fires |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
