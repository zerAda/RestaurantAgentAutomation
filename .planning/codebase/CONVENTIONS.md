# Coding Conventions

**Analysis Date:** 2026-06-20

RESTO BOT ("Ralphé") is a polyglot monorepo. Conventions differ per stack, so this
document is split by surface: React/TS frontends, Strapi CMS, n8n workflow JSON,
bash/Python scripts, plus cross-cutting error handling and the workflow governance gate.

## Surfaces & Where They Live

| Surface | Language | Location | Lint/Build |
|---------|----------|----------|------------|
| Admin Dashboard | React 19 + TS | `admin-dashboard/src/` | ESLint flat + `tsc --noEmit` + Vite |
| Kiosk App | React 19 + TS | `kiosk-app/src/` | ESLint flat + `tsc --noEmit` + Vite |
| Inventory CMS | Strapi 5 + TS | `inventory-cms/src/` | `tsc --noEmit` (no ESLint) |
| Workflows | n8n JSON | `workflows/*.json` | `integrity_gate.sh` + `workflow-validate.yml` |
| Ops scripts | bash + Python | `scripts/`, `tests/` | `bash -n`, integrity gate |

---

## Naming Patterns

**Files (React/TS — `admin-dashboard/`, `kiosk-app/`):**
- Components: `PascalCase.tsx` (`KitchenView.tsx`, `ErrorBoundary.tsx`, `AppSwitcher.tsx`)
- Page-level views: `PascalCase.tsx` under `src/pages/` (`OrdersKanban.tsx`, `GodMode.tsx`)
- Services: `camelCase.ts` under `src/services/` (`strapiClient.ts`, `menuService.ts`, `authService.ts`, `orders.ts`)
- Hooks: `useXxx.ts` under `src/hooks/` (`useEntitlements.ts`)
- Utilities: `camelCase.ts` under `src/utils/` or `src/lib/` (`i18n.ts`, `pii.ts`, `utils.ts`)
- UI primitives: lowercase under `src/components/ui/` (`card.tsx`, `badge.tsx`, `badge-variants.ts`)
- Tests: `*.test.ts` / `*.test.tsx` co-located with source (`App.lazy.test.tsx`, `menuService.cache.test.ts`)

**Files (Strapi — `inventory-cms/src/api/`):**
- One directory per content type in `kebab-case` (`tenant-entitlement/`, `delivery-zone/`, `conversation-state/`)
- Standard Strapi triplet inside each: `controllers/<name>.ts`, `routes/<name>.ts`, `services/<name>.ts`, `content-types/<name>/schema.json`
- Prefer `.ts` (41 controllers) over `.js` (6 legacy controllers — `agent-session`, `customer-reward`). New code is `.ts`.
- Lifecycle hooks: `content-types/<name>/lifecycles.ts`
- Middlewares: `src/middlewares/<kebab-case>.ts` (`request-id.ts`, `admin-cookie-auth.ts`)

**Files (workflows — `workflows/`):**
- Pattern enforced by CI: `^W[0-9]+(\.[0-9]+)?_.*\.json$` (e.g., `W1_IN_WA.json`, `W4.2_CART_MANAGER.json`)
- Channel-adapter convention: `W#_IN_<CHANNEL>` for inbound (`W1_IN_WA`, `W2_IN_IG`, `W3_IN_MSG`), `W#_OUT_<CHANNEL>` for outbound (`W5_OUT_WA`, `W6_OUT_IG`, `W7_OUT_MSG`)
- Named (non-numbered) workflows use `W_<DOMAIN>` SCREAMING_SNAKE (`W_DRIVER_ROUTER`, `W_PAYMENT_CALLBACK`, `W_KIOSK_ORDER`)
- Layer-0 infra/util workflows prefixed `W0_` (`W0_CONFIG_READER`, `W0_REDIS_HELPER`)

**Files (scripts — `scripts/`):**
- bash: `snake_case.sh` or `kebab-case.sh`; test scripts `test_*.sh`, smoke scripts `smoke-*.sh` / `smoke_*.sh`, patch scripts `patch_*.js`/`patch_*.py`
- Python helpers: `snake_case.py` (`validate_contracts.py`, `test_darja_intents.py`)

