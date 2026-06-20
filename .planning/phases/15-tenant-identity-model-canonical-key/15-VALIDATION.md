---
phase: 15
slug: tenant-identity-model-canonical-key
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-20
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Detailed checks are derived from `15-RESEARCH.md` → `## Validation Architecture`. The planner fills the Per-Task map below.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + psql (SQL assertions against ephemeral Postgres) + vitest (seeder assertion) + grep (fallback inventory) |
| **Config file** | none — uses CI ephemeral Postgres service + existing vitest in `inventory-cms` |
| **Quick run command** | `{quick command — planner to fill}` |
| **Full suite command** | `{full command — planner to fill}` |
| **Estimated runtime** | ~{N} seconds |

---

## Sampling Rate

- **After every task commit:** Run the quick command (SQL/seed assertion for the touched criterion)
- **After every plan wave:** Run the full suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** {N} seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | TEN-01 | doc/grep | `{command}` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky — planner completes this map from 15-RESEARCH.md Validation Architecture.*

---

## Wave 0 Requirements

- [ ] Backfill SQL assertion fixture against ephemeral Postgres (Strapi-created `tenant_entitlements` table)
- [ ] Seeder unit/seed assertion (canonical UUID, not `'default'`)
- [ ] Grep-based `DEFAULT_TENANT_ID` / `|| 'default'` fallback-inventory check

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 🔴 Live VPS entitlement-plane backfill to the real tenant UUID | TEN-01 | Requires prod SSH; discover live UUID via `SELECT tenant_id FROM tenants LIMIT 1` | Deferred to a prod-connected session per REMAINING posture |

*If none: "All phase behaviors have automated verification."*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < {N}s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
