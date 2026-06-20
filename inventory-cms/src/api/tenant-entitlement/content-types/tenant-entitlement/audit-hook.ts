// =============================================================================
// Phase 19 — PURE entitlement-audit helper (AUD-01 + AUD-02).
//
// ZERO Strapi-core import — only zod (runtime) + knex/ioredis types (import type).
// This is the testable seam: lifecycles.ts injects strapi.db.connection (raw Knex) + a
// memoized ioredis client; the node-test injects ephemeral clients. Because the helper has
// no Strapi dependency it imports cleanly under `node --test --experimental-strip-types`
// (Node >= 22.18) and unit-tests without booting Strapi (whose TS compile is already red).
//
// TYPE-STRIPPABLE STYLE ONLY (Blocker A): plain type annotations + `import type`; NO enums,
// NO namespaces, NO parameter-properties — so Node 22 native type-stripping loads it.
//
// CONTRACT (asserted by 19-03's audit-hook.test.mjs):
//   deriveAction(oldValue, newValue) -> string
//   validateTenantId(tenant_id) -> string | null   (zod GUID; THROWS on a non-canonical value;
//                                                    NULL/undefined is the legitimate global value)
//   writeAuditRow(knex, row) -> Promise<void>       (validate-then-raw-Knex-insert)
//   invalidateCache(redis, tenant_id, module_key) -> Promise<void>  (DEL the exact canonical key)
//
// CACHE KEY (LOCKED — ROADMAP:147 / ADR 0003): ralphe:entitlement:{tenant_id}:{module_key}
//   — the DEL must match the Phase-20 GRD-01 GET byte-for-byte (else a stale grant survives).
// =============================================================================

import { z } from 'zod';
import type { Knex } from 'knex';
import type { Redis } from 'ioredis';

// A "knex-like" callable so the helper accepts both the real strapi.db.connection and a test
// stub. Only `(table).insert(row)` is used.
type KnexLike = ((table: string) => { insert: (row: Record<string, unknown>) => Promise<unknown> }) | Knex;

// A "redis-like" object exposing the single `del` we need (real ioredis or a test stub).
type RedisLike = { del: (key: string) => Promise<unknown> } | Redis;

export type AuditRow = {
  tenant_id: string | null | undefined;
  module_key: string;
  action: string;
  changed_by?: string | null;
  old_value?: unknown;
  new_value?: unknown;
};

// zod 4: z.string().uuid() enforces RFC-9562 version/variant bits and REJECTS the all-zero
// canonical tenant (00000000-…-000000000001) and the all-zero global sentinel — values the
// Postgres `uuid` column accepts. z.string().guid() accepts any 8-4-4-4-12 hex string (the DB
// uuid plane) while still rejecting 'default'/empty/malformed. (Recorded in ADR 0003.)
const guidSchema = z.string().guid();

/**
 * Derive the audit `action` from the old→new entitlement rows.
 *   null old, non-null new  -> 'created'
 *   non-null old, null new  -> 'deleted'
 *   enabled false->true     -> 'enabled'
 *   enabled true->false     -> 'disabled'
 *   expires_at now-in-past (and was future/absent) -> 'expired'
 *   otherwise               -> 'config_changed'
 */
export function deriveAction(oldValue: any, newValue: any): string {
  if (oldValue == null && newValue != null) return 'created';
  if (oldValue != null && newValue == null) return 'deleted';

  const oldEnabled = oldValue ? oldValue.enabled : undefined;
  const newEnabled = newValue ? newValue.enabled : undefined;
  if (oldEnabled === true && newEnabled === false) return 'disabled';
  if (oldEnabled === false && newEnabled === true) return 'enabled';

  const newExpires = newValue ? newValue.expires_at : undefined;
  const oldExpires = oldValue ? oldValue.expires_at : undefined;
  if (newExpires != null) {
    const newPast = new Date(newExpires).getTime() <= Date.now();
    const oldPast = oldExpires != null ? new Date(oldExpires).getTime() <= Date.now() : false;
    if (newPast && !oldPast) return 'expired';
  }

  return 'config_changed';
}

/**
 * Validate a tenant_id to canonical-UUID (GUID) form.
 *   - A non-null value MUST be a canonical UUID string — THROWS (ZodError) otherwise (fail-loud,
 *     pre-insert; a bad value never reaches the DB).
 *   - NULL / undefined is the legitimate platform/global value (product-module rows) and is
 *     returned as null WITHOUT validation (ADR 0003 / Blocker B — the all-zero sentinel is NOT used).
 */
export function validateTenantId(tenant_id: string | null | undefined): string | null {
  if (tenant_id == null) return null;
  return guidSchema.parse(String(tenant_id));
}

/**
 * Write one entitlement_audit_log row via raw Knex (the table is NOT a Strapi content type —
 * ADR 0003 — so strapi.db.query('api::…') is impossible). validateTenantId runs FIRST: a
 * non-canonical non-null tenant_id throws BEFORE the insert. A null tenant_id (global) is kept.
 */
export async function writeAuditRow(knex: KnexLike, row: AuditRow): Promise<void> {
  const tenant_id = validateTenantId(row.tenant_id); // throws pre-insert on a bad non-null value
  await (knex as (t: string) => { insert: (r: Record<string, unknown>) => Promise<unknown> })(
    'entitlement_audit_log',
  ).insert({
    tenant_id, // uuid or NULL (global)
    module_key: row.module_key,
    action: row.action,
    changed_by: row.changed_by ?? null,
    old_value: row.old_value != null ? JSON.stringify(row.old_value) : null,
    new_value: row.new_value != null ? JSON.stringify(row.new_value) : null,
    // created_at defaults in the DB (NOW()).
  });
}

/**
 * Invalidate the entitlement cache for one (tenant, module) by issuing an exact-key DEL on the
 * canonical key ralphe:entitlement:{tenant_id}:{module_key}. O(1) — a single exact-key DEL,
 * never a cursor scan or a blocking key-enumeration (the single-threaded Redis hot path stays
 * safe). Must match the Phase-20 GRD-01 GET byte-for-byte.
 */
export async function invalidateCache(
  redis: RedisLike,
  tenant_id: string,
  module_key: string,
): Promise<void> {
  const key = `ralphe:entitlement:${tenant_id}:${module_key}`;
  await redis.del(key);
}
