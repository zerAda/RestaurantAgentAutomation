# Phase 21: UI Fail-Closed Parity + Module-Key Alignment + Type Cleanup — Research

**Researched:** 2026-06-20
**Domain:** React 19 + TypeScript 5.9 admin SPA (`admin-dashboard/`, Vite 6 / Vitest 4 / ESLint 9 flat-config / typescript-eslint 8) — flipping `useEntitlements.hasModule` from fail-OPEN to fail-CLOSED in parity with `W0_MODULE_GUARD`, reconciling gated nav/workflow `module_key`s to the seeder/manifest source-of-truth (`config/product_modules.json` + `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts`), and replacing the entitlement-response `any` debt with v4/v5-tolerant typed DTOs so the standing **Frontend Lint (admin-dashboard)** CI job goes green. The FINAL phase of the v2.0 milestone.
**Confidence:** HIGH — every claim verified by reading source + running `npm run lint`, `npm test` (vitest), and `npx tsc --noEmit` locally.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ENT-01 | `useEntitlements.hasModule` defaults to **false** (or a known `shared_core` allowlist) while `loading` AND on fetch error; UI surfaces an explicit error/locked state instead of silently rendering all modules — parity with `W0_MODULE_GUARD`'s fail-closed posture; asserted by a **Vitest** test. | §1 (exact current fail-OPEN behavior + response-shape parsing), §3 (fail-closed contract + `shared_core` allowlist source), §7 (Vitest test design — Vitest is ALREADY configured + green locally) |
| ENT-02 | Every gated nav `module_key` in `App.tsx` maps to a real key in `config/product_modules.json` / `saas-entitlements.ts` (no ghost `addon_kitchen_display`-style keys); a CI check asserts every `module_key` referenced in `workflows/` AND `App.tsx` exists in the seeder/manifest. | §2 (the COMPLETE ghost/orphan inventory — 3 App.tsx ghosts + 3 workflow ghosts, all verified zero-match), §6 (the `.mjs` consistency-check design + scope decision: fix-or-assert the workflow ghosts) |
| TYP-01 | Typed `ProductModule` + `TenantEntitlement` interfaces (v4/v5-tolerant) replace the `any` usages in `useEntitlements.ts` + 5 flagged components; `npm run lint` passes for `admin-dashboard`. | §4 (the EXACT 6 lint errors — all in `useEntitlements.ts`; the 5 "flagged" components are already lint-clean, finding clarified), §5 (the v4/v5-tolerant DTO design + where `strapiClient` already gives `StrapiResponse<T[]>`) |
</phase_requirements>

---

## Summary

**The Frontend Lint failure is precise and small.** Running `npm run lint` (= `eslint .`) in `admin-dashboard` (after `npm install --legacy-peer-deps`) produces **exactly 6 errors, ALL `@typescript-eslint/no-explicit-any`, ALL in `admin-dashboard/src/hooks/useEntitlements.ts`** at `23:23, 24:23, 30:36, 31:29, 39:33, 40:26`. Nothing else fails. The five "flagged" components in the ROADMAP/REQUIREMENTS (`NotificationCenter.tsx`, `ToastProvider.tsx`, `AnalyticsView.tsx`, `AutomationView.tsx`, `AIChatBubble.tsx`) are **already lint-clean today** — `AIChatBubble.tsx:134` has an `as any` but it is already wrapped in an inline `// eslint-disable-next-line @typescript-eslint/no-explicit-any` (so it does not fail), and the others carry `no-unused-vars`/`react-refresh`/`set-state-in-effect` disables, not `any`. **Finding clarified for the planner:** TYP-01's literal lint-gate is satisfied by fixing the 6 `any` usages in `useEntitlements.ts` alone. The "replace `any` across 5 components" language is a *quality* goal (and the cleanest place to spend it is removing the `AIChatBubble.tsx:134 as any` + its disable comment by reusing the agent-response shape) — but only `useEntitlements.ts` is load-bearing for the green job. Recommend doing both: fix `useEntitlements.ts` (mandatory) and opportunistically retire the `AIChatBubble` `as any`/disable (high-value, low-risk); leave the no-unused-vars disables alone (out of `any` scope).

