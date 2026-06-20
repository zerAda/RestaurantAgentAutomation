# Phase 18: Per-Tenant Data-Plane Scoping + Isolation CI — Research

**Researched:** 2026-06-20
**Domain:** Postgres data-plane tenant scoping (n8n DB `orders`/`customer_*` + Strapi `order`/`customer` content types) — query-scoping surgery, non-defaultable write enforcement, cross-tenant isolation CI
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEN-04 | Order and customer **reads and writes** are scoped by `tenant_id`. `tenant_id` is non-defaultable on the write path (NOT NULL, no `\|\| 'default'` fallback). Existing scoped reads (e.g. `W12_ADMIN_ORDERS.json`) are confirmed; unscoped paths are closed. | §1 (data-plane schema inventory — `orders.tenant_id` already `uuid NOT NULL`), §2 (workflow read/write inventory + checklist basis), §3 (non-defaultable write enforcement: the canonical write path is `create_order()` which derives tenant from `conversation_state`; the leak is `W_ORDER_FINALIZER` + Strapi `order`/`customer`) |
| TEN-05 | An automated CI test proves cross-tenant isolation — a request resolved to tenant A cannot read or write tenant B's orders/customers (seeds two tenants, asserts separation in both directions). | §4 (two-tenant seed + both-direction DO-block assertions mirroring `phase-17-assertions.yml`), §5 (Validation Architecture — local ephemeral Postgres as `postgres` system user) |
</phase_requirements>

---

## Summary

**The single most important finding: the n8n data plane is already tenant-scoped at the schema level, and the canonical write path is already correct.** `db/bootstrap.sql:179-182` declares `orders.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id)` and `restaurant_id uuid NOT NULL` — there is no `DEFAULT` and no `|| 'default'` possible at the column level; an omitted `tenant_id` already errors loudly with a NOT NULL violation. `conversation_state.tenant_id` (`:160`), `outbound_messages.tenant_id` (`:284`), `payment_intents.tenant_id` (`:614`), and `customer_payment_profiles.tenant_id` (`:657`) are all `uuid NOT NULL`. The dominant order-creation path — `public.create_order(p_conversation_key)` (`db/bootstrap.sql:1242-1364`) — derives `v_tenant`/`v_restaurant` from `conversation_state` via the `conversation_key` (the sealed, trusted context from Phase 17), then stamps them into `INSERT INTO public.orders (tenant_id, restaurant_id, ...)`. `W4_CORE`, `W4.2_CART_MANAGER`, and `W4.1_ROUTER` all write orders only through `create_order()`, so the highest-volume path is already non-defaultable and correct. The reference read `W12_ADMIN_ORDERS.json` "Q2 - List Orders (DB)" (`:159`) is confirmed scoped: `FROM orders o WHERE o.tenant_id = $1` with `$json.tenantId`.

