# Phase 6: Performance Tuning - Research

**Researched:** 2026-03-26
**Domain:** PostgreSQL index migrations, Redis eviction policy, React/Vite code splitting, frontend caching
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PERF-01 | Migration adds `CREATE INDEX idx_orders_status_created ON orders(status, created_at)` if not exists | `orders` table confirmed: has `status text` + `created_at timestamptz`. Migration pattern established in `db/migrations/2026-01-22_p1_db_indexes_retention.sql` using `CREATE INDEX IF NOT EXISTS`. |
| PERF-02 | Migration adds `CREATE INDEX idx_orders_customer_status ON orders(customer_id, status)` if not exists | **CRITICAL: `orders` table has NO `customer_id` column.** It has `user_id text`. The index must use `user_id` or the requirement column name is wrong. Resolution: use `user_id` as the customer column per actual schema. |
| PERF-03 | EXPLAIN ANALYZE on the 3 most common order queries confirms index usage | Existing `db_explain.sh` pattern is the template. New script needed targeting orders queries. |
| PERF-04 | Redis `maxmemory-policy` is set to `allkeys-lru` (prevents OOM kill) | **Already configured.** `infra/redis/entrypoint.sh` line 7: `ARGS="--appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru"`. Task is to verify, document, and add monitoring — not to configure. |
| PERF-05 | Redis memory usage is logged every 15 minutes; alert fires if > 200MB used | Phase 3 establishes n8n scheduled workflows + container-watchdog for alerting. New n8n workflow or cron extension needed. |
| PERF-06 | Redis configuration is documented in `ENV_REFERENCE.md` | `ENV_REFERENCE.md` does not exist yet. Must be created. |
| PERF-07 | Admin dashboard uses React Router `lazy()` for all view components | App.tsx currently uses 18 eager static imports for views. react-router-dom v7.13.1 supports `lazy()`. |
| PERF-08 | Initial JS bundle size reduced by at least 30% vs current monolithic build | No existing build output baseline. Baseline measurement step is required before split. Vite 6 build produces stats in dist/. |
| PERF-09 | Kiosk menu data uses ETag or 5-minute TTL caching; repeated renders do not trigger redundant Strapi API calls | **Already partially done.** `menuService.ts` has `CACHE_TTL_MS = 5 * 60 * 1000` with localStorage. `VerticalVideoFeed.tsx` fetches products directly via `fetch()` without caching — this is the gap. |
</phase_requirements>

---

## Summary

Phase 6 targets three distinct performance domains: database query latency, Redis memory safety,
and frontend bundle load time. Research reveals that two of the nine requirements are partially
or fully satisfied at the code level but not yet verified or documented — which reduces
implementation risk significantly.

The most important discovery is a schema mismatch in PERF-02: the `orders` table has no
`customer_id` column; the equivalent column is `user_id`. Any migration must use `user_id` or
the index will fail at apply time. This must be treated as a locked implementation detail.

The second major finding is that Redis is already configured with `allkeys-lru` and `maxmemory
256mb` in `infra/redis/entrypoint.sh`. PERF-04 requires verification and documentation, not a
new configuration change. The monitoring loop (PERF-05) is the actual new work for Redis.

On the frontend, the admin dashboard has 18+ eagerly imported view components in `App.tsx`
with no dynamic imports. React Router v7's `lazy()` API with Suspense is the straightforward
path. Kiosk `menuService.ts` already implements 5-minute TTL caching; only `VerticalVideoFeed.tsx`
bypasses it with direct `fetch()` calls and needs patching.

**Primary recommendation:** Implement in three parallel streams — DB migration, Redis monitoring,
frontend split — because they have no inter-dependencies within Phase 6.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| PostgreSQL 15-alpine | 15 | Relational DB for orders | Already in production |
| React | ^19.2.0 | Admin dashboard UI | Already in use |
| react-router-dom | ^7.13.1 | Routing + code splitting | Already in use; has `lazy()` API |
| Vite | ^6.0.0 | Build tool | Already in use; supports rollupOptions.output.manualChunks |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Redis 7-alpine | 7 | Bull queue backend | Already in production |
| vitest | ^4.0.18 | Unit tests for frontend | Already in use for admin-dashboard + kiosk |
| n8n (scheduled workflow) | 2.9.4 | Redis memory monitoring | Already used for Phase 3 metrics; same pattern |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| React.lazy() + Suspense | Loadable Components | React.lazy() is sufficient for route-level splitting; no extra dep needed |
| localStorage TTL cache (kiosk) | React Query / SWR | menuService.ts already has TTL logic; no new dependency required for the gap fix |
| n8n scheduled workflow (Redis monitor) | cron + shell script | n8n is already running and Phase 3 already uses this pattern; no new infrastructure |

