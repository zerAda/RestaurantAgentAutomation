// Shared, v4/v5-response-tolerant entitlement DTOs (TYP-01).
//
// Strapi 5 (this repo: 5.37.1) returns flat rows: { id, documentId, ...Fields }.
// Strapi v4 wrapped them: { id, attributes: Fields }. The hook historically tolerated
// both via `row.attributes || row`; `unwrap<T>()` is the typed equivalent.
//
// Type-only module — zero runtime dependencies (no new runtime library; milestone constraint).
// Consumed by admin-dashboard/src/hooks/useEntitlements.ts (21-01) to replace its `any` usages.

export interface ProductModuleFields {
  key: string;
  tier?: 'shared_core' | 'product_core' | 'channel_pack' | 'addon' | 'experimental';
  enabled_globally?: boolean;
  display_name?: string;
}

export interface TenantEntitlementFields {
  module_key: string;
  tenant_id?: string;
  enabled?: boolean;
}

// v5 flat shape OR v4 { id, attributes: Fields } wrapper.
export type ProductModuleRaw =
  | ProductModuleFields
  | { id: number; attributes: ProductModuleFields };

export type TenantEntitlementRaw =
  | TenantEntitlementFields
  | { id: number; attributes: TenantEntitlementFields };

// Normalizer replacing `m.attributes || m`: returns row.attributes when present, else row.
export function unwrap<T>(row: T | { attributes: T }): T {
  return row && typeof row === 'object' && 'attributes' in (row as object)
    ? (row as { attributes: T }).attributes
    : (row as T);
}
