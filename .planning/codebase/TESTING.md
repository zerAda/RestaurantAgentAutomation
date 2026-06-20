# Testing Patterns

**Analysis Date:** 2026-06-20

Testing in RESTO BOT is **layered and heterogeneous**. There is no single test runner;
each surface has its own mechanism, and the bulk of confidence comes from bash/Python
smoke and integration scripts plus the integrity gate — not unit tests. Understand which
layer you are touching before adding tests.

## Test Layers Overview

| Layer | Tooling | Location | Runs in CI? |
|-------|---------|----------|-------------|
| Integrity gate (static governance) | bash + `jq` + python | `scripts/integrity_gate.sh` | Yes — `integrity-gate` (blocking, first) |
| Python contract / L10N units | python3 + `jsonschema` | `scripts/validate_contracts.py`, `scripts/test_*.py` | Yes — `python-tests` (JUnit) |
| Frontend unit/contract | Vitest | `admin-dashboard/src/*.test.*`, `kiosk-app/src/*.test.*` | Lint+build only (see gap below) |
| DB integration | bash + `psql` | `.github/workflows/ci.yml` inline | Yes — `integration-tests` (PG15/16 matrix) |
| Full-stack harness | bash + docker compose | `scripts/test_harness.sh` | Yes — `test-harness` (main/release) |
| Smoke (HTTP) | bash + `curl` | `scripts/smoke*.sh`, `scripts/test-n8n-e2e.sh` | Syntax + dry-run on main/release |
| Load | k6 | `tests/k6-load-test.js` | No (manual/perf-baseline) |
| Chaos/destructive | bash | `tests/destructive/chaos-monkey.sh`, `scripts/chaos-monkey.sh` | No (manual) |

---

## Frontend Tests (Vitest)

**Runner:**
- Vitest `^4.0.18` (both `admin-dashboard` and `kiosk-app`), config inline in `vite.config.ts`:
  `test: { environment: 'jsdom', globals: true }`. `jsdom ^28` provides the DOM.
- Assertion library: Vitest built-in `expect` (`@testing-library/jest-dom` + `@testing-library/react` available but `@testing-library/react` is not yet used in committed tests).

**Run Commands:**
```bash
# from admin-dashboard/ or kiosk-app/
npm test                 # = "vitest run" (single pass, CI mode)
npx vitest               # watch mode (not scripted in package.json)
npx vitest run src/App.lazy.test.tsx   # single file
```

**Test file organization:**
- Co-located with source as `*.test.ts` / `*.test.tsx`. No separate `tests/` tree in the frontends.
- Current committed tests (4 total):
  - `admin-dashboard/src/setup.test.ts` — trivial truthiness smoke
  - `admin-dashboard/src/App.lazy.test.tsx` — **source-text assertion** test (reads `App.tsx` with `fs` and asserts `React.lazy()` / `<Suspense>` / skeleton patterns)
  - `kiosk-app/src/setup.test.ts` — trivial truthiness smoke
  - `kiosk-app/src/menuService.cache.test.ts` — behavioral test of the TTL cache with a mocked Strapi client

**Test structure (actual pattern):**
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('./services/strapiClient', () => ({
  strapi: { get: vi.fn().mockResolvedValue({ data: [/* fixture */] }) },
}));