**Installation:**
No new packages required. All implementation uses existing toolchain.

---

## Architecture Patterns

### Recommended Project Structure (no changes to existing layout)
```
db/migrations/
└── 2026-03-XX_p6_orders_indexes.sql   # new: PERF-01, PERF-02

scripts/
└── verify-orders-indexes.sh            # new: PERF-03 EXPLAIN ANALYZE

infra/redis/
└── entrypoint.sh                       # existing — already correct, no change needed

docs/ (or root)
└── ENV_REFERENCE.md                    # new: PERF-06

admin-dashboard/src/
└── App.tsx                             # modified: replace eager imports with lazy()

kiosk-app/src/components/
└── VerticalVideoFeed.tsx               # modified: use menuService instead of direct fetch()
```

### Pattern 1: Idempotent PostgreSQL Index Migration
**What:** SQL migration file using `CREATE INDEX IF NOT EXISTS ... CONCURRENTLY` to add
composite indexes without locking the table.
**When to use:** Any new index on a live production table.
**Example:**
```sql
-- Source: db/migrations/2026-01-22_p1_db_indexes_retention.sql (existing project pattern)
-- New file: db/migrations/2026-03-XX_p6_orders_indexes.sql

-- PERF-01: composite index for status-time range queries (most common order list query)
CREATE INDEX IF NOT EXISTS idx_orders_status_created
  ON orders (status, created_at DESC);

-- PERF-02: composite index for per-user order history
-- NOTE: orders table has NO customer_id. The column is user_id (text). Using user_id.
CREATE INDEX IF NOT EXISTS idx_orders_customer_status
  ON orders (user_id, status);
```

**Critical note on CONCURRENTLY:** The migration init container uses `set -e` and runs
non-interactively. `CREATE INDEX CONCURRENTLY` cannot run inside a transaction block and
will fail in the current `db_migrate.sh` pattern if it wraps statements in `BEGIN/COMMIT`.
Check `db/init/01_apply_migrations.sh` — if transactions are used, omit `CONCURRENTLY`
and use `IF NOT EXISTS` alone (safe for first apply, idempotent on re-apply).

### Pattern 2: React Router v7 Lazy Loading
**What:** Replace static `import` statements with `React.lazy()` + dynamic `import()`. Wrap
routes in `<Suspense>` with a fallback. This is route-level code splitting.
**When to use:** Any view component that is not shown on initial load.
**Example:**
```typescript
// Source: react-router-dom v7 docs + React.lazy() API
// Before (eager — loads ALL views in initial bundle):
import { StockView } from './components/StockView';
import { KitchenView } from './components/KitchenView';
// ... 18 more imports

// After (lazy — loads each view only when navigated to):
import React, { Suspense, lazy } from 'react';
const StockView = lazy(() => import('./components/StockView').then(m => ({ default: m.StockView })));
const KitchenView = lazy(() => import('./components/KitchenView').then(m => ({ default: m.KitchenView })));

// In JSX: wrap <Routes> with Suspense
<Suspense fallback={<div className="animate-pulse text-zinc-400">Loading...</div>}>
  <Routes>
    <Route path="/stock" element={<StockView />} />
    ...
  </Routes>
</Suspense>
```

**Named export caveat:** Most admin-dashboard components use named exports (e.g., `export function StockView`).
`React.lazy()` requires a default export. Use the `.then(m => ({ default: m.ComponentName }))` wrapper
shown above, OR add `export default` to each component.

### Pattern 3: Kiosk Cache Gap Fix (VerticalVideoFeed)
**What:** `VerticalVideoFeed.tsx` calls `fetch()` directly on Strapi `/api/products` without
going through `menuService`. This bypasses the existing 5-min TTL cache in `menuService.ts`.
**Fix:** Replace the raw `fetch()` call inside `fetchFeed()` with `menuService.getProducts()`.
**Example:**
```typescript
// Before (bypasses cache):
const res = await fetch(`${STRAPI_URL}/api/products?populate=creative_assets&...`);

// After (uses existing 5-min TTL cache):
import { menuService } from '../services/menuService';
const products = await menuService.getProducts(); // cached in localStorage with TTL
```

