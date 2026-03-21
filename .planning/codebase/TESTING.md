# Testing Patterns

**Analysis Date:** 2026-03-16

## Test Framework

**Runner:**
- Vitest 4.0.18
- Config location: `vite.config.ts` (shared with Vite build config)
- Test environment: jsdom (browser-like DOM in Node.js)
- Global test functions enabled: `describe`, `it`, `expect` available without imports

**Assertion Library:**
- Vitest built-in: Uses Chai assertions (compatible with Jest)
- Imported from vitest directly: `import { describe, it, expect } from 'vitest'`

**Run Commands:**
```bash
npm run test              # Run all tests once
npm run lint              # Run ESLint (separate from tests)
npm run build             # TypeScript check + Vite build
```

**Test Projects:**
- `project/admin-dashboard/` — React admin UI with Vitest
- `project/kiosk-app/` — React kiosk UI with Vitest
- `project/inventory-cms/` — Strapi backend (TypeScript, no Vitest configured)
- `project/scripts/` — Python tests (validate contracts, handle l10n)

## Test File Organization

**Location:**
- Co-located with source: Tests live in `src/` directory alongside components
- Naming: `<name>.test.ts` or `<name>.test.tsx`
- Current test files: `setup.test.ts` in both admin-dashboard and kiosk-app

**Naming:**
- Convention: `<module>.test.ts` for unit tests
- No separate `__tests__/` directory used
- Test files included in same source tree as implementation

**Structure:**
```
admin-dashboard/
├── src/
│   ├── components/
│   │   ├── AIChatBubble.tsx
│   │   ├── ErrorBoundary.tsx
│   │   └── ...
│   ├── services/
│   │   ├── authService.ts
│   │   └── strapiClient.ts
│   ├── setup.test.ts         ← Test file
│   └── main.tsx
└── vite.config.ts            ← Test config
```

## Test Structure

**Suite Organization:**
```typescript
import { describe, it, expect } from 'vitest';

describe('Admin Dashboard Basic Setup', () => {
  it('should pass a basic truthiness test', () => {
    expect(true).toBe(true);
  });
});
```

**Patterns:**
- Setup: Import dependencies and functions at top of test file
- Teardown: Use hooks if needed (not currently used in setup.test.ts)
- Assertion: Single assertion per `it()` block preferred for clarity
- Describe blocks: Group related tests logically

**Current Coverage:**
- Minimal: `setup.test.ts` contains only placeholder test (`expect(true).toBe(true)`)
- No component integration tests
- No service mocking or API testing
- No end-to-end tests

## Mocking

**Framework:**
- Vitest has built-in mocking via `vi` object (not explicitly used in current tests)
- Can mock modules with `vi.mock()`, spies with `vi.spyOn()`

**Patterns:**
- Not heavily used in current codebase
- Would follow Vitest docs for module and function mocking
- Service mocking: Mock `strapiClient` for unit tests of components using it

**What to Mock:**
- External API calls (strapi, HTTP requests) — mock via `fetch` interception or service stub
- Custom event dispatch — mock `window.dispatchEvent`
- setTimeout/setInterval — use `vi.useFakeTimers()`
- localStorage/sessionStorage — can be mocked or use jsdom's built-in

**What NOT to Mock:**
- React internals (hooks, components)
- JavaScript built-ins in jsdom (DOM, localStorage already available)
- Business logic inside the component being tested (test real behavior)

## Fixtures and Factories

**Test Data:**
- No centralized fixture files currently
- Test data would be created inline in test files
- Python tests use JSON payloads in `tests/contracts/` directory

**Location:**
- Frontend: Would place in `src/__fixtures__/` or alongside test file
- Backend (Python): `tests/contracts/` for JSON contract payloads

**Example (not in codebase, pattern to follow):**
```typescript
const mockOrder = {
  id: '#0001',
  documentId: 'doc123',
  customer: 'customer1',
  status: 'pending' as OrderStatus,
  total: '1000 DA',
  items: ['burger x2'],
  method: 'DELIVERY' as const,
  time: '5 min',
  rawCreatedAt: new Date().toISOString(),
};
```

## Coverage

**Requirements:**
- No enforced coverage threshold in current setup
- No coverage reporting configured in Vitest config

**View Coverage:**
```bash
# Not currently configured, but would use:
npm run test -- --coverage
# Requires: @vitest/coverage-v8 or @vitest/coverage-c8
```

