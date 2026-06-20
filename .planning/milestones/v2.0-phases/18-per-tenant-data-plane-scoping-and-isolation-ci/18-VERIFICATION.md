---
phase: 18-per-tenant-data-plane-scoping-and-isolation-ci
verified: 2026-06-20T17:05:00Z
status: passed
score: 4/4 success criteria verified (live strapi-DB apply + CMS rebuild + prod n8n import deferred)
gaps: []
requirements_satisfied: [TEN-04, TEN-05]
deferred_to_vps:
  - "apply db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql to the LIVE strapi DB (column add + backfill + NOT NULL + CREATE UNIQUE INDEX CONCURRENTLY direct to postgres:5432, NOT pgbouncer:6432)"
  - "rebuild the CMS so the new order/customer tenant_id/restaurant_id attributes + fail-loud lifecycles take effect"
  - "import the scoped workflows (W_ORDER_FINALIZER, W51, W53, W_THE_USUAL, W_ADMIN_PROACTIVE, W14, W4_CORE) on prod n8n"
---

# Phase 18: Per-Tenant Data-Plane Scoping + Isolation CI — Verification

**Goal:** Every order/customer READ and WRITE is scoped by a non-defaultable `tenant_id`, and an automated CI test proves a request resolved to tenant A cannot read or write tenant B's data.
**Status:** passed — 4/4 ROADMAP success criteria met at code/CI level; the 5-assertion isolation proof was independently reproduced on ephemeral Postgres (exit 0); prod migration apply + CMS rebuild + workflow import deferred.

## Observable Truths

| # | Success Criterion | Status | Evidence |
|---|-------------------|--------|----------|
| 1 | Checklist enumerates EVERY order/customer read+write path across BOTH DB planes, annotated scoped/unscoped, resolves O-1 (two separate DBs) | VERIFIED | `18-SCOPING-CHECKLIST.md` (128 lines): O-1 RESOLVED with file:line citations (`inventory-cms/config/database.ts:30` `DATABASE_NAME='strapi'` vs `docker-compose.base.yml:48` `POSTGRES_DB: n8n`; kiosk `CartContext.tsx:142` writes strapi-DB orders) → TWO physically separate DBs, Strapi migration REQUIRED. 16-row inventory covers W12/W4_CORE/W4.2/W4.1/W_ORDER_FINALIZER (3 nodes)/W14/W51/W53/W_THE_USUAL/W_ADMIN_PROACTIVE/W61/W60/W_KIOSK_ORDER/W_PAYMENT_CHARGILY + both Strapi content types, each with a concrete 18-02 action; Carts Sub-Scoping + Sweep Decisions (O-2) pinned. |
| 2 | `tenant_id` non-defaultable on every WRITE (NOT NULL, no `\|\| 'default'`/`DEFAULT_TENANT_ID`); every previously-unscoped READ now `WHERE tenant_id = $ctx`; n8n + Strapi planes both closed | VERIFIED | **n8n:** W_ORDER_FINALIZER `Create Order` INSERT lists `tenant_id, restaurant_id` first (`VALUES ($1,$2,…)`), `Batch Insert Items` uses `qty`/`unit_price_cents` (drift fixed), `E1` UPDATE is PK-keyed `WHERE id=$1 AND tenant_id=$3` (parity). Scoped reads confirmed: W51 `WHERE tenant_id=$1`, W53 `AND tenant_id=$1`, W_THE_USUAL `AND o.tenant_id=$2`, W_ADMIN_PROACTIVE sales `AND tenant_id=$1` + carts transitive `JOIN conversation_state … cs.tenant_id=$1`, W14 E5a cancel `AND tenant_id=$2::uuid`, W4_CORE self-ref `AND tenant_id=(SELECT tenant_id FROM ord)`. Repo-grep: **zero** `DEFAULT_TENANT_ID`/`\|\| 'default'` in any of the 7 fixed workflows or either lifecycle. **Strapi:** `order/schema.json` required `tenant_id`+`restaurant_id`; `customer/schema.json` required `tenant_id`, `phone` no longer `unique:true`; both `lifecycles.ts` `beforeCreate` throw on blank `tenant_id` (no fallback, `node --experimental-strip-types --check` clean); `db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql` exists and is idempotent (proven apply-twice, below). |
| 3 | CI SQL proves BOTH-direction read isolation + write isolation + non-defaultable-write + FK rejection via nested `BEGIN..EXCEPTION` (no SAVEPOINT inside any DO block) | VERIFIED | `db/ci-assertions/18-cross-tenant-isolation.sql`: 5 `DO $$` blocks — (1) A↛B read, (2) B↛A read, (3) A↛B UPDATE, (4) INSERT omitting `tenant_id` caught `WHEN not_null_violation`, (5) bogus `tenant_id` caught `WHEN foreign_key_violation`. Case-insensitive grep for `SAVEPOINT`/`ROLLBACK TO` = **none**. Independently re-run on ephemeral PG 16.13 → **exit 0 with all 5 PASS NOTICEs** (lines below). |
| 4 | `.github/workflows/phase-18-assertions.yml` wires the SQL job (seed → two-tenant fixture → assertions) + a structural jq/grep job, and FAILS the build on a cross-tenant read/write success | VERIFIED | YAML parses (`yaml.safe_load` OK). Job `cross-tenant-isolation-sql`: `postgres:15-alpine` service, pinned `actions/checkout@11bd719…`, `ON_ERROR_STOP=1`, seeds FK parents (tenants A+B, restaurants A+B) → minimal orders table (`tenant_id NOT NULL REFERENCES tenants`) → `18-two-tenant-seed.sql` → `18-cross-tenant-isolation.sql`. Job `workflow-structural`: W12 regression guard, finalizer `tenant_id`+`qty`/`unit_price_cents` (no `quantity, price_cents`), 5 scoped queries, Strapi schemas + phone-not-unique, no-fallback grep, JSON validity. All 6 structural checks reproduced locally on the current tree → ALL-PASS. Negative control (unscoped read of B with `ON_ERROR_STOP=1`) `RAISE`d exit 3 → the gate FAILS the build on a cross-tenant read success. |

