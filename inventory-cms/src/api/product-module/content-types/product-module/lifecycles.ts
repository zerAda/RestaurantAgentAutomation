// =============================================================================
// Phase 19 — product-module lifecycle adapter (AUD-01; O-1 audit-only).
//
// AUDIT-ONLY (ADR 0003 decision O-1): a product-module definition change writes an
// entitlement_audit_log row but does NOT global-flush the cache. A product-module row is a
// GLOBAL module definition affecting every tenant; flushing would need a full-keyspace
// SCAN *:{key}. The ≤5-min positive TTL (Phase 20) bounds staleness — recorded as a
// TTL-bounded known gap. So there is intentionally NO cache-DEL / invalidation call here.
//
// CORRECTION (ADR 0003 / Blocker B): product-module rows are tenant-AGNOSTIC, so the audit
// tenant_id is NULL (the legitimate platform/global value — NOT the all-zero sentinel). The
// helper's validateTenantId skips validation for null, and the migration's nullable FK accepts
// it.
//
// Pitfall 3 (research §1): product-module's column is `key`, NOT `module_key` — map key ->
// the audit module_key column.
//
// Imports the SHARED pure helper from tenant-entitlement (no duplication). Fail-loud mirrors
// the tenant-entitlement adapter: validate-throw-pre-write inside writeAuditRow; the
// post-commit insert is try/catch -> strapi.log.error + counter (NOT re-thrown).
// =============================================================================

import {
  deriveAction,
  writeAuditRow,
} from '../../../tenant-entitlement/content-types/tenant-entitlement/audit-hook';

const UID = 'api::product-module.product-module';

let auditFailureCount = 0;

async function runAudit(action: string, oldValue: any, result: any): Promise<void> {
  // Pitfall 3: product-module's key column is `key`, mapped to the audit `module_key`.
  const module_key = result?.key ?? oldValue?.key;
  // Tenant-agnostic global definition -> tenant_id NULL (Blocker B; no all-zero sentinel).
  const tenant_id = null;
  const changed_by = strapi.requestContext.get()?.state?.user?.email ?? 'system';

  try {
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
      `[ProductModuleAudit] audit write FAILED (non-blocking; failures=${auditFailureCount})`,
      err,
    );
  }
  // O-1: audit-only — NO cache flush (the ≤5-min Phase-20 TTL bounds staleness).
}

export default {
  async beforeUpdate(event: any) {
    event.state.oldValue = await strapi.db.query(UID).findOne({ where: event.params.where });
  },

  async beforeDelete(event: any) {
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
