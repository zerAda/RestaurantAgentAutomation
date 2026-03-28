---
phase: 7
slug: fix-critical-defects
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-28
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Structural verification (grep + node JSON.parse) — no unit test framework required |
| **Config file** | none — ad hoc verification commands |
| **Quick run command** | `node -e "JSON.parse(require('fs').readFileSync('workflows/W_QUEUE_METRICS.json','utf8')); console.log('valid')"` |
| **Full suite command** | Run all 9 grep/node checks in the Per-Task Verification Map below |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run the 2-3 grep checks specific to that task's file changes
- **After every plan wave:** Run full suite (all 9 checks)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 7-01-01 | 01 | 1 | METR-05 | structural | `node -e "JSON.parse(require('fs').readFileSync('workflows/W_QUEUE_METRICS.json','utf8')); console.log('valid')"` | ✅ | ⬜ pending |
| 7-01-02 | 01 | 1 | METR-05 | structural | `grep -c "df -k /" workflows/W_QUEUE_METRICS.json` | ✅ | ⬜ pending |
| 7-01-03 | 01 | 1 | METR-05 | structural | `grep -c "DISK_ALERT" workflows/W_QUEUE_METRICS.json` | ✅ | ⬜ pending |
| 7-02-01 | 02 | 1 | AUDIT-03 | structural | `grep "ARG VITE_N8N_URL" admin-dashboard/Dockerfile` | ✅ | ⬜ pending |
| 7-02-02 | 02 | 1 | AUDIT-03 | structural | `grep "ENV VITE_N8N_URL" admin-dashboard/Dockerfile` | ✅ | ⬜ pending |
| 7-02-03 | 02 | 1 | AUDIT-03 | structural | `grep "VITE_N8N_URL" docker-compose.hostinger.prod.yml` | ✅ | ⬜ pending |
| 7-02-04 | 02 | 1 | AUDIT-03 | structural | `grep "audit-log" admin-dashboard/src/pages/AuditLogView.tsx` | ✅ | ⬜ pending |
| 7-02-05 | 02 | 1 | AUDIT-03 | structural | `grep -c "audit-query" admin-dashboard/src/pages/AuditLogView.tsx` → must return 0 | ✅ | ⬜ pending |
| 7-02-06 | 02 | 1 | AUDIT-03 | structural | `node -e "JSON.parse(require('fs').readFileSync('workflows/W_AUDIT_QUERY.json','utf8')); console.log('valid')"` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

No new test infrastructure required — all verification commands operate on files that already exist (source files + workflow JSON files). No stubs, fixtures, or framework installs needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Disk alert fires correctly at threshold | METR-05 | Requires running n8n workflow against live container with real df output | 1. Import updated W_QUEUE_METRICS.json to VPS n8n. 2. Set diskAlertPct to current disk usage - 1 in config. 3. Trigger workflow manually. 4. Check n8n-main logs for DISK_ALERT CRITICAL event |
| AuditLogView renders audit records | AUDIT-03 | Requires rebuilt admin-dashboard image + running n8n + Strapi with audit data | 1. Rebuild admin-dashboard with new Dockerfile. 2. Open admin dashboard AuditLogView. 3. Confirm records appear (no empty state or error) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
