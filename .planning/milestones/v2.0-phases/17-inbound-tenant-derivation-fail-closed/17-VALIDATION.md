---
phase: 17
slug: inbound-tenant-derivation-fail-closed
status: planned
nyquist_compliant: true
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
| **Config file** | `.github/workflows/phase-17-assertions.yml` |
| **Quick run command** | `for f in W1_IN_WA W2_IN_IG W3_IN_MSG; do python3 -c "import json;json.load(open('workflows/$f.json'))"; jq -e '.nodes[]\|select(.name=="B0 - Resolve Channel Identity (DB)")' workflows/$f.json; done` |
| **Full suite command** | `act pull_request -W .github/workflows/phase-17-assertions.yml` (or push to PR) |
| **Estimated runtime** | ~90s (CI: PG service start + migration + SQL + jq structural) |

---

## Sampling Rate

- **After every task commit:** touched-workflow json.load + node --check + grep checks
- **After every plan wave:** full suite (`phase-17-assertions.yml`)
- **Before `/gsd:verify-work`:** full suite green
- **Max feedback latency:** ~90s (full CI suite); <5s for per-task local jq/grep/node-check

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 17-01-01 | 01 | 1 | TEN-03 | json/jq | `for f in W1_IN_WA W2_IN_IG W3_IN_MSG; do python3 -c "import json;json.load(open('workflows/$f.json'))"; jq -e '.nodes[]\|select(.name=="B0 - Resolve Channel Identity (DB)")' workflows/$f.json; jq -e '.connections["B0 - Map Channel Identity Result"].main[0][0].node=="B0 - Apply Auth Context"' workflows/$f.json; done` | ✅ after 17-03 W0 | ⬜ pending |
| 17-01-02 | 01 | 1 | TEN-03 | node --check / grep | `for f in W1_IN_WA W2_IN_IG W3_IN_MSG; do jq -r '.nodes[]\|select(.name=="B0 - Apply Auth Context")\|.parameters.jsCode' workflows/$f.json>/tmp/a.js; node --check /tmp/a.js; grep -q UNKNOWN_CHANNEL_IDENTITY /tmp/a.js; grep -q ci_tenant_id /tmp/a.js; ! grep -Eq "\|\| *'default'\|DEFAULT_TENANT_ID\|00000000-0000-0000-0000-000000000001" /tmp/a.js; done` | ✅ | ⬜ pending |
| 17-02-01 | 02 | 1 | TEN-03 | node --check / grep | `jq -r '.nodes[]\|select(.name=="Module Guard")\|.parameters.jsCode' workflows/W0_MODULE_GUARD.json>/tmp/g.js; node --check /tmp/g.js; ! grep -Eq "\|\| *'default'\|DEFAULT_TENANT_ID" /tmp/g.js; ! grep -rq __inventory_15 workflows/W0_MODULE_GUARD.json workflows/W_DRIVER_ONBOARDING.json` | ✅ | ⬜ pending |
| 17-02-02 | 02 | 1 | TEN-03 | grep | `[ $(grep -c "REMOVED (Phase 17)" docs/adr/0002-tenant-id-fallback-inventory.md) -ge 3 ] && grep -qi "Post-Phase 17" docs/adr/0002-tenant-id-fallback-inventory.md` | ✅ | ⬜ pending |
| 17-03-01 | 03 | 1 | TEN-03 | psql (ephemeral PG) | `psql -v ON_ERROR_STOP=1 -d n8n -f db/ci-assertions/17-tenant-resolution.sql` (known WA+IG resolve; unknown → 0 rows) | ❌ W0 | ⬜ pending |
| 17-03-02 | 03 | 1 | TEN-03 | yaml / CI gate | `python3 -c "import yaml;yaml.safe_load(open('.github/workflows/phase-17-assertions.yml'))"`; full gate via `act pull_request -W .github/workflows/phase-17-assertions.yml` | ❌ W0 | ⬜ pending |

*Wave-0 SQL + CI gate files (17-03) are themselves the validation infrastructure; they are created in this phase (Plan 17-03, also Wave 1) and gate 17-01/17-02 structurally.*

---

## Wave 0 Requirements

- [ ] `db/ci-assertions/17-tenant-resolution.sql` — known `(channel, identity)` resolves to tenant; unknown returns 0 rows (Plan 17-03 Task 1)
- [ ] `.github/workflows/phase-17-assertions.yml` — CI gate (workflow-json structural + tenant-resolution SQL) (Plan 17-03 Task 2)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 🔴 Import updated W1/W2/W3 + W0_MODULE_GUARD + W_DRIVER_ONBOARDING workflows on prod n8n | TEN-03 | Requires prod n8n API/SSH | Deferred to prod-connected session |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (17-tenant-resolution.sql + phase-17-assertions.yml, both in Plan 17-03)
- [x] No watch-mode flags
- [x] Feedback latency < 90s (full suite); <5s per-task local
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planned (3 plans, all Wave 1, disjoint file ownership)
