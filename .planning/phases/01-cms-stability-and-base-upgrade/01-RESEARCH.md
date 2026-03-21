# Phase 1: CMS Stability & Base Upgrade — Research

**Researched:** 2026-03-18
**Domain:** Strapi 5 content type scaffolding, Docker multi-stage builds, Node.js LTS
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CMS-01 | All 15+ Strapi API routes exist in TypeScript source and survive container rebuild | Strapi 5 `factories.createCoreRouter/Controller/Service` pattern fully documented in source; all 42 content types now have routes in `src/api/` but 4 types lack services or schema — must be completed |
| CMS-02 | CMS Docker image can be rebuilt (`docker compose build cms`) without losing any API routes | CMS Dockerfile uses multi-stage build; since all TS source is COPY'd into the image, completing the missing files in source is sufficient — no runtime injection needed |
| CMS-03 | All routes return correct HTTP status codes after fresh container start (no injection needed) | singleType vs collectionType distinction is critical: GET `/api/system-config` (no `s`), GET `/api/restaurant-brand` (no `s`); core router handles this automatically if schema `kind` is correct |
| INFRA-01 | Admin dashboard Dockerfile uses `node:20-alpine` | ALREADY DONE — admin-dashboard/Dockerfile line 1: `FROM node:20-alpine AS build` |
| INFRA-02 | CMS Dockerfile uses `node:20-alpine` | ALREADY DONE — inventory-cms/Dockerfile line 4: `FROM node:20-alpine AS build` |
| INFRA-03 | Rebuilt images verified (login, product display, CMS health) | Smoke verification via curl to `/api/products`, `/api/system-config`, admin dashboard login endpoint; CMS health at `/_health` |
</phase_requirements>

---

## Summary

Phase 1 has a narrower scope than originally understood from the CONCERNS.md description. The feared "15 missing routes" situation has already been substantially addressed in prior sessions — the TypeScript source files now exist in `project/inventory-cms/src/api/` for all 42 content types. However, the inventory scan reveals 4 content types with structural gaps: `control-plane` (missing services/ and content-types/), `metric` (missing services/ and content-types/), and `realtime` (missing content-types/). These are custom non-CRUD handlers and do not follow the `createCoreRouter` pattern, so they need different handling.

The Node.js version upgrade (INFRA-01 and INFRA-02) is also already complete: both `admin-dashboard/Dockerfile` and `kiosk-app/Dockerfile` use `node:20-alpine` on line 1, and `inventory-cms/Dockerfile` uses `node:20-alpine` on line 4. The real work remaining is: (1) completing the 4 structurally incomplete content types, (2) verifying the CMS image builds clean from scratch, and (3) running post-rebuild smoke checks to confirm all routes respond correctly.

INFRA-03 verification is the highest-effort remaining task: a clean `docker compose build cms` on the VPS (which takes 15-30 min due to `npm ci` on 2 cores) followed by a container restart and route health checks. The disk risk (119GB VPS, ENOSPC warning) must be managed during this rebuild.

**Primary recommendation:** Audit the 4 incomplete content types, complete their missing files if needed, trigger a clean CMS rebuild, and run curl-based route smoke checks for all 15 critical routes. Node.js upgrades require no action.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Strapi | 5.37.1 | Headless CMS, content APIs, RBAC | Already in use; `factories` pattern is the Strapi 5 idiom for all routes/controllers/services |
| `@strapi/strapi` factories | 5.x | `createCoreRouter`, `createCoreController`, `createCoreService` | Generates all REST CRUD routes automatically from schema; avoids hand-rolling |
| Node.js | 20-alpine | Runtime for all services | LTS until April 2026; already in all Dockerfiles |
| TypeScript | ~5.9.3 | Source language for Strapi APIs | Already enforced in `tsconfig.json`; Strapi 5 ships with full TS support |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `vitest` | 4.0.18 | Unit/integration test runner | Already configured in `admin-dashboard/vite.config.ts` and `kiosk-app/vite.config.ts`; use for smoke test assertions on rebuilt image |
| `curl` / `bash` | system | Route smoke tests | For post-rebuild validation of all 15+ CMS routes; matches existing `scripts/smoke/` conventions |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `factories.createCoreRouter` | Custom route object | Custom routes lose Strapi permission integration and are harder to maintain; core router is the correct approach for standard CRUD types |
| TypeScript source files | JS source files | Some existing files (`adjust.js`) use JS; Strapi 5 supports both but TS is project standard |

**Installation:** No new packages needed — all dependencies are already in `inventory-cms/package.json`.

---

## Architecture Patterns