### Pattern 4: Redis Memory Monitoring (n8n Scheduled Workflow)
**What:** n8n scheduled workflow (every 15 min) runs `redis-cli INFO memory` via Execute
Command node (or HTTP to n8n internal API that delegates to a shell exec node), extracts
`used_memory_human` and `used_memory`, emits structured JSON log, fires ALERT_WEBHOOK_URL
if `used_memory > 200_000_000` bytes (200MB).
**When to use:** Consistent with Phase 3 monitoring architecture (log-based, no Prometheus).
**Implementation path:** Same pattern as W_QUEUE_METRICS from Phase 3 context:
- Node 1: Schedule Trigger (every 15 min)
- Node 2: Execute Command — `redis-cli -h redis INFO memory`
- Node 3: Code node — parse output, extract used_memory bytes
- Node 4: IF node — used_memory > 200MB threshold
- Node 5 (true path): HTTP Request to ALERT_WEBHOOK_URL

**Alternative if Execute Command is restricted:** Use the existing `container-watchdog.sh`
pattern — extend it with a Redis memory check block, deployed as an additional cron rule on VPS.

### Anti-Patterns to Avoid
- **`CREATE INDEX` without `IF NOT EXISTS`:** Will fail on re-apply. Always use `IF NOT EXISTS`.
- **`CREATE INDEX CONCURRENTLY` in migration init container:** Fails in transaction context. Use plain `CREATE INDEX IF NOT EXISTS` for the migration runner.
- **Lazy-loading LoginView or App shell components:** These are always needed; lazy-loading them adds latency without benefit. Only lazy-load route-level views.
- **Setting `maxmemory-policy` via `redis.conf` while also setting it in `entrypoint.sh`:** Config file values are overridden by CLI args. The entrypoint.sh approach is correct; do not add a redis.conf that conflicts.
- **ETag caching for kiosk (browser-side):** The kiosk is a PWA-like SPA making XHR requests, not a browser loading pages. HTTP ETags require `If-None-Match` header handling in the fetch layer. The existing localStorage TTL pattern is simpler and already correct — extend it, don't replace it.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| React code splitting | Custom dynamic import registry | `React.lazy()` + `Suspense` | Built into React 18+; works with react-router-dom v7; tree-shakeable |
| Menu data caching | Custom HTTP cache layer or service worker | Extend existing `menuService.ts` TTL logic | Already implemented and working; fixing the gap (VerticalVideoFeed) is a 5-line change |
| Index existence check | Runtime SQL query before migration | `CREATE INDEX IF NOT EXISTS` | Standard PostgreSQL idempotency pattern; already used in this codebase |
| Redis memory alerting | New Node.js process or sidecar container | n8n scheduled workflow (Phase 3 pattern) | Zero new infrastructure; same execution path as W_QUEUE_METRICS |
| Bundle size measurement | Custom webpack stats | `vite build` outputs `dist/assets/*.js` with sizes; `du -sh dist/` gives total | Vite 6 provides rollup bundle stats natively |

**Key insight:** Every performance problem in this phase has an existing solution at the correct
abstraction layer. The work is wiring existing tools together, not building new infrastructure.

---

## Common Pitfalls

### Pitfall 1: PERF-02 Index Uses Wrong Column Name
**What goes wrong:** `CREATE INDEX idx_orders_customer_status ON orders(customer_id, status)` fails
with `ERROR: column "customer_id" does not exist` because the orders table uses `user_id text`.
**Why it happens:** Requirement PERF-02 was written with a conceptual column name that doesn't
match the actual schema.
**How to avoid:** Confirm column names from `db/bootstrap.sql` (authoritative schema source).
The orders table columns are: `user_id text`, `status text`, `created_at timestamptz`. Use
`user_id` for the customer column in the index.
**Warning signs:** Migration apply exits with non-zero if running in `set -e` context.

### Pitfall 2: React.lazy() With Named Exports
**What goes wrong:** `const StockView = lazy(() => import('./components/StockView'))` throws
`"The default export of a lazy-loaded module must be a React component"` because StockView
uses a named export, not `export default`.
**Why it happens:** `React.lazy()` requires modules to have a default export.
**How to avoid:** Use the `.then()` wrapper: `lazy(() => import('./components/StockView').then(m => ({ default: m.StockView })))` OR
add `export default` to each component file. The `.then()` wrapper avoids modifying 18+ component files.
**Warning signs:** Blank white screen on route navigation, console error about default export.

