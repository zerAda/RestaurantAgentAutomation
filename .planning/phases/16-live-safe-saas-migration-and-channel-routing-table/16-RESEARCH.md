# Phase 16: Live-Safe SaaS Migration + Channel Routing Table — Research

**Researched:** 2026-06-20
**Domain:** PostgreSQL live-safe migration (CONCURRENTLY, dup-probe, idempotency) + channel-to-tenant routing table design
**Confidence:** HIGH (all claims grounded in direct repo reads; no inferred facts)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEN-02 | `channel_identities` routing table maps channel-native identifiers to `(tenant_id, restaurant_id)`; seeded for the current single tenant | Covered in sections: Channel Identities Design, Seed Source, DB Target |
| DB-01 | `db/migrations/2026-04-06_saas_modules_entitlements.sql` constraints made live-safe: dup-probe + `CREATE UNIQUE INDEX CONCURRENTLY` + attach; no exclusive lock; no failure on pre-existing duplicates; idempotent; wired into `db-migrate` | Covered in sections: Current Migration State, Live-Safe Rewrite, CONCURRENTLY/pgBouncer Resolution, db-migrate Wiring |
</phase_requirements>

---

## Summary

Phase 16 has two parallel, independently landable deliverables that share the same `db-migrate` wiring mechanism.

**Deliverable A — Rewrite `db/migrations/2026-04-06_saas_modules_entitlements.sql` to be live-safe.** The file as committed (`db/migrations/2026-04-06_saas_modules_entitlements.sql:11-19`) uses a bare `ALTER TABLE tenant_entitlements ADD CONSTRAINT uq_tenant_module UNIQUE (tenant_id, module_key)` inside a `DO $$` block that only guards on constraint-name existence, not on pre-existing duplicate rows. On a live VPS with any duplicate entitlement rows this fails outright and takes an `ACCESS EXCLUSIVE` lock during the attempt. The rewrite must: (1) run a read-only duplicate probe on both `tenant_entitlements(tenant_id,module_key)` and `product_modules(key)`; (2) dedupe (keep latest `activated_at`) as an explicit step before index creation; (3) build the unique constraint via `CREATE UNIQUE INDEX CONCURRENTLY` followed by `ALTER TABLE ... ADD CONSTRAINT ... USING INDEX`; (4) set `lock_timeout` and `statement_timeout`; and (5) remain fully idempotent (safe to re-run). The critical complication is that `CREATE INDEX CONCURRENTLY` cannot run inside a transaction — and the `db-migrate` service connects via **pgBouncer in transaction-pooling mode** (`POOL_MODE=transaction`, `docker-compose.base.yml:89`), which wraps every client interaction in a short-lived transaction. The resolution is to bypass pgBouncer for the CONCURRENTLY step by connecting directly to `postgres:5432` instead of `pgbouncer:5432`.

**Deliverable B — New `channel_identities` migration + seed.** The routing table lives in the **n8n DB** (same DB as `tenants`/`restaurants`/`api_clients`) so n8n inbound adapters can query it with the existing `postgres-main` credential and `tenant_id`/`restaurant_id` FKs are valid. The seed values for the current single tenant come from `platform_settings` rows `WA_PHONE_NUMBER_ID`, `IG_PAGE_ID`, `MESSENGER_PAGE_ID` in the n8n DB (seeded by `db/migrations/011_platform_settings_seed.sql:45,51,56` as empty strings that operators fill in) and, for kiosk, a sentinel placeholder device ID. Because the real values are operator-supplied and not hardcoded in the repo, the migration seeds a single row per channel using `ON CONFLICT DO NOTHING` with the CI/dev canonical UUIDs; the 🔴 VPS seed must discover the real values from `platform_settings` or the operator's environment.

**Primary recommendation:** Write the rewrite SQL and the channel_identities migration as two separate files (`2026-04-06_saas_modules_entitlements.sql` rewritten in place, new `2026-06-20_channel_identities.sql`) and have the CONCURRENTLY steps connect directly to `postgres:5432` rather than through pgBouncer by exporting a direct `PGHOST`/`PGPORT` inside the migration shell wrapper or in a separate `db-migrate`-adjacent one-shot service.

---

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| PostgreSQL 15 | 15-alpine | `CREATE UNIQUE INDEX CONCURRENTLY`, `DO $$` idempotency blocks, `USING INDEX` attach pattern | Hard constraint; already running (`docker-compose.base.yml:28`) |
| pgBouncer | edoburu/pgbouncer:latest | Connection pooler (transaction mode) in front of Postgres | Already running; `db-migrate` service connects through it (`docker-compose.base.yml:136` `PGHOST=pgbouncer`) |
| `psql` (postgres:15-alpine image) | 15 | Migration runner CLI; `db-migrate` uses it with `-v ON_ERROR_STOP=1` | Same image as `db-migrate` service |
| `schema_migrations` table | n8n DB | Idempotency tracking for the `db-migrate` service | Already implemented (`docker-compose.base.yml:137-152`); Phase 16 migrations must register here |

### CONCURRENTLY / pgBouncer Resolution

`CREATE INDEX CONCURRENTLY` is prohibited inside a transaction block. pgBouncer in `POOL_MODE=transaction` wraps every `psql` invocation in an implicit transaction, making CONCURRENTLY fail with:
```
ERROR:  CREATE INDEX CONCURRENTLY cannot run inside a transaction block
```

**Resolution (HIGH confidence — this is the standard pattern):**

The CONCURRENTLY steps must connect **directly to `postgres:5432`**, bypassing pgBouncer. The `db-migrate` service runs inside the `internal` Docker network alongside `postgres` (`docker-compose.base.yml:65-69,175-177`), so it can reach `postgres:5432` directly. The migration wrapper shell script or a split step sets `PGHOST=postgres PGPORT=5432` only for the CONCURRENTLY commands, while all other `psql` invocations (probe, dedupe, `schema_migrations` INSERT) continue to use `pgbouncer:5432`.

This approach:
- Requires no new service or image
- Does not require disabling pgBouncer
- Follows standard Postgres operational practice for live index builds
- Keeps all other migration steps using the pooled connection

