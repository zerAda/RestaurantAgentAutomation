---
phase: 18-per-tenant-data-plane-scoping-and-isolation-ci
plan: 02
subsystem: tenant-isolation / data-plane scoping
tags: [tenant_id, scoping, strapi-lifecycle, migration, TEN-04]
requires: [18-SCOPING-CHECKLIST.md, db/bootstrap.sql, db/migrations-strapi style]
provides:
  - "7 tenant-scoped n8n order workflows (W_ORDER_FINALIZER fixed; W51/W53/W_THE_USUAL/W_ADMIN_PROACTIVE/W14/W4_CORE scoped)"
  - "Strapi order/customer content types with required tenant_id (+restaurant_id) + fail-loud beforeCreate"
  - "db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql (idempotent column-add + backfill + composite phone unique)"
affects: [18-03 structural CI job, prod n8n import (VPS), prod strapi-DB apply (VPS)]
tech-stack:
  added: []
  patterns: ["WHERE tenant_id scoped read", "transitive carts scoping via conversation_state", "Strapi beforeCreate non-defaultable throw", "idempotent strapi-DB migration"]
key-files:
  created:
    - inventory-cms/src/api/customer/content-types/customer/lifecycles.ts
    - db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql
  modified:
    - workflows/W_ORDER_FINALIZER.json
    - workflows/W51_VIP_WIN_BACK.json
    - workflows/W53_DYNAMIC_KITCHEN_LOAD.json
    - workflows/W_THE_USUAL.json
    - workflows/W_ADMIN_PROACTIVE_AGENT.json
    - workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json
    - workflows/W4_CORE.json
    - inventory-cms/src/api/order/content-types/order/schema.json
    - inventory-cms/src/api/order/content-types/order/lifecycles.ts
    - inventory-cms/src/api/customer/content-types/customer/schema.json
decisions:
  - "W_ORDER_FINALIZER: minimal-correct fix — add tenant_id+restaurant_id to the raw INSERT column list from sealed body.tenantId/body.restaurantId (NOT routed through create_order(), which needs a conversation_key the webhook finalizer doesn't have). Non-defaultable; an absent tenant hits the NOT NULL violation."
  - "W_ORDER_FINALIZER E1 - Mark Inventory ERROR: left PK-keyed (id = the just-created order's serial id from Create Order (DB)) + added AND tenant_id=$3 parity with an inline note. Not a leak."
  - "Scheduled sweeps (W51/W53/W_ADMIN_PROACTIVE) have no per-request tenant; scoped via WHERE tenant_id=$1 bound to $json.tenant_id from the config-reader output (fail-closed: absent tenant => 0 rows, never a fallback)."
  - "W_ADMIN_PROACTIVE carts read scoped transitively via JOIN conversation_state ON conversation_key, cs.tenant_id=$1 (carts has no tenant_id column)."
  - "Strapi tenant_id/restaurant_id stored as 'string' (Strapi has no native uuid scalar); the strapi-DB column is uuid (migration). Lifecycles throw on blank tenant_id; no fallback."
metrics:
  duration: ~40m
  completed: 2026-06-20
---

# Phase 18 Plan 02: Per-Tenant Data-Plane Scoping Summary

Closed every previously-unscoped order/customer read/write across the n8n direct-SQL paths and the Strapi sub-plane. The n8n plane now carries a `tenant_id` filter on every order query, the broken `W_ORDER_FINALIZER` write is non-defaultable and column-correct, and the Strapi `order`/`customer` content types gain required `tenant_id`/`restaurant_id` + fail-loud lifecycle injection, backed by an idempotent strapi-DB migration with a per-tenant `(tenant_id, phone)` unique.

## Task 1 — n8n direct-SQL scoping (7 workflows, commit aa8319f)