## Test Types

**Unit Tests:**
- Scope: Individual functions, utilities, hooks
- Approach: Test function outputs with various inputs
- Example: `formatTime()`, `cn()`, `buildQueryString()`
- Status: Minimal — only placeholder test present

**Integration Tests:**
- Scope: Multiple components working together, API integration
- Approach: Test full flow of user actions (login → fetch data → update)
- Status: Not implemented (would require API mocking)
- Example: Test login flow → verify auth token stored → verify redirect

**E2E Tests:**
- Framework: Not implemented (would use Playwright, Cypress, or similar)
- Scope: Full user workflows (browser automation)
- Status: Not configured

**Python Contract Tests:**
- Framework: jsonschema (JSON Schema validation)
- Location: `scripts/validate_contracts.py`
- Purpose: Validate inbound n8n webhook payloads match schema
- Run: `python scripts/validate_contracts.py`

**Python Contract Example:**
```bash
# Validates test payloads against JSON schemas
schemas:
  - schemas/inbound/v1.json
  - schemas/inbound/v2.json

test payloads:
  - tests/contracts/valid_v1.json        (should pass)
  - tests/contracts/invalid_missing_msg_id.json  (should fail)
```

## Common Patterns

**Async Testing:**
```typescript
// Current approach: vitest auto-handles async
it('should fetch data', async () => {
  const result = await strapi.find('orders', { pagination: { limit: 10 } });
  expect(result.data).toBeDefined();
});

// With mocking:
it('should handle network error', async () => {
  vi.spyOn(global, 'fetch').mockRejectedValue(new Error('Network error'));
  const result = await authService.login('user', 'pass');
  expect(result).toBe(false);
});
```

**Error Testing:**
```typescript
// Test error handling
it('should return false on login failure', async () => {
  vi.spyOn(global, 'fetch').mockResolvedValue(
    new Response(null, { status: 401 })
  );
  const result = await authService.login('user', 'wrong');
  expect(result).toBe(false);
});

// Test error parsing
it('should extract Strapi error message', async () => {
  vi.spyOn(global, 'fetch').mockResolvedValue(
    new Response(
      JSON.stringify({ error: { message: 'Email already exists' } }),
      { status: 400 }
    )
  );
  try {
    await strapi.post('/api/users', { email: 'dup@example.com' });
  } catch (e) {
    expect(e.message).toBe('Email already exists');
  }
});
```

**React Hook Testing:**
```typescript
// Using @testing-library/react (installed but not heavily used)
import { renderHook, act } from '@testing-library/react';
import { useOrders } from '@/services/orders';

it('should fetch orders', async () => {
  const { result } = renderHook(() => useOrders());

  // Wait for async query to complete
  await act(async () => {
    await vi.waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });
  });

  expect(result.current.data).toBeDefined();
});
```

## CI/CD Integration

**GitHub Actions:**
- Runs: `npm run test` via Vitest
- Trigger: On PR to main/develop, on push to main/release/*
- Job: `frontend-lint` (separate from test-harness)
- Matrix: Runs for both admin-dashboard and kiosk-app

**CI Workflow Location:** `.github/workflows/ci.yml`

**Test Job Snippet:**
```yaml
frontend-lint:
  name: Frontend Lint (admin-dashboard, kiosk-app)
  runs-on: ubuntu-latest
  needs: [integrity-gate]
  strategy:
    matrix:
      app: [admin-dashboard, kiosk-app]
  steps:
    - uses: actions/checkout@...
    - uses: actions/setup-node@...
    - run: cd project/${{ matrix.app }} && npm ci
    - run: cd project/${{ matrix.app }} && npm run lint
    - run: cd project/${{ matrix.app }} && npm run test
```

## Testing Best Practices

**Naming:**
- Describe blocks should describe the unit being tested: `describe('formatTime', () => { ... })`
- Test cases should describe the scenario and expected outcome: `it('should format 14:30 as "14h30"', () => { ... })`

**Isolation:**
- Mock external dependencies (Strapi API, localStorage)
- Use `beforeEach` and `afterEach` hooks to reset mocks
- Each test should be independent and not rely on test execution order

**Assertions:**
- One logical assertion per test (can have multiple expect calls checking same behavior)
- Positive and negative cases: test success and failure paths
- Clear assertion messages: `expect(result).toBe(true, 'Login should succeed with valid credentials')`

---

*Testing analysis: 2026-03-16*
