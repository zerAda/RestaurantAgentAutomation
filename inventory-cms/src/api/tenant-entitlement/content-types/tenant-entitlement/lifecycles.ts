// =============================================================================
// Phase 19 — tenant-entitlement lifecycle adapter (AUD-01 + AUD-02).
//
// Thin Strapi-5 adapter over the PURE audit-hook.ts helper. On every entitlement
// create/update/delete it writes an entitlement_audit_log row (who/what/when/old->new) via
// raw Knex AND issues an exact-key Redis DEL of ralphe:entitlement:{tenant_id}:{module_key}
// so a revoked/expired grant cannot survive in cache.
//
// Strapi-5 quirk (research §3): afterUpdate/afterDelete carry NO old value — capture it in
// beforeUpdate/beforeDelete via event.state.oldValue, read it back in the after* hook.
//
// Fail-loud (research §6 / ADR 0003): validateTenantId (inside writeAuditRow) THROWS pre-insert
// on a bad non-null tenant_id (loud, blocks the malformed row). The post-commit audit insert +
// cache DEL are wrapped in try/catch that logs at error/warn + increments a counter — NOT a
// re-throw (after-hooks fire post-commit; a throw can't roll back the grant and would only 500
// the admin). No bare error-swallowing: every catch logs at error/warn AND counts.
//
// Redis client: static `import Redis from 'ioredis'` (the realtime.ts constructable pattern),
// memoized + guarded by USE_REDIS — NOT the dynamic-import form (the auth-ratelimit.ts baseline
// TS2351 error).
// =============================================================================

import Redis from 'ioredis';
import { deriveAction, writeAuditRow, invalidateCache } from './audit-hook';

const UID = 'api::tenant-entitlement.tenant-entitlement';

const USE_REDIS = !!process.env.REDIS_URL || !!process.env.REDIS_HOST;
let entRedis: Redis | null = null;

// Module-level fail-loud counter (scraped via the log line; visible to the metrics plane).
let auditFailureCount = 0;

function getRedis(): Redis {
  if (!entRedis) {
    if (process.env.REDIS_URL) {
      entRedis = new Redis(process.env.REDIS_URL);
    } else {
      const port = parseInt(process.env.REDIS_PORT || '6379', 10);
      const host = process.env.REDIS_HOST || 'localhost';
      entRedis = new Redis(port, host);
    }
    entRedis.on('error', (err: Error) =>
      strapi.log.error('[EntitlementAudit] redis client error', err),
    );
  }
  return entRedis;
}

async function runAudit(action: string, oldValue: any, result: any): Promise<void> {
  const tenant_id = result?.tenant_id ?? oldValue?.tenant_id;
  const module_key = result?.module_key ?? oldValue?.module_key;
  // Called INSIDE the hook so the AsyncLocalStorage request context is populated (research §4).
  const changed_by = strapi.requestContext.get()?.state?.user?.email ?? 'system';

  try {
    // validateTenantId inside writeAuditRow throws on a bad non-null tenant_id BEFORE the insert
    // (the fail-loud pre-write seam) — caught here, logged at error + counted (the row is
    // correctly NOT written). A null tenant_id (not expected on the entitlement path) is allowed.
    await writeAuditRow(strapi.db.connection, {
      tenant_id,
      module_key,
      action,
      changed_by,
      old_value: oldValue,
      new_value: result,
    });
  } catch (err) {
    auditFailureCount += 1;
    strapi.log.error(
      `[EntitlementAudit] audit write FAILED (non-blocking; failures=${auditFailureCount})`,
      err,
    );
  }

  // Cache invalidation: exact-key DEL. A Redis outage must not break the edit -> warn + count.
  if (USE_REDIS && tenant_id && module_key) {
    try {
      await invalidateCache(getRedis(), tenant_id, module_key);
    } catch (err) {
      auditFailureCount += 1;
      strapi.log.warn(
        `[EntitlementAudit] cache DEL FAILED (non-blocking; failures=${auditFailureCount})`,
        err,
      );
    }
  }
}

export default {
  async beforeUpdate(event: any) {
    // afterUpdate carries no "old" value — fetch + stash it now.
    event.state.oldValue = await strapi.db.query(UID).findOne({ where: event.params.where });
  },

  async beforeDelete(event: any) {
    // afterDelete's result is the deleted row, but capture defensively (draft/publish can delete a copy).
    event.state.oldValue = await strapi.db.query(UID).findOne({ where: event.params.where });
  },

  async afterCreate(event: any) {
    await runAudit('created', null, event.result);
  },

  async afterUpdate(event: any) {
    const oldValue = event.state?.oldValue ?? null;
    await runAudit(deriveAction(oldValue, event.result), oldValue, event.result);
  },

  async afterDelete(event: any) {
    const oldValue = event.state?.oldValue ?? null;
    await runAudit('deleted', oldValue, event.result ?? oldValue);
  },
};
