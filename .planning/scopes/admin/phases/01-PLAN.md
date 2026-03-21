---
phase: 01-critical-runtime-fixes
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - project/admin-dashboard/src/main.tsx
  - project/admin-dashboard/src/lib/queryClient.ts
  - project/admin-dashboard/src/components/NotificationCenter.tsx
  - project/admin-dashboard/src/pages/KitchenDisplay.tsx
  - project/admin-dashboard/src/pages/GodMode.tsx
autonomous: true
requirements: [T-01, T-05, T-06, T-07, T-09]

must_haves:
  truths:
    - "KitchenDisplay and KitchenView mount without throwing 'No QueryClient set' runtime error"
    - "Order totals in NotificationCenter show actual DA amounts (1200 DA, not 12 DA)"
    - "KitchenDisplay hides orders with status 'done' or 'cancelled'"
    - "KitchenDisplay shows 'COOKING' status label for orders with status 'preparing'"
    - "GodMode kill switch does not silently fail after a DB restore or re-import"
  artifacts:
    - path: "project/admin-dashboard/src/main.tsx"
      provides: "QueryClientProvider in the React tree"
      contains: "Providers"
    - path: "project/admin-dashboard/src/lib/queryClient.ts"
      provides: "Configured QueryClient with staleTime and retry"
      contains: "staleTime"
    - path: "project/admin-dashboard/src/components/NotificationCenter.tsx"
      provides: "Correct order total display"
      contains: "total_amount"
    - path: "project/admin-dashboard/src/pages/KitchenDisplay.tsx"
      provides: "Lowercase status filter matching Strapi enum"
      contains: "'done'"
    - path: "project/admin-dashboard/src/pages/GodMode.tsx"
      provides: "documentId-based Strapi v5 update"
      contains: "documentId"
  key_links:
    - from: "project/admin-dashboard/src/main.tsx"
      to: "project/admin-dashboard/src/components/Providers.tsx"
      via: "import and wrap App with Providers"
      pattern: "<Providers>"
    - from: "project/admin-dashboard/src/components/NotificationCenter.tsx"
      to: "Strapi orders schema"
      via: "total_amount field (not total_cents)"
      pattern: "total_amount"
    - from: "project/admin-dashboard/src/pages/KitchenDisplay.tsx"
      to: "project/admin-dashboard/src/services/orders.ts OrderStatus type"
      via: "lowercase status enum values"
      pattern: "done.*cancelled"
---

<objective>
Fix five confirmed runtime and data bugs that make the admin dashboard partially or fully broken in production.

Purpose: KitchenView crashes on mount (T-01), notification prices are 100x wrong (T-05), the kitchen display never hides completed orders (T-06), QueryClient has no resilience config (T-07), and the GodMode kill switch uses an unstable numeric ID (T-09). All five bugs are isolated 1-3 line changes in existing files.

Output: Five modified source files. No new dependencies. No API changes. Build passes `npm run build` with no TypeScript errors.
</objective>

<execution_context>
All work is inside `project/admin-dashboard/src/`.
Build command: `cd project/admin-dashboard && npm run build`
Type-check command: `cd project/admin-dashboard && npx tsc --noEmit`
Install (if needed): `cd project/admin-dashboard && npm ci --legacy-peer-deps`
</execution_context>

<context>
<!-- Key interfaces the executor needs. Read from source. -->
<interfaces>

From project/admin-dashboard/src/components/Providers.tsx:
```typescript
import { QueryClientProvider } from '@tanstack/react-query';
import { queryClient } from '../lib/queryClient';

export function Providers({ children }: { children: React.ReactNode }) {
    return (
        <QueryClientProvider client={queryClient}>
            {children}
        </QueryClientProvider>
    );
}
```

From project/admin-dashboard/src/lib/queryClient.ts (current — broken):
```typescript
import { QueryClient } from '@tanstack/react-query';
export const queryClient = new QueryClient();   // no config
```

From project/admin-dashboard/src/services/orders.ts (OrderStatus and field docs):
```typescript
// F-04 FIX: Strapi order schema status enum is LOWERCASE
// ('pending','confirmed','preparing','ready','delivered','cancelled')
export type OrderStatus = 'pending' | 'confirmed' | 'preparing' | 'ready' | 'delivered' | 'cancelled';

interface StrapiOrder {
    // F-03 FIX: Strapi field is 'total_amount' in DA (not 'total_cents' in centimes).
    total_amount: number;
    documentId: string;
    // ...
}
```