Alternative patterns (rejected for this project):
- `SET local_preload_libraries` / advisory locks within a transaction: does not unblock CONCURRENTLY
- Pausing pgBouncer: zero-downtime violation
- `session_pool_mode` in pgBouncer: requires pgBouncer config change and restart

---

## Architecture Patterns

### Pattern 1: Live-Safe Unique Constraint via CONCURRENTLY + ATTACH

This is the Postgres-standard zero-downtime pattern for adding a unique constraint to a live table.

```sql
-- Source: PostgreSQL 15 official docs — "ALTER TABLE ... USING INDEX"
-- https://www.postgresql.org/docs/15/sql-altertable.html

-- Step 1: Probe (read-only, no locks)
SELECT tenant_id, module_key, COUNT(*)
  FROM tenant_entitlements
  GROUP BY tenant_id, module_key
  HAVING COUNT(*) > 1;

-- Step 2: Dedupe (keep latest activated_at, delete rest) — only if probe finds rows
-- (inside a regular transaction, via pgbouncer:5432)

-- Step 3: CREATE UNIQUE INDEX CONCURRENTLY — NO transaction, direct postgres:5432
-- Takes ShareUpdateExclusiveLock only (reads and DML allowed concurrently)
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_tenant_module_idx
  ON tenant_entitlements (tenant_id, module_key);

-- Step 4: ATTACH — converts the index to a constraint
-- (inside a transaction with lock_timeout, via pgbouncer:5432)
ALTER TABLE tenant_entitlements
  ADD CONSTRAINT uq_tenant_module UNIQUE USING INDEX uq_tenant_module_idx;
-- Takes AccessShareLock briefly at attach time (< 1ms for non-contended tables)
```

The idempotency guard must check BOTH the index name (for re-run after step 3 but before step 4) AND the constraint name (for fully-applied runs).

### Pattern 2: Idempotent Migration Block (DO $$)

```sql
-- Source: existing project pattern, db/migrations/2026-04-06_saas_modules_entitlements.sql:11-19
DO $$
BEGIN
  -- Check index exists (created by CONCURRENTLY in a prior run)
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid
    WHERE c.relname = 'uq_tenant_module_idx'
  ) THEN
    -- Probe + dedupe + CONCURRENTLY happen OUTSIDE this block (see above)
    RAISE NOTICE 'Index uq_tenant_module_idx not found — CONCURRENTLY step must have been skipped';
  END IF;
  -- Attach index as constraint if constraint doesn't already exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_tenant_module'
  ) THEN
    ALTER TABLE tenant_entitlements
      ADD CONSTRAINT uq_tenant_module UNIQUE USING INDEX uq_tenant_module_idx;
  END IF;
END $$;
```

**IMPORTANT:** `CREATE INDEX CONCURRENTLY` cannot run inside a `DO $$` block either (it implicitly starts a transaction). The CONCURRENTLY step must be a bare top-level `CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ...` statement executed outside any transaction or PL/pgSQL block, via direct `psql` to `postgres:5432`.

### Pattern 3: channel_identities Table Design

```sql
-- Source: .planning/research/ARCHITECTURE.md "Pattern 1: Channel-Identity Tenant Resolution"
-- DB target: n8n DB (NOT strapi) — shares FK graph with tenants/restaurants/api_clients
CREATE TABLE IF NOT EXISTS channel_identities (
  channel        text NOT NULL
                 CHECK (channel IN ('whatsapp','instagram','messenger','tiktok','kiosk')),
  identity       text NOT NULL,
  -- WA: phone_number_id | IG/MSG: page recipient.id | kiosk: device_id placeholder
  tenant_id      uuid NOT NULL
                 REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  restaurant_id  uuid NOT NULL
                 REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (channel, identity)
);

CREATE INDEX IF NOT EXISTS idx_channel_identities_tenant
  ON channel_identities (tenant_id);
```

### Recommended Project Structure

```
db/migrations/
├── 2026-04-06_saas_modules_entitlements.sql    # REWRITE IN PLACE (live-safe)
└── 2026-06-20_channel_identities.sql           # NEW: routing table + seed
db/ci-assertions/
├── 15-backfill-tenant-entitlements.sql         # EXISTS (Phase 15)
├── 15-tenant-canonical-key.sql                 # EXISTS (Phase 15)
├── 16-saas-migration-schema-check.sql          # NEW: assert all 6 objects exist
└── 16-channel-identities-check.sql             # NEW: assert table + seed rows
db/ci-fixtures/
└── 16-duplicate-entitlements-fixture.sql       # NEW: seed dup rows to test dup-survival
.github/workflows/
└── phase-16-assertions.yml                     # NEW: ephemeral PG, two-DB test harness
```

### Anti-Patterns to Avoid

- **Bare `ALTER TABLE ... ADD CONSTRAINT UNIQUE`:** Takes `ACCESS EXCLUSIVE` lock; fails outright on duplicate rows. Never use against a live table. (`db/migrations/2026-04-06_saas_modules_entitlements.sql:17` — the current violation.)
- **`CREATE INDEX CONCURRENTLY` inside a `DO $$` block or `BEGIN`/`COMMIT`:** Fails with transaction-block error. Must be a bare top-level statement.
- **Running CONCURRENTLY through pgBouncer transaction mode:** Fails silently or explicitly. Must bypass to `postgres:5432`.
- **Checking only constraint existence in the idempotency guard:** A partially-applied run (CONCURRENTLY done, ATTACH not yet done) leaves the index without a constraint; a second run that skips the CONCURRENTLY step then tries to ATTACH a non-existent index. Both index AND constraint existence must be checked.
- **Seeding `channel_identities` with hardcoded VPS values:** The real `WA_PHONE_NUMBER_ID`, `IG_PAGE_ID`, `MESSENGER_PAGE_ID` are operator-supplied secrets not in the repo. CI/dev seed uses placeholder values; the 🔴 VPS seed must read from `platform_settings` or the operator's `.env`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Zero-downtime unique constraint on live table | Custom lock-management or application-layer dedupe | `CREATE UNIQUE INDEX CONCURRENTLY` + `ALTER TABLE ... USING INDEX` | PG15 native; ShareUpdateExclusiveLock only; guaranteed safe for concurrent reads/writes |
| Migration idempotency | Timestamp-based versioning or `IF EXISTS` on every line | `schema_migrations` table (already present) + `IF NOT EXISTS` / `DO $$`-guarded DDL | Already implemented in `db-migrate` service; pattern proven in Phase 15 |
| Duplicate detection | Application-layer dedup-scan before migration | `SELECT ... GROUP BY ... HAVING COUNT(*) > 1` probe SQL | Atomic, read-only, zero-impact probe; catches concurrent-write duplicates the app layer misses |
| FK validation for channel routing | Custom lookup/validation in n8n code | `REFERENCES tenants(tenant_id)` + `REFERENCES restaurants(restaurant_id)` FKs in DDL | DB enforces referential integrity; prevents orphaned routing rows at the storage layer |