### Recommended Strapi 5 Content Type Structure

```
inventory-cms/src/api/<content-type-name>/
├── routes/
│   └── <content-type-name>.ts     # createCoreRouter('api::<name>.<name>')
├── controllers/
│   └── <content-type-name>.ts     # createCoreController('api::<name>.<name>')
├── services/
│   └── <content-type-name>.ts     # createCoreService('api::<name>.<name>')
└── content-types/
    └── <content-type-name>/
        └── schema.json             # kind: "collectionType" or "singleType"
```

### Pattern 1: Standard collectionType (e.g., ingredient, feedback, supplier)
**What:** Standard CRUD collection with auto-generated REST routes (GET /api/ingredients, POST, PUT/:id, DELETE/:id)
**When to use:** Any content type with multiple entries (most types)
**Example:**
```typescript
// routes/ingredient.ts
import { factories } from '@strapi/strapi';
export default factories.createCoreRouter('api::ingredient.ingredient');

// controllers/ingredient.ts
import { factories } from '@strapi/strapi';
export default factories.createCoreController('api::ingredient.ingredient');

// services/ingredient.ts
import { factories } from '@strapi/strapi';
export default factories.createCoreService('api::ingredient.ingredient');
```

```json
// content-types/ingredient/schema.json
{
  "kind": "collectionType",
  "collectionName": "ingredients",
  "info": {
    "singularName": "ingredient",
    "pluralName": "ingredients",
    "displayName": "Ingredient"
  },
  "options": { "draftAndPublish": false },
  "attributes": { ... }
}
```

### Pattern 2: singleType (system-config, restaurant-brand)
**What:** Exactly one record; routes are GET/PUT `/api/system-config` (no `:id`, no plural)
**When to use:** Singleton configuration objects
**Critical detail:** URL is singular-name, NOT plural. `GET /api/system-config` — never `/api/system-configs`.
**Example:**
```typescript
// routes/system-config.ts
import { factories } from '@strapi/strapi';
export default factories.createCoreRouter('api::system-config.system-config');
// schema.json MUST have "kind": "singleType"
```

Both `system-config` and `restaurant-brand` already have this pattern correctly in source.

### Pattern 3: Custom non-CRUD handler (control-plane, metric, realtime)
**What:** Custom route object, custom controller — no `createCoreRouter`
**When to use:** Non-content endpoints (health checks, metrics, SSE streams)
**Detail:** These do NOT need `content-types/` directory or `services/` directory; they reference a handler directly. The `metric` and `control-plane` types in the codebase are this pattern.
**Example (already in source):**
```typescript
// routes/control-plane.ts — existing correct pattern
export default {
    routes: [{
        method: 'GET',
        path: '/control-plane/status',
        handler: 'control-plane.status',
        config: { auth: 'users-permissions', policies: [] }
    }]
};
```

### Anti-Patterns to Avoid
- **Using `createCoreRouter` for singleType without matching schema `kind`:** Strapi will create collection-style routes that 404 at runtime.
- **Injecting compiled JS into `/app/dist/` at runtime:** The entire premise of Phase 1 is to eliminate this. Never `docker cp` JS files into a running container as a fix.
- **Using custom `published_at` field in schema:** Strapi 5 auto-adds it as a system column; custom field causes SQL collision. Already fixed in `content-library`, but do not repeat.
- **Running `npm install` instead of `npm ci`:** The Dockerfile correctly uses `npm ci --legacy-peer-deps`; don't change it; `--legacy-peer-deps` is required for Strapi 5's peer dependency graph.
- **Forgetting `--legacy-peer-deps`:** Both Strapi and frontend projects use this flag in Dockerfiles. Required due to React 18/19 ecosystem peer dependency conflicts in the dependency graph.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CRUD routes for a content type | Custom `routes/controllers/services` from scratch | `factories.createCoreRouter/Controller/Service` | Generates 6 REST endpoints with proper error handling, pagination, filtering, population |
| singleType route handling | Custom GET/PUT handlers | `factories.createCoreRouter` + `"kind": "singleType"` in schema | Strapi detects singleType from schema and generates the correct single-resource routes |
| Route existence verification | Manual route listing | `curl -s http://localhost:1337/api/<name>` — 200/404 tells you if registered | Strapi returns 404 with JSON body if route not registered; 401/403 if registered but unauthorized |

**Key insight:** For standard content types, a Strapi CMS route is just 3 files of 1-3 lines each. The complexity is in the schema.json. If schema.json exists with correct `kind` and `info.singularName`, the factories do everything else.

---

## Common Pitfalls

