# ADR 0001: Canonical Tenant Key — tenants.tenant_id (UUID)

**Status:** Accepted
**Date:** 2026-06-20
**Phase:** 15
**Requirement:** TEN-01

---

## Context

The platform has two structurally disjoint `tenant_id` systems in the same Postgres instance that
have never been reconciled:

**Data plane (n8n DB)** — already correct, uses `uuid` type with FK enforcement:

- `tenants.tenant_id uuid PRIMARY KEY DEFAULT gen_random_uuid()` (`db/schema.sql:9-10`)
- `orders.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE` (`db/schema.sql:99`)
- `restaurants.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE` (`db/bootstrap.sql:86-87`)
- `api_clients.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id)` (`db/bootstrap.sql:106-107`)
- `conversation_state.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id)` (`db/bootstrap.sql:160-163`)
- `outbound_messages.tenant_id uuid NOT NULL REFERENCES tenants(tenant_id)` (`db/bootstrap.sql:284-285`)

**Entitlement plane (strapi DB)** — Strapi-managed, currently holds the literal string `'default'`:

- `tenant_entitlements.tenant_id` — Strapi-created VARCHAR column (no FK to `tenants`), currently
  seeded with the literal string `'default'` by the Strapi bootstrap seeder.
- `entitlement_audit_log.tenant_id VARCHAR(255) NOT NULL` — created by the SaaS migration
  (`db/migrations/2026-04-06_saas_modules_entitlements.sql:47`), no FK, no writers yet.

**The failure mode:** Comparing `'default'` against a `uuid` column throws
`invalid input syntax for type uuid: "default"` or silently returns zero rows. Any guard or workflow
that attempts to join or compare these two planes on `tenant_id` will fail without intervention.

---

## Decision

`tenants.tenant_id` (UUID) is the **single system of record** and canonical tenant key for the entire
platform.

The entitlement plane stores the **same UUID in string form** in its existing `VARCHAR(255)` columns.
No `ALTER TABLE` is required in Phase 15 — Option A (store UUID-as-string) is chosen over Option B
(migrate column type to `uuid`) because it requires no schema change, no exclusive lock, and no
Strapi content-type update in Phase 15.

The canonical UUID for the first (and currently only) tenant in **CI/dev** is:

```
00000000-0000-0000-0000-000000000001
```

This is seeded by `db/bootstrap.sql:2510-2517` (tenant: `'Default Chain'`, slug: `'default-chain'`,
plan: `'professional'`) with associated `restaurant_id = '00000000-0000-0000-0000-000000000000'`
(`db/bootstrap.sql:2518-2533`).

---

## Reconciliation: 1:1 Mapping

**Option A (chosen for Phase 15):** Store the UUID-as-string in the existing `VARCHAR(255)`
entitlement column. No `ALTER TABLE`, no FK required in Phase 15. This is safe because:

1. The backfill is a plain `UPDATE ... WHERE tenant_id = 'default'` — no unique-constraint risk.
2. Writers (Phase 19) validate the value before insert.
3. Zero schema lock or Strapi boot-cycle risk.

**Option B (deferred to Phase 16/19):** Migrate `tenant_entitlements.tenant_id` to `uuid` type with
a FK to `tenants(tenant_id)`. Deferred because:

- Requires the Phase 16 live-safe migration apparatus (`CREATE INDEX CONCURRENTLY` + `lock_timeout`).
- Strapi may regenerate the auto-created column on next boot if the content-type schema is not also
  updated to declare a `uid` type.
- No writers exist yet — deferring has no operational cost.

**Canonical 1:1 mapping table (entitlement plane → data plane):**

| Entitlement plane value (VARCHAR) | Data plane value (uuid)                    |
|-----------------------------------|--------------------------------------------|
| `'default'` (current, stale)      | `'00000000-0000-0000-0000-000000000001'`   |

After Phase 15 the entitlement plane value is `'00000000-0000-0000-0000-000000000001'`
(UUID-as-string, stored in `VARCHAR(255)`). The mapping becomes an identity: both sides hold the
same UUID string.

---

## entitlement_audit_log.tenant_id Type Decision