---

## Current State of `db/migrations/2026-04-06_saas_modules_entitlements.sql`

Full file read: `db/migrations/2026-04-06_saas_modules_entitlements.sql` (58 lines).

### What the file does (current, unsafe state)

| Lines | Object | Problem |
|-------|--------|---------|
| 11-19 | `uq_tenant_module UNIQUE (tenant_id, module_key)` on `tenant_entitlements` | `ALTER TABLE ... ADD CONSTRAINT` — takes `ACCESS EXCLUSIVE` lock; **fails if any duplicate `(tenant_id,module_key)` rows exist** |
| 22-23 | `idx_entitlements_tenant` on `tenant_entitlements(tenant_id)` | `CREATE INDEX IF NOT EXISTS` — safe (non-unique, no issue) |
| 26-27 | `idx_entitlements_module` on `tenant_entitlements(module_key)` | `CREATE INDEX IF NOT EXISTS` — safe |
| 30-31 | `idx_entitlements_active` on `tenant_entitlements(tenant_id,enabled) WHERE enabled=true` | `CREATE INDEX IF NOT EXISTS` — safe |
| 34-42 | `uq_product_module_key UNIQUE (key)` on `product_modules` | Same pattern — `ALTER TABLE ... ADD CONSTRAINT` with `DO $$` IF-NOT-EXISTS guard; **fails on duplicate `key` rows** |
| 45-54 | `entitlement_audit_log` table | `CREATE TABLE IF NOT EXISTS` — safe, idempotent |
| 56-57 | `idx_entitlement_audit_tenant` on `entitlement_audit_log(tenant_id, created_at DESC)` | `CREATE INDEX IF NOT EXISTS` — safe |

### Which DB this file targets

**STRAPI DB** — `tenant_entitlements` and `product_modules` are Strapi-auto-created tables in the `strapi` database. This migration is applied to the `strapi` DB, NOT the n8n DB.

Confirmed by:
- `docs/adr/0001-canonical-tenant-key.md:24-29`: "Entitlement plane (strapi DB) — Strapi-managed"
- `db/init/02_create_strapi_db.sh`: creates the `strapi` DB and `strapi` user
- `.planning/research/ARCHITECTURE.md:46`: `strapi DB: product_modules, tenant_entitlements (+ uq_tenant_module ◆)`

### The idempotency gap in the current `DO $$` guard

The existing guard (`db/migrations/2026-04-06_saas_modules_entitlements.sql:12-18`) checks:
```sql
IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_tenant_module') THEN
  ALTER TABLE tenant_entitlements ADD CONSTRAINT uq_tenant_module UNIQUE (tenant_id, module_key);
END IF;
```

**Gap 1:** Does NOT check for duplicate rows before attempting the constraint. If duplicates exist, the `ALTER TABLE` fails regardless of the `IF NOT EXISTS` guard.

**Gap 2:** Does NOT use CONCURRENTLY — takes `ACCESS EXCLUSIVE` lock on `tenant_entitlements` during the constraint build, blocking all concurrent reads and writes.

**Gap 3:** No `lock_timeout` or `statement_timeout` — a concurrent long-running query can cause the `ACCESS EXCLUSIVE` lock to queue indefinitely, stalling the table for all subsequent requests.

---

## The CONCURRENTLY-vs-pgBouncer Resolution (Critical Finding)

### The constraint

`docker-compose.base.yml:89`: `POOL_MODE=transaction` — pgBouncer assigns a server connection only for the duration of a client transaction, then returns it to the pool.

`docker-compose.base.yml:136-152`: The `db-migrate` service's `command` uses `psql -h pgbouncer -v ON_ERROR_STOP=1` for all statements.

`CREATE INDEX CONCURRENTLY` must NOT run inside a transaction block. pgBouncer's transaction-pooling mode means every `psql` session is implicitly treated as a transaction scope by pgBouncer — but the critical constraint is that `CONCURRENTLY` specifically requires a **non-transactional session** at the Postgres level.

### The resolution

**Connect directly to `postgres:5432` for CONCURRENTLY steps only.** The `db-migrate` service is on the `internal` network alongside `postgres` (`docker-compose.base.yml:68,176-177`). The direct `postgres` hostname resolves inside that network. The `db-migrate` service already has the password via `/run/secrets/postgres_password`.

Implementation in the migration shell wrapper or a dedicated step:

```bash
# All regular steps: via pgbouncer (pooled, transactional)
psql -h pgbouncer -U n8n -d strapi -v ON_ERROR_STOP=1 < probe_and_dedupe.sql

# CONCURRENTLY step: direct to postgres (bypasses pooler, no implicit transaction)
PGHOST=postgres PGPORT=5432 psql -U n8n -d strapi -v ON_ERROR_STOP=1 \
  -c "CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_tenant_module_idx ON tenant_entitlements (tenant_id, module_key);"

# Attach step: via pgbouncer again (short DDL, safe through pooler)
psql -h pgbouncer -U n8n -d strapi -v ON_ERROR_STOP=1 < attach_and_register.sql
```