### Pitfall 3: Baseline Bundle Measurement Order
**What goes wrong:** Measuring bundle size after code splitting and claiming "30% reduction"
without a pre-split baseline number.
**Why it happens:** No existing baseline measurement exists (no CI bundle size check).
**How to avoid:** The first task must measure and record the pre-split bundle size.
Run `cd admin-dashboard && npm run build` before any lazy() changes; record the total JS size
from `dist/assets/`. Then apply changes and measure again. The 30% claim requires both numbers.
**Warning signs:** PERF-08 cannot be verified without this baseline.

### Pitfall 4: Redis entrypoint.sh Already Sets maxmemory-policy
**What goes wrong:** A plan task "configures Redis `maxmemory-policy allkeys-lru`" and creates
a `redis.conf` override, creating a duplicate/conflicting configuration.
**Why it happens:** Not reading the existing `infra/redis/entrypoint.sh` before writing the plan.
**How to avoid:** The policy is already set (line 7: `--maxmemory-policy allkeys-lru`). The task
for PERF-04 is to verify it is in effect via `redis-cli CONFIG GET maxmemory-policy`, then document
it. Do not add a redis.conf — the CLI args in entrypoint.sh take precedence.
**Warning signs:** Two contradictory configurations causing unexpected eviction behavior.

### Pitfall 5: Migration Naming Convention
**What goes wrong:** Migration file is applied out of alphabetical order or skipped because
naming doesn't follow the project convention.
**Why it happens:** The existing migrations use two naming patterns (numeric prefix `006_...` and
date-prefix `2026-01-22_...`). The date-prefix files sort after numeric ones.
**How to avoid:** Use date-prefix naming consistent with Phase 1 migrations:
`2026-03-XX_p6_orders_indexes.sql`. Verify `db/init/01_apply_migrations.sh` applies in sort order.
**Warning signs:** `schema_migrations` table shows file skipped; indexes not present after migrate.

### Pitfall 6: Suspense Fallback During Initial Load
**What goes wrong:** App shows broken layout while lazy components load on first navigation.
**Why it happens:** Suspense fallback renders while the dynamic chunk downloads.
**How to avoid:** Use the existing `SkeletonLoader` component (present in admin-dashboard/src/components/)
as the Suspense fallback for consistency with the loading UX pattern already in the app.

---

## Code Examples

Verified patterns from project source:

### Existing Migration Pattern (from `db/migrations/2026-01-22_p1_db_indexes_retention.sql`)
```sql
-- Source: db/migrations/2026-01-22_p1_db_indexes_retention.sql
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_status
  ON orders (restaurant_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_created
  ON orders (created_at);
```

### New PERF-01 and PERF-02 Indexes
```sql
-- Source: analysis of db/bootstrap.sql orders table schema
-- File: db/migrations/2026-03-XX_p6_orders_indexes.sql

-- PERF-01
CREATE INDEX IF NOT EXISTS idx_orders_status_created
  ON orders (status, created_at DESC);

-- PERF-02 (NOTE: column is user_id, NOT customer_id — confirmed from bootstrap.sql line 253)
CREATE INDEX IF NOT EXISTS idx_orders_customer_status
  ON orders (user_id, status);
```

### EXPLAIN ANALYZE for Order Queries (PERF-03 verification script pattern)
```bash
# Source: scripts/db_explain.sh (existing pattern)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
-- Query 1: Orders by status (kitchen display, admin dashboard)
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, status, created_at, total_cents
FROM orders
WHERE status IN ('NEW', 'ACCEPTED', 'IN_PROGRESS')
ORDER BY created_at DESC
LIMIT 50;

-- Query 2: Orders by user (customer history)
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, status, created_at, total_cents
FROM orders
WHERE user_id = 'test_user_id'
  AND status != 'CANCELLED'
ORDER BY created_at DESC
LIMIT 20;

-- Query 3: Recent orders (dashboard home widget)
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, status, channel, total_cents, created_at
FROM orders
WHERE created_at > now() - interval '24 hours'
ORDER BY created_at DESC
LIMIT 100;
SQL
```

