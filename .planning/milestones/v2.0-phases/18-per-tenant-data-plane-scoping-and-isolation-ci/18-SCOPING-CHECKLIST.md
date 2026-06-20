# Phase 18 — Order/Customer Scoping Checklist

**Date:** 2026-06-20
**Requirements:** TEN-04 (order/customer reads+writes scoped by `tenant_id`, non-defaultable on the write path), TEN-05 (automated cross-tenant isolation CI proof).
**Purpose:** The success-criterion-1 deliverable. Enumerates EVERY order/customer read and write path across the n8n workflows and the Strapi content types, annotates each scoped/unscoped BEFORE any change, and records the exact fix 18-02 must apply — so 18-02 is a mechanical execution with zero open design choices.

This is the spec that Plan 18-03's `workflow-structural` CI job validates against once 18-02 lands.

---

## O-1 Resolution: One physical orders table, or two?

> **O-1 RESOLVED: TWO physically separate databases.** The n8n `orders` table (DB `n8n`) carries `tenant_id uuid NOT NULL` and is correct. The Strapi `order`/`customer` content types live in a **separate `strapi` database** and carry **NO `tenant_id`**. The kiosk path (`strapi.post('/api/orders')`) writes the *strapi-DB* `orders` table. **=> A Strapi-side `tenant_id`/`restaurant_id` migration + lifecycle injection IS REQUIRED (owned by 18-02).**

Re-verified evidence (file:line citations):

1. **Strapi connection DB** — `inventory-cms/config/database.ts:30`: postgres `database: env('DATABASE_NAME', 'strapi')`. The Strapi CMS connects to a database named **`strapi`** by default.
2. **Compose env** — `docker-compose.base.yml:251`: Strapi service `DATABASE_NAME=${STRAPI_DATABASE_NAME:-strapi}`; `docker-compose.base.yml:48`: n8n Postgres `POSTGRES_DB: n8n`. => Strapi and n8n are wired to **two different physical databases** (`strapi` vs `n8n`).
3. **Strapi content-type tables (no tenant field):**
   - `inventory-cms/src/api/order/content-types/order/schema.json:3` `"collectionName": "orders"` — attributes (`total_amount`, `status`, `customer_phone`, `items_summary`, `order_type`, `source`, `customer`/`driver` relations, `metadata`, …) include **NO `tenant_id` and NO `restaurant_id`**.
   - `inventory-cms/src/api/customer/content-types/customer/schema.json:3` `"collectionName": "customers"`, `phone` is `{"type":"string","unique":true,"required":true}` (`:14-18`) — **globally unique**, **NO `tenant_id`**.
4. **Kiosk write path** — `kiosk-app/src/context/CartContext.tsx:142`: `await strapi.post('/api/orders', { channel:'kiosk', … order_items })`. The kiosk body carries **no tenant** and lands in the **strapi-DB** `orders` table (Strapi REST), not the n8n `orders` table.
5. **n8n table (correct, scoped)** — `db/bootstrap.sql:179-205`: `orders.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id)` + `restaurant_id uuid NOT NULL`. Already non-defaultable; an omitted tenant errors with a NOT NULL violation. `order_items` real columns are `qty int` and `unit_price_cents int` (`db/bootstrap.sql:272-275`), NOT `quantity`/`price_cents`.

**Conclusion (unambiguous):** Two parallel `orders` tables. The n8n plane needs only query scoping (the column already exists NOT NULL). The Strapi plane needs a real `tenant_id`/`restaurant_id` column add + lifecycle injection + per-tenant phone unique (the actual cross-tenant exposure). This GATES the 18-02 Strapi `tenant_id` migration as **REQUIRED**.

---

## Inventory

Op: READ (SELECT) / WRITE (INSERT/UPDATE/DELETE) / VIA-FN (routes through `create_order()`).
Scoped today: ✅ scoped · ⚠️ transitively/PK scoped (safe but implicit) · ❌ unscoped (must fix).