**Why this is safe:**
- The `postgres` service is on the `internal` network at a fixed hostname
- `db-migrate` is `restart: "no"` — it runs once at startup before any application traffic
- `postgres` max_connections=200 (`docker-compose.base.yml:43`) — one direct connection for a migration step is trivially safe
- The direct connection is used only for the CONCURRENTLY statement (seconds to minutes); all other DDL uses pgbouncer

**Alternative — separate migration phase file for CONCURRENTLY:**

Split the migration into two SQL files:
1. `2026-04-06_saas_modules_entitlements_prep.sql` — probe, dedupe, non-CONCURRENTLY-requiring DDL (via pgbouncer)
2. `2026-04-06_saas_modules_entitlements_concurrently.sql` — CONCURRENTLY index build + attach (invoked with `PGHOST=postgres` in the shell script)

This keeps SQL files pure and puts the connection-routing logic in the shell wrapper (`db/init/01_apply_migrations.sh` or a Phase 16 variant).

**Chosen approach for this research:** A single rewritten `2026-04-06_saas_modules_entitlements.sql` with the CONCURRENTLY step split into a companion shell invocation that sets `PGHOST=postgres`. The `01_apply_migrations.sh` (which runs at first boot) already runs `psql` per file — it can detect `_concurrently.sql` suffix or the Phase 16 plan can introduce a second pass. The planner should choose the simplest mechanical split.

---

## channel_identities: Design Decisions

### DB target: n8n DB (confirmed HIGH confidence)

Source: `.planning/research/ARCHITECTURE.md:109`:
> "`channel_identities` in the n8n DB (not strapi): tenant resolution happens inside n8n adapters that already hold a `postgres-main` credential to the n8n DB (where `tenants`/`restaurants`/`api_clients` already live, `db/bootstrap.sql:48-114`). Putting the routing table there avoids a cross-DB hop and reuses the existing FK graph (`REFERENCES tenants(tenant_id)`)."

`tenants`, `restaurants`, `api_clients` all live in the n8n DB (`db/bootstrap.sql:48-114`). FKs from `channel_identities(tenant_id)` to `tenants(tenant_id)` and `channel_identities(restaurant_id)` to `restaurants(restaurant_id)` are valid only in the n8n DB.

The `db-migrate` service connects to n8n DB by default (`docker-compose.base.yml:159-163`: `PGDATABASE: n8n`, `PGHOST: pgbouncer`). The `channel_identities` migration runs against this default — no DB-switching needed.

### Column design (confirmed HIGH confidence)

Source: `.planning/research/ARCHITECTURE.md:123-132`

```sql
channel        text NOT NULL CHECK (channel IN ('whatsapp','instagram','messenger','tiktok','kiosk'))
identity       text NOT NULL      -- WA phone_number_id | IG/MSG page recipient.id | kiosk device_id
tenant_id      uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE
restaurant_id  uuid NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE
is_active      boolean NOT NULL DEFAULT true
PRIMARY KEY    (channel, identity)
```

`REQUIREMENTS.md:16` explicitly lists: "WhatsApp `phone_number_id`, Instagram/Messenger `recipient_id`/page id, kiosk device id".

### Seed values source (MEDIUM confidence — operator-supplied)

The real identity values are NOT hardcoded in the repo. They are operator-supplied and stored in `platform_settings` (n8n DB, seeded empty by `db/migrations/011_platform_settings_seed.sql:45,51,56`):

| Channel | `platform_settings.key` | Value in repo seed | CI/dev status |
|---------|------------------------|--------------------|---------------|
| WhatsApp | `WA_PHONE_NUMBER_ID` | `''` (empty) | Placeholder |
| Instagram | `IG_PAGE_ID` | `''` (empty) | Placeholder |
| Messenger | `MESSENGER_PAGE_ID` | `''` (empty) | Placeholder |
| Kiosk | (no `platform_settings` key) | n/a | Device-ID-as-text placeholder |

Also confirmed via `config/.env.example:268`: `WA_PHONE_NUMBER_ID=   # [REQUIRED for production]`; `config/.env.example:276`: `IG_PAGE_ID=`; `config/.env.example:284`: `MSG_PAGE_ID=`.

**CI/dev seed strategy:** Seed with placeholder / CI-sentinel values:

```sql
INSERT INTO channel_identities (channel, identity, tenant_id, restaurant_id) VALUES
  ('whatsapp',  'CI_WA_PHONE_NUMBER_ID',  '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000'),
  ('instagram', 'CI_IG_PAGE_ID',           '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000'),
  ('messenger', 'CI_MSG_PAGE_ID',          '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000'),
  ('kiosk',     'CI_KIOSK_DEVICE_ID',      '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000')
ON CONFLICT (channel, identity) DO NOTHING;
```

CI seed UUIDs: `tenant_id = '00000000-0000-0000-0000-000000000001'`, `restaurant_id = '00000000-0000-0000-0000-000000000000'` — the canonical CI/dev seed rows from `db/bootstrap.sql:2510-2533`.

**VPS seed: 🔴 DEFERRED.** On production the planner must:
1. Read `WA_PHONE_NUMBER_ID` from `platform_settings WHERE key = 'WA_PHONE_NUMBER_ID'`
2. Read `IG_PAGE_ID` from `platform_settings WHERE key = 'IG_PAGE_ID'`
3. Read `MESSENGER_PAGE_ID` from `platform_settings WHERE key = 'MESSENGER_PAGE_ID'`
4. Discover the real tenant UUID via `SELECT tenant_id FROM tenants LIMIT 1` (n8n DB) — NEVER hardcode the CI UUID
5. Discover the real restaurant UUID via `SELECT restaurant_id FROM restaurants WHERE tenant_id = $real_tenant LIMIT 1`
6. INSERT using those runtime-discovered values

---

## db-migrate Wiring

### How the service works (from docker-compose.base.yml:132-177)