### Redis Memory Check (PERF-04 verification + PERF-05 monitoring seed)
```bash
# Verify current policy is active
docker exec current-redis-1 redis-cli CONFIG GET maxmemory-policy
# Expected: allkeys-lru

# Check current memory usage
docker exec current-redis-1 redis-cli INFO memory | grep -E 'used_memory_human|maxmemory_human|maxmemory_policy'
```

### React Router v7 lazy() Pattern
```typescript
// Source: react-router-dom v7 + React.lazy() API docs
import React, { lazy, Suspense } from 'react';

// Named export pattern (most components in this codebase)
const StockView = lazy(() =>
  import('./components/StockView').then(m => ({ default: m.StockView }))
);

// In JSX (wrap all Routes):
<Suspense fallback={<SkeletonLoader />}>
  <Routes>
    <Route path="/stock" element={<StockView />} />
  </Routes>
</Suspense>
```

### Vite Bundle Size Baseline Measurement
```bash
# Source: Vite 6 docs — build output
cd admin-dashboard
npm run build 2>&1 | grep -E "\.js|kB|gzip"
# OR measure total:
du -sh dist/assets/*.js | sort -h
# Record total before any lazy() changes
```

### Kiosk menuService Cache (existing — confirmed working)
```typescript
// Source: kiosk-app/src/services/menuService.ts lines 88-103
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes — already implemented

function getCachedMenu(cacheKey: string): Product[] | null {
    const cached = localStorage.getItem(cacheKey);
    if (!cached) return null;
    const { data, timestamp } = JSON.parse(cached);
    if (Date.now() - timestamp > CACHE_TTL_MS) {
        localStorage.removeItem(cacheKey);
        return null;
    }
    return data;
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Webpack bundle | Vite 6 + Rollup | Already in use | `manualChunks` in `vite.config.ts` for vendor splitting |
| React Router v6 `lazy()` | React Router v7 `lazy()` (same API) | react-router-dom upgraded to 7.13.1 | No change to pattern; API is identical |
| PostgreSQL CREATE INDEX (locks) | `IF NOT EXISTS` idempotent | Already used in project | No new pattern needed |

**Already current:**
- Redis `allkeys-lru`: already configured (not a state-of-the-art change)
- menuService TTL cache: already implemented (not a state-of-the-art change)

---

## Open Questions

1. **`CREATE INDEX CONCURRENTLY` vs plain `CREATE INDEX` in migration runner**
   - What we know: The DB safety protocol skill states "use safe migration patterns (CREATE INDEX CONCURRENTLY)"; the existing migration examples use plain `CREATE INDEX IF NOT EXISTS`.
   - What's unclear: Whether `db/init/01_apply_migrations.sh` wraps migrations in transactions (CONCURRENTLY fails in a transaction block).
   - Recommendation: Read `db/init/01_apply_migrations.sh` before writing migration. If no transaction wrapping, use CONCURRENTLY. If transaction-wrapped, use plain IF NOT EXISTS.

2. **n8n vs cron for Redis 15-minute monitoring (PERF-05)**
   - What we know: Phase 3 uses n8n for queue metrics (5-min schedule). The container-watchdog.sh runs as cron every 5 minutes. Redis check could go in either.
   - What's unclear: Whether Phase 3's W_QUEUE_METRICS workflow is completed before Phase 6 runs (Phase 6 depends on Phase 3).
   - Recommendation: Use the n8n pattern for PERF-05 (consistent with Phase 3). If Phase 3 is not complete, fall back to extending container-watchdog.sh as a cron addition.

3. **Admin dashboard bundle size 30% target achievability**
   - What we know: 18+ view components are eagerly imported; framer-motion, recharts, and react-markdown are large dependencies that appear in every route currently.
   - What's unclear: Without running the build, cannot confirm whether lazy() alone achieves 30% initial bundle reduction, or if vendor chunking in vite.config is also needed.
   - Recommendation: Measure baseline first. If lazy() alone achieves >30%, no vite.config changes needed. If borderline, add `manualChunks` to move recharts/framer-motion to separate vendor chunks.

---

## Validation Architecture

> nyquist_validation: true in .planning/config.json

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Vitest 4.0.18 |
| Config file | `admin-dashboard/vite.config.ts` (test section present) |
| Quick run command | `cd admin-dashboard && npm test` |
| Full suite command | `cd admin-dashboard && npm test && cd ../kiosk-app && npm test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PERF-01 | `idx_orders_status_created` index created by migration | smoke/shell | `psql $DATABASE_URL -c "\d orders" | grep idx_orders_status_created` | Wave 0 |
| PERF-02 | `idx_orders_customer_status` index created by migration | smoke/shell | `psql $DATABASE_URL -c "\d orders" | grep idx_orders_customer_status` | Wave 0 |
| PERF-03 | EXPLAIN ANALYZE confirms index usage on 3 queries | smoke/shell | `DATABASE_URL=... bash scripts/verify-orders-indexes.sh` | Wave 0 |
| PERF-04 | Redis maxmemory-policy is allkeys-lru | smoke/shell | `docker exec current-redis-1 redis-cli CONFIG GET maxmemory-policy \| grep allkeys-lru` | Wave 0 |
| PERF-05 | Redis memory logged every 15 min; alert fires at >200MB | manual-only | N/A — requires live n8n execution over time | manual-only |
| PERF-06 | ENV_REFERENCE.md documents Redis config | unit (file existence) | `test -f ENV_REFERENCE.md && grep -q maxmemory-policy ENV_REFERENCE.md` | Wave 0 |
| PERF-07 | All view components use lazy() | unit | `cd admin-dashboard && npm test -- --run src/App.lazy.test.tsx` | Wave 0 |
| PERF-08 | Initial bundle >=30% smaller than baseline | smoke/build | `cd admin-dashboard && npm run build && node scripts/check-bundle-size.js` | Wave 0 |
| PERF-09 | Repeated kiosk renders don't trigger redundant Strapi calls | unit | `cd kiosk-app && npm test -- --run src/menuService.cache.test.ts` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd admin-dashboard && npm test` (fast; <5s)
- **Per wave merge:** `cd admin-dashboard && npm test && cd ../kiosk-app && npm test`
- **Phase gate:** Full suite green + DB smoke checks + bundle size delta before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `scripts/verify-orders-indexes.sh` — covers PERF-01, PERF-02, PERF-03
- [ ] `admin-dashboard/src/App.lazy.test.tsx` — asserts lazy() used for all route components (PERF-07)
- [ ] `admin-dashboard/scripts/check-bundle-size.js` — compares current build vs baseline (PERF-08)
- [ ] `kiosk-app/src/menuService.cache.test.ts` — asserts getProducts() returns cached result on 2nd call (PERF-09)