From project/admin-dashboard/src/components/NotificationCenter.tsx (current — broken, line 8):
```typescript
interface StrapiOrder { id: number; total_cents: number; createdAt: string; }
// line 75:
message: `#${...} — ${(o.total_cents / 100).toFixed(0)} DA Linked`,
```

From project/admin-dashboard/src/pages/KitchenDisplay.tsx (current — broken, lines 34 and 49):
```typescript
const activeOrders = orders.filter(o => !['DONE', 'CANCELLED'].includes(o.status));
// ...
status: order.status === 'PREPARING' ? 'COOKING' : 'PENDING',
```

From project/admin-dashboard/src/pages/GodMode.tsx (current — broken, lines 42-43, 72):
```typescript
const setting = res.data[0] as unknown as { id: number; key: string; value: string };
setSettingId(setting.id);
// ...
await strapi.put(`/api/platform-settings/${settingId}`, { value: ... });
```

From project/admin-dashboard/src/main.tsx (current — missing Providers):
```typescript
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </ErrorBoundary>
  </StrictMode>,
);
```
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Mount QueryClientProvider and configure QueryClient</name>
  <files>
    project/admin-dashboard/src/main.tsx,
    project/admin-dashboard/src/lib/queryClient.ts,
    project/admin-dashboard/src/setup.test.ts
  </files>
  <behavior>
    - Test 1: QueryClient has staleTime of 5000ms on default queries
    - Test 2: QueryClient has retry of 1 on default queries (not the default 3)
    - Test 3: After fix, importing useOrders in a test environment does not throw "No QueryClient set"
  </behavior>
  <action>
Fix T-01 (QueryClientProvider never mounted) and T-07 (QueryClient unconfigured):

Step 1 — Update `project/admin-dashboard/src/lib/queryClient.ts`:
Replace the bare `new QueryClient()` with a configured instance:
```typescript
import { QueryClient } from '@tanstack/react-query';

export const queryClient = new QueryClient({
    defaultOptions: {
        queries: {
            staleTime: 5000,   // 5s — avoids treating data as stale on every tick
            retry: 1,          // 1 retry on failure (default 3 causes ~4s hung loading states)
            refetchOnWindowFocus: false,
        },
    },
});
```

Step 2 — Update `project/admin-dashboard/src/main.tsx`:
Add the `Providers` import and wrap the tree. `Providers` already exists at `src/components/Providers.tsx` and wraps children in `QueryClientProvider`. The new tree is:
```typescript
import { Providers } from './components/Providers.tsx';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <BrowserRouter>
        <Providers>
          <App />
        </Providers>
      </BrowserRouter>
    </ErrorBoundary>
  </StrictMode>,
);
```

Step 3 — Replace the placeholder in `src/setup.test.ts` with real assertions:
```typescript
import { describe, it, expect } from 'vitest';
import { queryClient } from './lib/queryClient';