The `db-migrate` service:
- Image: `postgres:15-alpine` (same as DB — has `psql` available)
- Command: inline shell script that:
  1. Reads password from `/run/secrets/postgres_password`
  2. Waits for pgBouncer (`pg_isready -h pgbouncer`)
  3. Creates `schema_migrations` table if not exists (via pgbouncer, n8n DB)
  4. Lists applied migrations from `schema_migrations`
  5. For each `.sql` file in `/migrations/` (sorted alphabetically): if not already in `schema_migrations`, applies it via `psql -h pgbouncer -v ON_ERROR_STOP=1 < "$migration"`, then inserts the filename into `schema_migrations`
- Volumes: `./db/migrations:/migrations:ro`
- Environment: `PGDATABASE: n8n` — default target is n8n DB
- `restart: "no"` — runs once per `docker compose up`
- `depends_on: pgbouncer: condition: service_started`

### How Phase 16 migrations integrate

**`2026-06-20_channel_identities.sql`** (n8n DB):
- Standard SQL file in `db/migrations/`; auto-picked up by `db-migrate` service
- Uses `CREATE TABLE IF NOT EXISTS` + `INSERT ... ON CONFLICT DO NOTHING` — fully idempotent
- No CONCURRENTLY needed (new table, no live-data risk)
- Connected via `pgbouncer:5432` (default) — safe

**`2026-04-06_saas_modules_entitlements.sql`** (STRAPI DB):
- The file targets the STRAPI DB — but `db-migrate` service connects to n8n DB by default
- **DB-switching issue:** The current migration applies to Strapi tables (`tenant_entitlements`, `product_modules`) but the `db-migrate` service runs as `PGDATABASE: n8n`. This is a gap: if `db-migrate` applies this file to n8n DB, the tables won't exist and it will error.
- **Resolution:** The migration shell command or a separate CI step must pass `-d strapi` for this specific migration. The Phase 16 plan must account for this: either (a) the migration's `DO $$` block connects to the strapi DB explicitly (not possible in psql without reconnecting), or (b) a separate migration-apply wrapper script passes `PGDATABASE=strapi` when processing files targeting the strapi DB, or (c) the migration file is placed outside `db/migrations/` (e.g., `db/migrations-strapi/`) and applied by a separate step.

**Recommended resolution:** Introduce a convention of a dedicated `strapi-migrate` one-shot service (or a second pass in the existing `db-migrate` command) that applies `db/migrations-strapi/*.sql` with `PGDATABASE=strapi`. This mirrors the two-DB structure (n8n DB vs strapi DB) and prevents accidental cross-DB application.

Alternatively: add the strapi migration to a separate path and invoke `psql -h postgres -U n8n -d strapi` directly (bypassing pgBouncer AND targeting strapi DB) since the CONCURRENTLY step already requires a direct connection to `postgres:5432`. This is the most compact solution for Phase 16.

### `schema_migrations` tracking for strapi-DB migrations