| # | Workflow / File | Node / Query (current SQL, abbrev — file:line) | Op | Scoped today? | 18-02 Action |
|---|-----------------|------------------------------------------------|----|---------------|--------------|
| 1 | `W12_ADMIN_ORDERS.json` | `Q2 - List Orders (DB)` — `FROM orders o WHERE o.tenant_id = $1` (`:159`) | READ | ✅ `$json.tenantId` | **Confirm only** (reference pattern; 18-03 regression-guards it) |
| 2 | `W4_CORE.json` | `C9 - Create Order (DB)` — `WITH ord AS (SELECT * FROM create_order($1)), upd AS (UPDATE orders SET attributed_campaign=… WHERE id=(SELECT COALESCE(order_id,id) FROM ord LIMIT 1) RETURNING 1) SELECT * FROM ord` (`:395`) | VIA-FN + WRITE | ⚠️ `create_order()` is tenant-safe; the self-ref `UPDATE` is keyed by the just-created `id` (no `tenant_id` filter) | **Defense-in-depth:** add `AND tenant_id = (SELECT tenant_id FROM ord)` to the self-ref UPDATE |
| 3 | `W4_CORE.json` | `C1 - Load State+Cart (DB)` — `conversation_state/carts/customer_preferences WHERE conversation_key=$1 / tenant_id=$2` | READ | ✅ key is PK (tenant-bound); prefs use `tenant_id=$2` | **Confirm only** (already tenant-scoped) |
| 4 | `W4.2_CART_MANAGER.json` | `SELECT * FROM create_order($1)` | VIA-FN | ✅ tenant from `conversation_state` | **Confirm only** |
| 5 | `W4.2_CART_MANAGER.json` | `INSERT INTO conversation_state(…tenant_id…) / carts / customer_preferences(tenant_id,phone,locale)` | WRITE | ✅ sealed `tenant_id` `$2` | **Confirm only** |
| 6 | `W4.1_ROUTER.json` | `INSERT INTO restaurant_users(tenant_id, restaurant_id, …)` (`:52`) | WRITE | ✅ sealed `$1/$2` | **Confirm only** |
| 7 | `W_ORDER_FINALIZER.json` | `Create Order (DB)` — `INSERT INTO orders (customer_phone,"customer_userId",restaurant_id,total_amount,items_summary,status,source,metadata) VALUES($1,$2,$3,$4,$5,'confirmed',$6,$7) RETURNING id` — **OMITS tenant_id** | WRITE | ❌ **BROKEN** (would fail the NOT NULL `tenant_id` constraint today) | **FIX:** add `tenant_id` (and keep `restaurant_id`) to the column list, source `$1=tenantId`/`$2=restaurant_id` from `$node["Webhook - Finalize Order"].json.body.tenantId`/`.restaurantId` (sealed ctx — **NO `\|\| 'default'`**, NO env fallback). Renumber remaining params. |
| 7b | `W_ORDER_FINALIZER.json` | `Batch Insert Items (DB)` — `INSERT INTO order_items (order_id, item_code, quantity, price_cents) VALUES ($1,$2,$3,$4)` — **column drift** | WRITE | ❌ columns don't exist | **FIX:** `quantity`/`price_cents` → real cols `qty`/`unit_price_cents` (verified `db/bootstrap.sql:272-275`). Tenant inherited transitively via `order_id` FK → `orders`. |
| 7c | `W_ORDER_FINALIZER.json` | `E1 - Mark Inventory ERROR` — `UPDATE orders SET status='ERROR_INVENTORY', metadata=$2 WHERE id=$1` (PK serial id of the just-created order) | WRITE | ⚠️ **PK-keyed defense-in-depth** | **LEAVE PK-keyed** (`$1` is the serial `id` returned by `Create Order (DB)` two nodes earlier — it can only ever target the order this finalizer just created; cross-tenant impossible). Add a one-line note that it is intentionally PK-keyed. Optionally add `AND tenant_id = $ctx` for parity if trivial. **Not a leak.** |
| 8 | `W14_ADMIN_WA_SUPPORT_CONSOLE.json` | `E5a - Cancel Order (DB)` — `UPDATE orders SET status='CANCELLED', payment_status='CANCELLED', updated_at=now() WHERE order_id=$1::uuid AND status NOT IN ('DONE','CANCELLED') RETURNING order_id` | WRITE | ❌ no `tenant_id` filter | **FIX:** add `AND tenant_id = $2::uuid`, supply `$2 = $json.tenantId` (the admin's sealed RBAC tenant — an admin must not cancel another tenant's order) |
| 8b | `W14_ADMIN_WA_SUPPORT_CONSOLE.json` | `E1a - Get Orders (DB)` — `SELECT * FROM get_recent_orders($1,$2,$3)` with `$1=$json.restaurantId` | READ (VIA-FN) | ✅ **restaurant-scoped via `$1=restaurant_id`** | **Out of direct-SQL scope (see Note A).** `get_recent_orders()` is prod-only (not in repo); it is assumed restaurant-scoped via its `$1` arg. 18-02 does NOT touch it; 18-02 still scopes the E5a cancel UPDATE (#8). |
| 9 | `W51_VIP_WIN_BACK.json` | `Find Lost VIPs (DB)` — `SELECT customer_phone, COUNT(*) as total_orders, MAX(created_at) FROM orders GROUP BY customer_phone HAVING COUNT(*)>5 AND MAX(created_at)<NOW()-INTERVAL '30 days'` | READ | ❌ cross-tenant aggregate (all tenants) | **FIX:** add `WHERE tenant_id = $1` (per-tenant scope — see Sweep Decisions). Supply `$1` from the resolved tenant context (Fetch Strapi Config / W0_CONFIG_READER). |
| 10 | `W53_DYNAMIC_KITCHEN_LOAD.json` | `Check DB Active Tickets (Load)` — `SELECT COUNT(*) as current_workload FROM orders WHERE status IN ('confirmed','preparing')` | READ | ❌ counts all tenants | **FIX:** `… AND tenant_id = $1` (per-tenant scope — see Sweep Decisions), `$1` from resolved tenant ctx |
| 11 | `W_THE_USUAL.json` | `Predict Favorite` — `SELECT oi.label,count(*) FROM orders o JOIN order_items oi ON o.order_id=oi.order_id WHERE o."customer_userId"=$1 AND EXTRACT(HOUR …) GROUP BY oi.label …` | READ | ❌ filters by user only, not tenant | **FIX:** add `AND o.tenant_id = $2`, supply `$2` from sealed ctx alongside the existing `$1=user_id` |
| 12 | `W_ADMIN_PROACTIVE_AGENT.json` | `Fetch 4H KPIs` — `WITH sales AS (SELECT SUM(total_amount), COUNT(*) FROM orders WHERE created_at>now()-interval '4 hours'), abandoned AS (SELECT COUNT(*) FROM carts WHERE updated_at>now()-interval '4 hours') SELECT …` | READ | ❌ aggregates all tenants (orders AND carts) | **FIX:** `sales` CTE → `… AND tenant_id = $1`. `carts` has NO `tenant_id` column → scope **transitively** via join to `conversation_state` (see Carts Sub-Scoping Decision below). Supply `$1` from resolved tenant ctx. |
| 13 | `W61_REVIEW_CATCHER.json` | scheduled sweep: `SELECT o.order_id,…,o.tenant_id,o.restaurant_id FROM orders o WHERE o.created_at >= NOW()-INTERVAL … AND review_prompted=false` + `UPDATE orders SET review_prompted=true WHERE order_id=$1` | READ + WRITE | ⚠️ selects `o.tenant_id` but doesn't filter; UPDATE is PK-keyed (`order_id`) | **Sweep — per-row tenant-carry** (it already selects `o.tenant_id`): keep the sweep, carry each row's `tenant_id` into downstream sends. UPDATE is order_id-keyed (safe by PK). **Out of 18-02's required-fix set** (defense-in-depth; not a direct leak). |
| 14 | `W60_KITCHEN_CLOUD_PRINT.json` | `SELECT o.order_id,…,o.customer_phone FROM orders o WHERE o.order_id=$1` | READ | ⚠️ PK lookup (`order_id`) | Low risk (PK). Optional defense-in-depth `AND tenant_id=$ctx` to refuse cross-tenant print. **Out of 18-02's required-fix set.** |
| 15 | **Strapi** `order` content type — `order/schema.json` + `order/lifecycles.ts` | kiosk create/update via `W_KIOSK_ORDER` `POST /api/orders` (strapi-DB `orders`) | WRITE | ❌ **no `tenant_id`/`restaurant_id` attribute** | **FIX:** add `tenant_id` + `restaurant_id` required attributes to `order/schema.json`; `beforeCreate` throws if `data.tenant_id` blank (non-defaultable, mirrors existing empty-items throw); strapi-DB migration adds the columns + backfill + NOT NULL |
| 16 | **Strapi** `customer` content type — `customer/schema.json` + (new) `customer/lifecycles.ts` | kiosk/CMS customer rows | READ+WRITE | ❌ **no `tenant_id`; `phone` globally `unique:true`** | **FIX:** add `tenant_id` required attribute; drop schema-level `phone unique` (→ DB composite `(tenant_id, phone)`); CREATE `customer/lifecycles.ts` with `beforeCreate` throw on blank `tenant_id`; migration relaxes the global unique to `(tenant_id, phone)` |
| — | `W_KIOSK_ORDER.json` | `save-order` — `POST /api/orders` (Strapi REST, body has no tenant) (`:292`) | WRITE | ❌ relies on Strapi (#15) | **Covered by #15** (Strapi lifecycle + migration). Kiosk device→tenant resolution is O-3 (deferred; kiosk is effectively single-tenant today). |
| — | `W_PAYMENT_CHARGILY.json` | builds `payment_intents` row with `tenant_id` from `tenant_context.tenant_id` (`:122`) | WRITE | ✅ sealed ctx (`payment_intents.tenant_id NOT NULL`) | **Confirm only** (out of order/customer scope but confirms the pattern) |

---

## Carts Sub-Scoping Decision (W_ADMIN_PROACTIVE `abandoned` CTE) — PINNED

`carts` has **NO `tenant_id` column** (`db/bootstrap.sql:172-177`: PK `conversation_key text REFERENCES conversation_state(conversation_key)`). It is scoped **transitively** through `conversation_state.tenant_id` (`db/bootstrap.sql:160`, `tenant_id uuid NOT NULL`).

**DECISION (pinned so 18-02 has ZERO open design choice):** Scope the `abandoned` CTE's `carts` read **transitively via a join to `conversation_state`**, filtering `conversation_state.tenant_id = $1`:

```sql
abandoned AS (
  SELECT COUNT(*) as abandoned_carts
  FROM carts c
  JOIN conversation_state cs ON cs.conversation_key = c.conversation_key
  WHERE c.updated_at > now() - interval '4 hours'
    AND cs.tenant_id = $1
)
```

Rationale: `carts` cannot carry a direct `tenant_id` (no column, and adding one duplicates the FK-derived scope). The transitive join to `conversation_state` is the canonical pattern the schema intends (carts inherit conversation scope). `$1` is the same resolved-tenant parameter used by the `sales` CTE — a single bind serves both CTEs. **The automated grep verify alone will not catch an unscoped carts read; this decision makes the carts read explicitly tenant-bound.**

---

## Sweep Decisions (O-2)

Per scheduled sweep (run without a request tenant), the chosen strategy — recorded so 18-02 has no open design choice:

- **`W61_REVIEW_CATCHER` = per-row tenant-carry.** The sweep already `SELECT`s `o.tenant_id`; keep the cross-tenant scan and carry each row's `tenant_id` forward into its downstream per-row send so each notification stays tenant-correct. The `UPDATE orders SET review_prompted=true WHERE order_id=$1` is PK-keyed (safe). No schedule-breaking change. *(Not in 18-02's required-fix set — defense-in-depth.)*
- **`W51_VIP_WIN_BACK` = per-tenant scope (`WHERE tenant_id = $1`).** Pure cross-tenant aggregate (`GROUP BY customer_phone` over all orders) is a real marketing leak. Scope to the resolved tenant from `Fetch Strapi Config` (W0_CONFIG_READER); loop-ready if multi-tenant scheduling is later added. *(Required fix — #9.)*
- **`W53_DYNAMIC_KITCHEN_LOAD` = per-tenant scope (`AND tenant_id = $1`).** Kitchen-load count must reflect one tenant's tickets, not all tenants'. *(Required fix — #10.)*
- **`W_ADMIN_PROACTIVE_AGENT` = per-tenant scope (`AND tenant_id = $1` on `sales`; transitive `conversation_state` join on `carts` — see Carts Sub-Scoping Decision).** *(Required fix — #12.)*

Rationale (one line): per-tenant scoping is correct for pure aggregates that drive one tenant's ops/marketing; per-row carry is correct only where the query already selects each row's `tenant_id` and fans out per-row (W61).

---

## Net Work for 18-02

**(a) n8n direct-SQL workflow fixes (add `tenant_id` filter):**
- #8 `W14_ADMIN_WA_SUPPORT_CONSOLE` — cancel UPDATE: `AND tenant_id = $2::uuid`
- #9 `W51_VIP_WIN_BACK` — VIP aggregate: `WHERE tenant_id = $1`
- #10 `W53_DYNAMIC_KITCHEN_LOAD` — load count: `AND tenant_id = $1`
- #11 `W_THE_USUAL` — favorite predict: `AND o.tenant_id = $2`
- #12 `W_ADMIN_PROACTIVE_AGENT` — `sales` CTE `AND tenant_id = $1`; `carts` transitive join (Carts Sub-Scoping Decision)
- #2 `W4_CORE` — self-ref UPDATE `AND tenant_id = (SELECT tenant_id FROM ord)` (defense-in-depth)

**(b) The `W_ORDER_FINALIZER` broken-write fix:**
- #7 `Create Order (DB)` — add `tenant_id` (+ keep `restaurant_id`) from sealed `body.tenantId`/`body.restaurantId`, renumber params, NO default.
- #7b `Batch Insert Items (DB)` — column drift `quantity`/`price_cents` → `qty`/`unit_price_cents`.
- #7c `E1 - Mark Inventory ERROR` — leave PK-keyed (note added); not a leak.

**(c) The Strapi content-type fixes:**
- #15 `order/schema.json` — required `tenant_id` + `restaurant_id`; `order/lifecycles.ts` `beforeCreate` throw on blank `tenant_id`.
- #16 `customer/schema.json` — required `tenant_id`; drop global `phone unique`; CREATE `customer/lifecycles.ts` `beforeCreate` throw on blank `tenant_id`.
- `db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql` — add columns + backfill canonical tenant + NOT NULL + `(tenant_id, phone)` composite unique (idempotent).

**Defense-in-depth / out of required set (documented, not blocking):** #7c (PK-keyed), #13 W61 (per-row carry), #14 W60 (PK lookup).

---

## Notes

**Note A — W14 `get_recent_orders($1,$2,$3)` (out of direct-SQL scope).** The `E1a - Get Orders (DB)` read calls `get_recent_orders($1,$2,$3)` with `$1=$json.restaurantId`. This function is **prod-only — it is NOT defined in `db/bootstrap.sql` or anywhere in the repo**. It is **assumed restaurant-scoped via its `$1=restaurant_id` argument** and is therefore **out of this phase's direct-SQL scope** (we cannot edit a function we don't have). 18-02 still scopes the W14 **cancel** UPDATE (#8), which is the writable order path the admin console exposes. If `get_recent_orders` ever proves unscoped in prod, that is a separate prod-connected follow-up.

---

## 🔴 VPS Deferred

Deferred to a prod-connected session (NOT attempted in this phase):
- Applying `db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql` to the **live strapi-DB** `orders`/`customers` tables (column add + backfill + NOT NULL + `(tenant_id, phone)` composite unique, the `CREATE UNIQUE INDEX CONCURRENTLY` form direct to `postgres:5432`, NOT pgbouncer:6432).
- Rebuilding the CMS so the new `order`/`customer` `tenant_id` attributes + lifecycles take effect.
- Importing the updated scoped workflows (W_ORDER_FINALIZER, W51, W53, W_THE_USUAL, W_ADMIN_PROACTIVE, W14, W4_CORE) on prod n8n.
