---
phase: 16
slug: live-safe-saas-migration-and-channel-routing-table
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-20
---

# Phase 16 — Validation Strategy

> Per-phase validation contract. Detailed checks derive from `16-RESEARCH.md` → `## Validation Architecture`. The planner fills the Per-Task map below.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + psql against ephemeral Postgres (two instances: n8n DB + strapi DB) via `.github/workflows/phase-16-assertions.yml`; grep/yaml structural checks |
| **Config file** | none — CI ephemeral `postgres:15-alpine` services |
| **Quick run command** | `{planner fills}` |
| **Full suite command** | `{planner fills — fixture → live-safe migration → idempotent re-run → dup-survival + channel_identities checks}` |
| **Estimated runtime** | ~{N}s |

---

## Sampling Rate

- **After every task commit:** touched-criterion psql/grep check
- **After every plan wave:** full suite
- **Before `/gsd:verify-work`:** full suite green
- **Max feedback latency:** {N}s

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | DB-01 | sql | `{planner fills}` | ❌ W0 | ⬜ pending |
| 16-02-01 | 02 | 1 | TEN-02 | sql | `{planner fills}` | ❌ W0 | ⬜ pending |

*Planner completes from 16-RESEARCH.md Validation Architecture.*

---

## Wave 0 Requirements

- [ ] `db/ci-fixtures/16-duplicate-entitlements-fixture.sql` — seeds duplicate `(tenant_id, module_key)` rows to prove the migration survives dupes
- [ ] `db/ci-assertions/16-saas-migration-schema-check.sql` — uq_tenant_module/uq_product_module_key + indexes exist; re-run is a no-op
- [ ] `db/ci-assertions/16-channel-identities-check.sql` — table exists with PK `(channel, identity)` + FKs, seeded
- [ ] `.github/workflows/phase-16-assertions.yml` — two-DB CI gate (n8n + strapi)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 🔴 Apply live-safe migration + channel_identities seed on production Postgres (real WA/IG/MSG ids from `platform_settings`, real tenant UUID) | TEN-02, DB-01 | Requires prod SSH + live data; `CONCURRENTLY` direct-to-postgres | Deferred to prod-connected session |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < {N}s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