**Functions / variables (TS):**
- `camelCase` for functions and variables; `UPPER_SNAKE_CASE` for module constants (`CACHE_TTL_MS`, `MAX_STATE_JSON_BYTES`, `PLACEHOLDER_IMG`, `LAZY_COMPONENTS`)
- React hooks `useXxx`; event handlers `handleXxx` (`handleReset`)
- Internal/module-private values use a leading underscore sparingly (`_token`, `_auth`)
- Strapi-shaped DTOs interfaced separately from app models: `StrapiOrder` (raw API shape) vs `Order` (app shape); `StrapiProduct` vs `Product`. A `mapXxx()` function bridges them (`mapOrder`, `mapProduct`).

**Types (TS):**
- `PascalCase` interfaces, **no `I` prefix** (`Order`, `Product`, `RequestOptions`, `RequestContext`)
- Union string literals for enums/status (`OrderStatus = 'pending' | 'confirmed' | ...`) — **lowercase values to match Strapi schema enums** (see `orders.ts` F-04 fix)
- Generic wrapper types: `StrapiResponse<T>` for the `{ data, meta }` envelope

**SaaS multi-tenant terms (introduced by recent work — keep consistent):**
- `tenant_id` (string) — tenant identifier, snake_case in DB/schema and n8n; `tenantId` in TS code
- `module_key` / `key` — references `product-module.key`
- Content types: `product-module`, `tenant-entitlement` (`inventory-cms/src/api/`)
- Hook: `useEntitlements(tenantId)` exposing `hasModule(key)` (`admin-dashboard/src/hooks/useEntitlements.ts`)
- n8n tenant isolation uses `tenant_context` in Strapi filter `restaurant_id.$eq` (gate-enforced — see Workflow Authoring)

---

## Code Style

**Formatting (React/TS):**
- No Prettier config committed — style is enforced by ESLint + reviewer convention, not an auto-formatter.
- Indentation is inconsistent across files (2-space in services/hooks, 4-space in some components like `orders.ts`, `ErrorBoundary.tsx`). **Match the surrounding file**, do not reformat wholesale.
- Single quotes for strings; semicolons required; template literals for interpolation.
- Tailwind utility classes inline in `className`; compose with `cn()` helper (`clsx` + `tailwind-merge`) from `src/lib/utils.ts`.

**Linting (React/TS):**
- ESLint flat config at `admin-dashboard/eslint.config.js` and `kiosk-app/eslint.config.js` (identical):
  extends `@eslint/js` recommended, `typescript-eslint` recommended, `eslint-plugin-react-hooks` flat recommended, `eslint-plugin-react-refresh` vite. `dist` is globally ignored.
- Run: `npm run lint` (in each app dir). CI runs it per-app in the `frontend-lint` matrix.
- TS strictness (`tsconfig.app.json`): `strict: true`, `noUnusedLocals`, `noUnusedParameters`, `noFallthroughCasesInSwitch`, `verbatimModuleSyntax`, `erasableSyntaxOnly`, `noUncheckedSideEffectImports`. `skipLibCheck: true`.
- `any` appears in newer SaaS code (`useEntitlements.ts`) — tolerated but not preferred; prefer typed Strapi DTOs.

**Strapi TS:**
- No ESLint. The only gate is `npx tsc --noEmit` (CI job `cms-ts-compile`).
- **`tsconfig.json` `module` MUST be `CommonJS`** — CI hard-fails if set to ESNext/ES2022/NodeNext (Strapi 5 ESM-interop crash). This is the single most load-bearing CMS config rule.
- Strapi internals are loosely typed; `ctx: any` and `// @ts-ignore` on `strapi.db.connection.raw(...)` are accepted in controllers (`control-plane.ts`).

