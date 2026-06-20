import { useState, useEffect } from 'react';
import { strapi } from '../services/strapiClient';
import { authService } from '../services/authService';
import {
  type ProductModuleRaw,
  type TenantEntitlementRaw,
  unwrap,
} from '../types/entitlements';

// SHARED_CORE: the structurally-always-on tiers (config/product_modules.json
// tier === 'shared_core' || 'product_core'). The seeder never tenant-gates these
// (saas-entitlements.ts L166 skips them), so they are safe to hardcode and keep
// VISIBLE while loading/on error — this prevents a total admin lockout while the
// rest of the UI fails CLOSED, in parity with W0_MODULE_GUARD's fail-closed posture.
const SHARED_CORE = new Set<string>(['platform_runtime', 'order_bot_core']);

// INVENTORY-15 (ADR-0002 occurrence #5 — the LAST annotated 'default' fallback):
// authService exposes NO tenant UUID on the user shape (authService.ts:69), so a real
// authenticated-tenant context is NOT available to wire to the UI today. We therefore
// KEEP the query working (so the seeded canonical tenant's rows return once a real
// tenant id IS provided) but FAIL CLOSED on the RESULT: a zero-row / error result hides
// all GATED modules while SHARED_CORE keeps core nav usable — this prevents BOTH the
// old fail-open bug AND a total lockout. #5 is kept-but-fail-closed-on-result; full
// removal needs an authenticated tenant context exposed to the UI (future work).
// See docs/adr/0002-tenant-id-fallback-inventory.md
export function useEntitlements(tenantId = 'default') {
  const [modules, setModules] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    // If not authenticated, don't fetch — fail closed (modules stays []).
    if (!authService.isAuthenticated()) {
      setLoading(false);
      return;
    }

    async function fetchModules() {
      setError(false);
      try {
        const [modRes, entRes] = await Promise.all([
          strapi.find<ProductModuleRaw>('product-modules'),
          strapi.find<TenantEntitlementRaw>('tenant-entitlements', {
            filters: { tenant_id: { $eq: tenantId }, enabled: { $eq: true } },
          }),
        ]);

        const enabledKeys = new Set<string>();

        // Globally enabled modules + shared_core/product_core (v4/v5-tolerant via unwrap).
        const allMods = modRes.data ?? [];
        allMods.forEach((m: ProductModuleRaw) => {
          const mData = unwrap(m);
          if (
            mData.enabled_globally ||
            mData.tier === 'shared_core' ||
            mData.tier === 'product_core'
          ) {
            enabledKeys.add(mData.key);
          }
        });

        // Tenant entitlements (v4/v5-tolerant via unwrap).
        const ents = entRes.data ?? [];
        ents.forEach((e: TenantEntitlementRaw) => {
          const eData = unwrap(e);
          enabledKeys.add(eData.module_key);
        });

        setModules(Array.from(enabledKeys));
      } catch (err) {
        // Explicit error state — no longer a silent console.error (the second half of the bug).
        setError(true);
        console.error('Failed to fetch entitlements', err);
      } finally {
        setLoading(false);
      }
    }
    fetchModules();
  }, [tenantId]);

  const status: 'loading' | 'error' | 'ready' = loading
    ? 'loading'
    : error
      ? 'error'
      : 'ready';

  // FAIL CLOSED with a SHARED_CORE allowlist (no total lockout):
  //  - SHARED_CORE keys (platform_runtime, order_bot_core) are structurally always-on —
  //    the seeder never tenant-gates them and they never appear in the entitlements result,
  //    so they stay visible in EVERY state (loading, error, ready/empty, unauthenticated).
  //  - any other key fails CLOSED while loading or on error, else gates strictly on the
  //    fetched modules.
  const hasModule = (key: string) => {
    if (SHARED_CORE.has(key)) return true;
    if (loading || error) return false;
    return modules.includes(key);
  };

  return { modules, loading, error, status, hasModule };
}