describe('QueryClient configuration', () => {
    it('has staleTime of 5000 on default queries', () => {
        const opts = queryClient.getDefaultOptions();
        expect(opts.queries?.staleTime).toBe(5000);
    });
    it('has retry of 1 on default queries', () => {
        const opts = queryClient.getDefaultOptions();
        expect(opts.queries?.retry).toBe(1);
    });
});
```

Do NOT change anything in `src/components/Providers.tsx` — it is already correct.
  </action>
  <verify>
    <automated>cd "project/admin-dashboard" && npx tsc --noEmit && npm test -- --run 2>&1 | tail -20</automated>
  </verify>
  <done>
    - `tsc --noEmit` exits 0
    - `npm test` shows "QueryClient configuration > has staleTime of 5000" PASS
    - `npm test` shows "QueryClient configuration > has retry of 1" PASS
    - `src/main.tsx` contains `&lt;Providers&gt;` wrapping `&lt;App /&gt;`
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Fix NotificationCenter total_cents bug and KitchenDisplay status case bugs</name>
  <files>
    project/admin-dashboard/src/components/NotificationCenter.tsx,
    project/admin-dashboard/src/pages/KitchenDisplay.tsx
  </files>
  <behavior>
    - Test 1: A StrapiOrder with total_amount=1200 produces notification message containing "1200 DA" (not "12 DA")
    - Test 2: processOrdersIntoQueue() excludes an order with status 'done'
    - Test 3: processOrdersIntoQueue() excludes an order with status 'cancelled'
    - Test 4: processOrdersIntoQueue() maps order.status 'preparing' to KitchenItem.status 'COOKING'
    - Test 5: processOrdersIntoQueue() maps order.status 'pending' to KitchenItem.status 'PENDING'
  </behavior>
  <action>
Fix T-05 (wrong price field) in `NotificationCenter.tsx`:

Locate the `StrapiOrder` interface at line 8:
```typescript
interface StrapiOrder { id: number; total_cents: number; createdAt: string; }
```
Change `total_cents: number` to `total_amount: number`.

Locate the message construction at line 75 (approximately):
```typescript
message: `#${String(o.id).padStart(4, '0')} — ${(o.total_cents / 100).toFixed(0)} DA Linked`,
```
Change to:
```typescript
message: `#${String(o.id).padStart(4, '0')} — ${(o.total_amount ?? 0).toLocaleString('fr-DZ')} DA Linked`,
```
No division by 100 — `total_amount` is already in DA per the documented F-03 fix in `orders.ts`.

---

Fix T-06 (uppercase status filter) in `KitchenDisplay.tsx`:

Locate line 34:
```typescript
const activeOrders = orders.filter(o => !['DONE', 'CANCELLED'].includes(o.status));
```
Change to lowercase to match the Strapi enum (documented in `orders.ts` comment line 4):
```typescript
const activeOrders = orders.filter(o => !['done', 'cancelled', 'delivered'].includes(o.status));
```
Note: also include `'delivered'` since that is a terminal status in the Strapi enum alongside `'cancelled'`.

Locate line 49:
```typescript
status: order.status === 'PREPARING' ? 'COOKING' : 'PENDING',
```
Change to lowercase comparison:
```typescript
status: order.status === 'preparing' ? 'COOKING' : 'PENDING',
```

Create a co-located test file `src/pages/KitchenDisplay.test.ts` (not .tsx — tests pure logic, no rendering):
```typescript
import { describe, it, expect } from 'vitest';
import type { Order, OrderStatus } from '../services/orders';

// Extracted pure logic from KitchenDisplay for testability
function processOrdersIntoQueue(orders: Order[]) {
    const activeOrders = orders.filter(o => !['done', 'cancelled', 'delivered'].includes(o.status));
    const queue: Array<{ id: string; status: string }> = [];
    activeOrders.forEach(order => {
        order.items.forEach((_, index) => {
            queue.push({
                id: `${order.id}-${index}`,
                status: order.status === 'preparing' ? 'COOKING' : 'PENDING',
            });
        });
    });
    return queue;
}

function makeOrder(status: OrderStatus): Order {
    return { id: '#0001', documentId: 'doc1', customer: 'Test', items: ['Burger x1'], total: '500 DA', status, time: '5 min', method: 'TAKEOUT', rawCreatedAt: new Date().toISOString() };
}

describe('KitchenDisplay queue logic', () => {
    it('excludes done orders', () => {
        expect(processOrdersIntoQueue([makeOrder('done' as OrderStatus)])).toHaveLength(0);
    });
    it('excludes cancelled orders', () => {
        expect(processOrdersIntoQueue([makeOrder('cancelled')])).toHaveLength(0);
    });
    it('maps preparing to COOKING', () => {
        const q = processOrdersIntoQueue([makeOrder('preparing')]);
        expect(q[0].status).toBe('COOKING');
    });
    it('maps pending to PENDING', () => {
        const q = processOrdersIntoQueue([makeOrder('pending')]);
        expect(q[0].status).toBe('PENDING');
    });
});
```

Also create `src/components/NotificationCenter.test.ts`:
```typescript
import { describe, it, expect } from 'vitest';

// Test the message construction logic in isolation
function buildOrderMessage(total_amount: number, id: number): string {
    return `#${String(id).padStart(4, '0')} — ${(total_amount ?? 0).toLocaleString('fr-DZ')} DA Linked`;
}

