---
phase: 19-entitlement-audit-and-cache-invalidation-lifecycle-hook
plan: 01
subsystem: entitlement-audit
tags: [adr, migration, strapi-db, uuid, cache-key-contract]
requires:
  - "strapi-DB entitlement_audit_log table (Phase-16 migration 2026-04-06)"
  - "tenants(tenant_id) canonical UUID plane (ADR 0001)"
provides:
  - "ADR 0003: strapi-DB placement + raw-Knex writer + ralphe:entitlement:{tenant_id}:{module_key} cache-key contract"
  - "entitlement_audit_log.tenant_id uuid NULL + nullable FK migration (idempotent, live-safe)"
  - "O-1/O-2/O-3 decisions accepted; nullable-tenant_id correction recorded"
affects:
  - "19-02 (raw-Knex writer + exact-key DEL implement against this placement)"
  - "19-03 (seed declares uuid-shaped table; FK + NULL-tenant path exercised)"
  - "Phase 20 GRD-01 (consumes the locked cache-key contract)"
tech-stack:
  added: []
  patterns:
    - "Guarded ALTER … TYPE uuid USING tenant_id::uuid (idempotent type migration)"
    - "Nullable FK live-safe two-step: ADD … NOT VALID then VALIDATE CONSTRAINT"
    - "to_regclass + pg_constraint existence guards (re-run = no-op)"
key-files:
  created:
    - "docs/adr/0003-entitlement-audit-placement.md"
    - "db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql"
  modified: []
decisions:
  - "Audit table stays in strapi DB; writer is raw Knex strapi.db.connection (not a content type)"
  - "Cache key LOCKED: ralphe:entitlement:{tenant_id}:{module_key} (ROADMAP:147)"
  - "O-1 product-module = audit-only (TTL-bounded, no global flush); O-2 single-row only; O-3 migrate uuid now"
  - "CORRECTION (Blocker B): tenant_id is uuid NULL; global product-module rows carry tenant_id=NULL (parity with admin_audit_log); all-zero sentinel NOT used"
metrics:
  duration: ~10m
  completed: 2026-06-20
---

# Phase 19 Plan 01: Entitlement-Audit Placement ADR + uuid Migration Summary

ADR 0003 settles the cross-DB placement (strapi DB + raw-Knex `strapi.db.connection` writer, because
`entitlement_audit_log` is not a Strapi content type), locks the
`ralphe:entitlement:{tenant_id}:{module_key}` cache-key contract Phase 20 consumes, and records the
O-1/O-2/O-3 decisions; a new idempotent, live-safe migration moves
`entitlement_audit_log.tenant_id` `VARCHAR(255) → uuid NULL` with a nullable FK to `tenants`.

## What was built

- **`docs/adr/0003-entitlement-audit-placement.md`** (191 lines, Accepted, Phase 19, AUD-01/AUD-02):
  Decision 1 (strapi-DB placement + raw-Knex writer with the A/B/C option table + not-a-content-type
  rationale), Decision 2 (cache-key contract), Decision 3 (O-1 product-module audit-only), Decision 4
  (O-2 single-row), Decision 5 (O-3 migrate uuid now), fail-loud posture, 🔴 VPS deferrals, consequences.
- **`db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql`**: guarded `ALTER … TYPE uuid USING
  tenant_id::uuid` (only when not already uuid) + `DROP NOT NULL` + nullable FK (`NOT VALID` → `VALIDATE`,
  guarded on `to_regclass('tenants')` + `pg_constraint`) + re-asserted index. No `SAVEPOINT`/`ROLLBACK TO`
  in any DO block. 🔴 VPS apply deferred.

## Authoritative corrections landed (supersede the plan docs)

- **Correction 2 (Blocker B) — nullable tenant_id, product-module = NULL.** The migration makes
  `tenant_id` `uuid NULL` (not NOT-NULL) with a *nullable* FK, parity with `admin_audit_log.tenant_id`
  (ADR 0001:101-104, `db/bootstrap.sql:987-988`). Recorded in ADR 0003 Decision 5: "global product-module
  audit rows carry `tenant_id = NULL` (platform-scope); the all-zero sentinel is NOT used." This keeps the
  migration/writer/seed/test mutually consistent around a nullable tenant_id.

## Verification (proven on ephemeral Postgres 16)

- Migration applies **cleanly twice** (idempotent): APPLY #1 OK, APPLY #2 OK (no-op).
- Final shape confirmed: `tenant_id` = `uuid`, `is_nullable = YES`, FK `fk_entitlement_audit_tenant` present.
- A `tenant_id = NULL` insert (global product-module row) is **accepted** (1 null-tenant row).
- A non-null bogus UUID `99999999-…` is **FK-rejected** ("foreign key" violation).
- Structural greps pass: `TYPE uuid`, `tenant_id::uuid`, `NOT VALID`, `VALIDATE CONSTRAINT`,
  `to_regclass`/`pg_constraint`, `DROP NOT NULL`, VPS note; NO `SAVEPOINT`/`ROLLBACK TO` token.

## Deviations from Plan

**1. [Rule 1 - Bug] zod validator: `z.string().guid()` not `z.string().uuid()`** — discovered during
context probing; documented in ADR 0003 (affects 19-02, recorded here for the consumer). Under `zod ^4.3.6`,
`z.string().uuid()` enforces RFC-9562 version/variant bits and **rejects** the canonical CI tenant
`00000000-0000-0000-0000-000000000001` (and the all-zero form) — values the Postgres `uuid` column
accepts. `z.string().guid()` accepts any `8-4-4-4-12` hex string while still rejecting `'default'`/empty/
malformed. ADR records the correction; the 19-03 structural grep is widened to accept `uuid` OR `guid`.

**2. [Plan wording] Migration comment reworded** to avoid the literal `SAVEPOINT`/`ROLLBACK TO` tokens
(the plan's own verify grep is case-insensitive and would have matched the pitfall *warning* comment). The
guards are plain `IF EXISTS` checks; no transaction-control statements are present.

## 🔴 VPS-deferred (not attempted)

- Apply `2026-06-20_entitlement_audit_uuid.sql` on the prod strapi DB using the LIVE tenant UUID (ADR
  0001 runtime discovery — never `…0001`); rebuild the CMS; confirm prod Redis identity.

## Commits

- `845aea3` docs(19-01): ADR 0003 — entitlement-audit placement, raw-Knex writer, cache-key contract
- `e4b3147` feat(19-01): entitlement_audit_log.tenant_id VARCHAR->uuid + nullable FK migration

## Self-Check: PASSED

- FOUND: docs/adr/0003-entitlement-audit-placement.md
- FOUND: db/migrations-strapi/2026-06-20_entitlement_audit_uuid.sql
- FOUND commit: 845aea3
- FOUND commit: e4b3147