- **W_ORDER_FINALIZER** (3 nodes): `Create Order (DB)` INSERT now lists `tenant_id, restaurant_id` first, sourced from `$node["Webhook - Finalize Order"].json.body.tenantId`/`.restaurantId` (sealed ctx, no `|| 'default'`); params renumbered. `Batch Insert Items (DB)` column drift fixed `quantity`/`price_cents` → `qty`/`unit_price_cents` (verified `db/bootstrap.sql:272-275`). `E1 - Mark Inventory ERROR` left PK-keyed (the `id` is the serial returned by `Create Order (DB)` two nodes earlier — can only target the order this finalizer just created) with an `AND tenant_id=$3` parity filter + inline note.
- **W51_VIP_WIN_BACK** / **W53_DYNAMIC_KITCHEN_LOAD**: added `WHERE`/`AND tenant_id = $1` (per-tenant sweep, `$json.tenant_id`).
- **W_THE_USUAL**: added `AND o.tenant_id = $2`.
- **W_ADMIN_PROACTIVE_AGENT**: `sales` CTE `AND tenant_id = $1`; `carts` scoped transitively via `JOIN conversation_state ON conversation_key` filtering `cs.tenant_id = $1`.
- **W14_ADMIN_WA_SUPPORT_CONSOLE**: cancel UPDATE `AND tenant_id=$2::uuid` (`$json.tenantId`).
- **W4_CORE** C9 self-ref UPDATE: `AND tenant_id = (SELECT tenant_id FROM ord)` (defense-in-depth).

## Task 2 — Strapi content types + fail-loud lifecycles (commit 10e2cb5)

- `order/schema.json`: required `tenant_id` + `restaurant_id` (string, no default).
- `order/lifecycles.ts`: `beforeCreate` throws on blank `tenant_id` (added before the existing empty-items throw; price-recompute logic intact).
- `customer/schema.json`: required `tenant_id`; dropped schema-level global `phone unique`.
- `customer/lifecycles.ts`: CREATED (did not exist) with a `beforeCreate` blank-tenant throw.
- No `|| 'default'`/`DEFAULT_TENANT_ID`/hardcoded UUID on either lifecycle (comment wording adjusted so the CI no-fallback grep is not falsely tripped by the explanatory text).

## Task 3 — strapi-DB migration (commit 5c852c5)

`db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql`: idempotent `ADD COLUMN IF NOT EXISTS` for `orders.tenant_id`/`restaurant_id` + `customers.tenant_id`, backfill to canonical tenant `…0001`/restaurant `…0000`, `SET NOT NULL`, drop global phone unique, `CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_tenant_phone (tenant_id, phone)`, with the `CONCURRENTLY` VPS form commented (postgres:5432, not pgbouncer).

**Ephemeral-PG idempotency proof (run as `postgres` system user, port 54399):**
- Apply #1: columns added, 2 orders + 2 customers backfilled, NOT NULL flipped, global `customers_phone_unique` dropped, composite index created.
- Apply #2: clean no-op (`UPDATE 0`/`UPDATE 0`, "already exists, skipping" notices, no errors).
- Final state: `orders.tenant_id`/`restaurant_id` NOT NULL, `customers.tenant_id` NOT NULL, `uq_customers_tenant_phone` present, global phone unique gone, and **two tenants successfully shared phone `+213600000001`** — proving the composite unique replaced the global one.

## Deviations from Plan

None material. Folded in plan-checker warning #1 (W_ORDER_FINALIZER E1 PK-keyed note + parity). One micro-correction: the lifecycle explanatory comments were reworded to avoid the literal `|| 'default'` / `DEFAULT_TENANT_ID` tokens, which the CI no-fallback grep would otherwise flag inside a comment.

## 🔴 VPS Deferred (NOT attempted)

- Applying `2026-06-20_strapi_order_customer_tenant.sql` to the live strapi DB (column add + backfill + NOT NULL + `CREATE UNIQUE INDEX CONCURRENTLY` direct to postgres:5432).
- Rebuilding the CMS so the new order/customer `tenant_id` attributes + lifecycles take effect.
- Importing the updated scoped workflows into prod n8n.

## Verification

- Task 1 verify: PASS (7 valid JSON; finalizer INSERT has tenant_id + qty/unit_price_cents; W51/W53/W_THE_USUAL/W_ADMIN_PROACTIVE/W14 scoped; no fallback; W4_CORE defense-in-depth).
- Task 2 verify: PASS (both schemas valid; order tenant_id+restaurant_id; customer tenant_id; phone no longer unique; both lifecycles throw; no fallback). `node --experimental-strip-types --check` passes on both lifecycles (no new TS errors).
- Task 3 verify: PASS (structural) + ephemeral-PG apply-twice idempotency proven.

## Self-Check: PASSED