**Phase 18 is therefore NOT a column-add/backfill migration on the n8n `orders`/`customer_payment_profiles` tables — those columns already exist as `NOT NULL`.** It is (a) closing a small set of direct-SQL workflow paths that read/write `orders` without `WHERE tenant_id`, (b) fixing one genuinely broken write path (`W_ORDER_FINALIZER`'s `INSERT INTO orders` omits `tenant_id` entirely and would fail the NOT NULL constraint today — it is also schema-drifted), and (c) closing the **Strapi sub-plane**, which is the real exposure: the Strapi `order` content type (`inventory-cms/src/api/order/content-types/order/schema.json`) and `customer` content type (`.../customer/schema.json`) have **no `tenant_id`/`restaurant_id` attribute at all**, and `customer.phone` is `unique: true` globally — so the kiosk path (`W_KIOSK_ORDER`, which writes via `POST /api/orders` REST) carries no tenant, and two tenants cannot share a customer phone. That Strapi gap is where cross-tenant leakage actually lives.

**Primary recommendation:** Split into 3 plans. (1) Produce the scoping-checklist artifact enumerating every order/customer read+write path with its current scoped/unscoped status (basis drafted in §2). (2) Close the unscoped n8n direct-SQL paths by adding `WHERE tenant_id = $ctx` / a tenant param, fix the `W_ORDER_FINALIZER` INSERT to route through `create_order()` (or stamp `tenant_id` from the sealed context), and add a `tenant_id`/`restaurant_id` field to the Strapi `order` + `customer` content types with a tenant-injection lifecycle + relax the global-unique `phone` to a per-tenant composite. (3) Add the two-tenant isolation CI test (`db/ci-assertions/18-cross-tenant-isolation.sql` + `db/ci-fixtures/18-two-tenant-seed.sql` + `.github/workflows/phase-18-assertions.yml`) proving both-direction separation. Mark prod migration apply + workflow/CMS import as 🔴 VPS deferred.

---

## 1. Data-Plane Schema Inventory (the keystone finding)

All line numbers are `db/bootstrap.sql` unless noted. **None of the order/customer tables need a `tenant_id` column added — they already have it, NOT NULL.**

| Table | tenant_id column | NOT NULL? | Default / fallback? | FK to tenants? | Notes |
|-------|------------------|-----------|---------------------|----------------|-------|
| `orders` (`:179`) | `tenant_id uuid` (`:181`) | **YES** | none | **YES** `REFERENCES tenants(tenant_id) ON DELETE CASCADE` | Also `restaurant_id uuid NOT NULL` (`:182`). Already non-defaultable. `id serial UNIQUE` (`:189`) is the Strapi integer handle. |
| `conversation_state` (`:158`) | `tenant_id uuid` (`:160`) | **YES** | none | **YES** | PK is `conversation_key`; tenant is sealed in. This is the trusted source `create_order()` reads from. |
| `carts` (`:172`) | **NONE** | — | — | — | Scoped **transitively** via `conversation_key` PK → `conversation_state` FK (`:173`). No direct tenant column needed; it inherits scope from the conversation. |
| `order_items` (`:268`) | **NONE** | — | — | — | Scoped **transitively** via `order_id` FK → `orders` (`:270`). Inherits scope. |
| `customer_payment_profiles` (`:654`) | `tenant_id uuid` (`:657`) | **YES** | none | **NO FK** | ⚠️ `user_id text NOT NULL UNIQUE` (`:656`) — UNIQUE on `user_id` **alone**, not `(tenant_id, user_id)`. Cross-tenant collision risk: the same `user_id` cannot exist for two tenants. |
| `customer_preferences` (`:701`) | `tenant_id **text**` (`:702`) | **YES** | none | **NO FK** | ⚠️ VARCHAR plane (text, not uuid). PK `(tenant_id, phone)`. This is the `'default'`-style plane the keystone warns about — reconciliation concern, but already composite-scoped. |
| `payment_intents` (`:611`) | `tenant_id uuid` (`:614`) | **YES** | none | **NO FK** | Has `restaurant_id uuid NOT NULL` too. |
| `outbound_messages` (`:281`) | `tenant_id uuid` (`:284`) | **YES** | none | **YES** | Already scoped; out of TEN-04's order/customer scope but confirms the pattern. |
| `orders_audit` (`:917`) | **NONE** | — | — | — | Trigger-written audit; keyed by `order_id`. No tenant column. |

### Strapi sub-plane (the actual exposure)

The Strapi CMS manages content types that map to the **same physical tables**:
- `inventory-cms/src/api/order/content-types/order/schema.json` → `"collectionName": "orders"` — attributes list has **no `tenant_id` and no `restaurant_id`** (verified: `total_amount`, `status`, `customer_phone`, `items_summary`, `order_type`, `driver` relation, `customer` relation, etc.). Writes via `POST /api/orders`.
- `inventory-cms/src/api/customer/content-types/customer/schema.json` → `"collectionName": "customers"` — **no `tenant_id`/`restaurant_id`**, and `phone` is `unique: true` (`:14-18`) **globally**. There is no n8n-DB `customers` table in `bootstrap.sql`; this Strapi `customers` table is the customer entity for the kiosk/CMS plane.

**Implication:** A column-add migration IS needed — but for the **Strapi `orders`/`customers` tables** (add `tenant_id`/`restaurant_id`), not the n8n-native ones. The Strapi-managed `orders` table and the n8n `orders` table share `collectionName: "orders"` (same table). Reconcile carefully: if they are literally one table, the n8n `tenant_id NOT NULL` column already exists and the kiosk REST write currently succeeds only because Strapi supplies… nothing — meaning **kiosk order creation through Strapi REST would violate the NOT NULL `tenant_id` unless Strapi sets it**. This contradiction (kiosk appears to work in prod) must be resolved in planning: either (a) the two `orders` are physically distinct (Strapi on the strapi DB, n8n on the n8n DB) — most likely given the two-DB architecture — or (b) the kiosk path has a hidden default. **Open question O-1 below.**

**Verdict on migration need:** No new migration on the **n8n** order/customer tables. **A migration IS likely needed to add `tenant_id`/`restaurant_id` to the Strapi `order`/`customer` content types** and relax `customers.phone unique → (tenant_id, phone) unique`, plus optionally tighten `customer_payment_profiles` UNIQUE to `(tenant_id, user_id)`. All such DDL is 🔴 VPS-apply-deferred.

---

## 2. Workflow / Lifecycle Read+Write Inventory (basis for the Success-Criterion-1 checklist artifact)

Enumerated by grepping `workflows/` for `FROM orders` / `INTO orders` / `UPDATE orders` / `create_order` / `customer_*` and reading each node. Classification: **READ** (SELECT), **WRITE** (INSERT/UPDATE/DELETE), **VIA-FN** (routes through `create_order()` which is tenant-safe). Status: ✅ scoped, ⚠️ transitively scoped (safe but implicit), ❌ unscoped (must fix).

| # | Workflow / file | Node / query (abbrev) | Op | tenant_id scoped today? | Action for Phase 18 |
|---|-----------------|------------------------|----|-----------------------|---------------------|
| 1 | `W12_ADMIN_ORDERS.json` `:159` | `Q2 - List Orders (DB)` — `FROM orders o WHERE o.tenant_id = $1` | READ | ✅ `$json.tenantId` | **Confirm only** (reference pattern) |
| 2 | `W4_CORE.json` `:395` | `WITH ord AS (SELECT * FROM create_order($1)), upd AS (UPDATE orders SET attributed_campaign=… WHERE id=(SELECT … FROM ord))` | VIA-FN + WRITE | ⚠️ create_order safe; the `UPDATE` self-refs the just-created `id` (no `WHERE tenant_id`) | Add `AND tenant_id = (SELECT tenant_id FROM ord)` to the UPDATE for defense-in-depth |
| 3 | `W4_CORE.json` `:120` | `SELECT state_json, cart_json FROM conversation_state … WHERE conversation_key=$1` | READ | ⚠️ key encodes tenant (sealed) | Confirm; key is PK, implicitly tenant-bound |
| 4 | `W4.2_CART_MANAGER.json` `:221` | `SELECT * FROM create_order($1)` | VIA-FN | ✅ tenant from conversation_state | Confirm |
| 5 | `W4.2_CART_MANAGER.json` `:24,:170` | `INSERT INTO conversation_state(... tenant_id ...) / INSERT INTO carts / INSERT INTO customer_preferences(tenant_id,phone,locale)` | WRITE | ✅ tenant `$2` from sealed ctx | Confirm |
| 6 | `W4.1_ROUTER.json` `:52` | `INSERT INTO restaurant_users(tenant_id, restaurant_id, ...)` | WRITE | ✅ `$1/$2` sealed | Confirm (customer-profile write) |
| 7 | `W_ORDER_FINALIZER.json` `:38` | `INSERT INTO orders (customer_phone,"customer_userId",restaurant_id,total_amount,items_summary,status,source,metadata) VALUES(...)` — **omits tenant_id** | WRITE | ❌ **BROKEN** — NOT NULL `tenant_id` not supplied → fails today; also schema-drifted | **FIX**: route through `create_order()` OR add `tenant_id` from sealed context (`body.tenantId`); also fix `order_items(order_id,item_code,quantity,price_cents)` → real cols `qty`/`unit_price_cents` (`:67`) |
| 8 | `W14_ADMIN_WA_SUPPORT_CONSOLE.json` (jq line in grep) | `UPDATE orders SET status='CANCELLED',… WHERE order_id=$1::uuid AND status NOT IN(...)` | WRITE | ❌ no `tenant_id` filter | **FIX**: add `AND tenant_id = $ctx` (admin cancel must not cross tenants) |
| 9 | `W61_REVIEW_CATCHER.json` | `SELECT o.order_id,…,o.tenant_id,o.restaurant_id FROM orders o WHERE o.created_at >= NOW()-INTERVAL '75 min' AND review_prompted=false` + `UPDATE orders SET review_prompted=true WHERE order_id=$1` | READ + WRITE | ❌ cross-tenant scan (selects tenant_id but doesn't filter); UPDATE keyed by order_id only | **FIX read**: this is a scheduled cross-tenant sweep — acceptable IF it carries tenant forward per-row into downstream sends (it does select `tenant_id`); **document as scheduled-sweep exception** OR add per-tenant loop. UPDATE is order_id-keyed (safe by PK) |
| 10 | `W51_VIP_WIN_BACK.json` | `SELECT customer_phone, COUNT(*), MAX(created_at) FROM orders GROUP BY customer_phone HAVING …` | READ | ❌ aggregates across ALL tenants | **FIX**: add `WHERE tenant_id = $ctx` (or per-tenant loop) — this is a true cross-tenant leak in a marketing sweep |
| 11 | `W53_DYNAMIC_KITCHEN_LOAD.json` | `SELECT COUNT(*) FROM orders WHERE status IN('confirmed','preparing')` | READ | ❌ counts all tenants' orders | **FIX**: add `AND tenant_id = $ctx` (or per-restaurant) |
| 12 | `W60_KITCHEN_CLOUD_PRINT.json` | `SELECT o.order_id,…,o.customer_phone,… FROM orders o WHERE o.order_id=$1` | READ | ❌ keyed by order_id only (PK) | Low risk (PK lookup) but **add `AND tenant_id=$ctx`** to refuse cross-tenant print |
| 13 | `W_ADMIN_PROACTIVE_AGENT.json` | `… FROM orders WHERE created_at > now()-interval '4 hours' … FROM carts WHERE updated_at > …` | READ | ❌ aggregates all tenants | **FIX**: add `tenant_id = $ctx` |
| 14 | `W_THE_USUAL.json` | `SELECT oi.label,count(*) FROM orders o JOIN order_items oi … WHERE o."customer_userId"=$1 …` | READ | ❌ filters by user only, not tenant | **FIX**: add `AND o.tenant_id = $ctx` |
| 15 | **Strapi** `order` content type (`order/lifecycles.ts`, `order/controllers/order.ts`, REST `POST/PUT /api/orders`) | kiosk create/update via `W_KIOSK_ORDER.json` `save-order` node (REST) | WRITE | ❌ **no tenant_id field** | **FIX**: add `tenant_id`/`restaurant_id` to `order/schema.json`; inject in `beforeCreate` lifecycle from `ctx.state`; scope `find`/`findOne` via a controller override or document-service middleware |
| 16 | **Strapi** `customer` content type (`customer/schema.json`) | kiosk/CMS customer rows | READ+WRITE | ❌ **no tenant_id; `phone` globally unique** | **FIX**: add `tenant_id`; change `phone unique` → composite `(tenant_id, phone)` unique; inject tenant in lifecycle |
| — | `W_KIOSK_ORDER.json` `save-order` (`:292`) | `POST /api/orders` (Strapi REST) — body has no tenant | WRITE | ❌ relies on Strapi (#15) | Covered by #15 + ensure kiosk passes resolved `tenant_id` (device→tenant via `channel_identities` kiosk row, Phase 17) |
| — | `W10_CUSTOMER_DELIVERY_QUOTE.json` | `SELECT * FROM public.delivery_quote(...)` — no orders/customers touched | n/a | n/a | No order/customer read/write; out of scope (delivery zones only) |
| — | `W_PAYMENT_CHARGILY.json` `:122` | builds `payment_intents` row with `tenant_id` from `tenant_context.tenant_id` | WRITE | ✅ sealed ctx | Confirm (`payment_intents.tenant_id NOT NULL`) |
| — | `W_DRIVER_*` | operate on `delivery_assignments`/`drivers`, not `orders`/`customers` SQL | n/a | n/a | Out of scope (driver/delivery plane is a separate concern) |

**Proposed checklist-artifact path:** `.planning/phases/18-per-tenant-data-plane-scoping-and-isolation-ci/18-SCOPING-CHECKLIST.md` (phase-local, mirrors the `docs/adr/0002-tenant-id-fallback-inventory.md` annotation style). A draft is included alongside this research as the planner's success-criterion-1 deliverable seed. (`docs/tenant-scoping-inventory.md` is an acceptable alternative if a repo-permanent location is preferred over a phase-local one.)

**Net unscoped paths to close (the real Phase 18 work):** #7 (W_ORDER_FINALIZER — broken write), #8 (W14 cancel), #10 (W51 marketing aggregate — true leak), #11 (W53 kitchen count), #13 (W_ADMIN_PROACTIVE), #14 (W_THE_USUAL), plus the two Strapi content types (#15, #16). #2/#9/#12 are defense-in-depth hardening. Everything routing through `create_order()` is already correct.

---

## 3. Non-Defaultable Write Enforcement Mechanism

**The column-level guarantee already exists** — `orders.tenant_id uuid NOT NULL` with no `DEFAULT` (`:181`). An omitted tenant on any raw `INSERT INTO orders` errors with `null value in column "tenant_id" violates not-null constraint`. This is exactly the "errors loudly" posture TEN-04 mandates. No `CHECK`/trigger is strictly required for the n8n plane.

**Recommended minimal-robust approach (in priority order):**

1. **Keep `create_order()` as the single canonical write path.** It derives `v_tenant`/`v_restaurant` from `conversation_state` (`:1269-1283`, `SELECT … FOR UPDATE`) — the sealed Phase-17 context — and stamps them (`:1356-1358`). No default, no `||`. `W4_CORE`/`W4.2_CART_MANAGER`/`W4.1_ROUTER` already use it. **Mandate that every order-creating workflow call `create_order()` rather than raw `INSERT INTO orders`.**

2. **Fix `W_ORDER_FINALIZER`'s raw INSERT (#7).** Two options: (a) **preferred** — replace the raw `INSERT INTO orders (...)` with a call to `create_order()` (or a sibling function that accepts an explicit `(tenant_id, restaurant_id)` for the webhook-finalizer flow, since it may not have a `conversation_key`); (b) minimally — add `tenant_id, restaurant_id` to the column list and source them from `$node["Webhook - Finalize Order"].json.body.tenantId` (the finalizer already reads `body.tenantId` for its W0_MODULE_GUARD call at `:200`). Either way, **no `|| 'default'` and no env fallback.** Also fix the `order_items` column drift (`quantity`/`price_cents` → `qty`/`unit_price_cents`).

3. **Strapi plane — `tenant_id` non-defaultable via schema + lifecycle (#15, #16).** Add `tenant_id` (and `restaurant_id`) as `required: true` attributes to `order/schema.json` and `customer/schema.json`. Inject the resolved tenant in `beforeCreate(event)` from `event.params.data.tenant_id` (validated present) — throw if absent (mirrors the existing `order/lifecycles.ts:beforeCreate` which already `throw new Error(...)` on empty items). Do **not** default it. This makes a kiosk REST create without a tenant fail loudly, parity with the n8n NOT NULL.

4. **Optional DB hardening (defense-in-depth, document the decision):** tighten `customer_payment_profiles` UNIQUE from `(user_id)` to `(tenant_id, user_id)` and Strapi `customers.phone` from global-unique to `(tenant_id, phone)`. These prevent cross-tenant row hijack via shared identifiers. 🔴 VPS-apply-deferred.

**Do NOT add Postgres RLS** — the milestone `## Out of Scope` explicitly rejects it (pgBouncer transaction-pool incompatibility with session GUCs). App-layer `WHERE tenant_id` + NOT NULL + CI test is the chosen control (per `.planning/research/SUMMARY.md` Gaps reconciliation).

---

## 4. Cross-Tenant Isolation CI Test Design (TEN-05)

Mirror `phase-17-assertions.yml` structure exactly: an ephemeral `postgres:15-alpine` service, seed FK parents, apply schema, run DO-block assertions with `RAISE EXCEPTION` under `psql -v ON_ERROR_STOP=1`. **Two tenants, both-direction assertions.**

### Files (proposed paths, consistent with Phase 15/16/17 naming)

| Path | Purpose |
|------|---------|
| `db/ci-fixtures/18-two-tenant-seed.sql` | Seeds tenant A (`…0001`) + tenant B (a second UUID, e.g. `00000000-0000-0000-0000-0000000000B2`), one restaurant each, and one order + one customer-profile row per tenant. |
| `db/ci-assertions/18-cross-tenant-isolation.sql` | DO-block assertions proving A cannot read/write B and B cannot read/write A. |
| `.github/workflows/phase-18-assertions.yml` | CI job: ephemeral PG → bootstrap order/conversation/customer DDL → apply seed → run assertions; plus a `workflow-structural` job (jq/grep) asserting `WHERE tenant_id` present and no fallback. |

### Two-tenant seed sketch (`db/ci-fixtures/18-two-tenant-seed.sql`)

```sql
-- Tenant A = canonical CI tenant; Tenant B = a second isolated tenant.
INSERT INTO tenants(tenant_id, name) VALUES
  ('00000000-0000-0000-0000-000000000001','Tenant A'),
  ('00000000-0000-0000-0000-0000000000b2','Tenant B') ON CONFLICT DO NOTHING;
INSERT INTO restaurants(restaurant_id, tenant_id, name) VALUES
  ('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000001','Rest A'),
  ('00000000-0000-0000-0000-0000000000bb','00000000-0000-0000-0000-0000000000b2','Rest B') ON CONFLICT DO NOTHING;
INSERT INTO orders(order_id, tenant_id, restaurant_id, channel, "customer_userId", total_amount, status)
VALUES
  ('aaaaaaaa-0000-0000-0000-00000000000a','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','whatsapp','userA',100,'confirmed'),
  ('bbbbbbbb-0000-0000-0000-00000000000b','00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000bb','whatsapp','userB',200,'confirmed')
ON CONFLICT (order_id) DO NOTHING;
```

### Both-direction assertions sketch (`db/ci-assertions/18-cross-tenant-isolation.sql`)

```sql
-- Assertion 1: Tenant A's scoped read CANNOT see Tenant B's order (A→B blocked)
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM orders
  WHERE tenant_id = '00000000-0000-0000-0000-000000000001'   -- A's ctx
    AND order_id  = 'bbbbbbbb-0000-0000-0000-00000000000b';  -- B's order
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: tenant A read tenant B order (% rows)', v_count; END IF;
  RAISE NOTICE 'PASS: tenant A cannot read tenant B order';
END $$;

-- Assertion 2: Tenant B's scoped read CANNOT see Tenant A's order (B→A blocked)
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM orders
  WHERE tenant_id = '00000000-0000-0000-0000-0000000000b2'
    AND order_id  = 'aaaaaaaa-0000-0000-0000-00000000000a';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: tenant B read tenant A order (% rows)', v_count; END IF;
  RAISE NOTICE 'PASS: tenant B cannot read tenant A order';
END $$;

-- Assertion 3: a tenant-scoped UPDATE by A cannot mutate B's order (A→B write blocked)
DO $$
DECLARE v_rows integer;
BEGIN
  WITH upd AS (
    UPDATE orders SET status='cancelled'
    WHERE order_id='bbbbbbbb-0000-0000-0000-00000000000b'
      AND tenant_id='00000000-0000-0000-0000-000000000001'   -- A scoping B's row
    RETURNING 1
  ) SELECT COUNT(*) INTO v_rows FROM upd;
  IF v_rows <> 0 THEN RAISE EXCEPTION 'FAIL: tenant A updated tenant B order (% rows)', v_rows; END IF;
  RAISE NOTICE 'PASS: tenant A scoped UPDATE cannot mutate tenant B order';
END $$;

-- Assertion 4: omitting tenant_id on an INSERT fails loudly (non-defaultable write).
-- NOTE: a failing statement aborts the surrounding transaction; capture it in a nested
-- BEGIN..EXCEPTION block (SAVEPOINT/ROLLBACK TO SAVEPOINT are NOT allowed in a DO block).
DO $$
DECLARE v_failed boolean := false;
BEGIN
  BEGIN
    INSERT INTO orders(order_id, restaurant_id, channel, "customer_userId", total_amount, status)
    VALUES ('cccccccc-0000-0000-0000-00000000000c',
            '00000000-0000-0000-0000-000000000000','whatsapp','userC',50,'confirmed');
  EXCEPTION WHEN not_null_violation THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: INSERT without tenant_id succeeded (should be NOT NULL violation)'; END IF;
  RAISE NOTICE 'PASS: INSERT omitting tenant_id fails loudly (non-defaultable write enforced)';
END $$;

-- Assertion 5 (optional, FK enforcement): an order pointing at a non-existent tenant fails.
DO $$
DECLARE v_failed boolean := false;
BEGIN
  BEGIN
    INSERT INTO orders(order_id, tenant_id, restaurant_id, channel, "customer_userId", total_amount, status)
    VALUES ('dddddddd-0000-0000-0000-00000000000d',
            '99999999-9999-9999-9999-999999999999',
            '00000000-0000-0000-0000-000000000000','whatsapp','userD',50,'confirmed');
  EXCEPTION WHEN foreign_key_violation THEN v_failed := true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: order with bogus tenant_id accepted'; END IF;
  RAISE NOTICE 'PASS: order with non-existent tenant_id rejected by FK';
END $$;
```

### CI job structure (`.github/workflows/phase-18-assertions.yml`)

Two jobs, copying `phase-17-assertions.yml`:
1. **`cross-tenant-isolation-sql`** — `services: postgres:15-alpine` (PG 15 to match prod; the local-only runner uses PG 16 via the `postgres` system user — both work). Steps: create `tenants`/`restaurants`/`orders` DDL (the assertion needs the `orders` NOT NULL `tenant_id` + FK columns), run `db/ci-fixtures/18-two-tenant-seed.sql`, then `psql … -f db/ci-assertions/18-cross-tenant-isolation.sql`.
2. **`workflow-structural`** — jq/grep: assert the fixed workflows carry `WHERE tenant_id` / `tenant_id = $` on their order queries and have no `|| 'default'` / `DEFAULT_TENANT_ID`; assert `W_ORDER_FINALIZER` order INSERT includes `tenant_id`; assert Strapi `order/schema.json` + `customer/schema.json` contain a `tenant_id` attribute; assert all touched JSONs are valid JSON.

`paths:` trigger should list the fixed workflows + `db/ci-assertions/18-*.sql` + `db/ci-fixtures/18-*.sql` + the two Strapi schema files + the yml itself.

---

## 5. Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash + psql + jq (+ `yq` available) — same as Phase 15/16/17 |
| Config file | `.github/workflows/phase-18-assertions.yml` (new, Wave 0) |
| Quick run command (structural) | `jq -e '.nodes[] \| select(.parameters.query \| test("tenant_id"))' workflows/W51_VIP_WIN_BACK.json` |
| Full suite command (CI) | `act pull_request -W .github/workflows/phase-18-assertions.yml` (or push PR) |
| **Local SQL run (no docker)** | see "Local ephemeral Postgres" below — docker is **DOWN**; root **cannot** `initdb`; use the `postgres` system user + `/usr/lib/postgresql/16/bin`. |

### Local ephemeral Postgres (documented hard constraint)

Docker daemon is down on this host and `initdb` refuses to run as `root`. **Verified working** mechanism for running the SQL assertions locally:

```bash
TMPPG=$(mktemp -d); chown postgres:postgres "$TMPPG"
su postgres -c "/usr/lib/postgresql/16/bin/initdb -D $TMPPG/data -A trust -U postgres"
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D $TMPPG/data -o '-p 55433 -k $TMPPG' -l $TMPPG/log start"
# apply DDL + fixtures + assertions over the unix socket in $TMPPG:
su postgres -c "/usr/lib/postgresql/16/bin/psql -h $TMPPG -p 55433 -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/ci-fixtures/18-two-tenant-seed.sql"
su postgres -c "/usr/lib/postgresql/16/bin/psql -h $TMPPG -p 55433 -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/ci-assertions/18-cross-tenant-isolation.sql"
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D $TMPPG/data stop"; rm -rf "$TMPPG"
```

(Confirmed end-to-end on 2026-06-20: `initdb OK`, `pg_ctl start OK`, `SELECT 1` returned.) Local runner is PG **16.13**; CI service is PG **15-alpine** (prod). The DO-block / `not_null_violation` / `foreign_key_violation` semantics are identical across 15/16. **No pgBouncer in CI or local** — `CREATE UNIQUE INDEX CONCURRENTLY` and DDL run against plain Postgres directly.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEN-04 | `orders.tenant_id` is `NOT NULL` with no default (schema confirms non-defaultable) | SQL (psql) | `psql … -c "SELECT is_nullable,column_default FROM information_schema.columns WHERE table_name='orders' AND column_name='tenant_id'"` → `NO`,`NULL` | partial (schema exists; assertion ❌ Wave 0) |
| TEN-04 | `W_ORDER_FINALIZER` order INSERT carries `tenant_id` (no longer omitted) | Structural (jq/grep) | `jq -r '.nodes[]\|select(.parameters.query)\|.parameters.query' workflows/W_ORDER_FINALIZER.json \| grep -q "INSERT INTO orders" && grep -q "tenant_id" ` | ❌ Wave 0 |
| TEN-04 | Each previously-unscoped order read carries `tenant_id` filter (W51/W53/W_THE_USUAL/W_ADMIN_PROACTIVE/W14) | Structural (jq/grep) | per-file `grep -q "tenant_id"` on the order query node | ❌ Wave 0 |
| TEN-04 | Strapi `order` + `customer` schemas have a `tenant_id` attribute | Structural (jq) | `jq -e '.attributes.tenant_id' inventory-cms/src/api/order/content-types/order/schema.json` | ❌ Wave 0 |
| TEN-04 | No `\|\| 'default'` / `DEFAULT_TENANT_ID` on any fixed order path | Structural (grep) | `! grep -Eq "DEFAULT_TENANT_ID\|\\\|\\\| *'default'" workflows/W_ORDER_FINALIZER.json …` | ❌ Wave 0 |
| TEN-04 | `W12_ADMIN_ORDERS` read still scoped (regression guard) | Structural (grep) | `grep -q "WHERE o.tenant_id = \$1" workflows/W12_ADMIN_ORDERS.json` | ✅ exists |
| TEN-05 | Tenant A cannot READ tenant B's order (both directions) | SQL (psql DO) | `psql … -f db/ci-assertions/18-cross-tenant-isolation.sql` (assertions 1–2) | ❌ Wave 0 |
| TEN-05 | Tenant A cannot WRITE/UPDATE tenant B's order | SQL (psql DO) | same file (assertion 3) | ❌ Wave 0 |
| TEN-05 | INSERT omitting tenant_id fails loudly (non-defaultable) | SQL (psql DO, nested BEGIN..EXCEPTION) | same file (assertion 4) | ❌ Wave 0 |
| TEN-05 | Bogus tenant_id rejected by FK | SQL (psql DO) | same file (assertion 5) | ❌ Wave 0 |
| TEN-05 | Isolation test wired into pipeline and fails build on cross-tenant success | CI (yml) | `.github/workflows/phase-18-assertions.yml` present + green | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** jq/grep structural checks on the modified workflow JSON + Strapi schema files; for SQL changes, run the local ephemeral-Postgres assertion (§5 mechanism).
- **Per wave merge:** full `phase-18-assertions.yml` suite (both jobs).
- **Phase gate:** full suite green + the scoping-checklist artifact complete (every order/customer path annotated) before `/gsd:verify-work`.

### Wave 0 Gaps

- [ ] `db/ci-fixtures/18-two-tenant-seed.sql` — two-tenant + per-tenant order/customer seed
- [ ] `db/ci-assertions/18-cross-tenant-isolation.sql` — both-direction read/write + non-defaultable-write + FK DO-block assertions
- [ ] `.github/workflows/phase-18-assertions.yml` — SQL job + structural job, wired to fail the build
- [ ] `.planning/phases/18-…/18-SCOPING-CHECKLIST.md` — the success-criterion-1 enumeration artifact (basis in §2)

*(No new framework install — same `jq`/`psql`/`yq` toolchain as Phase 15/16/17.)*

---

## Standard Stack

### Core (all already in repo, no new installs)

| Component | Version | Purpose | Source |
|-----------|---------|---------|--------|
| Postgres column constraint | PG 15 (prod) / 16 (local) | `orders.tenant_id uuid NOT NULL REFERENCES tenants` already enforces non-defaultable writes | `db/bootstrap.sql:181-182` |
| `public.create_order(text)` | existing fn | Canonical tenant-safe order write — derives tenant from `conversation_state` | `db/bootstrap.sql:1242-1364` |
| `n8n-nodes-base.postgres` | typeVersion 2 | The order/customer query nodes to scope | every `W*` order query node |
| Strapi 5 lifecycles (`beforeCreate`) | Strapi 5.37.1 | Inject `tenant_id` on Strapi `order`/`customer` create; throw if absent | `inventory-cms/src/api/order/content-types/order/lifecycles.ts` (pattern exists) |
| Strapi Document-Service middleware / controller override | Strapi 5.37.1 | Cross-cutting `tenant_id` filter on `order`/`customer` reads | `.planning/research/STACK.md` (Strapi-5-native, no plugin) |
| Bash + psql + jq | — | CI assertions (mirror Phase 17) | `.github/workflows/phase-17-assertions.yml` |

**Installation:** None. No new packages, no new credentials. CI uses the same `postgres:15-alpine` service image as Phase 16/17; local uses the system `postgres` user + `/usr/lib/postgresql/16/bin`.

---

## Architecture Patterns

### Pattern 1: Derive-Then-Stamp (the canonical write path — already correct)

**What:** `create_order()` reads `(tenant_id, restaurant_id)` from `conversation_state` (the sealed Phase-17 trusted context) via the `conversation_key`, then stamps them into the order INSERT. Never accepts a tenant from untrusted payload, never defaults.
**When to use:** Every order-creating workflow. `W4_CORE`/`W4.2_CART_MANAGER` already do; `W_ORDER_FINALIZER` must be migrated onto it (or a sibling that accepts an explicit, validated `(tenant_id, restaurant_id)`).
**Source:** `db/bootstrap.sql:1269-1364`.

### Pattern 2: Scoped Read (`WHERE tenant_id = $ctx`) — the reference

**What:** `FROM orders o WHERE o.tenant_id = $1` with the tenant supplied from the sealed auth context (`$json.tenantId`).
**Source:** `W12_ADMIN_ORDERS.json:159` "Q2 - List Orders (DB)".
**Apply to:** #8, #10, #11, #13, #14 (and defense-in-depth #2, #9, #12).

### Pattern 3: Strapi tenant injection via lifecycle + schema-required field

**What:** Add `tenant_id` `required: true` to `order`/`customer` schema; in `beforeCreate` validate `data.tenant_id` present (throw if not — parity with the existing items-empty throw); add a read filter via controller override or `strapi.documents.use` middleware.
**Anti-pattern:** defaulting `tenant_id` in the lifecycle — that re-introduces the fail-open leak Phase 17 removed.

### Anti-Patterns to Avoid

- **Adding Postgres RLS / `SET app.tenant_id` session GUCs** — incompatible with pgBouncer transaction pooling; explicitly out of scope.
- **Backfilling existing prod orders with a single default tenant inside the same migration that flips NOT NULL** — on the n8n plane the column is already NOT NULL and populated, so no backfill is needed there; on the Strapi plane, any new `tenant_id` column added to `customers`/`orders` must be backfilled to the canonical tenant **before** flipping NOT NULL (separate VPS step).
- **Scoping a scheduled cross-tenant sweep (W51/W61) by bolting a single `$ctx`** — these run without a request tenant. Either loop per tenant or carry each row's own `tenant_id` forward into downstream per-row sends. Document the chosen approach.
- **Relying on `id serial` (Strapi integer handle) instead of `order_id uuid` for tenant joins** — both exist on `orders`; tenant scoping must use `tenant_id`, not the integer `id`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tenant-stamped order creation | A new raw `INSERT INTO orders` in each workflow | `public.create_order()` | Already derives tenant from sealed context, prices the cart, writes `order_items`, handles idempotency (`stage='PLACED'`); a raw INSERT re-introduces the `W_ORDER_FINALIZER` omission bug. |
| Cross-tenant test harness | A bespoke node script spinning a DB | psql DO-blocks + ephemeral `postgres:15-alpine` (CI) / system `postgres` user (local) | Matches Phase 15/16/17; `RAISE EXCEPTION` + `ON_ERROR_STOP=1` is the established gate. |
| Strapi read-scoping | Per-controller hand-written `where` clauses everywhere | One Document-Service middleware (`strapi.documents.use`) injecting `tenant_id` | Strapi-5-native single chokepoint; avoids forgetting a controller. |
| Non-defaultable write guard | A trigger that substitutes a default | The existing `NOT NULL` + FK on `orders.tenant_id` | The constraint already errors loudly; a substituting trigger would be fail-open. |

**Key insight:** The hardest part of Phase 18 is *enumeration completeness*, not mechanism — the mechanism (NOT NULL column + `WHERE tenant_id` + `create_order()`) already exists and works. The checklist artifact is the load-bearing deliverable.

---

## Common Pitfalls

### Pitfall 1: Assuming a column-add/backfill migration is needed on the n8n `orders` table

**What goes wrong:** Planning a `ALTER TABLE orders ADD COLUMN tenant_id … ; backfill ; SET NOT NULL` migration that is redundant and risks a long lock on a live table.
**Why it happens:** The milestone goal phrasing ("non-defaultable on the write path") sounds like new schema work.
**How to avoid:** `orders.tenant_id` is **already** `uuid NOT NULL REFERENCES tenants` (`:181`). The n8n plane needs query scoping, not DDL. The DDL work is on the **Strapi** `order`/`customer` content types (which lack tenant fields). Verify with `information_schema.columns` before authoring any ALTER.

### Pitfall 2: The `W_ORDER_FINALIZER` INSERT is already broken and schema-drifted

**What goes wrong:** `INSERT INTO orders (customer_phone,"customer_userId",restaurant_id,total_amount,…)` omits `tenant_id` → NOT NULL violation; and `INSERT INTO order_items (order_id,item_code,quantity,price_cents)` references columns that don't exist (`qty`/`unit_price_cents` are the real names).
**Why it happens:** This path predates the canonical `create_order()` and drifted from the schema.
**How to avoid:** Route it through `create_order()` (preferred) or add `tenant_id, restaurant_id` from the validated `body.tenantId`/`restaurant_id`; fix the `order_items` column names. Add a structural CI assertion that this INSERT lists `tenant_id`.

### Pitfall 3: Strapi `customer.phone` is globally unique — a true cross-tenant leak

**What goes wrong:** Two tenants with the same customer phone collide; the second tenant's create fails or hijacks the first's customer row. The Strapi `order`/`customer` types carry no tenant at all.
**Why it happens:** The CMS content types were authored single-tenant.
**How to avoid:** Add `tenant_id` to both content types; change `phone unique` → composite `(tenant_id, phone)`; backfill to canonical tenant before NOT NULL (🔴 VPS). Also tighten `customer_payment_profiles.user_id UNIQUE` → `(tenant_id, user_id)`.

### Pitfall 4: Scheduled cross-tenant sweeps (W51_VIP_WIN_BACK, W61_REVIEW_CATCHER, W53, W_ADMIN_PROACTIVE)

**What goes wrong:** These run on a schedule with no request tenant and aggregate across all tenants (`GROUP BY customer_phone`, `COUNT(*) FROM orders`). Bolting one `$ctx` breaks them; leaving them unscoped leaks one tenant's aggregates into another's marketing/ops action.
**How to avoid:** Decide per-workflow: either iterate per active tenant, or carry each row's own `tenant_id` forward so downstream sends stay tenant-correct (W61 already selects `o.tenant_id`). Record the decision in the checklist artifact.

### Pitfall 5: SAVEPOINT inside a DO block (CI assertion writing)

**What goes wrong:** Testing "INSERT without tenant_id fails" by `SAVEPOINT`/`ROLLBACK TO SAVEPOINT` inside a `DO $$` block throws `SAVEPOINT can only be used in transaction blocks` / is disallowed in PL/pgSQL.
**How to avoid:** Use a **nested `BEGIN … EXCEPTION WHEN not_null_violation THEN … END`** block to catch the expected failure (as in §4 assertion 4), or mutate-then-restore (as Phase 17 assertion 4 does). Never `SAVEPOINT` in a DO block.

### Pitfall 6: pgBouncer + `CREATE UNIQUE INDEX CONCURRENTLY` (VPS only)

**What goes wrong:** If the Strapi composite-unique change is shipped as `CREATE UNIQUE INDEX CONCURRENTLY`, it must target `postgres:5432` directly, NOT pgBouncer (transaction-pool mode aborts CONCURRENTLY). CI/local have no pgBouncer so this only bites on the VPS.
**How to avoid:** Mark the index migration 🔴 VPS-deferred with an explicit "apply to postgres:5432, not pgbouncer:6432" note (same constraint Phase 16 documented).

### Pitfall 7: Two `orders` tables vs one (n8n DB vs strapi DB)

**What goes wrong:** Assuming the Strapi `order` content type and the n8n `orders` table are the same physical table (both `collectionName: "orders"`). If they are distinct (n8n DB vs strapi DB), the kiosk REST write lands in the strapi-DB `orders`, which has no `tenant_id` — a separate table from the well-scoped n8n `orders`.
**How to avoid:** Confirm during planning which DB each lives in (the milestone keystone says order/customer DATA lives in the n8n DB, but Strapi's content-type table may be a parallel CMS copy). The scoping fix must target whichever physical table the kiosk path actually writes. **Open question O-1.**

---

## State of the Art

| Old Approach | Current Approach (Phase 18) | When Changed | Impact |
|---|---|---|---|
| Order writes scattered across raw `INSERT INTO orders` | Single canonical `create_order()` deriving tenant from sealed `conversation_state` | already in place; Phase 18 migrates the last stragglers (`W_ORDER_FINALIZER`) onto it | Omitted-tenant writes error loudly (NOT NULL) instead of silently defaulting |
| Strapi `order`/`customer` single-tenant (no tenant field, global-unique phone) | `tenant_id`/`restaurant_id` required attributes + lifecycle injection + composite unique | Phase 18 | Kiosk/CMS plane can serve multiple tenants without phone collision or cross-tenant read |
| Cross-tenant ops/marketing sweeps (`COUNT(*) FROM orders`) | Per-tenant scoped or per-row tenant-carried sweeps | Phase 18 | One tenant's order volume no longer drives another's automation |
| No automated isolation proof | `phase-18-assertions.yml` two-tenant both-direction CI gate | Phase 18 | Build fails if a cross-tenant read or write ever succeeds |

**Deprecated/outdated:**
- `W_ORDER_FINALIZER`'s raw order INSERT — broken (NOT NULL + column drift); replace with `create_order()`.

---

## Open Questions

1. **O-1: Are the Strapi `orders`/`customers` content-type tables the same physical tables as the n8n `orders`/`customer_*` tables, or parallel CMS copies in the strapi DB?**
   - What we know: Strapi `order` schema has `collectionName: "orders"`; n8n `orders` table exists in `db/bootstrap.sql` on the n8n DB with `tenant_id NOT NULL`. The milestone keystone states order/customer DATA lives in the n8n DB. The kiosk path writes via Strapi REST (`POST /api/orders`).
   - What's unclear: Whether the kiosk REST write lands in the same NOT-NULL-scoped `orders` table (in which case it must already be supplying a tenant, contradicting the schema) or a separate strapi-DB `orders` table (no tenant field).
   - Recommendation: First planning task — run `\d orders` against both the n8n DB and the strapi DB (or read `docker-compose`/Strapi `database` config) to determine connection targets. Scope the fix to whichever physical table the kiosk writes. This determines whether a Strapi-side `tenant_id` migration is needed at all.

2. **O-2: Scoping strategy for scheduled cross-tenant sweeps (W51/W61/W53/W_ADMIN_PROACTIVE).**
   - What we know: They run without a request tenant and aggregate across tenants.
   - What's unclear: Whether to loop per tenant or carry per-row tenant forward.
   - Recommendation: Per-row carry where the query already selects `tenant_id` (W61); per-tenant loop for pure aggregates (W51/W53/W_ADMIN_PROACTIVE). Record in the checklist.

3. **O-3: Kiosk device→tenant trust for the unauthenticated `POST /kiosk-order`.**
   - What we know: Phase 17 added a `kiosk` row to `channel_identities` (`CI_KIOSK_DEVICE_ID`). `W_KIOSK_ORDER` currently uses `$json.tenant_id || $json.restaurant_id` for its guard call (`:39`).
   - Recommendation: Resolve kiosk `tenant_id` via the `channel_identities` kiosk row (device id → tenant) before the order write, same fail-closed posture as Phase 17. May be a small Phase 18 sub-task or explicitly deferred if the kiosk is single-tenant-only for now.

---

## Sources

### Primary (HIGH confidence)
- `db/bootstrap.sql` — direct read: `orders` DDL (`:179-266`, `tenant_id uuid NOT NULL` `:181`), `conversation_state` (`:158-170`), `carts` (`:172-177`), `order_items` (`:268-279`), `customer_payment_profiles` (`:654-677`), `customer_preferences` (`:701-714`), `payment_intents` (`:611-634`), `orders_audit` (`:917-932`), `public.create_order()` (`:1242-1364`, INSERT at `:1348-1364`)
- `workflows/W12_ADMIN_ORDERS.json:159` — confirmed scoped read `WHERE o.tenant_id = $1`
- `workflows/W_ORDER_FINALIZER.json:38,67` — raw `INSERT INTO orders` omitting `tenant_id` + `order_items` column drift
- `workflows/W4_CORE.json:395,120,236` — `create_order()` wrap + unscoped `UPDATE orders` self-ref; conversation_state read; faq scoped
- `workflows/W4.2_CART_MANAGER.json:221,24,170` — `create_order()`; conversation_state/carts/customer_preferences writes with sealed `tenant_id`
- `workflows/W4.1_ROUTER.json:52` — `restaurant_users` write with sealed `tenant_id`
- `workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json` — `UPDATE orders … WHERE order_id=$1` unscoped; support_tickets scoped by restaurant_id
- `workflows/W61_REVIEW_CATCHER.json`, `W51_VIP_WIN_BACK.json`, `W53_DYNAMIC_KITCHEN_LOAD.json`, `W60_KITCHEN_CLOUD_PRINT.json`, `W_ADMIN_PROACTIVE_AGENT.json`, `W_THE_USUAL.json` — unscoped order reads/writes (direct grep + read)
- `workflows/W_KIOSK_ORDER.json:292` — kiosk order via `POST /api/orders` Strapi REST (no tenant in body)
- `inventory-cms/src/api/order/content-types/order/schema.json` — no `tenant_id`/`restaurant_id` attributes; `customer`/`driver` relations
- `inventory-cms/src/api/order/content-types/order/lifecycles.ts` — `beforeCreate` throw-on-invalid pattern (injection point)
- `inventory-cms/src/api/customer/content-types/customer/schema.json` — no `tenant_id`; `phone unique:true` global
- `db/migrations/2026-06-20_channel_identities.sql` — kiosk identity row + canonical UUIDs
- `db/ci-assertions/17-tenant-resolution.sql`, `.github/workflows/phase-17-assertions.yml` — CI DO-block + ephemeral-PG pattern to mirror
- Local probe (2026-06-20): docker DOWN; `initdb` works as `postgres` system user via `/usr/lib/postgresql/16/bin`; `psql 16.13`, `jq 1.7`, `yq` present

### Secondary (MEDIUM confidence)
- `.planning/research/SUMMARY.md` — keystone (two `tenant_id` planes), RLS-rejection reconciliation, "~11 workflows + Strapi controllers/lifecycles" enumeration target, Phase 4 research flag (exact scoping nodes not pre-enumerated)
- `.planning/ROADMAP.md` Phase 18 block (`:109-124`) — success criteria + plan seeds
- `.planning/REQUIREMENTS.md` TEN-04, TEN-05 (`:18-19`) + Out-of-Scope RLS rationale (`:42`)
- `docs/adr/0001-canonical-tenant-key.md` (referenced) — canonical CI UUIDs `…0001`/`…0000`

---

## Metadata

**Confidence breakdown:**
- Data-plane schema inventory: HIGH — every order/customer table DDL read directly from `db/bootstrap.sql` with line numbers; `orders.tenant_id NOT NULL` confirmed
- Workflow read/write inventory: HIGH — each order query node grepped and read; classification grounded in actual SQL text
- Non-defaultable write mechanism: HIGH — `create_order()` body read in full; NOT NULL constraint confirmed
- CI test design: HIGH — mirrors verified `phase-17-assertions.yml`; ephemeral-PG mechanism tested end-to-end locally
- Strapi sub-plane gap: HIGH — both content-type schemas read; absence of `tenant_id` and global-unique `phone` confirmed
- O-1 (one vs two `orders` tables): MEDIUM — flagged as the first planning question; depends on DB connection config not yet read

**Research date:** 2026-06-20
**Valid until:** 2026-07-20 (stable — DDL, workflow JSON, and Strapi schemas are static artifacts)

---

## RESEARCH COMPLETE

**Phase:** 18 - Per-Tenant Data-Plane Scoping + Isolation CI
**Confidence:** HIGH

### Key Findings

- **THE headline finding: orders and the n8n customer tables ALREADY carry a non-defaultable `tenant_id`.** `orders.tenant_id uuid NOT NULL REFERENCES tenants` (`db/bootstrap.sql:181`), plus `conversation_state`, `customer_payment_profiles`, `payment_intents`, `outbound_messages` all `tenant_id NOT NULL`. No column-add/backfill migration is needed on the n8n plane — only query scoping. An omitted tenant already errors loudly (NOT NULL violation).
- **The canonical write path is already correct:** `public.create_order(conversation_key)` (`:1242-1364`) derives tenant/restaurant from the sealed `conversation_state` and stamps them; `W4_CORE`/`W4.2_CART_MANAGER`/`W4.1_ROUTER` all use it. `W12_ADMIN_ORDERS` read is confirmed scoped (`WHERE o.tenant_id = $1`).
- **The real exposure is two-fold:** (1) `W_ORDER_FINALIZER`'s raw `INSERT INTO orders` omits `tenant_id` (broken today + column-drifted) and a handful of direct-SQL workflows read/write orders unscoped (W51 marketing aggregate, W53 kitchen count, W_THE_USUAL, W_ADMIN_PROACTIVE, W14 cancel); (2) the **Strapi `order`/`customer` content types carry no `tenant_id` at all** and `customer.phone` is globally unique — the kiosk REST path (`POST /api/orders`) writes with no tenant. This Strapi sub-plane is where a column-add migration + lifecycle injection IS needed.
- **CI design (TEN-05):** two-tenant seed + both-direction read/write DO-block assertions + a non-defaultable-write (NOT NULL) + FK assertion, using nested `BEGIN..EXCEPTION` (NOT SAVEPOINT) inside DO blocks, mirroring `phase-17-assertions.yml`. Local runs use the `postgres` system user + `/usr/lib/postgresql/16/bin` (docker DOWN, root can't `initdb`) — verified working end-to-end.

### File Created
`.planning/phases/18-per-tenant-data-plane-scoping-and-isolation-ci/18-RESEARCH.md`

### Confidence Assessment
| Area | Level | Reason |
|------|-------|--------|
| Data-plane schema (orders/customers carry tenant_id) | HIGH | Direct DDL read with line numbers |
| Workflow read/write inventory | HIGH | Every order query node grepped + read |
| Non-defaultable write mechanism | HIGH | `create_order()` + NOT NULL confirmed |
| CI isolation test | HIGH | Mirrors Phase 17; ephemeral PG tested locally |
| Strapi sub-plane gap | HIGH | Both schemas read; tenant field absent confirmed |
| One vs two physical `orders` tables (O-1) | MEDIUM | Depends on DB-connection config — first planning question |

### Open Questions
1. O-1: Strapi `orders`/`customers` — same physical tables as n8n, or parallel strapi-DB copies? (determines whether a Strapi `tenant_id` migration is needed)
2. O-2: per-tenant-loop vs per-row-carry for scheduled cross-tenant sweeps
3. O-3: kiosk device→tenant trust for unauthenticated `POST /kiosk-order`

### Ready for Planning
Research complete. Proposed **3 plans** (matching ROADMAP seeds):
- `18-01-PLAN.md` — Order/customer read+write inventory checklist artifact (`18-SCOPING-CHECKLIST.md`), every path annotated scoped/unscoped; resolve O-1 (which physical `orders` table the kiosk writes)
- `18-02-PLAN.md` — Apply `WHERE tenant_id` scoping to the unscoped n8n direct-SQL paths; fix `W_ORDER_FINALIZER` onto `create_order()` (+ column-drift fix); add `tenant_id`/`restaurant_id` to Strapi `order`/`customer` schemas with lifecycle injection + composite-unique phone (🔴 VPS apply deferred)
- `18-03-PLAN.md` — Cross-tenant isolation CI: `db/ci-fixtures/18-two-tenant-seed.sql`, `db/ci-assertions/18-cross-tenant-isolation.sql`, `.github/workflows/phase-18-assertions.yml` (both-direction + non-defaultable-write + FK assertions, wired to fail the build)

**🔴 VPS deferred:** applying any Strapi-side `tenant_id` column/backfill/composite-unique migration to prod Postgres, and importing the updated workflows/CMS — deferred to a prod-connected session.
