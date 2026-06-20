# Phase 21 — Deferred / Out-of-Scope Discoveries

These were observed during Phase 21 execution but are NOT caused by Phase 21 changes and are
explicitly out of Phase 21 scope (the phase gate is admin-dashboard `eslint .` + `vitest run`,
which are both GREEN; the CMS gate is `npx tsc --noEmit`, which is 0 errors).

## admin-dashboard `npx tsc -b --noEmit` pre-existing errors (NOT the lint gate)

The research (`21-RESEARCH.md` §7, Anti-Patterns) flagged these as the stale-`tsc_output.txt`
errors and instructed "do not chase them" — they are NOT Phase-21 scope and live entirely in
files Phase 21 never touched:

- `src/App.lazy.test.tsx` — `fs`/`path`/`__dirname` (Node-builtin types not in the app tsconfig lib).
- `src/components/AnalyticsView.tsx:92` — unused `@ts-expect-error` directive.
- `src/components/AutomationView.tsx:74` — `_t` declared but never read.
- `src/components/KitchenView.tsx` — multiple `OrderStatus` casing mismatches (`"NEW"` vs lowercase, etc.).
- `src/components/QuickAdjust.tsx:87` — `"ok" | "low"` vs `"warning"` overlap.

Zero tsc errors exist in any Phase-21-touched file (`useEntitlements.ts`, `EntitlementErrorBanner.tsx`,
`types/entitlements.ts`, `AIChatBubble.tsx`, `App.tsx`). Verified: the touched-file grep over the
`tsc -b` output returned NONE.

These belong to a future type-cleanup pass (OrderStatus casing reconciliation), not this phase.