The `schema_migrations` table exists in the n8n DB (that's where `db-migrate` creates it). For strapi-DB migrations, the Phase 16 plan must decide: track them in the n8n `schema_migrations` table (cross-DB tracking) or create a separate `schema_migrations` in the strapi DB. The simplest approach (no new infra) is to track strapi-DB migration filenames in the same n8n `schema_migrations` table, since that table is already the authoritative migration ledger.

---

## Common Pitfalls

### Pitfall 1: `ALTER TABLE ... ADD CONSTRAINT` on live table with duplicates
**What goes wrong:** Fails outright with `could not create unique index ... Key (tenant_id, module_key) is duplicated`. The constraint attempt takes `ACCESS EXCLUSIVE` lock during its build, blocking all concurrent reads/writes for the duration.
**Why it happens:** Current migration `db/migrations/2026-04-06_saas_modules_entitlements.sql:17` uses bare `ADD CONSTRAINT`, only guarded on constraint-name existence — not on duplicate row existence.
**How to avoid:** Read-only probe before any DDL; dedupe (keep latest `activated_at`); then `CREATE UNIQUE INDEX CONCURRENTLY`.
**Warning signs:** `ERROR: could not create unique index "uq_tenant_module"`, migration passes CI but fails on VPS, entitlement reads hang during apply.

### Pitfall 2: Running `CREATE INDEX CONCURRENTLY` through pgBouncer transaction mode
**What goes wrong:** `ERROR: CREATE INDEX CONCURRENTLY cannot run inside a transaction block`
**Why it happens:** `docker-compose.base.yml:89`: `POOL_MODE=transaction` — pgBouncer wraps each client session in a transaction scope.
**How to avoid:** Connect directly to `postgres:5432` for the CONCURRENTLY statement only.
**Warning signs:** Error during migration apply; index not created; migration may mark as applied in `schema_migrations` even if CONCURRENTLY fails (depending on error handling).

### Pitfall 3: Idempotency guard doesn't account for partial application
**What goes wrong:** A run that completed CONCURRENTLY but crashed before ATTACH leaves an index (`uq_tenant_module_idx`) but no constraint (`uq_tenant_module`). A re-run that only checks the constraint tries to build the index again with CONCURRENTLY — which fails because the index already exists (without `IF NOT EXISTS`) or succeeds but the ATTACH then fails for a different reason.
**How to avoid:** Use `CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS` (idempotent index creation); check constraint existence separately from index existence in the ATTACH guard.

### Pitfall 4: Seeding `channel_identities` with hardcoded VPS values
**What goes wrong:** Real `WA_PHONE_NUMBER_ID` values committed to the repo are visible in git history; the values rotate; the seed SQL is wrong for staging vs production.
**How to avoid:** CI/dev seed uses CI-sentinel placeholder values (`CI_WA_PHONE_NUMBER_ID`, etc.); VPS seed discovers real values from `platform_settings` at runtime.

### Pitfall 5: Applying the strapi-DB migration via the n8n-DB-defaulting `db-migrate` service
**What goes wrong:** `db-migrate` connects to n8n DB (`PGDATABASE: n8n`); `tenant_entitlements` does not exist in the n8n DB; the migration errors with `relation "tenant_entitlements" does not exist`.
**How to avoid:** The strapi-DB migration must be applied with an explicit `-d strapi` switch (separate step, separate service, or a shell conditional in the migration wrapper).

---

## Code Examples

### Idempotent duplicate probe (strapi DB)

```sql
-- Source: recommended pattern per PITFALLS.md, verified against PG15 catalog
-- Run via: psql -h postgres -U n8n -d strapi -v ON_ERROR_STOP=1

DO $$
DECLARE
  v_dup_count integer;
BEGIN
  SELECT COUNT(*) INTO v_dup_count
    FROM (
      SELECT tenant_id, module_key, COUNT(*)
        FROM tenant_entitlements
       GROUP BY tenant_id, module_key
      HAVING COUNT(*) > 1
    ) dups;
  IF v_dup_count > 0 THEN
    RAISE NOTICE 'PROBE: % duplicate (tenant_id,module_key) groups found — dedupe required before CONCURRENTLY', v_dup_count;
  ELSE
    RAISE NOTICE 'PROBE: no duplicates found in tenant_entitlements — safe to proceed with CONCURRENTLY';
  END IF;
END $$;
```

### Dedupe step (keep latest activated_at)

```sql
-- Source: recommended pattern from PITFALLS.md "dedupe (keep latest activated_at)"
-- Run via: psql -h pgbouncer -U n8n -d strapi -v ON_ERROR_STOP=1

DELETE FROM tenant_entitlements
WHERE id NOT IN (
  SELECT DISTINCT ON (tenant_id, module_key) id
    FROM tenant_entitlements
   ORDER BY tenant_id, module_key, activated_at DESC NULLS LAST, id DESC
);
```

### CONCURRENTLY index creation (direct to postgres, no transaction)

```bash
# Must run OUTSIDE a transaction block; connect direct to postgres (bypass pgBouncer)
PGPASSWORD=$(cat /run/secrets/postgres_password) \
psql -h postgres -p 5432 -U n8n -d strapi -v ON_ERROR_STOP=1 \
  -c "CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_tenant_module_idx ON tenant_entitlements (tenant_id, module_key);"
```

### ATTACH step (constraint from index, with timeouts)

```sql
-- Source: PostgreSQL 15 docs — ALTER TABLE ... USING INDEX
-- Run via: psql -h pgbouncer -U n8n -d strapi -v ON_ERROR_STOP=1

SET lock_timeout = '5s';
SET statement_timeout = '120s';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_tenant_module'
  ) THEN
    ALTER TABLE tenant_entitlements
      ADD CONSTRAINT uq_tenant_module UNIQUE USING INDEX uq_tenant_module_idx;
    RAISE NOTICE 'APPLIED: uq_tenant_module constraint attached from index';
  ELSE
    RAISE NOTICE 'SKIP: uq_tenant_module constraint already exists';
  END IF;
END $$;
```

### channel_identities migration (n8n DB, full idempotent)

```sql
-- Source: ARCHITECTURE.md Pattern 1, adapted with CI seed values
-- File: db/migrations/2026-06-20_channel_identities.sql
-- Target: n8n DB (db-migrate default PGDATABASE=n8n)

SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE TABLE IF NOT EXISTS channel_identities (
  channel        text        NOT NULL
                             CHECK (channel IN ('whatsapp','instagram','messenger','tiktok','kiosk')),
  identity       text        NOT NULL,
  tenant_id      uuid        NOT NULL REFERENCES tenants(tenant_id)      ON DELETE CASCADE,
  restaurant_id  uuid        NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  is_active      boolean     NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (channel, identity)
);

CREATE INDEX IF NOT EXISTS idx_channel_identities_tenant
  ON channel_identities (tenant_id);

-- CI/dev seed: placeholder identity values; real values discovered at VPS apply time
INSERT INTO channel_identities (channel, identity, tenant_id, restaurant_id)
VALUES
  ('whatsapp',  'CI_WA_PHONE_NUMBER_ID',  '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000'),
  ('instagram', 'CI_IG_PAGE_ID',           '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000'),
  ('messenger', 'CI_MSG_PAGE_ID',          '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000'),
  ('kiosk',     'CI_KIOSK_DEVICE_ID',      '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000')
ON CONFLICT (channel, identity) DO NOTHING;
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ALTER TABLE ... ADD CONSTRAINT UNIQUE` on live table | `CREATE UNIQUE INDEX CONCURRENTLY` + `ALTER TABLE ... USING INDEX` | PG 9.2+ (CONCURRENTLY), PG 12+ (USING INDEX pattern) | No exclusive lock during index build; only brief lock at ATTACH |
| Apply migration through connection pooler | Bypass pooler (direct to Postgres) for CONCURRENTLY | Standard operational practice | Required for transaction-pooling pgBouncer |
| Idempotency via `IF NOT EXISTS` on constraint only | Check both index AND constraint existence; separate probe for duplicate rows | Phase 16 design | Handles partial-apply recovery correctly |

**Deprecated/outdated in this project:**
- `ALTER TABLE ... ADD CONSTRAINT UNIQUE` (lines 17, 41 in `db/migrations/2026-04-06_saas_modules_entitlements.sql`): must be replaced with CONCURRENTLY pattern
- `DO $$` guard that checks only `pg_constraint.conname` (line 13-14): insufficient — also check `pg_index` for partial-apply state

---

## VPS-Deferred Boundary

| Step | Local/CI | 🔴 VPS Deferred |
|------|----------|----------------|
| Rewrite migration SQL file | Local (author) | — |
| CI assertion: migration idempotent on clean DB | CI (ephemeral PG) | — |
| CI assertion: migration survives seeded duplicates | CI (ephemeral PG) | — |
| CI assertion: `channel_identities` table + CI seed rows exist | CI (ephemeral PG) | — |
| CI assertion: all 6 SaaS objects exist after apply | CI (ephemeral PG) | — |
| Apply rewritten migration to live VPS Postgres (strapi DB) | — | 🔴 prod-connected session |
| Apply `channel_identities` migration to live VPS Postgres (n8n DB) | — | 🔴 prod-connected session |
| Seed `channel_identities` with real `WA_PHONE_NUMBER_ID` / `IG_PAGE_ID` / `MESSENGER_PAGE_ID` (discovered from live `platform_settings`) | — | 🔴 prod-connected session |
| Discover real VPS tenant UUID and restaurant UUID before seeding | — | 🔴 prod-connected session |

---

## Validation Architecture

> `workflow.nyquist_validation = true` in `.planning/config.json` — section REQUIRED.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `psql` + `DO $$ ... RAISE EXCEPTION` pattern (established in Phase 15) |
| Config file | `.github/workflows/phase-16-assertions.yml` (new, extends Phase 15 pattern) |
| Quick run command | `psql -h localhost -U n8n -d strapi/n8n -v ON_ERROR_STOP=1 -f db/ci-assertions/16-*.sql` |
| Full suite command | Full `phase-16-assertions.yml` GitHub Actions job (ephemeral PG, two DBs) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DB-01 | All 6 SaaS objects exist in strapi DB after migration apply | SQL assertion | `psql -d strapi -f db/ci-assertions/16-saas-migration-schema-check.sql` | ❌ Wave 0 |
| DB-01 | Migration survives pre-seeded duplicate entitlement rows (does not error) | SQL fixture + migration rerun | `psql -d strapi -f db/ci-fixtures/16-duplicate-entitlements-fixture.sql && psql -d strapi ... (migration)` | ❌ Wave 0 |
| DB-01 | Migration is idempotent (re-run = no-op, no error) | SQL rerun | Apply migration twice; assert no error on second run | ❌ Wave 0 |
| DB-01 | `uq_tenant_module` prevents inserting a duplicate `(tenant_id, module_key)` row | SQL constraint test | `INSERT INTO tenant_entitlements ... ON CONFLICT` test in assertion file | ❌ Wave 0 |
| DB-01 | No `ACCESS EXCLUSIVE` lock taken during index build (CONCURRENTLY verify) | SQL catalog check | `SELECT * FROM pg_index WHERE indexrelid = 'uq_tenant_module_idx'::regclass` — asserts index `indisunique` and `indisready` | ❌ Wave 0 |
| TEN-02 | `channel_identities` table exists in n8n DB | SQL assertion | `psql -d n8n -f db/ci-assertions/16-channel-identities-check.sql` | ❌ Wave 0 |
| TEN-02 | CI seed rows exist for all 4 channels (whatsapp/instagram/messenger/kiosk) | SQL assertion | `SELECT COUNT(*) FROM channel_identities` asserts 4 rows | ❌ Wave 0 |
| TEN-02 | `channel_identities` FK to `tenants` and `restaurants` is enforced | SQL constraint test | Attempt INSERT with non-existent `tenant_id`; expect FK violation | ❌ Wave 0 |
| TEN-02 | Migration idempotent (re-run = no-op) | SQL rerun | Apply `2026-06-20_channel_identities.sql` twice; assert 4 rows still = 4 | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** Run `psql -v ON_ERROR_STOP=1 -f db/ci-assertions/16-*.sql` against a local ephemeral Postgres
- **Per wave merge:** Full `phase-16-assertions.yml` CI job
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps (files to create before implementation)

- [ ] `db/ci-fixtures/16-duplicate-entitlements-fixture.sql` — seeds `tenant_entitlements` with duplicate `(tenant_id, module_key)` rows to prove dup-survival
- [ ] `db/ci-assertions/16-saas-migration-schema-check.sql` — asserts: `uq_tenant_module` constraint exists, `idx_entitlements_tenant` exists, `idx_entitlements_module` exists, `idx_entitlements_active` exists, `uq_product_module_key` exists, `entitlement_audit_log` table exists, `idx_entitlement_audit_tenant` exists
- [ ] `db/ci-assertions/16-channel-identities-check.sql` — asserts: `channel_identities` table exists, 4 seed rows present, FK constraints active, `(channel, identity)` PK enforced
- [ ] `.github/workflows/phase-16-assertions.yml` — two-service GitHub Actions job (postgres n8n DB + postgres strapi DB), applying migrations and running assertions; extends `phase-15-assertions.yml` pattern

---

## Open Questions

1. **Strapi-DB migration delivery mechanism**
   - What we know: `db-migrate` defaults to n8n DB (`PGDATABASE: n8n`); `2026-04-06_saas_modules_entitlements.sql` targets strapi DB tables; the current `01_apply_migrations.sh` does not switch DBs per file
   - What's unclear: Whether to (a) add a second pass in `db-migrate` command for strapi-targeted files, (b) introduce a `strapi-migrate` service, or (c) apply via a separate one-shot script
   - Recommendation: Plan 16-03 should introduce a second volume mount + pass in the `db-migrate` command that applies `db/migrations-strapi/*.sql` with `PGDATABASE=strapi`. Move `2026-04-06_saas_modules_entitlements.sql` to `db/migrations-strapi/`. Keeps the two-DB structure explicit.

2. **`schema_migrations` table placement for strapi-DB migrations**
   - What we know: `schema_migrations` exists in n8n DB only
   - What's unclear: Track strapi-DB filenames in n8n `schema_migrations` (cross-DB tracking but one table) or create a separate `schema_migrations` in strapi DB
   - Recommendation: Create `schema_migrations` in the strapi DB too (idempotent `CREATE TABLE IF NOT EXISTS`, done as the first step of the strapi-migrate pass). Keeps tracking co-located with the migrations it tracks.

3. **`is_active` column in `channel_identities`**
   - What we know: ARCHITECTURE.md includes `is_active boolean NOT NULL DEFAULT true`
   - What's unclear: Whether Phase 17 (the consumer) uses `is_active` for soft-disable, or if it's premature optimization for Phase 16
   - Recommendation: Include `is_active` in Phase 16 DDL (additive, zero cost); Phase 17 adds `AND is_active = true` to the resolution query. Avoids a DDL migration in Phase 17.

---

## Sources

### Primary (HIGH confidence)

- `db/migrations/2026-04-06_saas_modules_entitlements.sql` (direct read, all 58 lines) — current state: unsafe `ALTER TABLE ADD CONSTRAINT`, no dup-probe, no CONCURRENTLY
- `docker-compose.base.yml:89,132-177` — pgBouncer `POOL_MODE=transaction`; `db-migrate` service command, environment (`PGDATABASE: n8n`), volumes
- `db/init/01_apply_migrations.sh` — migration runner: `psql -h pgbouncer -v ON_ERROR_STOP=1 < "$migration"`, no DB-switching logic
- `db/init/02_create_strapi_db.sh` — confirms strapi DB is a separate database with separate `strapi` user
- `db/bootstrap.sql:48-114,2510-2533` — `tenants`, `restaurants`, `api_clients` tables in n8n DB; canonical CI/dev seed UUIDs
- `docs/adr/0001-canonical-tenant-key.md` — confirms strapi DB target for entitlement plane; canonical UUID `00000000-0000-0000-0000-000000000001`; restaurant UUID `00000000-0000-0000-0000-000000000000`; VPS caveat
- `.github/workflows/phase-15-assertions.yml` — CI assertion pattern to extend (service: postgres:15-alpine, `ON_ERROR_STOP=1`, `RAISE EXCEPTION` assertions)
- `db/ci-assertions/15-backfill-tenant-entitlements.sql`, `db/ci-assertions/15-tenant-canonical-key.sql` — Phase 15 assertion patterns to reuse
- `.planning/phases/15-tenant-identity-model-canonical-key/15-VERIFICATION.md` — Phase 15 COMPLETE; keystone confirmed
- `.planning/research/ARCHITECTURE.md:109-131` — `channel_identities` design: n8n DB, columns, FK pattern
- `.planning/research/PITFALLS.md:91-105` — live constraint pitfall: probe + CONCURRENTLY + lock_timeout
- `db/migrations/011_platform_settings_seed.sql:45,51,56` — `WA_PHONE_NUMBER_ID`, `IG_PAGE_ID`, `MESSENGER_PAGE_ID` keys seeded empty — confirms seed values are operator-supplied
- `config/.env.example:268,276,284` — confirms `WA_PHONE_NUMBER_ID`, `IG_PAGE_ID`, `MSG_PAGE_ID` are `[REQUIRED for production]` but empty in template
- `.planning/config.json` — `workflow.nyquist_validation: true`

### Secondary (MEDIUM confidence)

- PostgreSQL 15 documentation — `CREATE INDEX CONCURRENTLY` cannot run inside a transaction block; `ALTER TABLE ... ADD CONSTRAINT ... USING INDEX` pattern for zero-downtime constraint promotion
- pgBouncer documentation — `transaction` pool mode; `CONCURRENTLY` incompatibility
- `.planning/research/SUMMARY.md` — milestone-level confirmation of CONCURRENTLY pattern and pgBouncer caveat (cross-researcher finding)

---

## Metadata

**Confidence breakdown:**
- Current migration state: HIGH — read the file directly (all 58 lines)
- CONCURRENTLY/pgBouncer constraint: HIGH — confirmed in docker-compose.base.yml (`POOL_MODE=transaction`, `PGHOST=pgbouncer` in db-migrate command) + PG15 docs
- channel_identities DB target: HIGH — confirmed by ADR 0001, ARCHITECTURE.md, bootstrap.sql FK graph
- channel_identities seed source: MEDIUM — `platform_settings` empty-string seeds confirmed; real VPS values are operator-supplied secrets
- db-migrate wiring mechanism: HIGH — read the full command (lines 132-152 of docker-compose.base.yml)
- Strapi-DB migration delivery gap: HIGH (gap confirmed) / MEDIUM (resolution options)

**Research date:** 2026-06-20
**Valid until:** 2026-07-20 (stable stack, no major version changes; pgBouncer mode won't change)

---

## RESEARCH COMPLETE

**Phase:** 16 — Live-Safe SaaS Migration + Channel Routing Table
**Confidence:** HIGH

### Key Findings

- **The current migration is doubly unsafe:** `db/migrations/2026-04-06_saas_modules_entitlements.sql:17` uses bare `ALTER TABLE ... ADD CONSTRAINT UNIQUE` which (a) takes `ACCESS EXCLUSIVE` lock and (b) fails outright on pre-existing duplicate rows. The `DO $$` guard checks only constraint-name existence, not duplicate-row existence.

- **The CONCURRENTLY/pgBouncer resolution is clear:** `docker-compose.base.yml:89` sets `POOL_MODE=transaction`; `CREATE INDEX CONCURRENTLY` cannot run inside a transaction block. The fix is to bypass pgBouncer for the CONCURRENTLY statement only by connecting directly to `postgres:5432` (which `db-migrate` can reach from the `internal` network). All other steps continue using `pgbouncer:5432`.

- **`channel_identities` belongs in the n8n DB:** FKs to `tenants(tenant_id)` and `restaurants(restaurant_id)` are valid only in the n8n DB (where those tables live, per `db/bootstrap.sql:48-114`). n8n inbound adapters already hold a `postgres-main` credential to this DB — no new credential required.

- **Seed values are operator-supplied, not hardcoded:** `WA_PHONE_NUMBER_ID`, `IG_PAGE_ID`, and `MESSENGER_PAGE_ID` are all seeded as empty strings in `db/migrations/011_platform_settings_seed.sql:45,51,56`. CI/dev seed uses sentinel placeholder values; the 🔴 VPS seed must discover real values from `platform_settings` at runtime (same pattern as the Phase 15 tenant UUID VPS discovery caveat in `docs/adr/0001-canonical-tenant-key.md`).

- **The strapi-DB migration delivery is a new gap:** The `db-migrate` service targets n8n DB by default (`PGDATABASE: n8n` in `docker-compose.base.yml:160`). The SaaS migration targets strapi DB tables. Plan 16-03 must introduce a strapi-DB migration pass (either a second volume/pass in `db-migrate` command, a new `strapi-migrate` service, or a `db/migrations-strapi/` directory with a separate apply step).

- **The Phase 15 CI assertion pattern (`phase-15-assertions.yml` + `DO $$ RAISE EXCEPTION` + `ON_ERROR_STOP=1`) is directly reusable** for Phase 16's four assertion types: schema-presence check, idempotency re-run, dup-survival (fixture + migration), and `channel_identities` existence/seed check.
