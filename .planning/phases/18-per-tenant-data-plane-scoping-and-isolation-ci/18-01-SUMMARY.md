---
phase: 18-per-tenant-data-plane-scoping-and-isolation-ci
plan: 01
subsystem: tenant-isolation / data-plane scoping
tags: [tenant_id, scoping, checklist, O-1, TEN-04]
requires: [18-RESEARCH.md, db/bootstrap.sql, inventory-cms schemas, docker-compose.base.yml]
provides: ["18-SCOPING-CHECKLIST.md (success-criterion-1 enumeration; O-1 resolved; per-path 18-02 fix spec)"]
affects: [18-02-PLAN.md execution, 18-03 structural CI job]
tech-stack:
  added: []
  patterns: ["derive-then-stamp", "WHERE tenant_id scoped read", "transitive carts scoping via conversation_state"]
key-files:
  created:
    - .planning/phases/18-per-tenant-data-plane-scoping-and-isolation-ci/18-SCOPING-CHECKLIST.md
  modified: []
decisions:
  - "O-1: TWO physically separate DBs (strapi vs n8n); kiosk writes the tenant-less strapi-DB orders table => Strapi tenant_id migration REQUIRED in 18-02"
  - "Carts sub-scoping: scope W_ADMIN_PROACTIVE carts read transitively via JOIN conversation_state ON conversation_key, filter cs.tenant_id (carts has no tenant_id column)"
  - "Sweep decisions (O-2): W51/W53/W_ADMIN_PROACTIVE = per-tenant WHERE tenant_id=$1; W61 = per-row tenant-carry (already selects o.tenant_id)"
  - "W14 get_recent_orders($1=restaurant_id) is prod-only (not in repo), restaurant-scoped via its arg => out of direct-SQL scope; 18-02 still scopes the W14 cancel UPDATE"
metrics:
  duration: ~25m
  completed: 2026-06-20
---

# Phase 18 Plan 01: Order/Customer Scoping Checklist Summary

Produced `18-SCOPING-CHECKLIST.md` — the load-bearing enumeration artifact that resolves Open Question O-1 with evidence and lists every order/customer read+write path annotated scoped/unscoped with the exact 18-02 fix, making 18-02 a mechanical execution with zero open design choices.

## What Was Built

- **O-1 Resolution** (with file:line citations): re-verified `inventory-cms/config/database.ts:30` (`database: env('DATABASE_NAME','strapi')`), `docker-compose.base.yml:251` (Strapi `DATABASE_NAME=…:-strapi`) vs `:48` (n8n `POSTGRES_DB: n8n`), both Strapi schemas (no `tenant_id`), `kiosk-app/src/context/CartContext.tsx:142` (`strapi.post('/api/orders')`), and `db/bootstrap.sql:179-205` (n8n `orders.tenant_id uuid NOT NULL`). **Verdict: TWO separate databases; the Strapi tenant_id migration is REQUIRED.**
- **Inventory table** — 16+ rows covering W12 (reference), W4_CORE (self-ref UPDATE + state read), W4.2, W4.1, W_ORDER_FINALIZER (3 nodes: Create Order / Batch Insert Items / E1 - Mark Inventory ERROR), W14 (cancel + get_recent_orders), W51, W53, W_THE_USUAL, W_ADMIN_PROACTIVE, W61, W60, W_KIOSK_ORDER, W_PAYMENT_CHARGILY, and both Strapi content types — each with a concrete `18-02 Action`.
- **Carts Sub-Scoping Decision** (pinned): transitive join to `conversation_state` for the W_ADMIN_PROACTIVE `abandoned` CTE (carts has no tenant_id column).
- **Sweep Decisions (O-2)**, **Net Work for 18-02** breakdown (a/b/c), **Note A** (W14 get_recent_orders out of scope), and the **🔴 VPS Deferred** note.

## Decisions Made

See frontmatter `decisions`. The four load-bearing calls: O-1 = two DBs (Strapi migration required), carts transitive scoping, the per-tenant vs per-row sweep split, and W14 get_recent_orders being out of direct-SQL scope.

## Deviations from Plan

None — plan executed exactly as written. Folded in the three plan-checker warnings:
- W_ORDER_FINALIZER E1 node documented as intentionally PK-keyed defense-in-depth (warning #1), order_items drift verified against `db/bootstrap.sql:272-275`.
- Carts sub-scoping decision pinned explicitly (warning #2).
- W14 get_recent_orders documented as prod-only / out of scope (warning #3).

## 🔴 VPS Deferred

Documented in the checklist: strapi-DB migration apply, CMS rebuild, prod n8n workflow import.

## Verification

- Task 1 verify: PASS (O-1 evidence + verdict + kiosk write-path present).
- Task 2 verify: PASS (all 9 named workflows + Strapi rows present; create_order + WHERE tenant_id fixes; Sweep Decisions; VPS note; 128 lines ≥ 80).

## Self-Check: PASSED