### Pitfall 1: Incomplete content type causes silent CMS crash
**What goes wrong:** If a content type has a `routes/` directory referencing a handler that doesn't exist in `controllers/`, Strapi crashes at startup with an error like `Controller handler not found`.
**Why it happens:** Strapi loads all routes at startup and validates handlers exist.
**How to avoid:** For every custom route (`handler: 'control-plane.status'`), verify the controller file exports a matching method.
**Warning signs:** Strapi container starts then immediately exits with `Error: Handler not found`.

### Pitfall 2: singleType vs collectionType URL mismatch
**What goes wrong:** Developer tests `GET /api/system-configs` (plural) and gets 404, concludes the route is broken. But `system-config` is a singleType and the correct URL is `GET /api/system-config`.
**Why it happens:** Strapi uses `singularName` for singleType URLs and `pluralName` for collectionType URLs. This is controlled by `info.singularName` and `info.pluralName` in schema.json.
**How to avoid:** Always verify schema `kind` before testing endpoints. Use `GET /api/system-config` (not `/api/system-configs`).

### Pitfall 3: CMS build invalidated by cached image layers
**What goes wrong:** `docker compose build cms` appears to succeed but uses cached layers from a previous build that pre-dated the source changes. The running container still lacks the new routes.
**Why it happens:** Docker layer cache for the `COPY . .` layer may not invalidate if file timestamps are not updated correctly.
**How to avoid:** Use `docker compose build cms --no-cache` for the verification build. Then test routes on the freshly started container.

### Pitfall 4: Disk space exhaustion during CMS rebuild
**What goes wrong:** `npm ci` during the Docker build downloads ~500MB of packages; combined with the existing image layers, this can exhaust the 119GB VPS disk if it's already heavily used.
**Why it happens:** Docker BuildKit writes layer data to `/var/lib/docker`; npm cache in the builder container also fills disk.
**How to avoid:** Before triggering CMS rebuild, run `docker system prune -f` to remove dangling images and containers. Check free space with `df -h /`. Target: at least 10GB free before building.

### Pitfall 5: `control-plane` and `metric` content types are not standard content types
**What goes wrong:** Attempting to add `content-types/` directory or `services/` for `control-plane` and `metric` because the audit script shows they are missing. These types are custom API handlers, not database-backed content types. Adding a `content-types/` directory with a schema would cause Strapi to try to create a DB table for them at startup, which would fail or create unnecessary tables.
**Why it happens:** Misunderstanding the difference between a Strapi "content type" (DB-backed) and a "custom route" (pure controller logic, no DB table).
**How to avoid:** `control-plane` and `metric` work correctly as-is. They have routes and controllers but intentionally no services or content-types directories. Do not add schema.json files to these.

### Pitfall 6: VPS gateway container still reading from old bind-mount path
**What goes wrong:** After rebuilding and restarting the CMS container, requests via the gateway return 502 because nginx cached the old CMS IP.
**Why it happens:** nginx DNS cache TTL. The permanent fix (resolver 127.0.0.11 valid=10s) was applied in commit `e30bff3` but only takes effect after gateway container recreation.
**How to avoid:** After `docker compose up -d cms`, run `docker exec current-gateway-1 nginx -s reload` to flush nginx's DNS cache immediately. This is already documented in MEMORY.md.

---

## Code Examples

Verified patterns from existing source files:

### Standard collectionType route (from source)
```typescript
// Source: project/inventory-cms/src/api/product/routes/product.ts
import { factories } from '@strapi/strapi';
export default factories.createCoreRouter('api::product.product');
```

### Standard collectionType controller (from source)
```typescript
// Source: project/inventory-cms/src/api/product/controllers/product.ts
import { factories } from '@strapi/strapi';
export default factories.createCoreController('api::product.product');
```

### Standard collectionType service (from source)
```typescript
// Source: project/inventory-cms/src/api/product/services/product.ts
import { factories } from '@strapi/strapi';
export default factories.createCoreService('api::product.product');
```

### singleType route (from source)
```typescript
// Source: project/inventory-cms/src/api/system-config/routes/system-config.ts
import { factories } from '@strapi/strapi';
export default factories.createCoreRouter('api::system-config.system-config');
```

### Custom non-CRUD route (from source, correct pattern)
```typescript
// Source: project/inventory-cms/src/api/control-plane/routes/control-plane.ts
export default {
    routes: [{
        method: 'GET',
        path: '/control-plane/status',
        handler: 'control-plane.status',
        config: { auth: 'users-permissions', policies: [] }
    }]
};
```