**bash:**
- Every script starts with `#!/usr/bin/env bash` then `set -euo pipefail`.
- Resolve repo root via `ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` then `cd "$ROOT_DIR"`.
- Define a `fail() { echo "❌ $*" >&2; exit 1; }` helper and a `need()` dependency-check helper (see `test_harness.sh`).
- Env inputs use defaulting `${VAR:-default}` and required-assertion `: "${VAR:?missing}"` (see `smoke.sh`).

---

## Import Organization

**React/TS order (observed convention):**
1. External packages (`react`, `@tanstack/react-query`, `lucide-react`, `framer-motion`)
2. Internal services/hooks/lib via relative or `@/` alias
3. Type-only imports inline with `import type { ... }` or `import { type Foo }` (`verbatimModuleSyntax` requires explicit `type`)

**Path alias:** `@/` → `src/` (configured in both `tsconfig.app.json` `paths` and `vite.config.ts` `resolve.alias`). Many files still use relative imports (`../services/strapiClient`); both are accepted.

**Strapi:** factory imports from `@strapi/strapi` (`import { factories } from '@strapi/strapi'`); node built-ins via `node:` prefix (`import { AsyncLocalStorage } from 'node:async_hooks'`).

---

## Error Handling

**React/TS (frontend):**
- Centralized fetch wrapper `request<T>()` in each app's `services/strapiClient.ts` is the single error boundary for network calls. It:
  - Adds a configurable `AbortController` timeout (default 10s, `timeoutMs` override e.g. 60s for agent chat)
  - On `401`: clears `admin_jwt` from session/local storage, stores `redirect_after_login`, dispatches a `strapi-auth-error` CustomEvent, redirects to `/`
  - On `>=500`: dispatches a `strapi-network-error` CustomEvent (consumed by `ApiErrorListener.tsx` / `ToastProvider.tsx`)
  - Parses the Strapi error JSON body (`error.message`) before throwing, falling back to HTTP status
  - Distinguishes `AbortError` (timeout) vs `Failed to fetch` (network/CORS) for user-facing French messages
- Cross-component errors surface via `window.dispatchEvent(new CustomEvent(...))` — a DOM-event bus, not a context/store.
- Render errors are caught by class `ErrorBoundary` (`components/ErrorBoundary.tsx`) using `getDerivedStateFromError` + `componentDidCatch`; user-facing copy is in French, reset reloads the page.
- React Query mutations log failures in `onError` with a bracketed tag: `console.error('[KitchenView] Failed to update order status:', err)`.
- Throwing style: `throw new Error(message)` with the parsed/contextual message; no custom error subclasses.

**Strapi (CMS):**
- Lightweight controllers default to Strapi factories (`factories.createCoreController(...)`) — no try/catch needed.
- Custom controllers use Koa `ctx`: `ctx.send(body, statusCode)` for success/degraded, `ctx.throw(500, message)` for failures (`control-plane.ts`).
- Lifecycle validation throws `Error` with a descriptive, prefixed message that propagates to the API client (`[ConversationState] state_json exceeds maximum size...` in `conversation-state/.../lifecycles.ts`).
- Health endpoints fail soft: DB ping failure returns `503` with `{ status: 'degraded' }`, never leaks internals on the public route.

**bash:** `set -euo pipefail` + `fail()` helper; smoke/test scripts use explicit HTTP status capture (`curl -s -o file -w "%{http_code}"`) and compare expected codes; non-fatal probes wrapped in `set +e` / `set -e`.

**n8n workflows:** see Workflow Authoring — explicit `RESP - 200` / `RESP - 4xx` responder nodes, deny logging to `security_events`, and a global `W8_OPS` / `W_ERROR_HANDLER` error workflow.

---

## Logging

**Frontend:** `console.error`/`console.warn` only, tagged with a bracketed component/module name. No logging framework. Avoid `console.log` in committed code.

**Strapi:** Pino via Strapi's `strapi::logger` middleware (config `inventory-cms/config/logger.ts`). Request correlation: `request-id.ts` middleware reads the nginx-injected `X-Request-ID` header into an `AsyncLocalStorage` store (`requestContextStorage`) so service/controller code without `ctx` still logs the request id. A `prometheus-tracker` middleware exposes metrics.

