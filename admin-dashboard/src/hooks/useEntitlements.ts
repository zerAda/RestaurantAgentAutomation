import { useState, useEffect } from 'react';
import { strapi } from '../services/strapiClient';
import { authService } from '../services/authService';

// INVENTORY-15: default parameter 'default' is a Phase-21 cleanup item (ENT-01/ENT-02).
// The UI queries entitlements for 'default' when no authenticated context provides the real UUID.
// This parameter will be removed/replaced once Phase 21 wires authenticated tenant context to the UI.
// See docs/adr/0002-tenant-id-fallback-inventory.md
export function useEntitlements(tenantId = 'default') {
  const [modules, setModules] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // If not authenticated, don't fetch
    if (!authService.isAuthenticated()) {
      setLoading(false);
      return;
    }

    async function fetchModules() {
      try {
        const [modRes, entRes] = await Promise.all([
          strapi.find<any>('product-modules'),
          strapi.find<any>('tenant-entitlements', { filters: { tenant_id: { $eq: tenantId }, enabled: { $eq: true } } })
        ]);
        
        const enabledKeys = new Set<string>();
        
        // Add globally enabled modules and shared_core
        const allMods = (modRes as any).data || [];
        allMods.forEach((m: any) => {
          const mData = m.attributes || m; // Handle both strapi v4 shapes
          if (mData.enabled_globally || mData.tier === 'shared_core' || mData.tier === 'product_core') {
            enabledKeys.add(mData.key);
          }
        });

        // Add tenant entitlements
        const ents = (entRes as any).data || [];
        ents.forEach((e: any) => {
          const eData = e.attributes || e;
          enabledKeys.add(eData.module_key);
        });

        setModules(Array.from(enabledKeys));
      } catch (err) {
        console.error('Failed to fetch entitlements', err);
      } finally {
        setLoading(false);
      }
    }
    fetchModules();
  }, [tenantId]);

  // Expose an easy checker function
  const hasModule = (key: string) => {
    // Fail-open for local dev or if loading
    if (loading) return true;
    return modules.includes(key);
  };

  return { modules, loading, hasModule };
}
