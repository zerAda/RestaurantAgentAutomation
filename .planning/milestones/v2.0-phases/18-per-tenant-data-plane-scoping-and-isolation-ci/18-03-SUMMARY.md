---
phase: 18-per-tenant-data-plane-scoping-and-isolation-ci
plan: 03
subsystem: tenant-isolation / CI gate
tags: [tenant_id, isolation, ci, do-block, TEN-05]
requires: [phase-17-assertions.yml, 17-tenant-resolution.sql, 18-02 scoped workflows + Strapi schemas]
provides:
  - "db/ci-fixtures/18-two-tenant-seed.sql (two-tenant + per-tenant order seed)"
  - "db/ci-assertions/18-cross-tenant-isolation.sql (both-direction read/write + non-defaultable + FK)"
  - ".github/workflows/phase-18-assertions.yml (isolation SQL job + structural workflow/schema job)"
affects: [Phase 18 CI gate, branch protection]
tech-stack:
  added: []
  patterns: ["ephemeral postgres:15-alpine service", "nested BEGIN..EXCEPTION expected-failure assertion", "jq/grep structural gate"]
key-files:
  created:
    - db/ci-fixtures/18-two-tenant-seed.sql
    - db/ci-assertions/18-cross-tenant-isolation.sql
    - .github/workflows/phase-18-assertions.yml
  modified: []
decisions:
  - "Mirror phase-17-assertions.yml exactly: pinned checkout SHA, postgres:15-alpine, PGPASSWORD env, ON_ERROR_STOP=1, ::group:: wrapping; extend the FK-parents step to seed BOTH tenants A and B."
  - "Expected-failure assertions (non-defaultable write, FK) use nested BEGIN..EXCEPTION (never SAVEPOINT inside a DO block — Pitfall 5)."
  - "Comments in the assertion file avoid the literal SAVEPOINT/ROLLBACK TO tokens so the CI no-SAVEPOINT grep (case-insensitive) is not falsely tripped by explanatory text."
  - "Structural job greps the scoped workflows + Strapi schemas; it passes only after 18-02 landed — by design (the gate is what proves 18-02)."
metrics:
  duration: ~30m
  completed: 2026-06-20
---

# Phase 18 Plan 03: Cross-Tenant Isolation CI Gate Summary

Created the Phase 18 machine-checkable isolation proof (TEN-05): a two-tenant seed, a both-direction read/write isolation assertion file (plus non-defaultable-write and FK assertions), and a GitHub Actions gate that runs the SQL against an ephemeral Postgres AND performs structural jq/grep assertions on the 18-02 scoped workflows + Strapi schemas — mirroring `phase-17-assertions.yml`. A cross-tenant read/write success or a missing tenant filter fails the build.

## What Was Built

- **`db/ci-fixtures/18-two-tenant-seed.sql`** (commit 9b5aabf): tenant A (`…0001`) + tenant B (`…00b2`), restaurant A (`…0000`) + restaurant B (`…00bb`), one order each (`aaaaaaaa…`/`bbbbbbbb…`) with all NOT NULL columns supplied; idempotent via `ON CONFLICT DO NOTHING`; quotes the mixed-case `"customer_userId"`.
- **`db/ci-assertions/18-cross-tenant-isolation.sql`** (commit f91001c): 5 DO-blocks — (1) A→B read blocked, (2) B→A read blocked, (3) A→B UPDATE blocked, (4) INSERT omitting `tenant_id` caught via nested `BEGIN..EXCEPTION WHEN not_null_violation`, (5) bogus `tenant_id` caught `WHEN foreign_key_violation`. No SAVEPOINT/ROLLBACK TO anywhere; each failure `RAISE EXCEPTION` (non-zero exit under `ON_ERROR_STOP=1`).
- **`.github/workflows/phase-18-assertions.yml`** (commit 0f1bf80): two jobs.
  - `cross-tenant-isolation-sql` — `postgres:15-alpine` service; seeds FK parents (tenants A+B, restaurants A+B), creates the minimal isolation `orders` table (`tenant_id NOT NULL REFERENCES tenants` + FK), applies the seed, runs the assertions.
  - `workflow-structural` — W12 regression guard (`o.tenant_id = $1`), W_ORDER_FINALIZER INSERT carries `tenant_id` + no `quantity, price_cents` drift, the five fixed order queries carry `tenant_id`, Strapi order/customer schemas have `tenant_id` (and customer `phone` not globally unique), no `DEFAULT_TENANT_ID`/`'default'` fallback, all touched JSON valid.
  - Mirrors phase-17: pinned `actions/checkout@11bd71901…`, `permissions: contents: read + pull-requests: read`, `PGPASSWORD: n8npass`, `-v ON_ERROR_STOP=1`, `::group::`/`::endgroup::`.

## Local Ephemeral-PG Verification (run as `postgres` system user, port 54399)

Docker is down / root cannot initdb, so the SQL suite was verified via the system `postgres` user + `/usr/lib/postgresql/16/bin` (the documented mechanism). Seed + assertions were run TWICE to prove idempotency, plus a negative control:

- **RUN #1 assertions — all 5 PASS** (exit 0):
  - `PASS: tenant A cannot read tenant B order`
  - `PASS: tenant B cannot read tenant A order`
  - `PASS: tenant A scoped UPDATE cannot mutate tenant B order`
  - `PASS: INSERT omitting tenant_id fails loudly (non-defaultable write enforced)`
  - `PASS: order with non-existent tenant_id rejected by FK`
- **RUN #2 (idempotency)** — seed re-run is a clean no-op (`INSERT 0 0` for all rows); all 5 assertions still PASS (exit 0).
- **Negative control** — an unscoped read of B's order (no `tenant_id` filter) correctly `RAISE`d and exited non-zero (3): `FAIL (negative control fired correctly): unscoped read saw B order (1 rows)` — proving the gate FAILS the build on a cross-tenant read success.
- **Structural job** simulated locally against the landed 18-02 changes: all checks green (W12 guard, finalizer tenant_id + order_items cols, 5 scoped queries, Strapi schemas, no-fallback, all JSON valid).

## Deviations from Plan

None material. One micro-correction: the assertion-file comments were reworded to remove the literal `SAVEPOINT`/`ROLLBACK TO` tokens, because the CI structural job's no-SAVEPOINT check is case-insensitive and would otherwise be tripped by the explanatory comment text (not by actual SAVEPOINT usage).

## 🔴 VPS Deferred

N/A for this plan — the CI gate runs in GitHub Actions / locally, no prod dependency. (Importing the scoped workflows + applying the strapi-DB migration on prod remain deferred from 18-02.)

## Verification

- Task 1 verify: PASS (seed has tenant B, both per-tenant orders, ON CONFLICT, customer_userId).
- Task 2 verify: PASS (5 DO-blocks, not_null_violation + foreign_key_violation, no SAVEPOINT, both-direction reads).
- Task 3 verify: PASS (YAML parses; references seed + assertions + postgres:15-alpine + pinned SHA + structural job + schema check).
- End-to-end ephemeral-PG: PASS twice (idempotent) + negative control fires correctly.

## Self-Check: PASSED