---

## Sources

### Primary (HIGH confidence)
- `db/bootstrap.sql` lines 179-259 — authoritative orders table schema (user_id, no customer_id)
- `db/migrations/2026-01-22_p1_db_indexes_retention.sql` — existing migration pattern
- `infra/redis/entrypoint.sh` — Redis configuration: maxmemory 256mb, allkeys-lru already set
- `admin-dashboard/src/App.tsx` — 18 eager static imports confirmed; react-router-dom v7 Routes present
- `admin-dashboard/package.json` — react-router-dom 7.13.1, React 19, Vite 6, vitest 4
- `kiosk-app/src/services/menuService.ts` — 5-min TTL cache already implemented
- `kiosk-app/src/components/VerticalVideoFeed.tsx` — raw fetch() bypasses menuService cache (confirmed gap)
- `.planning/phases/03-metrics-alerting-and-audit-trail/03-CONTEXT.md` — Phase 3 architecture pattern for Redis monitoring approach
- `scripts/db_explain.sh` — existing EXPLAIN ANALYZE pattern
- `scripts/container-watchdog.sh` — existing alerting pattern (fallback for Redis monitoring)

### Secondary (MEDIUM confidence)
- React Router v7 `lazy()` API — same as React Router v6; no breaking changes to `lazy()` interface
- Vite 6 rollup chunk splitting — `manualChunks` option confirmed stable in Vite 5+/6

### Tertiary (LOW confidence)
- 30% bundle size reduction estimate — based on count of eagerly-loaded components (18+); actual number requires measurement

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools already in use in this project
- Architecture: HIGH — patterns directly verified from existing source files
- Pitfalls: HIGH — PERF-02 schema mismatch confirmed from bootstrap.sql; Redis config confirmed from entrypoint.sh; lazy() named-export issue is a well-known React gotcha
- Validation: MEDIUM — test file paths are proposed (Wave 0 gaps); commands verified syntactically

**Research date:** 2026-03-26
**Valid until:** 2026-04-26 (stable domain; only risk is if schema changes before Phase 6 executes)
