---
phase: 17-inbound-tenant-derivation-fail-closed
verified: 2026-06-20T16:30:00Z
status: passed
score: 4/4 success criteria verified (workflow import to prod n8n deferred)
gaps: []
requirements_satisfied: [TEN-03]
deferred_to_vps: ["import updated W1/W2/W3 + W0_MODULE_GUARD + W_DRIVER_ONBOARDING workflows on prod n8n"]
---

# Phase 17: Inbound Tenant Derivation (Fail-Closed) — Verification

**Goal:** Resolve tenant from `channel_identities` in the inbound adapters' `B0 - Apply Auth Context`; an unknown channel identity FAILS CLOSED (never `'default'`).
**Status:** passed — 4/4 ROADMAP success criteria met at code/CI level; prod workflow import deferred.

## Observable Truths

| # | Success Criterion | Status | Evidence |
|---|-------------------|--------|----------|
| 1 | Resolver queries `channel_identities` and is wired in W1/W2/W3 | VERIFIED | All 3 have `B0 - Resolve Channel Identity (DB)` (postgres v2, `postgres-main`) wired `Resolve Client → Resolve Channel Identity → Map Channel Identity Result → Apply Auth Context` (middle hop asserted). Commit `ce9f724`. |
| 2 | Resolved identity stamps the real tenant (namespaced, no collision) | VERIFIED | Apply-Auth jsCode reads `ci_tenant_id`/`ci_restaurant_id`; `node --check` clean on all 3. |
| 3 | Unknown identity FAILS CLOSED, never `'default'` | VERIFIED | `denyReason='UNKNOWN_CHANNEL_IDENTITY'` drives existing deny branch; repo-wide grep = **zero** `DEFAULT_TENANT_ID`/`\|\| 'default'`/`00000000-…0001` in any Apply-Auth jsCode. |
| 4 | Fail-open fallbacks removed outside adapters + inventory closed | VERIFIED | W0_MODULE_GUARD + W_DRIVER_ONBOARDING fallbacks removed; `INVENTORY-15`/`__inventory_15` markers stripped from all 3 fixed sites (incl. W1 node key); `docs/adr/0002` ≥3 `REMOVED (Phase 17)`. Commits `1b91f99`. |

## Local Verification

**27/27 structural checks pass**, including the **full integrity gate (`scripts/integrity_gate.sh` exit 0)** — all 5 edited workflow JSONs remain valid and governance-clean. Latent bug fixed: W2/W3 now have a single `const metaSigValid` (was a duplicate-declaration SyntaxError). Plan-checker's 1 blocker + 2 warnings were folded into execution and confirmed applied.

The tenant-resolution SQL (`db/ci-assertions/17-tenant-resolution.sql`: known→resolves, unknown→0 rows) runs in `.github/workflows/phase-17-assertions.yml` against ephemeral Postgres — not runnable locally (no Postgres).

## Deferred (🔴 VPS)

Import the updated W1/W2/W3 + W0_MODULE_GUARD + W_DRIVER_ONBOARDING workflows on prod n8n (and seed real channel_identities — Phase 16). Deferred to a prod-connected session.

## Verdict

`passed` — TEN-03 satisfied at code/CI level. Inbound tenant derivation now fails closed on unknown identities with no `'default'` path remaining; one annotated fallback remains in `useEntitlements.ts` (Phase 21 scope).