**Score: 4/4 success criteria verified.**

## Local Verification

**Structural job (both jobs' jq/grep, re-run on the current tree): ALL-PASS** — W12 still `o.tenant_id = $1`; W_ORDER_FINALIZER INSERT carries `tenant_id` + `qty`/`unit_price_cents` with no drift; W51/W53/W_THE_USUAL/W_ADMIN_PROACTIVE/W14 all carry `tenant_id`; Strapi order has `tenant_id`+`restaurant_id`, customer has `tenant_id` and `phone.unique != true`; no `DEFAULT_TENANT_ID`/`|| 'default'` in any of the 7 fixed workflows; all 8 workflow JSONs + 2 schema JSONs valid.

**Independent ephemeral-Postgres SQL run (PG 16.13, system `postgres` user, port 55433 — docker down / root cannot initdb):**

Seed FK parents (both tenants + restaurants) → minimal `orders` table → `18-two-tenant-seed.sql` (`INSERT 0 2` orders) → `18-cross-tenant-isolation.sql`:

```
NOTICE:  PASS: tenant A cannot read tenant B order
NOTICE:  PASS: tenant B cannot read tenant A order
NOTICE:  PASS: tenant A scoped UPDATE cannot mutate tenant B order
NOTICE:  PASS: INSERT omitting tenant_id fails loudly (non-defaultable write enforced)
NOTICE:  PASS: order with non-existent tenant_id rejected by FK
ASSERTIONS EXIT CODE: 0
```

- **Negative control** — an intentionally *unscoped* read of B's order (no `tenant_id` filter) saw 1 row and `RAISE`d `ERROR … unscoped read saw B order (1 rows)`, exiting **non-zero (3)** under `ON_ERROR_STOP=1` → confirms the gate FAILS the build on a real cross-tenant leak (not a vacuous pass).
- **Idempotency** — re-running the seed is a clean no-op (`INSERT 0 0`) and the 5 assertions still PASS (exit 0).

**Strapi-DB migration idempotency (separate `strapi` database, stub `orders`/`customers` with a global `customers_phone_unique`):**

- **Apply #1:** columns added, `UPDATE 2` orders + `UPDATE 1` customer backfilled, NOT NULL flipped, global phone unique dropped, `uq_customers_tenant_phone` created — exit 0.
- **Apply #2:** clean no-op — "already exists, skipping" notices, `UPDATE 0`/`UPDATE 0`, no errors — exit 0.
- **Final state:** `orders.tenant_id`/`restaurant_id` + `customers.tenant_id` all `NOT NULL`; indexes are `customers_pkey` + `uq_customers_tenant_phone` (global `customers_phone_unique` gone). **Two different tenants successfully shared phone `+213600000001`** (INSERT 0 1), while a **same-tenant + same-phone** duplicate was correctly rejected (`duplicate key value violates unique constraint "uq_customers_tenant_phone"`) — proving the composite unique replaced the global one.

`node --experimental-strip-types --check` is clean on both `order/lifecycles.ts` and `customer/lifecycles.ts`.

## Deferred (🔴 VPS)

These require a prod-connected session and are legitimately out of code/CI scope (NOT gaps):
1. Apply `db/migrations-strapi/2026-06-20_strapi_order_customer_tenant.sql` to the LIVE strapi DB — column add + backfill + NOT NULL + `CREATE UNIQUE INDEX CONCURRENTLY uq_customers_tenant_phone` direct to `postgres:5432` (NOT pgbouncer:6432; CONCURRENTLY cannot run in a txn block and pgBouncer transaction-mode aborts it).
2. Rebuild the CMS so the new `order`/`customer` `tenant_id`/`restaurant_id` attributes + fail-loud `beforeCreate` lifecycles take effect.
3. Import the 7 scoped workflows (W_ORDER_FINALIZER, W51, W53, W_THE_USUAL, W_ADMIN_PROACTIVE, W14, W4_CORE) on prod n8n.

(Note A from the checklist: W14 `get_recent_orders($1=restaurant_id)` is prod-only — not in the repo — and is assumed restaurant-scoped via its argument; out of this phase's direct-SQL scope. The writable W14 cancel UPDATE (E5a) IS scoped this phase.)

## Verdict

`passed` — TEN-04 and TEN-05 satisfied at the code/CI level with no gaps. Every order/customer read/write across both data planes (n8n direct-SQL + Strapi content types) is now tenant-scoped with a non-defaultable, fail-loud `tenant_id` write path, and the automated cross-tenant isolation gate proves both-direction read/write separation + non-defaultable-write + FK rejection — independently reproduced here on ephemeral Postgres (5/5 PASS, exit 0; negative control fires non-zero; idempotent; strapi-DB migration applies twice cleanly with per-tenant phone uniqueness). The three VPS items (live strapi-DB apply, CMS rebuild, prod workflow import) are deferred to a prod-connected session.
