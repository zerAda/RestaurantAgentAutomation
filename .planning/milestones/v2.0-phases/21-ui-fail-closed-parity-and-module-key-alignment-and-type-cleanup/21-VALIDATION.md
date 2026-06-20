---
phase: 21
slug: ui-fail-closed-parity-and-module-key-alignment-and-type-cleanup
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-20
---

# Phase 21 — Validation Strategy

> Per-phase validation contract. Detailed checks derive from `21-RESEARCH.md` → `## 7. Validation
> Architecture`. Phase 21 is the v2.0 milestone's **clean-finish** phase: it flips the admin UI
> `useEntitlements.hasModule` from fail-OPEN to fail-CLOSED (Vitest), reconciles 6 ghost `module_key`s to
> the seeder/manifest source-of-truth (a dependency-free `node --test` `.mjs`), clears the standing
> Frontend-Lint `no-explicit-any` debt (ESLint `npm run lint`), and — as a bonus — greens the CMS
> TypeScript Compilation (`npx tsc --noEmit` → 0 errors). Everything runs **locally** (node_modules already
> installed in admin-dashboard + inventory-cms, gitignored) and in CI; **NO docker, NO VPS**.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | **Vitest 4.0.18** (jsdom, globals — ALREADY configured + green: `setup.test.ts`, `App.lazy.test.tsx` 5/5) + `@testing-library/react` 16 `renderHook` for the ENT-01 hook test; **ESLint 9.39 flat-config** (`eslint .` = `npm run lint`) as the TYP-01 gate; **`node --test`** (Node **22.22.2** at `/opt/node22/bin/node`) for the repo-root module-key `.mjs` check + its test; **`npx tsc --noEmit`** in `inventory-cms` for the CMS-TS gate (21-04); `python3 yaml.safe_load` / `json.load` for the CI YAML + workflow JSON |
| **Config file** | `admin-dashboard/vite.config.ts` (`test:{environment:'jsdom',globals:true}` — exists); `admin-dashboard/eslint.config.js` (flat, `tseslint.configs.recommended` → `no-explicit-any` is **error**); new `.github/workflows/phase-21-assertions.yml` (mirrors `phase-20-assertions.yml`; **admin jobs Node 20** for parity with the real `frontend-lint`/`cms-ts-compile` gates — ci.yml `NODE_VERSION=20.20.0`; **the `.mjs` `node --test` job Node 22**; both pin `actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af # v4.1.0`, `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2`) |
| **Quick run commands (<5s)** | `cd admin-dashboard && npx vitest run src/hooks/useEntitlements.test.tsx` ; `/opt/node22/bin/node --test scripts/__tests__/check-module-keys.test.mjs` ; `/opt/node22/bin/node scripts/check-module-keys.mjs` |
| **Full suite (admin)** | `cd admin-dashboard && npm run lint && npx vitest run` (the milestone-closing green gate + the full Vitest suite) |
| **Full suite (CMS, 21-04)** | `cd inventory-cms && npx tsc --noEmit` (0 errors) |
| **Estimated runtime** | <5s per-task local (vitest single-file / eslint single-file / `node --test`); ~10s `npm run lint` tree-wide; ~30s `npx tsc --noEmit` (CMS); ~90s CI (Node setup + install + lint + vitest + node-test + cms tsc) |

### Local-verify reality — NO docker, NO VPS (verified on this host 2026-06-20)

`node_modules` is already installed in **both** `admin-dashboard/` and `inventory-cms/` (gitignored). All
checks run locally — there is no Postgres/Redis dependency in Phase 21 (pure frontend + static JSON checks
+ CMS type-check):

```bash
# 1. ENT-01 fail-closed hook test (Vitest, jsdom — already configured):
cd admin-dashboard && npx vitest run src/hooks/useEntitlements.test.tsx   # -> false-while-loading, shared_core-visible, false+error-on-reject, entitled-true (v4 AND v5)

# 2. TYP-01 lint gate (the standing Frontend-Lint failure -> green):
cd admin-dashboard && npm run lint                                        # -> exit 0 (was 6 no-explicit-any in useEntitlements.ts)

# 3. Full admin Vitest suite (existing + ENT-01):
cd admin-dashboard && npx vitest run                                      # -> all green

# 4. ENT-02 module-key consistency (repo-root, zero deps, Node 22):
/opt/node22/bin/node scripts/check-module-keys.mjs                        # -> exit 0 on the post-fix tree (no ghosts; manifest==seeder)
/opt/node22/bin/node --test scripts/__tests__/check-module-keys.test.mjs  # -> ghost fixture fails, canonical passes, manifest==seeder invariant

# 5. CMS-TS bonus (21-04) — fully green:
cd inventory-cms && npx tsc --noEmit                                      # -> 0 errors (4 @ts-ignore + ioredis static import)
```