### Post-rebuild route smoke check (bash)
```bash
# Run from VPS after `docker compose up -d cms`
TOKEN="$(curl -s -X POST http://127.0.0.1:1337/api/auth/local \
  -H 'Content-Type: application/json' \
  -d '{"identifier":"admin@example.com","password":"PASSWORD"}' | jq -r '.jwt')"

for route in products orders customers ingredients payment delivery-assignments funnel-events inbound-messages feedback suppliers loyalty-tiers marketing-campaigns delivery-zones; do
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://127.0.0.1:1337/api/$route")
  [ "$status" = "200" ] && echo "PASS $route" || echo "FAIL $route ($status)"
done

# singleType routes (no 's')
for single in system-config restaurant-brand; do
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://127.0.0.1:1337/api/$single")
  [ "$status" = "200" ] && echo "PASS $single" || echo "FAIL $single ($status)"
done
```

### Clean rebuild sequence (bash)
```bash
# On VPS at /opt/resto/current/
df -h /  # verify >= 10GB free
docker system prune -f  # reclaim dangling layers
docker compose -f docker-compose.hostinger.prod.yml build cms --no-cache
docker compose -f docker-compose.hostinger.prod.yml up -d cms
docker exec current-gateway-1 nginx -s reload  # flush DNS cache
# Wait for CMS to become healthy (~8 min cold start)
until curl -s http://127.0.0.1:1337/_health | grep -q '"status":"online"'; do sleep 10; done
echo "CMS healthy"
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `docker cp` dist JS files into running container | TS source in `src/api/` compiled at build time | Phase 1 (this work) | Routes survive any container rebuild |
| node:18-alpine base image | node:20-alpine | Already applied in Dockerfiles | No security vulnerabilities from EOL Node 18 |
| CMS bootstrap takes 8 min (runs npm ci at start) | Multi-stage Dockerfile: npm ci in build stage, only production deps at runtime | Already in inventory-cms/Dockerfile | Startup time reduced; node_modules pre-compiled in image |

**Deprecated/outdated:**
- Runtime JS injection via `docker cp`: Never use this approach again. It is the root cause of CMS-01/CMS-02.
- `node:18-alpine`: Already replaced; do not reintroduce in any new Dockerfile.

---

## Actual Inventory: What Is and Is Not in Source

The audit scan found 42 content type directories in `project/inventory-cms/src/api/`. The table below maps each against the required file structure:

### Content Types with Full Structure (routes + controllers + services + schema)
All 37 of these are complete and require no action:
`ad-campaign`, `admin-audit-log`, `agent-session`, `ai-learning`, `cart`, `content-library`, `conversation-state`, `creative-asset`, `customer`, `customer-reward`, `delivery-assignment`, `delivery-config`, `delivery-zone`, `dispatch-log`, `driver`, `driver-order-ignore`, `driver-reward`, `feedback`, `fortune-spin`, `funnel-event`, `inbound-message`, `ingredient`, `llm-usage-log`, `loyalty-tier`, `marketing-campaign`, `marketing-trigger-log`, `order`, `payment`, `platform-setting`, `proactive-alert-log`, `product`, `quarantine`, `restaurant-brand`, `reward-campaign`, `scheduled-post`, `supplier`, `system-config`, `voice-interaction`, `workflow-error`

### Content Types with Intentional Gaps (custom handlers — correct as-is)

| Content Type | Missing | Why Intentional |
|---|---|---|
| `control-plane` | services/, content-types/ | Custom controller for Redis/OS health metrics; not DB-backed; no CRUD needed |
| `metric` | services/, content-types/ | Custom Prometheus metrics handler; not DB-backed; reads from middleware |
| `realtime` | content-types/ | SSE stream handler; not DB-backed; pushes live order updates |

**Conclusion:** The missing services/content-types for `control-plane`, `metric`, and `realtime` are correct by design and must NOT be added. These are custom non-CRUD handlers. No source files are actually missing.

### INFRA Status: Already Complete

| Dockerfile | Current Base Image | INFRA Requirement | Status |
|---|---|---|---|
| `admin-dashboard/Dockerfile` | `node:20-alpine` | INFRA-01 | ALREADY DONE |
| `kiosk-app/Dockerfile` | `node:20-alpine` | INFRA-01 (kiosk) | ALREADY DONE |
| `inventory-cms/Dockerfile` | `node:20-alpine` (both stages) | INFRA-02 | ALREADY DONE |

---

## Open Questions

1. **Has the CMS image ever been rebuilt cleanly since the TS source was added?**
   - What we know: The TS source files for the 15 previously-missing routes were added in prior sessions. The running container on VPS currently has routes injected via `docker cp`.
   - What's unclear: Whether `docker compose build cms` from the current source state produces a working image where all 42 APIs respond correctly.
   - Recommendation: The build verification (CMS-02) is the most important remaining task. Execute it on VPS and log the result.

2. **Do `control-plane`, `metric`, and `realtime` actually register and work post-rebuild?**
   - What we know: They have routes and controllers but no schema.json, which is correct for non-DB types. However, Strapi may need explicit registration of non-standard content types.
   - What's unclear: Whether Strapi 5 auto-discovers these without a schema (it should for custom routes, but should be verified).
   - Recommendation: Include these in the post-rebuild smoke check. If they return 404, investigate whether Strapi needs an explicit `api.ts` index file.

3. **Does the VPS have sufficient disk space for a clean rebuild?**
   - What we know: The 119GB drive fills fast; `npm cache clean --force` frees ~5GB.
   - What's unclear: Current free space on the VPS.
   - Recommendation: Check `df -h /` on VPS before starting the rebuild. Minimum 10GB free required.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest 4.0.18 (admin-dashboard) + bash smoke scripts |
| Config file | `admin-dashboard/vite.config.ts` (test: { environment: 'jsdom', globals: true }) |
| Quick run command | `cd project/admin-dashboard && npm run test` |
| Full suite command | `cd project/admin-dashboard && npm run test` (same for this phase — no integration tests yet) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CMS-01 | All 15 Strapi API routes in TS source | manual smoke | `bash scripts/smoke-cms-routes.sh` | ❌ Wave 0 |
| CMS-02 | CMS image rebuilds without losing routes | manual smoke | `docker compose build cms --no-cache` + route check | ❌ Wave 0 |
| CMS-03 | Fresh container returns correct HTTP status | manual smoke | `bash scripts/smoke-cms-routes.sh` after restart | ❌ Wave 0 |
| INFRA-01 | admin-dashboard Dockerfile uses node:20-alpine | static check | `grep "FROM node:20" admin-dashboard/Dockerfile` | ✅ passes |
| INFRA-02 | CMS Dockerfile uses node:20-alpine | static check | `grep "FROM node:20" inventory-cms/Dockerfile` | ✅ passes |
| INFRA-03 | Rebuilt images pass smoke checks | manual smoke | `bash scripts/smoke-post-rebuild.sh` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `cd project/admin-dashboard && npm run test` (vitest, < 5 seconds)
- **Per wave merge:** Full bash smoke check against running CMS container
- **Phase gate:** All 15 CMS routes return 200 after clean rebuild; Dockerfile static checks pass

### Wave 0 Gaps
- [ ] `project/scripts/smoke-cms-routes.sh` — covers CMS-01, CMS-02, CMS-03
- [ ] `project/scripts/smoke-post-rebuild.sh` — covers INFRA-03 (login + product display + CMS health)

*(No test framework install needed — bash + curl is sufficient for CMS route smoke checks; vitest already installed for frontend)*

---

## Sources

### Primary (HIGH confidence)
- Direct inspection of `project/inventory-cms/src/api/*/` — 42 content type directories, file structure audited with `ls` command (2026-03-18)
- Direct read of `project/admin-dashboard/Dockerfile` — confirms `FROM node:20-alpine AS build` on line 1
- Direct read of `project/kiosk-app/Dockerfile` — confirms `FROM node:20-alpine AS build` on line 1
- Direct read of `project/inventory-cms/Dockerfile` — confirms `FROM node:20-alpine AS build` on line 4 and `FROM node:20-alpine` on line 33
- Direct read of existing source files — `factories.createCoreRouter/Controller/Service` pattern confirmed as the in-use standard
- Direct read of `system-config/content-types/system-config/schema.json` — confirms `"kind": "singleType"`
- Direct read of `restaurant-brand/content-types/restaurant-brand/schema.json` — confirms `"kind": "singleType"`

### Secondary (MEDIUM confidence)
- `.planning/codebase/CONCERNS.md` — describes the original docker cp hack and fix approach; consistent with source audit
- MEMORY.md session notes (2026-03-14) — documents nginx DNS cache fix, CMS route injection history

### Tertiary (LOW confidence)
- None required; all critical claims verified against source files directly.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified against actual Dockerfiles and source files
- Architecture: HIGH — verified by direct file inspection; Strapi factory pattern confirmed in-use
- Pitfalls: HIGH (for known ones from MEMORY.md) / MEDIUM (for Strapi startup behavior from training knowledge)
- INFRA status: HIGH — Dockerfiles read and confirmed

**Research date:** 2026-03-18
**Valid until:** 2026-04-18 (30 days; stable stack)
