import type { Core } from '@strapi/strapi';

export interface ProductModuleSeed {
  key: string;
  display_name: string;
  tier: 'shared_core' | 'product_core' | 'channel_pack' | 'addon' | 'experimental';
  description: string;
  enabled_globally?: boolean;
  rollout_default?: string;
}

/**
 * IMPORTANT: These keys MUST match config/product_modules.json exactly.
 * The W0_MODULE_GUARD queries Strapi by module_key, so any mismatch
 * will cause the guard to deny access.
 */
export const SAAS_MODULES: ProductModuleSeed[] = [
  {
    key: 'platform_runtime',
    display_name: 'Platform Runtime',
    tier: 'shared_core',
    description: 'Always-on platform primitives: config, Redis, meta verification, outbox, DLQ, health, monitoring, error handling, audit.',
    enabled_globally: true,
    rollout_default: 'always_on'
  },
  {
    key: 'order_bot_core',
    display_name: 'Order Bot Core',
    tier: 'product_core',
    description: 'Base conversational commerce engine: router, cart, FAQ, delivery quote, admin orders.',
    rollout_default: 'always_on'
  },
  {
    key: 'channel_whatsapp',
    display_name: 'WhatsApp Channel',
    tier: 'channel_pack',
    description: 'WhatsApp Business inbound/outbound messaging and admin support console.',
    rollout_default: 'tenant_flagged'
  },
  {
    key: 'channel_instagram',
    display_name: 'Instagram Channel',
    tier: 'channel_pack',
    description: 'Instagram DM inbound/outbound messaging.',
    rollout_default: 'tenant_flagged'
  },
  {
    key: 'channel_messenger',
    display_name: 'Messenger Channel',
    tier: 'channel_pack',
    description: 'Facebook Messenger inbound/outbound messaging.',
    rollout_default: 'tenant_flagged'
  },
  {
    key: 'channel_tiktok',
    display_name: 'TikTok Channel',
    tier: 'channel_pack',
    description: 'TikTok DM inbound and content publishing.',
    rollout_default: 'disabled_by_default'
  },
  {
    key: 'payment',
    display_name: 'Payment Processing',
    tier: 'addon',
    description: 'Chargily payment initiation, callback handling, and order finalization.',
    rollout_default: 'env_flagged'
  },
  {
    key: 'delivery_dispatch',
    display_name: 'Delivery & Dispatch',
    tier: 'addon',
    description: 'Driver management, dispatch, logistics, surge pricing, weather triggers.',
    rollout_default: 'env_flagged'
  },
  {
    key: 'inventory',
    display_name: 'Inventory Management',
    tier: 'addon',
    description: 'Inventory orchestration, sync, stock alerts, predictive 86ing, menu validation.',
    rollout_default: 'env_flagged'
  },
  {
    key: 'kiosk_instore',
    display_name: 'Kiosk & In-Store',
    tier: 'addon',
    description: 'In-store kiosk ordering, QR table detection, gamification wheel, kitchen printing.',
    rollout_default: 'env_flagged'
  },
  {
    key: 'voice',
    display_name: 'Voice Ordering',
    tier: 'addon',
    description: 'Speech-to-text, text-to-speech, voice call initiation and confirmation.',
    rollout_default: 'disabled_by_default'
  },
  {
    key: 'loyalty_crm',
    display_name: 'Loyalty & CRM',
    tier: 'addon',
    description: 'Loyalty engine, cart abandonment, VIP win-back, upsell engine, review catcher.',
    rollout_default: 'tenant_flagged'
  },
  {
    key: 'growth_marketing',
    display_name: 'Growth & Marketing',
    tier: 'addon',
    description: 'Funnel tracking, AI learning, revenue intelligence, marketing autopilot, content generation.',
    rollout_default: 'disabled_by_default'
  },
  {
    key: 'admin_ai_intelligence',
    display_name: 'Admin AI & Intelligence',
    tier: 'addon',
    description: 'Operator-facing AI agent, live monitoring, proactive alerts, cortex registry, omniscient brain.',
    rollout_default: 'tenant_flagged'
  },
  {
    key: 'experimental',
    display_name: 'Experimental / Review',
    tier: 'experimental',
    description: 'Unclear ownership, stale, duplicated, or partially integrated workflows.',
    rollout_default: 'disabled_by_default'
  }
];

export async function seedSaaSEntitlements(strapi: Core.Strapi) {
  // This MUST match the 'Default Chain' tenant seeded at bootstrap (db/bootstrap.sql).
  // Never fall back to the string 'default' — that is an invalid tenant_id in the data plane
  // (uuid column) and will cause silent zero-row matches or type errors.
  // If DEFAULT_TENANT_ID is set in env (e.g. for future tenants), that value wins.
  // See docs/adr/0001-canonical-tenant-key.md for the full decision record.
  const CANONICAL_FIRST_TENANT_UUID = '00000000-0000-0000-0000-000000000001';
  const defaultTenantId = (process.env.DEFAULT_TENANT_ID || '').trim() || CANONICAL_FIRST_TENANT_UUID;
  strapi.log.info(`[SaaS] Seeding activation for tenant: ${defaultTenantId}`);

  // 1. Seed Modules
  for (const mod of SAAS_MODULES) {
    try {
      const existing = await strapi.query('api::product-module.product-module').findOne({
        where: { key: mod.key }
      });

      if (!existing) {
        await strapi.query('api::product-module.product-module').create({
          data: {
            key: mod.key,
            display_name: mod.display_name,
            tier: mod.tier,
            description: mod.description,
            enabled_globally: mod.enabled_globally || false,
            rollout_policy: mod.rollout_default || 'disabled_by_default',
            publishedAt: new Date()
          }
        });
        strapi.log.info(`[SaaS] Module registered: ${mod.key}`);
      }
    } catch (err: any) {
      strapi.log.error(`[SaaS] Failed to seed module ${mod.key}: ${err.message}`);
    }
  }

  // 2. Seed Default Entitlements
  // Enable all non-experimental, non-shared_core modules for the default tenant
  for (const mod of SAAS_MODULES) {
    // shared_core is always allowed globally; experimental is disabled
    if (mod.tier === 'shared_core' || mod.enabled_globally || mod.tier === 'experimental') continue;

    try {
      const existingEnt = await strapi.query('api::tenant-entitlement.tenant-entitlement').findOne({
        where: { tenant_id: defaultTenantId, module_key: mod.key }
      });

      if (!existingEnt) {
        await strapi.query('api::tenant-entitlement.tenant-entitlement').create({
          data: {
            tenant_id: defaultTenantId,
            module_key: mod.key,
            enabled: true,
            activated_at: new Date(),
            activated_by: 'system_bootstrap@ralphe.ai',
            notes: `Initial SaaS bootstrap — auto-enabled for default tenant. Rollout: ${mod.rollout_default}.`
          }
        });
        strapi.log.info(`[SaaS] Entitled tenant ${defaultTenantId} → ${mod.key}`);
      }
    } catch (err: any) {
      strapi.log.error(`[SaaS] Failed to entitle tenant ${defaultTenantId} to ${mod.key}: ${err.message}`);
    }
  }

  strapi.log.info('[SaaS] Activation seeding completed.');
}