describe('menuService — PERF-09: TTL cache prevents redundant API calls', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.clearAllMocks();
  });

  it('should return cached data on second call without a network request', async () => {
    const { menuService } = await import('./services/menuService');
    const { strapi } = await import('./services/strapiClient');
    await menuService.getProducts();
    await menuService.getProducts();
    expect(strapi.get).toHaveBeenCalledTimes(1);
  });
});
```

**Patterns / conventions:**
- `describe` titles encode the issue/requirement under test (e.g. `PERF-09`, `PERF-07`).
- Custom assertion messages passed as the 2nd arg to `expect(value, 'why this matters')`.
- Module-under-test imported **lazily inside the test** (`await import(...)`) after `vi.mock(...)`, so module-level state (caches) resets per test.
- Mock at the module boundary (`vi.mock('./services/strapiClient', ...)`); reset history with `vi.clearAllMocks()` in `beforeEach`.
- Two distinct test styles co-exist: **behavioral** (cache, network calls) and **structural/source-grep** (assert that `App.tsx`/`VerticalVideoFeed.tsx` contain required strings). The source-grep style is a lightweight guard against regressions in lazy-loading and "use the service, not raw fetch" rules.

**Coverage:** No coverage target or `--coverage` config. Vitest coverage is not wired into CI.

---

## Python Tests (contract & localization)

**Runner:** plain `python3` scripts (no pytest). Dependencies in `scripts/requirements-ci.txt` (`jsonschema`, `pyyaml`). Each script is self-contained, prints `OK:`/`FAIL:` lines, and exits non-zero on failure.

**Files:**
- `scripts/validate_contracts.py` — validates inbound payload fixtures in `tests/contracts/` against JSON Schemas in `schemas/inbound/v1.json` & `v2.json` using `Draft202012Validator`. Tests both **expected-pass** (`valid_v1.json`, `valid_v2.json`) and **expected-fail** (`invalid_missing_msg_id.json`, `invalid_wrong_types.json`) cases. Prints schema SHA-256 hashes for drift detection.
- `scripts/test_darja_intents.py` — Algerian Darija intent detection cases (`tests/darja_phrases.json`).
- `scripts/test_template_render.py` — message template rendering (`tests/template_render_cases.json`).
- `scripts/test_l10n_script_detection.py` — Arabic vs Latin script detection (`tests/arabic_script_cases.json`).

**Runner wrapper (CI):** `scripts/ci_test_runner.sh` runs the four python tests, times each, and emits **JUnit XML** to `test-results/results.xml` (uploaded as the `python-test-results` artifact). The same four tests are also invoked directly inside `integrity_gate.sh` steps [4] and [4b].

```bash
python3 scripts/validate_contracts.py     # contracts
bash scripts/ci_test_runner.sh            # all four + JUnit output locally
```

---

## DB Integration Tests

Defined **inline in `.github/workflows/ci.yml`** (jobs `integration-tests` and `integration-tests-pg16`), not as a standalone script. Spins up `postgres` (matrix `15-alpine`; `16-alpine` on main/release) + `redis:7-alpine` service containers, then:
1. Applies `db/bootstrap.sql`, creates the `strapi` database.
2. Applies every `db/migrations/*.sql` in sorted order (special-casing cross-database `\c` migrations).
3. **Idempotence check** — re-applies all migrations and warns if any are not idempotent.
4. **Schema integrity** — asserts a hardcoded list of ~18 critical tables exists (`tenants`, `restaurants`, `api_clients`, `orders`, `outbound_messages`, `security_events`, `conversation_state`, `delivery_zones`, ...). Missing table = hard fail.

Migration-only validation is also available standalone via `.github/workflows/migration-validate.yml` and `scripts/db_migrate_all.sh`.

---

## Full-Stack Test Harness

`scripts/test_harness.sh` is the heaviest test — a CI-friendly ephemeral stack:
- Uses `docker/docker-compose.test.yml` (`COMPOSE_FILE` override), base URL `http://localhost:18080`.
- Boots `postgres + redis + mock-api` (mock-api in `mock-api/`), waits for readiness, applies migrations, seeds fixtures, imports workflows, then runs smoke tests **including scope enforcement** with `INBOUND_TOKEN` / `ADMIN_TOKEN` / `CUSTOMER_TOKEN`, then tears down (`down -v`).
- Requires `docker`, `curl`, `jq` (checked via `need()`).
- CI job `test-harness` runs it on main/release only; uploads `docker compose logs` + container state as artifacts on failure.
- Related broad scripts: `scripts/test_battery.sh`, `scripts/test_e2e.sh`, `scripts/test_outbound.sh`, `scripts/test_dedupe.sh`, and per-epic suites `scripts/test_p2*.sh` / `test_p106_logging.sh` / `test_security_hardening.sh`.

---

## Smoke Tests (HTTP, live services)

Live HTTP probes against a deployed/ephemeral stack. They require real services; in CI they are **syntax-checked (`bash -n`) and run as best-effort dry-runs** that downgrade failures to warnings (no live backend in CI).

Key smoke scripts in `scripts/`:
- `smoke.sh` — health + inbound auth (valid/invalid token → expect `AUTH_DENY` in `security_events`), v2 contract (valid → 200, invalid → 400), SSRF `audioUrl` block, optional query-token deny. Reads `DOMAIN_NAME`, `WEBHOOK_SHARED_TOKEN`.
- `smoke-n8n-e2e.sh` / `test-n8n-e2e.sh` — n8n webhook end-to-end (CI job `smoke-n8n-e2e`, needs `integration-tests`).
- `smoke-nginx-routing.sh` / `smoke-nginx-routing-v2.sh` — gateway routing (CI job `smoke-nginx-routing` against an `nginx:1.27-alpine` service).
- `smoke-strapi-permissions.sh` — Strapi role/permission checks (CI job `smoke-strapi-permissions`).
- `smoke-cms-routes.sh`, `smoke-correlation.sh`, `smoke_meta.sh`, `smoke_security.sh`, `smoke_security_gateway.sh`, `smoke-post-rebuild.sh`.
- `tests/tests.md` documents the manual smoke procedure (curl recipes) in French.

**Smoke conventions:** capture status explicitly with `curl -s -o /tmp/file -w "%{http_code}"` and compare; print `✅`/`❌`/`⚠️` markers; treat security outcomes as DB assertions (event written to `security_events`) rather than just HTTP codes.

---

## Load & Chaos Tests

- **Load:** `tests/k6-load-test.js` (k6). Stages ramp to 20 VUs; thresholds `http_req_duration p(95)<500ms` and `http_req_failed rate<0.01`. Targets `__ENV.API_URL` (default `http://localhost:8080`): `/healthz`, `/v1/menu`, and a prompt-injection POST to `/v1/inbound/whatsapp` (expects `<500`). Run: `k6 run -e API_URL=... tests/k6-load-test.js`. Not in `ci.yml`; perf tracked via `.github/workflows/perf-baseline.yml`.
- **Chaos:** `tests/destructive/chaos-monkey.sh` and `scripts/chaos-monkey.sh` — manual resilience drills (container kills, etc.). Not CI-gated.
- **Restore drill:** `scripts/restore_drill.sh` exercises backup/restore.

---

## Fixtures & Mocking

**SQL seed fixtures** (`tests/fixtures/`, applied by the harness in numeric order):
- `00_seed_api_clients.sql` (token hashes + scopes — referenced by integrity gate), `10_seed_orders_outbox.sql`, `20_seed_delivery_demo.sql`, `40_seed_support_faq.sql`, `45_seed_l10n_demo.sql`.

**Contract fixtures** (`tests/contracts/`): paired valid/invalid JSON payloads for schema tests, plus media-fetch request/DLQ samples.

**Data-driven case files** (`tests/`): `darja_phrases.json`, `template_render_cases.json`, `arabic_script_cases.json` — case tables consumed by the python tests.

**Mocking:**
- Frontend: Vitest `vi.mock()` at the module boundary (the Strapi client); `vi.fn().mockResolvedValue(...)`; `localStorage`/jsdom provided by `environment: 'jsdom'`.
- Harness/smoke: a real `mock-api` service (`mock-api/`) stands in for external send URLs (WhatsApp/IG/Messenger) instead of in-process mocks.
- No Strapi-side unit test framework or mocks; CMS confidence comes from `tsc --noEmit` + integration/smoke.

---

## CI Test Jobs (`.github/workflows/`)

Dependency graph (all jobs `needs: integrity-gate` first):
- `integrity-gate` — blocking governance gate (`scripts/integrity_gate.sh`).
- `lint-validate` — workflow JSON syntax, naming convention, `bash -n scripts/*.sh`, compose `config` validation.
- `python-tests` — `ci_test_runner.sh`, uploads JUnit `results.xml`.
- `integration-tests` (PG15) + `integration-tests-pg16` (main/release) — migrations + schema integrity.
- `cms-ts-compile` — asserts `tsconfig module != ESNext` then `npx tsc --noEmit` for `inventory-cms`.
- `frontend-lint` (matrix `admin-dashboard`, `kiosk-app`) — `npm run lint` + `npm run build` (which is `tsc --noEmit && vite build`). **Note: this does NOT run `npm test` — Vitest is not executed in CI.**
- `security-scan` — Gitleaks, `.env`-not-committed check, nginx header validation.
- `smoke-nginx-routing`, `smoke-strapi-permissions`, `smoke-n8n-e2e` — dry-run smoke on main/release.
- `docker-build` (matrix cms/admin/kiosk) + Trivy scan on main/release.
- `test-harness` — full-stack harness on main/release.
- `ci-summary` — aggregates results; fails the pipeline if any critical job failed.

Separate workflows: `workflow-validate.yml` (path-filtered to `workflows/*.json`: JSON syntax, required fields, naming, hardcoded-IP warning, executeCommand warning), `migration-validate.yml`, `security-scan.yml`, `secret-scan.yml`, `perf-baseline.yml`. A parallel `ralphe-ci.yml` mirrors the main pipeline. GitLab parity exists in `.gitlab-ci.yml`.

---

## What Is Covered vs Not

**Well covered:**
- Workflow JSON structure, inbound security gates, and tenant isolation (integrity gate — static but strong).
- Inbound message contracts and L10N (python schema/case tests, gated).
- DB migrations: applicability, idempotence, schema integrity across PG15/16.
- Frontend lazy-loading and the kiosk menu TTL cache (Vitest, but not run in CI).
- Auth/scope/SSRF behavior end-to-end (harness + smoke, on main/release).

**Gaps to be aware of when planning test work:**
- **Vitest is not executed in CI** — only lint + build run for the frontends; `npm test` must be run locally to get value from `*.test.*`.
- Minimal React component testing (`@testing-library/react` installed but unused); no rendering/interaction tests for views.
- No Strapi controller/service/lifecycle unit tests; CMS logic (`conversation-state` size guard, `control-plane` health) is only covered indirectly via smoke/integration.
- No E2E browser tests (no Playwright/Cypress).
- Many smoke/e2e scripts only run as dry-runs in CI (no live backends) — true coverage requires a deployed environment.

---

## How to Run Locally

```bash
# Static governance gate (fast, no docker needed beyond jq/python)
bash scripts/integrity_gate.sh

# Python contract + L10N tests (with JUnit output)
pip install -r scripts/requirements-ci.txt
bash scripts/ci_test_runner.sh

# Frontend unit tests (run per app — NOT covered by CI)
cd admin-dashboard && npm install && npm test
cd kiosk-app && npm install && npm test

# Full-stack harness (needs docker, curl, jq)
bash scripts/test_harness.sh

# Live smoke (needs a deployed/ephemeral stack)
DOMAIN_NAME=example.com WEBHOOK_SHARED_TOKEN=... bash scripts/smoke.sh

# Load test
k6 run -e API_URL=http://localhost:8080 tests/k6-load-test.js
```

---

*Testing analysis: 2026-06-20*
*Update when test patterns change*