**Decision: KEEP `VARCHAR(255)` through Phase 15.**

Rationale:

- The table is created by the unapplied SaaS migration
  (`db/migrations/2026-04-06_saas_modules_entitlements.sql:45-54`).
- The table has **NO writers yet** — changing the type now would require the Phase 16 live-safe
  migration apparatus and provides no operational benefit in Phase 15.
- Changing `VARCHAR(255)` to `uuid` requires an `ALTER TABLE` with an exclusive lock; the Phase 16
  infrastructure (`CREATE INDEX CONCURRENTLY`, `lock_timeout` patterns) is not available in Phase 15.

**Decision: migrate to `uuid` with a nullable FK to `tenants(tenant_id)` in Phase 19**, mirroring
the existing `admin_audit_log.tenant_id uuid NULL REFERENCES tenants(tenant_id)` precedent
(`db/bootstrap.sql:987-988`). Phase 19 wires the audit writers that must validate the value before
insert — that is the right point to enforce the type.

---

## Schema Confirmation (Open Question 2 — RESOLVED)

`tenant-entitlement` schema.json **DEFINES** `tenant_id` as a custom string field:

```json
"tenant_id": {
  "type": "string",
  "required": true,
  "description": "Tenant identifier — matches default_tenant_id in system-config or deployment context"
}
```

Source: `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/schema.json:13-17`

Open Question 2 from the Phase 15 research is **RESOLVED**: Strapi is creating the `tenant_id`
column from this schema definition. The seeder's `where: { tenant_id: defaultTenantId }` maps to a
real DB column. The seeder is structurally correct; only the value it writes (`'default'`) must be
fixed (Plan 15-03).

---

## VPS Backfill Caveat (🔴 DEFERRED)

The production / VPS backfill of `tenant_entitlements.tenant_id` is **deferred to a prod-connected
session**.

**Critical runtime-discovery rule:** The production backfill MUST discover the live tenant UUID at
runtime via:

```sql
SELECT tenant_id FROM tenants LIMIT 1
```

Run against the **n8n DB** and use THAT value for the `UPDATE` against the **strapi DB**. It MUST
NOT hardcode `00000000-0000-0000-0000-000000000001` — that UUID is a CI/dev seed value only (seeded
by `db/bootstrap.sql`). The VPS may have a different UUID for the actual restaurant tenant, especially
if it was provisioned before the fixed-UUID seed was committed.

The CI/dev backfill (Plan 15-02) uses `00000000-0000-0000-0000-000000000001` safely because it
operates against an ephemeral Postgres that always applies `db/bootstrap.sql` from scratch.

---

## Consequences

**(a) Guard/workflow comparisons become valid:** Once Phase 17 resolves real UUIDs from
`channel_identities`, the guard can compare the channel-derived UUID against
`tenant_entitlements.tenant_id` as apples-to-apples. The Phase 15 fix eliminates the root cause
(both sides now hold the same UUID string format).

**(b) Phase 15 also delivers:** the seeder fix (Plan 15-03, eliminates the `'default'` write path)
and the CI backfill harness (Plan 15-02, proves zero `'default'` rows post-backfill with a PR gate).

**(c) Phase 19 owns:** the `entitlement_audit_log.tenant_id` type migration (`VARCHAR(255)` →
`uuid` with nullable FK) and the entitlement audit writers that validate values before insert.

**(d) Phase 16/Phase 17 owns:** the live-safe migration apparatus and the `channel_identities`
lookup that makes tenant derivation trustworthy end-to-end.

---

## References

- `db/schema.sql:9-10` — `tenants.tenant_id uuid PRIMARY KEY`
- `db/bootstrap.sql:986-988` — `admin_audit_log.tenant_id uuid NULL REFERENCES tenants(tenant_id)` (precedent)
- `db/bootstrap.sql:2509-2533` — canonical seed rows
- `db/migrations/2026-04-06_saas_modules_entitlements.sql:45-54` — `entitlement_audit_log` definition
- `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/schema.json` — schema confirmation
- `docs/DECISIONS_L10N.md` — existing decision-record precedent in this repo
- `15-RESEARCH.md` — Phase 15 research grounding all claims above
