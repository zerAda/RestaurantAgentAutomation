---
phase: 21-ui-fail-closed-parity-and-module-key-alignment-and-type-cleanup
plan: 03
subsystem: entitlements-types
tags: [TYP-01, dto, strapi-v4-v5, type-cleanup]
requires:
  - "admin-dashboard/src/hooks/useEntitlements.ts L30-43 attributes||self tolerance (read-only contract)"
provides:
  - "admin-dashboard/src/types/entitlements.ts: ProductModuleRaw/TenantEntitlementRaw + unwrap<T>() (consumed by 21-01)"
  - "AIChatBubble.tsx typed agent response (AgentChatResponse), no as-any/disable"
affects:
  - "admin-dashboard/src/components/AIChatBubble.tsx"
tech-stack:
  added: []
  patterns: ["v4/v5-tolerant Raw union + unwrap<T>()"]
key-files:
  created:
    - "admin-dashboard/src/types/entitlements.ts"
  modified:
    - "admin-dashboard/src/components/AIChatBubble.tsx"
decisions:
  - "Per-file tsc verify dropped in favour of eslint typed-parser advisory gate + tree-wide gate in 21-01 (warning #3)"
metrics:
  tasks: 2
  files: 2
  completed: "2026-06-20"
---

# Phase 21 Plan 03: Shared Entitlement DTOs + AIChatBubble Type Cleanup Summary

Introduced the shared v4/v5-tolerant entitlement DTOs in a new type-only `admin-dashboard/src/types/entitlements.ts` (the contract 21-01 consumes) and retired the one genuine cross-component `any` (`AIChatBubble.tsx:134`'s `as any` + its eslint-disable) via a typed `AgentChatResponse`.

## What was built

- **`admin-dashboard/src/types/entitlements.ts`** (new, type-only, zero runtime deps): `ProductModuleFields` (key + optional tier/enabled_globally/display_name), `TenantEntitlementFields` (module_key + optional tenant_id/enabled), the `ProductModuleRaw`/`TenantEntitlementRaw` unions (v5 flat OR v4 `{id, attributes}`), and `unwrap<T>(row)` returning `row.attributes` when present else `row` (the typed equivalent of the hook's `m.attributes || m`).
- **`AIChatBubble.tsx`:** a file-local `interface AgentChatResponse { reply?; actions?: ChatMessage['actions']; needsConfirmation?; confirmAction?: ChatMessage['confirmAction']; ragSlices?: string[]; }` reusing the existing `ChatMessage` field types; replaced `// eslint-disable-next-line @typescript-eslint/no-explicit-any` + `(resJson?.data || resJson || {}) as any` with `(resJson?.data ?? resJson ?? {}) as AgentChatResponse`.
- **Untouched (no churn):** `NotificationCenter`, `ToastProvider`, `AnalyticsView`, `AutomationView` — verified zero `any`; left alone as planned.

## Verification

- Task 1 structural checks: PASS (Fields/Raw/unwrap present, v4/v5 `attributes` tolerance, no `any`). `npx eslint src/types/entitlements.ts` clean (typed parser).
- Task 2: `interface AgentChatResponse` present, `as AgentChatResponse` present, no `as any`, no orphaned disable; `npx eslint src/components/AIChatBubble.tsx` clean.
- `git status` confirmed only `AIChatBubble.tsx` modified among components (the 4 already-clean files untouched).
- Tree-wide `npm run lint` (0 errors) + full `npx vitest run` are gated in 21-01 (Wave 2, which compiles the DTOs through their consumer) and the `phase-21-assertions.yml` admin jobs.

## Deviation: per-file tsc verify (warning #3 folded in)

The plan's per-task verify proposed `npx tsc --noEmit src/types/entitlements.ts … || true`. A single-file `tsc` invocation ignores the project `tsconfig` (spurious lib/module diagnostics) and the `|| true` would swallow real errors — i.e. a verify that always passes. Per the brief's warning #3, this was replaced with a genuinely-gated check: `npx eslint src/types/entitlements.ts` (typed-parser, no `|| true`) as the advisory per-file gate, with the REAL compile-through-consumer gate being the tree-wide `npm run lint` + `npx vitest run` in 21-01. No always-passing verify shipped.

## VPS deferral

NONE. Pure frontend type work; locally + CI verifiable.

## Self-Check: PASSED