describe('NotificationCenter order message', () => {
    it('shows total_amount directly without dividing by 100', () => {
        const msg = buildOrderMessage(1200, 1);
        expect(msg).toContain('1 200');  // fr-DZ locale formats 1200 as "1 200"
        expect(msg).not.toContain('12 ');
    });
});
```
  </action>
  <verify>
    <automated>cd "project/admin-dashboard" && npx tsc --noEmit && npm test -- --run 2>&1 | tail -30</automated>
  </verify>
  <done>
    - `tsc --noEmit` exits 0
    - All 4 KitchenDisplay logic tests pass
    - NotificationCenter order message test passes
    - `NotificationCenter.tsx` contains `total_amount` and no `total_cents`
    - `KitchenDisplay.tsx` contains `'done'` and `'cancelled'` (lowercase) and `=== 'preparing'` (lowercase)
  </done>
</task>

<task type="auto">
  <name>Task 3: Fix GodMode kill switch to use documentId (T-09)</name>
  <files>
    project/admin-dashboard/src/pages/GodMode.tsx
  </files>
  <action>
Fix T-09 (numeric id used instead of stable documentId for Strapi v5 PUT) in `GodMode.tsx`.

Current broken code (lines 42-43):
```typescript
const setting = res.data[0] as unknown as { id: number; key: string; value: string };
setSettingId(setting.id);
```
And the state declaration (line 16):
```typescript
const [settingId, setSettingId] = useState<number | null>(null);
```
And the PUT call (line 72):
```typescript
await strapi.put(`/api/platform-settings/${settingId}`, { value: ... });
```

Perform these changes:

1. Change the state type from `number | null` to `string | null`:
```typescript
const [settingId, setSettingId] = useState<string | null>(null);
```

2. Change the `PlatformSetting` interface and the setting extraction to use `documentId`:
```typescript
interface PlatformSetting {
    id: number;
    documentId: string;
    key: string;
    value: string;
}
```
Then in the `.then()` callback:
```typescript
const setting = res.data[0] as unknown as PlatformSetting;
setSettingId(setting.documentId);   // use documentId (stable string), not id (numeric, unstable)
setOrdersPaused(setting.value === 'false');
```

3. The PUT URL at line 72 already uses `settingId` — no change needed there since the type will now be `string`.

4. Update the null-guard at line 61 — no change needed, it still checks `settingId === null`.

Verify TypeScript is happy: `npx tsc --noEmit` must exit 0.
  </action>
  <verify>
    <automated>cd "project/admin-dashboard" && npx tsc --noEmit 2>&1 && grep -n "documentId" src/pages/GodMode.tsx</automated>
  </verify>
  <done>
    - `tsc --noEmit` exits 0
    - `grep -n "documentId" src/pages/GodMode.tsx` shows at least 2 matches (field access + state type or comment)
    - `GodMode.tsx` contains no `setting.id` (numeric id) in the kill switch path
    - `settingId` state is typed `string | null` not `number | null`
  </done>
</task>

</tasks>

<verification>
After all three tasks:

1. Full TypeScript check: `cd project/admin-dashboard && npx tsc --noEmit` — must exit 0 with no errors.

2. Full test run: `cd project/admin-dashboard && npm test -- --run` — all tests pass. Minimum expected: QueryClient config tests (2), KitchenDisplay logic tests (4), NotificationCenter message test (1).

3. Build check: `cd project/admin-dashboard && npm run build` — must complete with no errors and emit `dist/`.

4. Manual spot checks (grep-based):
   - `grep "Providers" project/admin-dashboard/src/main.tsx` — shows `<Providers>`
   - `grep "total_amount" project/admin-dashboard/src/components/NotificationCenter.tsx` — shows match, no `total_cents`
   - `grep "'done'" project/admin-dashboard/src/pages/KitchenDisplay.tsx` — shows lowercase match
   - `grep "documentId" project/admin-dashboard/src/pages/GodMode.tsx` — shows at least 1 match
</verification>

<success_criteria>
- `npm run build` succeeds, producing `dist/`
- `npm test -- --run` shows 7+ tests passing, 0 failing
- `npx tsc --noEmit` exits 0
- KitchenView and KitchenDisplay can mount in a React tree without "No QueryClient set" error
- Notifications for orders show amounts in DA (e.g. "1200 DA"), not centimes
- Completed orders (status 'done', 'cancelled', 'delivered') are excluded from the KitchenDisplay queue
- GodMode state type is `string | null` and uses `documentId` for PUT
</success_criteria>

<rollback>
All changes are isolated TypeScript edits to existing files. No new dependencies, no migrations, no API contract changes.

If any task introduces a regression:
1. `git diff project/admin-dashboard/src/` to inspect all changes
2. `git checkout -- project/admin-dashboard/src/pages/KitchenDisplay.tsx` to revert an individual file
3. Re-run `npm run build` to confirm clean build

The pre-existing committed `dist/` in git is from the emergency patch session (2026-03-14). It is NOT affected by source changes — a clean rebuild will replace it.
</rollback>

<output>
After completion, create `.planning/scopes/admin/phases/01-SUMMARY.md` with:
- Files modified
- Bugs fixed (T-01, T-05, T-06, T-07, T-09)
- Test results
- Any issues encountered
</output>