**n8n / DB:** security-relevant events are written to Postgres tables, not stdout — `security_events` (deny/SSRF/scope events with severity) and `admin_audit_log` (allow/audit trail). Structured `jsonb_build_object(...)` payloads.

---

## Comments

- Comment **why**, not what. Heavy use of **change-tracking tags** keyed to the issue/fix that introduced a line — preserve these, they are load-bearing context:
  - `// BUG-0NN FIX: ...`, `// F-0N FIX: ...` (frontend), `// SEC-001:`, `// P0 SECURITY:`, `// PERF-09:` (tests), `[OBS-04]`, `[D-04] FIX:` (Strapi).
- Strapi files use JSDoc block headers describing the problem/solution rationale (`lifecycles.ts`, `request-id.ts`).
- No enforced TODO format; placeholders `CHANGE_ME` / `REPLACE_ME` are **forbidden in committed config** and fail the integrity gate.

---

## Function & Component Design

**React:**
- Functional components with hooks are the default; the only class component is `ErrorBoundary` (required for error boundaries).
- Route-level views are **lazy-loaded** via `React.lazy()` and wrapped in `<Suspense fallback=...>` — enforced by `App.lazy.test.tsx`. App-shell components (`LoginView`, `AppSwitcher`, `AIChatBubble`, `NotificationCenter`) stay eager. Suspense fallback uses the locked skeleton pattern `min-h-[60vh]` + `bg-white/5`.
- Data fetching via TanStack React Query: `useXxx` hooks return `useQuery`/`useMutation`; query keys are arrays (`["orders"]`); mutations `invalidateQueries` on success; polling via `refetchInterval`.
- Keep the Strapi raw shape and the app shape separate; convert with a pure `mapXxx()` function.

**Strapi:**
- Default to core factory controllers/routers/services unless custom behavior is needed; only then hand-write the handler.
- Validation/business rules live in lifecycle hooks or services, not routes.

**Exports:**
- Strapi: `export default` the factory or handler object (Strapi convention).
- React components: a named export plus an additional `export default` is common (`ErrorBoundary`).
- Services: named exports (`export const strapi = {...}`, `export const menuService = {...}`, `export function setStrapiToken`).

---

## Workflow Authoring (n8n JSON)

These conventions are partly **enforced** by `scripts/integrity_gate.sh` and `.github/workflows/workflow-validate.yml`; treat them as hard rules.

**Required top-level shape (gated):**
- Every `workflows/*.json` must have `.name` (string), `.nodes` (array), `.connections` (object), and `.active` (boolean or null). `jq -e '.name and .nodes and .connections ...'` must pass.
- Filename must match `W<N>_*.json` (warning-level for named `W_*` workflows).
- `.name` inside JSON is human-readable with a number prefix (`"W9 - ADMIN Ping (Scopes Enforced)"`), distinct from the filename slug.

**Node naming convention (strong, observed):**
- Nodes are named `<PREFIX> - <Description>` where the prefix encodes pipeline stage/branch:
  - `IN - Webhook` / `IN - Sub-workflow Trigger` — entry nodes (27 `IN` nodes)
  - `B0 - ...`, `B1 - ...`, `B1a - ...`, `B2/B3/B4` — sequential processing blocks (`B0` is the canonical parse/auth block, 155 occurrences)
  - `RESP - 200 OK`, `RESP - 400`, `RESP - 401`, `RESP - 403 Forbidden` — responder nodes (the gate requires a `RESP - 200` and a `RESP - (400|401)` on inbound parsers)
  - `END - ...`, `AUDIT - ...`, `CRON - ...`, `Strapi - ...`, `Redis - ...`, `PG - ...` — semantic stage prefixes
- Code nodes: `language: "javascript"` always (257/257); prefer `typeVersion: 2` (279 nodes) — v1 (62 nodes) exists in older workflows.

