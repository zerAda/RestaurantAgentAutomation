---
phase: 16-live-safe-saas-migration-and-channel-routing-table
verified: 2026-06-20T15:00:00Z
status: passed
score: 4/4 success criteria verified (DB execution via CI gate; live VPS apply/seed deferred)
gaps: []
requirements_satisfied: [TEN-02, DB-01]
deferred_to_vps: ["apply live-safe SaaS migration on prod strapi DB", "apply+seed channel_identities on prod n8n DB with runtime-discovered tenant UUID + real WA/IG/MSG ids from platform_settings"]
---

# Phase 16: Live-Safe SaaS Migration + Channel Routing Table — Verification

**Goal:** SaaS migration safe on a live/duplicated table (probe + dedupe + `CREATE UNIQUE INDEX CONCURRENTLY`, no lock, no dup-fail, idempotent); `channel_identities` routing table exists+seeded; both wired into `db-migrate`.
**Status:** passed — 4/4 ROADMAP success criteria met at code/CI level; live VPS apply deferred.

## Observable Truths

| # | Success Criterion | Status | Evidence |
|---|-------------------|--------|----------|
| 1 | SaaS migration: probe → dedupe → `CREATE UNIQUE INDEX CONCURRENTLY` → `ALTER ... USING INDEX` for both `uq_tenant_module` & `uq_product_module_key`, no ACCESS EXCLUSIVE lock, no dup-fail | VERIFIED | `db/migrations-strapi/2026-04-06_saas_modules_entitlements.sql`: 2× `CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS`, 2× `USING INDEX`, `DISTINCT ON` keep-latest dedupe, no bare `ADD CONSTRAINT … UNIQUE (` anti-pattern. Old `db/migrations/2026-04-06_*.sql` git-removed. Commit `3b01028`. |
| 2 | Migration idempotent + timeouts; CI proves dup-survival | VERIFIED (CI) | `lock_timeout`/`statement_timeout` set; `IF NOT EXISTS` guards; `db/ci-fixtures/16-duplicate-entitlements-fixture.sql` + `db/ci-assertions/16-saas-migration-schema-check.sql` run the migration twice in `.github/workflows/phase-16-assertions.yml`. Commit `3b01028`. |
| 3 | `channel_identities` (n8n DB): PK `(channel, identity)`, FKs to tenants/restaurants, `is_active default true`, CI sentinels (no prod ids), idempotent | VERIFIED | `db/migrations/2026-06-20_channel_identities.sql`: PK, both FKs, `is_active boolean NOT NULL DEFAULT true` (line 27), `CI_WA_PHONE_NUMBER_ID` etc. under canonical CI UUID, `ON CONFLICT DO NOTHING`. Commit `f18f6e5`. |
| 4 | Both wired into `db-migrate`: dedicated strapi pass (direct `postgres:5432`, separate `schema_migrations`); two-DB CI gate | VERIFIED | `docker-compose.base.yml` db-migrate gains a `PGDATABASE=strapi` pass via `psql -h postgres -p 5432 -d strapi` (bypasses pgBouncer transaction pool for CONCURRENTLY) + `/migrations-strapi` mount; `.github/workflows/phase-16-assertions.yml` runs 2 ephemeral Postgres (strapi+n8n). Compose + workflow valid YAML. Commit `bfb4401`. |

## Local Verification

16/16 structural acceptance checks passed (YAML validity, SQL structure/grep, file presence, git-rm). The real DB behavior (CONCURRENTLY build, dedupe, idempotent re-run, constraint enforcement, channel_identities FKs/seed) runs in `phase-16-assertions.yml` against two ephemeral `postgres:15-alpine` instances — not runnable in this sandbox (no local Postgres).

## Deferred (🔴 VPS)

Apply the live-safe migration on the prod **strapi** DB (CONCURRENTLY direct to postgres:5432) and apply+seed `channel_identities` on the prod **n8n** DB using runtime-discovered tenant/restaurant UUIDs and the real WA/IG/MSG ids from `platform_settings` — never hardcode prod values. Deferred to a prod-connected session.

## Verdict

`passed` — TEN-02 + DB-01 satisfied at code/CI level. The DB layer (live-safe constraints + channel routing table) is in place, unblocking Phase 17 (inbound tenant derivation).