**Install reality:** plain `npm ci` in `admin-dashboard` **FAILS** (ERESOLVE: `lucide-react@0.330.0` peers
react ^16/17/18 vs react 19). CI uses `npm ci || npm install --legacy-peer-deps` (the real `frontend-lint`
job's pattern); locally use `npm install --legacy-peer-deps`. CMS uses `npm ci --legacy-peer-deps`
(ci.yml:532). Local runner is Node **22.22.2** (`/opt/node22/bin/node`) + the project node_modules; CI pins
the admin jobs to Node **20** (parity with `frontend-lint`/`cms-ts-compile`) and the `.mjs` `node --test`
job to Node **22**. **No `.ts` type-stripping anywhere; no docker; no VPS.**

### 🔴 VPS deferral — NONE

Phase 21 is pure frontend (`admin-dashboard/`), static-JSON manifest checks, three workflow `module_key`
string edits, a Node `.mjs` script, a CI workflow, and (21-04) CMS one-line source edits. There is no
live-Postgres migration, no secret to provision, no live import that introduces a NEW deferral (the
workflow `module_key` corrections take effect on the next n8n import — already covered by the Phase
17/18/20 deferred-import note). Every success criterion (lint green, Vitest green, module-key check green,
CMS tsc 0 errors) is locally/CI-verifiable. **Confirmed across all 4 plans: Phase 21 carries NO 🔴 VPS
execution sub-step.**

---

## Sampling Rate

- **After every task commit:** for `useEntitlements.ts`/test/banner → `npx eslint <file>` + `npx vitest run
  src/hooks/useEntitlements.test.tsx`; for `App.tsx`/workflows → `python3 json.load` + the App.tsx grep +
  `node scripts/check-module-keys.mjs`; for `entitlements.ts`/`AIChatBubble.tsx` → `npx eslint <file>`;
  for the `.mjs` → `/opt/node22/bin/node --test`; for the CMS files → `npx tsc --noEmit`; for the CI yml →
  `python3 yaml.safe_load`.
- **After every plan wave:** Wave 1 → `node scripts/check-module-keys.mjs` + `node --test` + `npx tsc
  --noEmit` (CMS) + `npx eslint src/types/entitlements.ts src/components/AIChatBubble.tsx`. Wave 2 → full
  `cd admin-dashboard && npm run lint && npx vitest run`.
- **Before `/gsd:verify-work`:** full `phase-21-assertions.yml` green — `admin-dashboard-lint` (the
  milestone-closing gate), `admin-dashboard-vitest`, `module-key-consistency`, and `cms-ts-compile` (0
  errors) all green.
- **Max feedback latency:** ~90s (full CI suite); <5s per-task local (single-file eslint/vitest/node-test).

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 21-02-01 | 02 | 1 | ENT-02 | grep + json.load (ghost-key fix) | App.tsx gates `kiosk_instore`/`admin_ai_intelligence`/`growth_marketing` (no `addon_*`/`experimental_growth_agent`); 3 workflows pass `kiosk_instore`/`order_bot_core`/`voice` (no `feature_kiosk`/`ordering_core`/`channel_voice`); all valid JSON | ✅ (files exist) | ⬜ pending |
| 21-02-02 | 02 | 1 | ENT-02 | node --test (consistency check) | `/opt/node22/bin/node --test scripts/__tests__/check-module-keys.test.mjs` + `node scripts/check-module-keys.mjs` exit 0 on post-fix tree | ❌ W0 | ⬜ pending |
| 21-02-03 | 02 | 1 | ENT-02 | yaml (CI gate creation) | `python3 yaml.safe_load(phase-21-assertions.yml)`; pinned checkout + setup-node SHAs; admin-lint+vitest Node 20, module-key Node 22; `legacy-peer-deps` fallback | ❌ W0 | ⬜ pending |
| 21-03-01 | 03 | 1 | TYP-01 | grep + tsc (shared DTOs) | `src/types/entitlements.ts` exports `ProductModuleFields`/`TenantEntitlementFields`/`ProductModuleRaw`/`TenantEntitlementRaw`/`unwrap`; no `any`; v4/v5 `attributes` tolerance | ❌ W0 | ⬜ pending |
| 21-03-02 | 03 | 1 | TYP-01 | eslint (AIChatBubble tidy) | `AIChatBubble.tsx` typed `AgentChatResponse`, no `as any`, no orphaned disable; `npx eslint src/components/AIChatBubble.tsx` clean | ✅ (file exists) | ⬜ pending |
| 21-01-01 | 01 | 2 | ENT-01 | Vitest (ENT-01 spec, RED first) | `npx vitest run src/hooks/useEntitlements.test.tsx` — false-while-loading, shared_core-visible, false+error-on-reject, entitled-true (v4 AND v5) | ❌ W0 | ⬜ pending |
| 21-01-02 | 01 | 2 | ENT-01 + TYP-01 | eslint + Vitest (fail-closed rewrite, GREEN) | `useEntitlements.ts` fail-closed (no `if(loading)return true`), `SHARED_CORE` allowlist, `setError`, `unwrap`, 0 `any`; `EntitlementErrorBanner.tsx` present; `npx eslint` clean + `npx vitest run src/hooks/useEntitlements.test.tsx` green | ✅ (hook exists) | ⬜ pending |
| 21-01-03 | 01 | 2 | TYP-01 | eslint + Vitest (tree-wide gate) | `cd admin-dashboard && npm run lint` exit 0 (the standing Frontend-Lint failure cleared) + `npx vitest run` full suite green | n/a | ⬜ pending |
| 21-04-01 | 04 | 1 | TYP-01 | grep + tsc (CMS fix) | 4 SaaS files carry `// @ts-ignore - UID registered at runtime`; `auth-ratelimit.ts` static `import Redis from 'ioredis'`; `cd inventory-cms && npx tsc --noEmit` exit 0 | ✅ (files exist) | ⬜ pending |
| 21-04-02 | 04 | 1 | TYP-01 | yaml (CI append) | `cms-ts-compile` job appended to `phase-21-assertions.yml` (Node 20, `npx tsc --noEmit`); 21-02 jobs intact; ≥4 jobs; valid YAML | ❌ W0 (21-02 creates the file) | ⬜ pending |

*Wave-0 artifacts (`useEntitlements.test.tsx`, `scripts/check-module-keys.mjs` + its `node --test`,
`src/types/entitlements.ts`, `EntitlementErrorBanner.tsx`, `phase-21-assertions.yml`) are themselves the
validation infrastructure. Wave 1 = {21-02, 21-03, 21-04} parallel; Wave 2 = {21-01} (imports 21-03's
types). The one same-file append: 21-02 CREATES `phase-21-assertions.yml`; 21-04 APPENDS the
`cms-ts-compile` job — see "Wave / ordering note".*

---

## Wave 0 Requirements

- [ ] `admin-dashboard/src/types/entitlements.ts` — shared v4/v5-tolerant DTOs + `unwrap()` (Plan 21-03 Task 1)
- [ ] `admin-dashboard/src/hooks/useEntitlements.test.tsx` — Vitest ENT-01 spec (Plan 21-01 Task 1)
- [ ] `admin-dashboard/src/components/EntitlementErrorBanner.tsx` — explicit error/locked surface (Plan 21-01 Task 2)
- [ ] `scripts/check-module-keys.mjs` — ENT-02 consistency check (Plan 21-02 Task 2)
- [ ] `scripts/__tests__/check-module-keys.test.mjs` — `node --test` for the check (Plan 21-02 Task 2; the dir is created)
- [ ] `.github/workflows/phase-21-assertions.yml` — CI gate; 21-02 CREATES (admin-lint + admin-vitest + module-key jobs), 21-04 APPENDS the `cms-ts-compile` job (Plans 21-02 / 21-04)

*(No framework install — Vitest/jsdom/@testing-library already in `admin-dashboard` devDependencies; `node`
22 at `/opt/node22/bin`, `jq`, `python3` present on the host; `node_modules` already installed in both
apps.)*

---

## Wave / ordering note

| Wave | Plans | Owned files (disjoint) |
|------|-------|------------------------|
| 1 | 21-02 | `admin-dashboard/src/App.tsx`, `workflows/W_KIOSK_ORDER.json`, `workflows/W_ORDER_FINALIZER.json`, `workflows/W30_VOICE_CALL_INIT.json`, `scripts/check-module-keys.mjs`, `scripts/__tests__/check-module-keys.test.mjs`, **creates** `.github/workflows/phase-21-assertions.yml` |
| 1 | 21-03 | `admin-dashboard/src/types/entitlements.ts`, `admin-dashboard/src/components/AIChatBubble.tsx` |
| 1 | 21-04 | `inventory-cms/src/api/product-module/controllers/product-module.ts`, `…/product-module/routes/product-module.ts`, `…/tenant-entitlement/controllers/tenant-entitlement.ts`, `…/tenant-entitlement/routes/tenant-entitlement.ts`, `inventory-cms/src/middlewares/auth-ratelimit.ts`, **appends to** `phase-21-assertions.yml` |
| 2 | 21-01 | `admin-dashboard/src/hooks/useEntitlements.ts`, `admin-dashboard/src/hooks/useEntitlements.test.tsx`, `admin-dashboard/src/components/EntitlementErrorBanner.tsx` |

**Dependency:** 21-01 (Wave 2) imports `ProductModuleRaw`/`TenantEntitlementRaw`/`unwrap` from
`admin-dashboard/src/types/entitlements.ts` (created by 21-03 in Wave 1) → `depends_on: ["21-03"]`. 21-02
and 21-04 are independent of 21-01/21-03 (different files entirely).

**The only shared file is `.github/workflows/phase-21-assertions.yml`:** 21-02 **creates** it (3 jobs);
21-04 **appends** the `cms-ts-compile` job. The executor runs 21-02 before 21-04 within Wave 1 (the
file-creator first), then 21-04 appends — a file-creation-before-append ordering, NOT a behavioral
dependency (each plan's logic is independent and individually testable). No two plans WRITE the same
non-CI file. `App.tsx` is touched by 21-02 ONLY; `useEntitlements.ts` by 21-01 ONLY (21-03 only creates the
shared types it imports).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual confirmation that the `EntitlementErrorBanner` renders a clear locked/error indicator (not a silent blank sidebar) when entitlements fail to load | ENT-01 (crit 1) | The *automated* gate is the Vitest hook test (`error===true` + fail-closed `hasModule`); the visual rendering of the banner is a presentation detail best eyeballed | OPTIONAL local: `cd admin-dashboard && npm run dev`, block the `/api/tenant-entitlements` request (devtools offline), confirm a visible "Entitlements unavailable — some modules are hidden" banner + core nav still usable. NOT a phase gate (the Vitest test is). NO VPS. |

*(There are NO 🔴 VPS manual verifications in Phase 21 — see "🔴 VPS deferral — NONE" above.)*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (every task carries one)
- [x] Wave 0 covers all MISSING references (`useEntitlements.test.tsx`, `entitlements.ts`, `EntitlementErrorBanner.tsx`, `check-module-keys.mjs` + its test, `phase-21-assertions.yml`)
- [x] No watch-mode flags (`vitest run`, not `vitest`)
- [x] Feedback latency < 100s (full suite ~90s); <5s per-task local
- [x] No `SAVEPOINT` in any DO block (N/A — Phase 21 has no SQL)
- [x] `nyquist_compliant: true` set in frontmatter
- [x] NO 🔴 VPS deferral (confirmed across all 4 plans — the milestone's clean-finish phase)

**Approval:** planned (4 plans — disjoint file ownership. Wave 1 = {21-02 module-key alignment + CI
creation, 21-03 shared DTOs, 21-04 CMS-TS fully-green}; Wave 2 = {21-01 fail-closed `useEntitlements` +
ENT-01 Vitest, depends_on 21-03}. The only shared file is `phase-21-assertions.yml` — created by 21-02,
the `cms-ts-compile` job appended by 21-04 in that order. CMS-TS DECISION: 4 `@ts-ignore` + the
planning-verified ioredis static-import fix → `npx tsc --noEmit` 0 errors / fully-green CMS TS. NO VPS
deferral.)
