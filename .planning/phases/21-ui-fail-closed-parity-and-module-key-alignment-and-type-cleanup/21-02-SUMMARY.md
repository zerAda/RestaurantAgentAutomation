---
phase: 21-ui-fail-closed-parity-and-module-key-alignment-and-type-cleanup
plan: 02
subsystem: entitlements-ui-and-workflows
tags: [ENT-02, module-keys, ci-gate, fail-closed]
requires:
  - "config/product_modules.json (canonical 15 keys)"
  - "inventory-cms/src/bootstrap-seeds/saas-entitlements.ts (seeder 15 keys)"
provides:
  - "App.tsx nav gates on real manifest keys (kiosk_instore, admin_ai_intelligence, growth_marketing)"
  - "3 workflow guard calls on real keys (kiosk_instore, order_bot_core, voice)"
  - "scripts/check-module-keys.mjs ENT-02 consistency check + node --test"
  - ".github/workflows/phase-21-assertions.yml (3 jobs; 21-04 appends cms-ts-compile)"
affects:
  - "admin-dashboard/src/App.tsx"
  - "workflows/W_KIOSK_ORDER.json, W_ORDER_FINALIZER.json, W30_VOICE_CALL_INIT.json"
tech-stack:
  added: []
  patterns: ["dependency-free ESM check + node --test", "one-directional referenced⊆canonical"]
key-files:
  created:
    - "scripts/check-module-keys.mjs"
    - "scripts/__tests__/check-module-keys.test.mjs"
    - ".github/workflows/phase-21-assertions.yml"
  modified:
    - "admin-dashboard/src/App.tsx"
    - "workflows/W_KIOSK_ORDER.json"
    - "workflows/W_ORDER_FINALIZER.json"
    - "workflows/W30_VOICE_CALL_INIT.json"
decisions:
  - "W_ORDER_FINALIZER mapped to order_bot_core (NOT payment) — see note below"
metrics:
  tasks: 3
  files: 7
  completed: "2026-06-20"
---

# Phase 21 Plan 02: Module-Key Alignment + ENT-02 Consistency Gate Summary

Reconciled all 6 verified ghost `module_key` references (3 App.tsx nav gates + 3 workflow `W0_MODULE_GUARD` calls) to real keys in the canonical source-of-truth, then authored a dependency-free `scripts/check-module-keys.mjs` consistency check (+ 11-case `node --test`) and created `.github/workflows/phase-21-assertions.yml` with the three admin/module-key jobs.

## What was built

- **App.tsx (3 gates):** `addon_kitchen_display`→`kiosk_instore`, `addon_analytics`→`admin_ai_intelligence`, `experimental_growth_agent`→`growth_marketing`. No ghost key remains.
- **Workflows (3 guard calls, byte-for-byte except the key string):** `W_KIOSK_ORDER.json:39` `feature_kiosk`→`kiosk_instore`; `W_ORDER_FINALIZER.json:200` `ordering_core`→`order_bot_core`; `W30_VOICE_CALL_INIT.json:69` `channel_voice`→`voice`. All 3 remain valid JSON.
- **`scripts/check-module-keys.mjs`:** pure exported helpers (`loadCanonicalKeys`, `extractSeederKeys`, `extractAppTsxKeys`, `extractWorkflowKeys`, `findGhosts`, `setsEqual`) + a guarded CLI (`import.meta.url === file://${process.argv[1]}`) that enforces the manifest==seeder invariant and that every referenced key (App.tsx + `workflows/*.json`) is in the canonical set (one-directional — orphans allowed). Exit 1 on any ghost.
- **`scripts/__tests__/check-module-keys.test.mjs`:** 11 `node --test` cases — fixtures for each helper, synthetic ghost, one-directional orphan-allowed, manifest!=seeder fires, plus two LIVE tests (real manifest==seeder = 15 keys; real post-fix tree has zero ghosts).
- **`phase-21-assertions.yml`:** `admin-dashboard-lint` (Node 20), `admin-dashboard-vitest` (Node 20), `module-key-consistency` (Node 22). Pinned `actions/checkout@11bd71…` + `actions/setup-node@39370e… # v4.1.0`, `permissions` read, `::group::` wrapping, `paths:` filters (incl. the CMS api/middleware paths so 21-04's appended job runs). A trailing comment marks the 21-04 `cms-ts-compile` append point.

## NOTE for the milestone audit: W_ORDER_FINALIZER → order_bot_core (deliberate)

The product manifest lists `W_ORDER_FINALIZER` under the **`payment`** module (`config/product_modules.json:89`). The ghost it carried was `ordering_core`. We mapped it to **`order_bot_core`** (NOT `payment`) **deliberately**: gating order finalization on the optional `payment` addon would deny **COD (cash-on-delivery) orders** for any tenant without the payment addon — the exact silent-deny class ENT-02 exists to eliminate. `order_bot_core` is the always-on `product_core` tier (every tenant has it), so finalization is never spuriously denied. Both `order_bot_core` and `payment` are real canonical keys, so the consistency check passes either way; this records the packaging choice so the audit isn't surprised by the finalizer not gating on its manifest-listed `payment` module.

## Verification

- Task 1 verify block: PASS (3 App.tsx real gates present, no ghost; 3 workflows valid JSON with corrected keys).
- `node --test scripts/__tests__/check-module-keys.test.mjs`: 11/11 pass.
- `node scripts/check-module-keys.mjs`: exit 0 (`10 referenced module_key(s) across App.tsx + 98 workflows all exist in the 15-key manifest`).
- Synthetic-ghost injection: CLI exit 1 (then reverted; real tree exit 0).
- `python3 yaml.safe_load(phase-21-assertions.yml)`: valid; 3 jobs; pinned SHAs; admin Node 20 / module-key Node 22; `legacy-peer-deps` fallback present.

## Deviations from Plan

None — plan executed as written.

## VPS deferral

NONE. App.tsx + workflow JSON edits are pure source corrections; the workflow `module_key` fixes take effect on the next n8n import which is already covered by the Phase 17/18/20 deferred-import note (no NEW deferral). All success criteria are locally/CI-verifiable.

## Self-Check: PASSED
