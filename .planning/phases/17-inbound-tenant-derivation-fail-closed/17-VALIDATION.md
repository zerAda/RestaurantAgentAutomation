---
phase: 17
slug: inbound-tenant-derivation-fail-closed
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-20
---

# Phase 17 — Validation Strategy

> Per-phase validation contract. Detailed checks derive from `17-RESEARCH.md` → `## Validation Architecture`. The planner fills the Per-Task map below.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `python3 json.load` + jq/grep structural assertions on the workflow JSONs; `node --check` on extracted Code-node JS; psql tenant-resolution assertion against ephemeral Postgres via `.github/workflows/phase-17-assertions.yml`; integrity gate |
| **Config file** | none |
| **Quick run command** | `{planner fills}` |
| **Full suite command** | `{planner fills}` |
| **Estimated runtime** | ~{N}s |

---

## Sampling Rate

- **After every task commit:** touched-workflow json.load + node --check + grep checks
- **After every plan wave:** full suite (`phase-17-assertions.yml`)
- **Before `/gsd:verify-work`:** full suite green
- **Max feedback latency:** {N}s

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 17-01-01 | 01 | 1 | TEN-03 | json/grep | `{planner fills}` | ❌ W0 | ⬜ pending |

*Planner completes from 17-RESEARCH.md Validation Architecture.*

---

## Wave 0 Requirements

- [ ] `db/ci-assertions/17-tenant-resolution.sql` — known `(channel, identity)` resolves to tenant; unknown returns 0 rows
- [ ] `.github/workflows/phase-17-assertions.yml` — CI gate (workflow-json structural + tenant-resolution SQL)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 🔴 Import updated W1/W2/W3 + W0_MODULE_GUARD + W_DRIVER_ONBOARDING workflows on prod n8n | TEN-03 | Requires prod n8n API/SSH | Deferred to prod-connected session |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < {N}s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