**Code-node patterns:**
- Reference upstream node output with `$items("<Node Name>")[0].json` and current input with `$json`.
- Read config/secrets from env with `$env.<VAR>` (e.g. `$env.WEBHOOK_SHARED_TOKEN`, `$env.TENANT_CONTEXT_SECRET`, `$env.LLM_API_URL`). **Never inline secrets.**
- Auth/canonicalization happens in `B0 - Parse & Canonicalize` / `B0 - Parse Auth`: hash tokens with `crypto.createHash('sha256')`, extract bearer/`x-api-token`/`x-webhook-token`, build a `_auth` object (`tokenPresent`, `tokenHash`, `authOk`, `scopeOk`, `authMode`, `scopes`, `denyReason`).
- Return shape is always `return [{ json: { ... } }]`.

**Security gates the integrity gate enforces on inbound parsers (`W1_IN_WA`, `W2_IN_IG`, `W3_IN_MSG`):**
- `B0 - Parse & Canonicalize` jsCode must contain `ALLOW_QUERY_TOKEN` gating.
- `B0 - Token OK?` IF node must check `={{$json._auth.scopeOk}}`.
- `B0 - Log Deny (DB)` must parameterize `event_type` (`$6`) and insert into `security_events`.
- Must include `B0 - Contract Valid?`, a `RESP - 200`, and a `RESP - 400/401` node.
- `IN - Webhook` must use `responseMode: "responseNode"`.
- `W1_IN_WA` specifically must keep the `B1a - Admin Access Validator (SECURED)` node and route through it (no bypass).

**Tenant isolation (gated):**
- Any `n8n-nodes-base.strapi` read node with a `parameters.filters.restaurant_id.$eq` filter MUST reference `tenant_context` (authenticated context), not a hardcoded id. 14 workflows reference `tenant_context`.

**Credential referencing:**
- 36 workflows reference credentials by **env-injected credential ID**, not inline secrets:
  `"credentials": { "redis": { "id": "={{ $env.REDIS_CREDENTIAL_ID }}", "name": "Redis" } }`.
- Top credential types: `redis` (59 nodes), `postgres` (30), `strapiApi`/`strapiTokenApi` (6), `httpHeaderAuth` (1).
- No hardcoded IPs (CI warns); no `executeCommand` nodes without security review (CI warns).

**Registry & manifest:**
- Workflows are catalogued in `config/workflow_registry.json` and `workflows/MANIFEST.md`. `tests/test_registry_validity.sh` cross-checks that registry entries map to real files and flags unregistered workflows.
- Numeric workflow IDs are resolved from the live DB by `scripts/generate_workflow_ids.sh` into `.env.workflow_ids.generated` (never hardcoded).
- Patch/refactor scripts (`scripts/patch_w*.js`, `refactor_w4.js`) programmatically rewrite workflow JSON; prefer these for bulk edits over manual JSON surgery.

---

## Governance / Integrity Gate

`scripts/integrity_gate.sh` (`set -euo pipefail`, `fail()` helper) is the single quality gate run first in CI (`integrity-gate` job, all other jobs `needs` it). Its checks:
1. `bash -n scripts/*.sh` syntax check.
2. Forbidden `CHANGE_ME` placeholder scan (excludes docs/patches/templates/`.env.example`).
3. Workflow JSON validation + per-channel security-gate assertions + tenant-isolation assertions (above).
4. Python contract/L10N unit tests (`validate_contracts.py`, `test_darja_intents.py`, `test_template_render.py`, `test_l10n_script_detection.py`).
5. DB bootstrap ordering (orders before outbound_messages — FK dependency).
6. Required-files presence (migrations, scripts, docs, templates, fixtures, key workflows).
7. `VERSION` semver validation (`X.Y.Z`).
8. Compose YAML parse (best-effort PyYAML).
9. Backup/restore script lint (strict mode + `CONFIRM_RESTORE` gate).
10. P0 security flag presence in `config/.env.example` (`LEGACY_SHARED_ALLOWED`, `META_SIGNATURE_REQUIRED`, `STRICT_AR_OUT`, `ADMIN_WA_AUDIT_ENABLED`).

When adding a workflow, migration, script, or doc that other systems depend on, **add the corresponding presence/assertion to the integrity gate** so it stays enforced.

---

*Convention analysis: 2026-06-20*
*Update when patterns change*