**`useEntitlements.ts` currently fails OPEN — the exact ENT-01 hazard.** `hasModule(key)` returns `if (loading) return true;` (line 57-58) and the `catch` block (line 46-48) only `console.error`s — it does NOT set an error flag, so after a fetch failure `loading` flips to `false`, `modules` stays `[]`, and `hasModule` returns `modules.includes(key)` = `false`… **but during the entire loading window every gate renders.** Worse, on a *successful* fetch for the wrong tenant (the `tenantId = 'default'` default param, ADR 0002 occurrence #5 — the LAST remaining annotated fallback) it returns zero rows → silently hides everything with no error UI. The guard (`W0_MODULE_GUARD`, Phases 17/20) fails CLOSED on error/missing; the UI must mirror: `hasModule` = **false while `loading` and on fetch error**, EXCEPT a `shared_core`/`product_core` allowlist may stay visible, AND the UI must surface an **explicit error/locked state** (not a silent blank). The response-shape parsing is already v4/v5-tolerant (`const mData = m.attributes || m;` line 32, `e.attributes || e` line 41) — that tolerance must be preserved in the typed rewrite.

**ENT-02 is bigger than App.tsx — there are SIX ghost keys, verified zero-match against both source-of-truth sets.** App.tsx gates on three keys that do NOT exist in the manifest/seeder: `addon_kitchen_display` (L162), `addon_analytics` (L171), `experimental_growth_agent` (L174). The grep also surfaced **three MORE ghost keys in `workflows/*.json`** passed to the guard: `W_KIOSK_ORDER.json:39` → `feature_kiosk`, `W_ORDER_FINALIZER.json:200` → `ordering_core`, `W30_VOICE_CALL_INIT.json:69` → `channel_voice`. The real keys are `kiosk_instore`, `growth_marketing`, `voice`, `order_bot_core`, etc. (the 15 canonical keys in §2). Because the guard now fails CLOSED (Phase 17/20), every one of these ghosts is a **silent permanent deny** — the kiosk/finalizer/voice workflows and three nav items are gated on keys no tenant can ever be entitled to. ENT-02's CI check must scan **BOTH** `App.tsx` and `workflows/*.json` (the success-criterion text says exactly this). **Scope decision for the planner (O-1):** the App.tsx ghosts are unambiguously in scope (fix the 3 gates to real keys). The 3 workflow ghosts are a real correctness bug in already-shipped (Phase 17/18/20) workflows — recommend **fixing them too** (one-line `module_key` edits in 3 JSONs) since the check would otherwise have to be authored to *tolerate* them, which defeats the purpose; this is low-risk and the milestone audit wants the guard to actually work. (Confirm with planner; either way the `.mjs` check is authored to PASS on the final state.)

**Tooling reality is favorable — Vitest is ALREADY configured and green.** `admin-dashboard/package.json` has `"test": "vitest run"`, `vite.config.ts` sets `test:{environment:'jsdom',globals:true}`, and **two test files already exist and pass**: `src/setup.test.ts` + `src/App.lazy.test.tsx` (5 tests, verified `npm test` → all green on Node 22). `@testing-library/react` 16 + `@testing-library/jest-dom` 6 + `jsdom` 28 are installed. So ENT-01's Vitest test needs **no new framework setup** — just a new `src/hooks/useEntitlements.test.tsx` (with `vi.mock` of `strapiClient` + `authService`). **`npm ci` (plain) FAILS** with an ERESOLVE peer conflict (`lucide-react@0.330.0` peers `react ^16||^17||^18`, project is react 19) — but the CI `frontend-lint` job already handles this with `npm ci || npm install --legacy-peer-deps`, so install works in CI and locally via the fallback. **Lint, vitest, and tsc ALL run locally** here (verified). CMS `tsc` also runs locally (verified — see §8).

**Primary recommendation:** Ship **3 plans with disjoint file ownership** — **21-01** flips `useEntitlements.ts` to fail-closed + adds the explicit error/locked UI state + the Vitest test (this plan owns `useEntitlements.ts` and its test ONLY); **21-02** fixes the App.tsx gated keys (and the 3 workflow ghost keys, O-1) + authors the `scripts/check-module-keys.mjs` consistency check + its test + the CI workflow (`phase-21-assertions.yml`); **21-03** introduces the typed `ProductModule`/`TenantEntitlement` DTOs in a shared `src/types/entitlements.ts` and threads them through the components, retiring the `AIChatBubble` `as any` — and is the plan that proves `npm run lint` green. **Sequencing caveat:** 21-01 and 21-03 BOTH touch `useEntitlements.ts` (21-01 changes its logic; 21-03 changes its types). To keep ownership disjoint, **fold the DTO typing of `useEntitlements.ts` into 21-01** (it's the file being rewritten there anyway — typing it as part of the fail-closed rewrite is natural and removes all 6 lint errors in one stroke), and let 21-03 own ONLY the shared `src/types/entitlements.ts` + the component edits + the `AIChatBubble` cleanup. That makes `useEntitlements.ts` solely 21-01's, and the green-lint gate is a 21-03 verification step over the whole tree. Optionally add a tiny **21-04 (or a task in 21-02)** for the trivial, well-precedented CMS-TS fix (§8) — recommended as a small optional inclusion since it greens the *other* standing red and is about the SaaS content types this milestone created.

---

## 1. Current `useEntitlements.hasModule` behavior + response-shape (ENT-01 baseline)

**File:** `admin-dashboard/src/hooks/useEntitlements.ts` (63 lines, 2223 bytes). Read in full.

### Exact current behavior (verbatim logic)
- **Signature:** `useEntitlements(tenantId = 'default')` (L9) — the `'default'` default param is **ADR 0002 occurrence #5** (`docs/adr/0002-tenant-id-fallback-inventory.md:33,97-102`), the **LAST remaining annotated `'default'` fallback in the repo**. This phase closes it. App.tsx calls `useEntitlements()` with **no argument** (`App.tsx:64`), so today it queries `tenant-entitlements` filtered on the literal string `'default'` → after the Phase 15 UUID backfill this returns **zero rows** (the entitlement plane is keyed on the canonical UUID `00000000-0000-0000-0000-000000000001`, not `'default'`).
- **No-auth path (L14-18):** if `!authService.isAuthenticated()` → `setLoading(false)`, no fetch. So `modules` stays `[]`.
- **Fetch (L20-52):** `Promise.all([ strapi.find<any>('product-modules'), strapi.find<any>('tenant-entitlements', {filters:{tenant_id:{$eq:tenantId}, enabled:{$eq:true}}}) ])`.
- **Module aggregation (L30-36):** `const allMods = (modRes as any).data || []` then for each `const mData = m.attributes || m;` (← **v4/v5 shape tolerance, must preserve**); adds `mData.key` to `enabledKeys` if `mData.enabled_globally || mData.tier === 'shared_core' || mData.tier === 'product_core'`.
- **Entitlement aggregation (L38-43):** `const ents = (entRes as any).data || []`; `const eData = e.attributes || e;` adds `eData.module_key`.
- **Error handling (L46-48):** `catch (err) { console.error('Failed to fetch entitlements', err); }` — **NO error state set.** This is the fail-open bug's second half.
- **`finally` (L48-50):** `setLoading(false)` always.
- **`hasModule` (L56-60):**
  ```ts
  const hasModule = (key: string) => {
    if (loading) return true;   // ← FAIL-OPEN: every gate renders while loading
    return modules.includes(key);
  };
  ```
- **Returns:** `{ modules, loading, hasModule }`.

### The fail-open posture (the ENT-01 target)
| Window | Current `hasModule(key)` | Required (fail-closed parity) |
|--------|--------------------------|-------------------------------|
| `loading === true` | **`true`** (renders everything) | **`false`** — EXCEPT `shared_core`/`product_core` allowlist may stay visible |
| fetch error (catch) | falls to `modules.includes(key)` over an empty `modules` ⇒ `false`, but **no error UI** | **`false`** + an **explicit error/locked state** surfaced to the operator |
| success, wrong tenant (`'default'`) | `false` for everything, silently | resolve real tenant; if unresolved, locked state — never silent-blank |
| success, entitled | `modules.includes(key)` ⇒ `true` | same |

### Response-shape (v4 vs v5) — what it parses TODAY
The hook already handles **both** shapes via `m.attributes || m` and `e.attributes || e`:
- **Strapi v4:** `{ data: [ { id, attributes: { key, tier, enabled_globally } } ] }`
- **Strapi v5 (this repo: Strapi 5.37.1):** `{ data: [ { id, documentId, key, tier, enabled_globally } ] }` (flat — no `attributes` wrapper).
The repo's `strapiClient.find<T>()` returns `StrapiResponse<T[]>` = `{ data: T[]; meta? }` (`strapiClient.ts:3-14,146-147`). So the `(modRes as any).data` cast is unnecessary once typed — `find<ProductModule>('product-modules')` already gives `{data: ProductModule[]}`. **The typed DTO must keep the `attributes || self` tolerance** (a `ProductModuleRaw` union, see §5).

---

## 2. ENT-02 — the COMPLETE ghost/orphan module-key inventory

### Source-of-truth key set (the 15 canonical keys)
Both `config/product_modules.json` (`modules[].key`) and `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` (`SAAS_MODULES[].key`) define the SAME 15 keys (verified identical):

```
platform_runtime (shared_core)   order_bot_core (product_core)
channel_whatsapp                 channel_instagram
channel_messenger                channel_tiktok
payment                          delivery_dispatch
inventory                        kiosk_instore
voice                            loyalty_crm
growth_marketing                 admin_ai_intelligence
experimental
```

### Ghost keys — referenced but ABSENT from the source-of-truth (all verified ZERO matches)
| # | Referenced in | Line | Ghost key | Real key it SHOULD be | Effect (guard fails closed) |
|---|---------------|------|-----------|------------------------|------------------------------|
| G1 | `admin-dashboard/src/App.tsx` | 162 | `addon_kitchen_display` | `kiosk_instore` (Kitchen Display lives under kiosk_instore: `W60_KITCHEN_CLOUD_PRINT`) — *planner to confirm intended module* | Kitchen nav item permanently hidden |
| G2 | `admin-dashboard/src/App.tsx` | 171 | `addon_analytics` | `growth_marketing` or `admin_ai_intelligence` — *planner to confirm* | Intelligence/Analytics nav hidden |
| G3 | `admin-dashboard/src/App.tsx` | 174 | `experimental_growth_agent` | `growth_marketing` | Growth AI nav hidden |
| G4 | `workflows/W_KIOSK_ORDER.json` | 39 | `feature_kiosk` | `kiosk_instore` | Kiosk orders denied by guard |
| G5 | `workflows/W_ORDER_FINALIZER.json` | 200 | `ordering_core` | `order_bot_core` | Order finalization denied by guard |
| G6 | `workflows/W30_VOICE_CALL_INIT.json` | 69 | `channel_voice` | `voice` | Voice call init denied by guard |

**Workflow callers that already use CORRECT keys (the reference set the check must accept):** `W1_IN_WA.json` → `channel_whatsapp` ✅, `W2_IN_IG.json` → `channel_instagram` ✅, `W3_IN_MSG.json` → `channel_messenger` ✅, `W1_IN_TIKTOK.json` → `channel_tiktok` ✅.

**Orphans (keys in the seeder never gated anywhere):** most addons (`payment`, `delivery_dispatch`, `inventory`, `loyalty_crm`) are not gated in the UI — that's fine (orphans are allowed; the check is one-directional: every *referenced* key must EXIST in the source, not every source key must be referenced).

**Scope decision (O-1):** The 3 App.tsx ghosts are in-scope (21-02). The 3 workflow ghosts are a genuine correctness bug introduced when the guard flipped fail-closed — **recommend fixing all 6** so `check-module-keys.mjs` passes on the true-correct state. If the planner wants to keep the workflow JSONs frozen, the alternative is documenting G4–G6 as a known-defect the check *reports* (non-failing warning) — NOT recommended (a fail-closed guard on a ghost key is exactly the silent-deny ENT-02 exists to kill).

---

## 3. Fail-closed contract parity + the `shared_core` allowlist (ENT-01)

**Guard posture (mirror target):** `W0_MODULE_GUARD` denies on error/missing (Phases 17/20: blank tenant → `allowed:false`; Strapi error → `GUARD_ERROR_FAILCLOSED`/deny). The UI must adopt the same default-deny.

**The `shared_core` allowlist — SOURCE decided:** `config/product_modules.json` marks `platform_runtime` as `tier:"shared_core"` and `order_bot_core` as `tier:"product_core"`; the seeder additionally sets `enabled_globally:true` on `platform_runtime`. The *existing* hook already treats `tier==='shared_core' || tier==='product_core' || enabled_globally` as always-on (L33). **Allowlist rule (recommend):** while `loading` or on error, `hasModule(key)` returns `true` ONLY if `key` is in a statically-known shared-core allowlist; otherwise `false`. Two viable allowlist sources:
1. **Static constant** in the hook/types — `const ALWAYS_ON = new Set(['platform_runtime','order_bot_core'])` (the two `shared_core`/`product_core` keys). Simplest, no fetch dependency, safe during loading. **Recommended** — these tiers are structurally always-on and never tenant-gated (the seeder *skips* entitling them, L166), so they're safe to hardcode.
2. **Derive from the modules fetch** once `product-modules` resolves — but that's unavailable during `loading`, so a static fallback is still needed. Use #1.

In practice **none of App.tsx's gated nav items are shared_core/product_core** (they gate analytics/growth/kitchen, all addons), so after fixing the ghost keys (§2) every gated item is an addon ⇒ correctly hidden while loading/error. The allowlist mostly matters so a future `hasModule('order_bot_core')` gate wouldn't flicker-hide core UI.

**Explicit error/locked UI (the criterion-1 "surfaces an explicit error/locked state"):** add an `error: boolean` (and/or `status: 'loading'|'error'|'ready'`) to the hook return. App.tsx (or a small `<EntitlementGate>`/banner) renders a visible locked/error indicator when `error === true` instead of a silent empty sidebar. Minimal viable surface: a `ToastProvider` error toast on fetch failure + gates resolving to false. Recommend a small explicit banner/locked-state so the operator knows modules are hidden due to an error, not due to entitlement.

---

## 4. TYP-01 — the EXACT lint failure (verified by running `npm run lint`)

```
$ npm run lint            # = eslint .   (node_modules present via npm install --legacy-peer-deps)
src/hooks/useEntitlements.ts
  23:23  error  Unexpected any  @typescript-eslint/no-explicit-any
  24:23  error  Unexpected any  @typescript-eslint/no-explicit-any
  30:36  error  Unexpected any  @typescript-eslint/no-explicit-any
  31:29  error  Unexpected any  @typescript-eslint/no-explicit-any
  39:33  error  Unexpected any  @typescript-eslint/no-explicit-any
  40:26  error  Unexpected any  @typescript-eslint/no-explicit-any
✖ 6 problems (6 errors, 0 warnings)   →  exit 1
```

**That is the entire Frontend Lint failure.** The 6 errors are: `strapi.find<any>` ×2 (L23,24), `(modRes as any).data` (L30), `.forEach((m: any)=>` (L31), `(entRes as any).data` (L39), `.forEach((e: any)=>` (L40).

### The five "flagged" components — current lint reality (clarification)
| File | `any`? | Lint status now | Action |
|------|--------|-----------------|--------|
| `useEntitlements.ts` | 6× `any` | **FAILS** (the 6 errors) | **MANDATORY** — type it (21-01) |
| `AIChatBubble.tsx` | `:134 as any` | clean (inline `eslint-disable-next-line @typescript-eslint/no-explicit-any` :133) | **Recommended cleanup** — type the agent response, drop the `as any`+disable (21-03) |
| `AnalyticsView.tsx` | none | clean (`:93` has a `no-unused-vars` disable + `:92 @ts-expect-error`, NOT `any`) | out of `any` scope — leave |
| `AutomationView.tsx` | none | clean (`:74` `no-unused-vars` disable on `_t`, NOT `any`) | out of `any` scope — leave |
| `NotificationCenter.tsx` | none | clean (`:136` `react-hooks/set-state-in-effect` disable; fully typed Strapi interfaces already exist :7-10) | out of `any` scope — leave |
| `ToastProvider.tsx` | none | clean (`:21` `react-refresh/only-export-components` disable) | out of `any` scope — leave |

**So TYP-01's literal gate ("`npm run lint` passes") needs ONLY the `useEntitlements.ts` fix.** The "5 components" language overstates current lint debt — useful to record so the planner doesn't burn effort hunting non-existent `any` in 4 already-clean files. The genuine cross-component DTO value is: (a) `useEntitlements.ts` typed, (b) `AIChatBubble.tsx` `as any` retired. Keep `tsc --noEmit` (the `build` script) green too — note `noUnusedLocals`/`noUnusedParameters` are on (`tsconfig.app.json:24-26`), which is why `AnalyticsView`/`AutomationView` carry the `no-unused-vars` disables; do not introduce new unused symbols.

---

## 5. Typed DTO design (v4/v5-tolerant) — TYP-01

Put the shared types in **`admin-dashboard/src/types/entitlements.ts`** (new file, owned by 21-03):

```ts
// Strapi 5 flat shape AND v4 attributes shape — tolerant union (mirrors useEntitlements L32/L41).
export interface ProductModuleFields {
  key: string;
  tier?: 'shared_core' | 'product_core' | 'channel_pack' | 'addon' | 'experimental';
  enabled_globally?: boolean;
  display_name?: string;
}
export interface TenantEntitlementFields {
  module_key: string;
  tenant_id?: string;
  enabled?: boolean;
}
// v4 wrapped: { id, attributes: Fields }  |  v5 flat: { id, documentId, ...Fields }
export type ProductModuleRaw = ProductModuleFields | { id: number; attributes: ProductModuleFields };
export type TenantEntitlementRaw = TenantEntitlementFields | { id: number; attributes: TenantEntitlementFields };

// normalizer used in the hook (replaces `m.attributes || m`):
export function unwrap<T>(row: T | { attributes: T }): T {
  return (row && typeof row === 'object' && 'attributes' in (row as object))
    ? (row as { attributes: T }).attributes
    : (row as T);
}
```

Then in `useEntitlements.ts`: `strapi.find<ProductModuleRaw>('product-modules')` (no `<any>`), `(modRes.data ?? [])` (no `as any` — `find` already returns `StrapiResponse<ProductModuleRaw[]>`), `.forEach((m: ProductModuleRaw) => { const mData = unwrap(m); ... })`. All 6 `any` errors vanish. For `AIChatBubble.tsx:134`, type the agent response with a small `interface AgentChatResponse { reply?: string; actions?: AgentAction[]; needsConfirmation?: boolean; confirmAction?: {...}; ragSlices?: string[] }` and drop the `as any`+disable.

**Constraint:** No new runtime libraries (milestone constraint) — these are type-only files, zero dependency. `zod` is available in CMS but NOT in `admin-dashboard` (and not needed — pure TS interfaces suffice).

---

## 6. ENT-02 consistency check — `scripts/check-module-keys.mjs`

**Path (proposed):** `scripts/check-module-keys.mjs` (repo-root `scripts/`, peer of `scripts/guard/`, `scripts/preflight.sh`). Runnable with `/opt/node22/bin/node scripts/check-module-keys.mjs` (Node 22 verified present) — plain `.mjs`, zero deps.

**Logic:**
1. Build the canonical key Set from `config/product_modules.json` `modules[].key` (parse JSON). Cross-check it equals the seeder's `SAAS_MODULES[].key` (regex-extract `key: '...'` from `saas-entitlements.ts`, or import-by-regex) — fail if the two source-of-truth sets diverge (defends the seeder/manifest invariant the seeder's own comment asserts at L13-16).
2. Collect every referenced `module_key`:
   - **App.tsx:** regex `hasModule\(['"]([^'"]+)['"]\)` over `admin-dashboard/src/App.tsx` → `{addon_kitchen_display, addon_analytics, experimental_growth_agent}` today.
   - **workflows/*.json:** regex `module_key:\s*'([^']+)'` (the n8n expression form, e.g. `W_KIOSK_ORDER.json:39`) AND/OR `"module_key"\s*:\s*"([^"]+)"` over all `workflows/*.json`.
3. For each referenced key, assert membership in the canonical Set. Print every ghost with file:line; `process.exit(1)` if any ghost remains. On the post-fix tree it exits 0.

**Test (proposed):** `scripts/__tests__/check-module-keys.test.mjs` (`node --test`) — feed a fixture with a known ghost → assert non-zero/throw; feed the canonical set → assert pass. Mirror Phase 19/20's `node --test` seam discipline. (Alternatively, since admin-dashboard already runs Vitest and has the `App.lazy.test.tsx` precedent of reading `App.tsx` as text, the App.tsx-side assertion could ALSO live as a Vitest test — but the workflow-side scan must be a repo-root `.mjs`, so keep ONE `.mjs` check covering both for a single source of truth.)

---

## 7. Validation Architecture

> `.planning/config.json` → `workflow.nyquist_validation: true` — this section is REQUIRED.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | **Vitest 4.0.18** (ALREADY configured + green) for the admin-dashboard unit tests; **`node --test`** (Node 22.22.2 at `/opt/node22/bin/node`) for the repo-root module-key `.mjs` check; **ESLint 9.39 flat-config** (`eslint .`) as the TYP-01 gate |
| Config file | `admin-dashboard/vite.config.ts` (`test:{environment:'jsdom',globals:true}` — exists); ESLint `admin-dashboard/eslint.config.js` (flat, `tseslint.configs.recommended` → `no-explicit-any` is `error`); new `.github/workflows/phase-21-assertions.yml` (mirror `phase-20-assertions.yml`) |
| Quick run command | `cd admin-dashboard && npx vitest run src/hooks/useEntitlements.test.tsx` ; `/opt/node22/bin/node --test scripts/__tests__/check-module-keys.test.mjs` |
| Full suite command | `cd admin-dashboard && npm run lint && npm test` ; `/opt/node22/bin/node scripts/check-module-keys.mjs` |

### Local-verify reality (documented)
| Check | Runs locally? | How |
|-------|---------------|-----|
| `npm install` (admin-dashboard) | **Yes, via fallback** — plain `npm ci` FAILS (ERESOLVE: `lucide-react@0.330.0` peers react ^16/17/18 vs react 19). CI uses `npm ci \|\| npm install --legacy-peer-deps`; locally use `npm install --legacy-peer-deps`. | verified — node_modules built locally |
| `npm run lint` (the gate) | **Yes** | verified: 6 errors before fix, target 0 after |
| `npm test` (Vitest) | **Yes** | verified: 5/5 pass on Node 22 (existing tests). Vitest 4 engines `^20\|\|^22\|\|>=24` ⇒ CI Node 20.20.0 also OK |
| `scripts/check-module-keys.mjs` | **Yes** | `/opt/node22/bin/node`, zero deps |
| `npx tsc --noEmit` (admin build) | **Yes** | available; note the stale `tsc_output.txt` lists many *non-Phase-21* TS errors (KitchenView/OrdersKanban OrderStatus-casing, unused imports) — those are NOT the lint gate and NOT Phase-21 scope; do not chase them |
| CMS `npx tsc --noEmit` | **Yes** | verified — the 5 pre-existing errors reproduce exactly (§8) |
| Postgres / Redis | **Not needed** for Phase 21 (pure frontend + static JSON checks) | — |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ENT-01 | `hasModule` returns **false** while `loading` (non-allowlist key) | Vitest unit (mock `authService.isAuthenticated`→true, never resolve fetch) | `npx vitest run src/hooks/useEntitlements.test.tsx` | ❌ Wave 0 |
| ENT-01 | `hasModule` returns **false** on fetch error + sets `error` state | Vitest (mock `strapi.find` reject) | same | ❌ Wave 0 |
| ENT-01 | `shared_core`/`product_core` allowlist key stays **true** while loading | Vitest | same | ❌ Wave 0 |
| ENT-01 | entitled key → **true** after successful fetch (v5 flat AND v4 attributes shapes) | Vitest (two mock payloads) | same | ❌ Wave 0 |
| ENT-01 | no `tenantId='default'` query — real tenant resolved (or locked) | Vitest (assert filter arg) | same | ❌ Wave 0 |
| ENT-02 | every `hasModule(...)` key in App.tsx ∈ canonical set | `node --test` (or Vitest text-scan) | `node --test scripts/__tests__/check-module-keys.test.mjs` | ❌ Wave 0 |
| ENT-02 | every `module_key` in `workflows/*.json` ∈ canonical set | `node --test` | same | ❌ Wave 0 |
| ENT-02 | manifest key set == seeder key set | `node --test` | same | ❌ Wave 0 |
| TYP-01 | `npm run lint` exits 0 (0 `no-explicit-any`) | eslint | `cd admin-dashboard && npm run lint` | ✅ (script exists; currently RED) |
| TYP-01 | `tsc --noEmit` not regressed for touched files | tsc | `cd admin-dashboard && npx tsc --noEmit` (touched files only — pre-existing errors out of scope) | n/a |

### Sampling Rate
- **Per task commit:** `npm run lint` on admin-dashboard + `npx vitest run` on the changed test; `node scripts/check-module-keys.mjs`.
- **Per wave merge:** full `npm run lint && npm test` (admin-dashboard) + `node --test scripts/__tests__/check-module-keys.test.mjs` + `phase-21-assertions.yml`.
- **Phase gate:** Frontend Lint job green (the milestone-closing success criterion) + Vitest green + module-key check green before `/gsd:verify-work`. No 🔴 VPS step (see §10).

### CI gate — `.github/workflows/phase-21-assertions.yml` (mirror phase-20)
Jobs (pin `actions/setup-node` to the admin-dashboard's Node — package.json declares no `engines`, vitest 4 needs `^20||^22`, CI global `NODE_VERSION=20.20.0`; **pin `node-version: '20'` for parity with the existing `frontend-lint` job, OR `'22'` to match `scripts/` `.mjs` convention — recommend pinning the admin-dashboard jobs to `'20'` (parity with the real `frontend-lint` gate) and the `scripts/` `.mjs` job to `'22'`**):
1. **admin-dashboard-lint:** `npm ci || npm install --legacy-peer-deps` → `npm run lint` (the green gate). Node 20.
2. **admin-dashboard-vitest:** `npm ci || npm install --legacy-peer-deps` → `npx vitest run` (covers ENT-01). Node 20.
3. **module-key-consistency:** `node scripts/check-module-keys.mjs` + `node --test scripts/__tests__/check-module-keys.test.mjs` (ENT-02). Node 22.
Use `paths:` filters on `admin-dashboard/**`, `config/product_modules.json`, `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts`, `workflows/**`, `scripts/check-module-keys.mjs`, `.github/workflows/phase-21-assertions.yml`. Pin action SHAs exactly as phase-20 does (`actions/checkout@11bd71…`, `actions/setup-node@39370e…`).

### Wave 0 Gaps
- [ ] `admin-dashboard/src/types/entitlements.ts` — shared v4/v5-tolerant DTOs + `unwrap()` (21-03)
- [ ] `admin-dashboard/src/hooks/useEntitlements.test.tsx` — Vitest ENT-01 test (21-01)
- [ ] `scripts/check-module-keys.mjs` — ENT-02 consistency check (21-02)
- [ ] `scripts/__tests__/check-module-keys.test.mjs` — `node --test` for the check (21-02)
- [ ] `.github/workflows/phase-21-assertions.yml` — mirror phase-20 (21-02 creates; 21-01/21-03 may append jobs)
- [ ] No framework install needed — Vitest/jsdom/testing-library already in devDependencies; `node`/`jq` present.

---

## Standard Stack (all already in repo — milestone constraint: NO new runtime libraries)

### Core
| Library | Version | Purpose | Why standard / source |
|---------|---------|---------|------------------------|
| React | 19.2.0 | the admin SPA | `admin-dashboard/package.json:20` |
| TypeScript | ~5.9.3 | typing the DTOs | `package.json:46` |
| ESLint + typescript-eslint | 9.39.1 / 8.46.4 (flat config) | the `no-explicit-any` gate (`npm run lint`) | `eslint.config.js`; `tseslint.configs.recommended` makes `no-explicit-any` an error |
| Vitest | 4.0.18 | ENT-01 unit test (jsdom, globals) | `package.json:49`, `vite.config.ts:14-17`; **already green** (`setup.test.ts`, `App.lazy.test.tsx`) |
| @testing-library/react + jest-dom | 16.3.2 / 6.9.1 | render/assert the hook (renderHook) | `package.json:32-33` |
| jsdom | 28.1.0 | Vitest DOM env | `package.json:43` |
| `node --test` | Node 22.22.2 (`/opt/node22/bin/node`) | the repo-root `.mjs` module-key check + its test | host-verified |

**Installation:** None. Type-only files + tests using already-installed devDependencies. Install deps via `npm install --legacy-peer-deps` (plain `npm ci` fails ERESOLVE — see §7).

**Version verification (2026-06-20):** all versions read from `admin-dashboard/package.json` (committed). vitest 4.0.18 engines `^20.0.0||^22.0.0||>=24.0.0` (verified from installed `node_modules/vitest/package.json`) — compatible with CI `NODE_VERSION=20.20.0`. vite 6.4.1 engines `^18||^20||>=22`. No npm-registry fetch performed beyond the local install (Phase 21 adds zero runtime deps).

---

## Architecture Patterns

### Disjoint file ownership (3 plans + optional CMS-TS task)
```
admin-dashboard/src/hooks/useEntitlements.ts            # 21-01 ONLY — fail-closed rewrite + DTO-typed (kills all 6 lint errors here)
admin-dashboard/src/hooks/useEntitlements.test.tsx      # 21-01 — Vitest ENT-01
(error/locked UI surface: a small banner or ToastProvider hook) # 21-01 — explicit error state
admin-dashboard/src/App.tsx                             # 21-02 ONLY — fix 3 ghost gate keys (G1-G3)
workflows/W_KIOSK_ORDER.json                            # 21-02 — fix module_key feature_kiosk→kiosk_instore (G4, O-1)
workflows/W_ORDER_FINALIZER.json                        # 21-02 — fix ordering_core→order_bot_core (G5, O-1)
workflows/W30_VOICE_CALL_INIT.json                      # 21-02 — fix channel_voice→voice (G6, O-1)
scripts/check-module-keys.mjs                           # 21-02 — ENT-02 consistency check
scripts/__tests__/check-module-keys.test.mjs            # 21-02 — node --test
.github/workflows/phase-21-assertions.yml               # 21-02 creates (lint+vitest+module-key jobs)
admin-dashboard/src/types/entitlements.ts               # 21-03 ONLY — shared DTOs + unwrap()
admin-dashboard/src/components/AIChatBubble.tsx         # 21-03 — type agent response, drop `as any`+disable
(inventory-cms 4 SaaS controller/route files)           # optional 21-04 / 21-02-task — add `// @ts-ignore` UID line (§8)
```
**Sequencing note:** 21-01 and 21-03 both relate to entitlement types. To keep `useEntitlements.ts` single-owner, **21-01 imports the DTOs from `src/types/entitlements.ts`** (created by 21-03). Either land 21-03's types file FIRST (Wave 1) then 21-01 (Wave 2), OR have 21-01 define the DTOs inline and 21-03 extract+share them. **Recommend:** 21-03 owns `src/types/entitlements.ts` in Wave 1; 21-01 (Wave 2) consumes it; 21-02 is fully independent (Wave 1, parallel). This gives Wave 1 = {21-02, 21-03}, Wave 2 = {21-01}. The green-lint gate is verified after all three.

### Pattern 1: Fail-closed default with a static shared-core allowlist
**What:** `hasModule(key)` defaults `false` while loading/error; a static `ALWAYS_ON = new Set(['platform_runtime','order_bot_core'])` keeps structurally-always-on tiers visible.
**Source:** mirrors `W0_MODULE_GUARD` fail-closed (Phase 17/20) + the hook's own existing tier logic (`useEntitlements.ts:33`).

### Pattern 2: v4/v5 shape-tolerant `unwrap()`
**What:** preserve the existing `row.attributes || row` tolerance in a typed `unwrap<T>()` helper rather than re-introducing `any`.
**Source:** `useEntitlements.ts:32,41`; Strapi 5.37.1 returns flat shapes, v4 wraps in `attributes`.

### Pattern 3: text-scan consistency check as a pure `.mjs` (+ node --test)
**What:** a dependency-free `.mjs` that regex-scans App.tsx + workflows + parses the manifest JSON, exits non-zero on any ghost key.
**Source:** Phase 19/20 `scripts/guard/*.mjs` + `node --test` seam discipline; `App.lazy.test.tsx` precedent of asserting over source text.

### Anti-Patterns to Avoid
- **Leaving `hasModule` fail-open** (`if (loading) return true`) — the entire ENT-01 bug.
- **Silent empty sidebar on error** — must surface an explicit error/locked state (criterion 1).
- **Re-introducing `any`** to silence the gate (e.g. `as unknown as X` chains, or a blanket `eslint-disable`) — defeats TYP-01; use real DTOs.
- **Dropping the `attributes || self` tolerance** — would break against whichever Strapi shape the live API returns.
- **Authoring `check-module-keys.mjs` to tolerate the workflow ghosts** instead of fixing them — leaves three fail-closed silent-denies live.
- **Chasing the stale `tsc_output.txt` errors** (KitchenView/OrdersKanban OrderStatus casing, unused imports) — out of Phase-21 scope; the lint gate is `eslint .`, not `tsc`.
- **Over-fixing CMS TS** beyond the trivial `// @ts-ignore` lines (§8) — the milestone scope is admin-dashboard lint.

---

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| Strapi response typing | a bespoke `any`-cast parser | `strapiClient.find<T>()` already returns `StrapiResponse<T[]>` + a small `unwrap()` | the client is already generically typed; only the DTO is missing |
| Test framework for ENT-01 | install Jest / new runner | **Vitest (already configured + green)** + `@testing-library/react` `renderHook` | zero setup; `setup.test.ts`/`App.lazy.test.tsx` prove it works |
| Module-key check | a new lint plugin | a 40-line `.mjs` regex+JSON scan + `node --test` | zero deps, runs on `/opt/node22/bin/node`, mirrors Phase 19/20 |
| CI gate | a novel workflow | copy `phase-20-assertions.yml` (pinned SHAs, paths filters, job shape) | proven template in-repo |
| CMS SaaS-ContentType TS error | redesign the content types / typegen | the repo's own `// @ts-ignore - UID registered at runtime` one-liner (used by 12 other api files) | trivial, precedented, exact fix (§8) |

**Key insight:** Almost everything Phase 21 needs is already present and proven — Vitest is configured, the strapiClient is generically typed, the CI template exists, and the CMS-TS fix has a 12-file precedent. The genuinely new work is: (1) the fail-closed logic + error UI, (2) the typed DTOs, (3) the ghost-key fixes + the consistency check.

---

## Common Pitfalls

### Pitfall 1: Flipping the default but forgetting the error state
**What goes wrong:** `hasModule` returns false on error, but with no `error` flag the UI shows a silent empty sidebar — operator can't tell "no entitlement" from "fetch failed". **Avoid:** add `error`/`status` to the hook return and render an explicit locked/error surface (criterion 1).

### Pitfall 2: Allowlist too broad or too narrow
**What goes wrong:** allowlisting an addon during loading re-introduces fail-open; allowlisting nothing flickers core UI hidden. **Avoid:** allowlist exactly `shared_core`+`product_core` (`platform_runtime`, `order_bot_core`) — verified always-on tiers the seeder never gates.

### Pitfall 3: Incomplete ghost-key list
**What goes wrong:** fixing only the 3 App.tsx ghosts but missing the 3 workflow ghosts (`feature_kiosk`, `ordering_core`, `channel_voice`) leaves kiosk/finalizer/voice silently denied by the now-fail-closed guard. **Avoid:** the §2 table is the complete verified set (all 6 zero-match); the `.mjs` check scans both App.tsx AND workflows.

### Pitfall 4: ESLint flat-config + react 19 install
**What goes wrong:** `npm ci` aborts (ERESOLVE: lucide-react peers react ^18). **Avoid:** `npm install --legacy-peer-deps` (matches CI's `npm ci || npm install --legacy-peer-deps`); CI lint step also guards on `[ -d node_modules ]` so a failed install SKIPS (not fails) — but Phase 21 MUST make it actually run+pass, so ensure install succeeds.

### Pitfall 5: Re-typing breaks the v4/v5 tolerance
**What goes wrong:** typing the DTO as the flat v5 shape only → runtime read of `m.attributes.key` returns undefined if the API ever returns v4. **Avoid:** the `ProductModuleRaw` union + `unwrap()` (§5) keeps both shapes.

### Pitfall 6: Node-version drift between jobs
**What goes wrong:** the existing `frontend-lint` CI job runs on `NODE_VERSION=20.20.0`; if the new Vitest job pins Node 22 it could pass locally but mask a Node-20 issue (or vice versa). **Avoid:** pin admin-dashboard jobs to `'20'` (parity with the real gate); pin the `scripts/` `.mjs` job to `'22'`.

### Pitfall 7: Vitest job assumed to already run in CI
**What goes wrong:** the current `frontend-lint` job runs ONLY `npm run lint` — Vitest is NOT in CI today. Assuming "tests run in CI" is false. **Avoid:** add the vitest job in `phase-21-assertions.yml`.

---

## State of the Art

| Old approach | Current approach | When changed | Impact |
|--------------|------------------|--------------|--------|
| UI fails OPEN (`if(loading) return true`) | fail-CLOSED parity with the guard + explicit error UI | Phase 21 (this) | the milestone-closing entitlement-consistency fix |
| `tenantId='default'` query param (ADR 0002 #5) | real tenant context / locked state | Phase 21 | closes the LAST annotated `'default'` fallback repo-wide |
| `strapi.find<any>` + `as any` parsing | `strapi.find<ProductModuleRaw>` + `unwrap()` typed DTO | Phase 21 | greens Frontend Lint |
| 6 ghost module-keys (3 UI + 3 workflow) | reconciled to the 15 canonical seeder keys + a CI guard | Phase 21 | kills 6 silent fail-closed denies |

**Deprecated/outdated:** the stale `admin-dashboard/tsc_output.txt` (UTF-16 snapshot of an OLD `tsc` run listing ~30 non-Phase-21 TS errors) is not authoritative for the lint gate and should not drive scope.

---

## Open Questions

1. **O-1 — fix the 3 workflow ghost keys, or only assert?**
   - Known: `feature_kiosk`/`ordering_core`/`channel_voice` are zero-match ghosts passed to the now-fail-closed guard ⇒ live silent denies in kiosk/finalizer/voice.
   - Unclear: whether the planner wants to freeze already-shipped workflow JSONs.
   - **Recommendation (sensible default):** FIX all 6 (3 UI + 3 workflow) — one-line `module_key` edits — so `check-module-keys.mjs` passes on the truly-correct state. The alternative (a tolerant check) preserves a real bug.

2. **O-2 — which real key for the 3 App.tsx nav gates?**
   - `addon_kitchen_display` → `kiosk_instore`? (Kitchen Display = `W60_KITCHEN_CLOUD_PRINT`, under kiosk_instore) or a dedicated module?
   - `addon_analytics` → `growth_marketing` or `admin_ai_intelligence`?
   - `experimental_growth_agent` → `growth_marketing`.
   - **Recommendation:** map kitchen→`kiosk_instore`, analytics(Intelligence)→`admin_ai_intelligence`, growth→`growth_marketing`. Planner to confirm against intended product packaging; the consistency check only requires the chosen keys EXIST in the manifest.

3. **O-3 — scope of the "explicit error/locked state" UI.**
   - Minimal (toast on error + gates false) vs a visible persistent locked banner.
   - **Recommendation:** a small persistent error/locked indicator when the hook's `error` is true (so hidden modules read as "error", not "unentitled") — satisfies criterion 1 without a large UI build.

4. **O-4 — include the trivial CMS-TS fix? (see §8)**
   - **Recommendation:** YES, as a small optional task — 4 one-line `// @ts-ignore` additions green the *other* standing red (`CMS TypeScript Compilation`) and are about THIS milestone's SaaS content types. Keep the 5th error (`auth-ratelimit.ts:37` ioredis) OUT of scope (riskier ESM-interop typing, predates the milestone).

---

## 8. CMS TypeScript baseline — SCOPE DECISION (§ per the brief)

**Verified by running `cd inventory-cms && npx tsc --noEmit`** — exactly 5 errors reproduce:

```
src/api/product-module/controllers/product-module.ts(2,47): TS2345  '"api::product-module.product-module"' not assignable to 'ContentType'
src/api/product-module/routes/product-module.ts(2,43):      TS2345  (same UID, router)
src/api/tenant-entitlement/controllers/tenant-entitlement.ts(2,47): TS2345  (tenant-entitlement)
src/api/tenant-entitlement/routes/tenant-entitlement.ts(2,43):      TS2345  (router)
src/middlewares/auth-ratelimit.ts(37,27): TS2351  ioredis 'new Redis(...)' not constructable (ESM interop)
```

**Root cause of the 4 SaaS-ContentType TS2345 errors (HIGH confidence):** Strapi's type generator (`types/generated/contentTypes.d.ts`) does **NOT** include `product-module` / `tenant-entitlement` (grep count = 0 in that file) — these custom content types aren't in the generated `ContentType` union, so `factories.createCoreController('api::product-module.product-module')` fails the string-literal `ContentType` constraint. **The repo's OWN established fix is a one-line comment** — `// @ts-ignore - UID registered at runtime; type generator skips this custom type` directly above the `factories.create…` call. This pattern is ALREADY used by **12 other api files** (e.g. `src/api/dispatch-log/controllers/dispatch-log.ts:5`, its router, etc.). The 4 SaaS files simply MISSED the comment when created.

**Assessment:** The 4-error fix is **trivial, low-risk, well-precedented, and directly about THIS milestone's content types** → **RECOMMEND including a small optional task** (21-04, or a task in 21-02) that adds the `// @ts-ignore` line to the 4 SaaS controller/route files. Verify with `npx tsc --noEmit` dropping from 5→1 error. **The 5th error** (`auth-ratelimit.ts:37` `new Redis(url, …)` TS2351 — an `esModuleInterop`/default-import typing issue with `ioredis`, present since before this milestone, NOT a SaaS content type) is **riskier** (touching it risks the runtime Redis client) → **document as out-of-scope baseline for the milestone audit**; do NOT let it bloat Phase 21. So the optional CMS task takes the job from 5 errors → 1 known-baseline error, with a documented reason for the remaining one.

**Do NOT** let CMS work derail the core: Phase 21's gate is admin-dashboard `npm run lint`. The CMS-TS task is a bonus, gated independently in the `cms-ts-compile` CI job.

---

## 9. Proposed plan breakdown (3 plans + optional CMS task)

| Plan | Owns | Requirement | Wave |
|------|------|-------------|------|
| **21-01** | `useEntitlements.ts` (fail-closed rewrite, DTO-typed, kills its 6 `any`), `useEntitlements.test.tsx` (Vitest ENT-01), the explicit error/locked UI surface | ENT-01 (+ part of TYP-01) | Wave 2 (consumes 21-03's types) |
| **21-02** | `App.tsx` (fix 3 ghost gate keys), the 3 workflow ghost-key fixes (O-1), `scripts/check-module-keys.mjs` + its `node --test`, `phase-21-assertions.yml` | ENT-02 | Wave 1 (independent) |
| **21-03** | `src/types/entitlements.ts` (shared v4/v5 DTOs + `unwrap()`), `AIChatBubble.tsx` (type agent response, drop `as any`+disable); verifies `npm run lint` green tree-wide | TYP-01 | Wave 1 (types) |
| **21-04 (optional)** | 4× `// @ts-ignore` UID lines in the SaaS controller/route files | (milestone audit — CMS TS green) | Wave 1 (independent) |

Wave 1 = {21-02, 21-03, 21-04} parallel (disjoint files); Wave 2 = {21-01} (imports `src/types/entitlements.ts`). Green-lint gate verified after Wave 2.

---

## 10. VPS deferral

**NONE.** Phase 21 is pure frontend (`admin-dashboard/`), static JSON manifest checks, three workflow `module_key` string edits, a Node `.mjs` script, a CI workflow, and (optional) CMS one-line comments. There is no live-Postgres migration, no secret to provision, and the workflow edits are `module_key` string corrections that take effect on the next n8n import — which is already covered by the Phase 17/20 deferred-import note (no NEW deferral introduced). The success criteria (lint green, Vitest green, module-key check green) are all locally/CI-verifiable without VPS access. **Confirmed: Phase 21 carries no 🔴 VPS execution sub-step.**

---

## Sources

### Primary (HIGH confidence — read in full / executed locally 2026-06-20)
- `admin-dashboard/src/hooks/useEntitlements.ts` — current fail-open logic + v4/v5 parsing
- `admin-dashboard/src/App.tsx` — the 3 `hasModule(...)` ghost gates (L162,171,174)
- `config/product_modules.json` + `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` — the 15 canonical keys (verified identical sets)
- `admin-dashboard/src/services/strapiClient.ts` — `StrapiResponse<T[]>` generic, `find<T>()`
- `admin-dashboard/src/components/{AIChatBubble,NotificationCenter,ToastProvider,AnalyticsView,AutomationView}.tsx` — `any`/disable audit
- `admin-dashboard/package.json`, `eslint.config.js`, `vite.config.ts`, `tsconfig.app.json` — tooling
- `admin-dashboard/src/{setup.test.ts,App.lazy.test.tsx}` — existing Vitest tests (proven green)
- `docs/adr/0002-tenant-id-fallback-inventory.md` — occurrence #5 (the `'default'` default param)
- `.github/workflows/ci.yml` (+ `ralphe-ci.yml`) — `frontend-lint` (npm run lint, `npm ci||install --legacy-peer-deps`, Node 20.20.0) + `cms-ts-compile` (`npx tsc --noEmit`) jobs
- `.github/workflows/phase-20-assertions.yml` — the CI template
- `inventory-cms/src/api/{product-module,tenant-entitlement}/{controllers,routes}/*.ts` + `src/middlewares/auth-ratelimit.ts` + `src/api/dispatch-log/...` — CMS-TS errors + the 12-file `// @ts-ignore` precedent
- **Commands executed:** `npm install --legacy-peer-deps` (both apps), `npm run lint` (6 errors), `npm test` (5/5 pass), `npx tsc --noEmit` (CMS: 5 errors), grep over `workflows/*.json` for `module_key`
- `.planning/ROADMAP.md` (Phase 21 block), `.planning/REQUIREMENTS.md` (ENT-01/02, TYP-01), `.planning/config.json` (nyquist_validation:true)
- `.planning/phases/20-…/20-RESEARCH.md` — structure/depth template

### Secondary (MEDIUM)
- Vitest 4 / vite 6 engines read from installed `node_modules/*/package.json` (compat with CI Node 20.20.0)

### Tertiary (LOW)
- None — every claim is source-verified or command-verified.

---

## Metadata

**Confidence breakdown:**
- Current `useEntitlements` behavior + response-shape: **HIGH** — read in full, behavior is unambiguous.
- The exact lint failure (6 `any` in one file): **HIGH** — `npm run lint` executed, output captured.
- Ghost/orphan key inventory (6 ghosts): **HIGH** — grep + zero-match verification on both source sets.
- Vitest already configured + green: **HIGH** — `npm test` executed (5/5).
- `npm ci` ERESOLVE / `--legacy-peer-deps` reality: **HIGH** — both commands run.
- CMS-TS scope (4 trivial + 1 deferred): **HIGH** — `npx tsc --noEmit` executed; 12-file `// @ts-ignore` precedent confirmed.
- No VPS deferral: **HIGH** — scope is frontend + static checks + string edits.
- App.tsx gate→real-key mapping (O-2): **MEDIUM** — keys exist in manifest; intended product packaging needs planner confirmation.

**Research date:** 2026-06-20
**Valid until:** ~2026-07-20 (stable — no fast-moving external deps; all versions pinned in committed lockfiles).
