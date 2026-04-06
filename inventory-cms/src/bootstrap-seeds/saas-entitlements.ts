import type { Core } from '@strapi/strapi';

export interface ProductModuleSeed {
  key: string;
  display_name: string;
  tier: 'shared_core' | 'product_core' | 'channel_pack' | 'addon' | 'experimental';
  description: string;
  enabled_globally?: boolean;
}

export const SAAS_MODULES: ProductModuleSeed[] = [
  {
    key: 'shared_core',
    display_name: 'Platform Core',
    tier: 'shared_core',
    description: 'Essential platform services, logging, and security infrastructure.',
    enabled_globally: true
  },
  {
    key: 'channel_whatsapp',
    display_name: 'WhatsApp Business',
    tier: 'channel_pack',
    description: 'Official Meta WhatsApp Business API integration.'
  },
  {
    key: 'channel_messenger',
    display_name: 'Facebook Messenger',
    tier: 'channel_pack',
    description: 'Meta Messenger webhook and automation adapter.'
  },
  {
    key: 'channel_instagram',
    display_name: 'Instagram Direct',
    tier: 'channel_pack',
    description: 'Instagram DM and Story automation adapter.'
  },
  {
    key: 'channel_tiktok',
    display_name: 'TikTok Commerce',
    tier: 'channel_pack',
    description: 'TikTok DM and commerce webhook integration.'
  },
  {
    key: 'channel_voice',
    display_name: 'AI Voice Agent',
    tier: 'addon',
    description: 'RAG-enhanced AI voice ordering (Vapi/Retell integration).'
  },
  {
    key: 'ordering_kiosk',
    display_name: 'Physical Kiosk',
    tier: 'product_core',
    description: 'React-based self-service ordering interface.'
  },
  {
    key: 'delivery_dispatch',
    display_name: 'Delivery & Dispatch',
    tier: 'product_core',
    description: 'Zone management, driver assignment, and status tracking.'
  },
  {
    key: 'marketing_loyalty',
    display_name: 'Loyalty & Rewards',
    tier: 'addon',
    description: 'Customer tiers, points, and automated win-back campaigns.'
  },
  {
    key: 'payment_gateway',
    display_name: 'Payment Gateway',
    tier: 'product_core',
    description: 'Secure processing for CIB, Edahabia, and Stripe.'
  },
  {
    key: 'analytics_studio',
    display_name: 'Analytics Studio',
    tier: 'addon',
    description: 'DORA metrics, sales reporting, and AI business insights.'
  },
  {
    key: 'admin_agent',
    display_name: 'AI Admin Assistant',
    tier: 'addon',
    description: 'Proactive agent for order management and stock alerts.'
  },
  {
    key: 'inventory_manager',
    display_name: 'Inventory Manager',
    tier: 'product_core',
    description: 'Real-time stock tracking and low-inventory triggers.'
  }
];

export async function seedSaaSEntitlements(strapi: Core.Strapi) {
  const defaultTenantId = process.env.DEFAULT_TENANT_ID || 'default';
  strapi.log.info(`Seeding SaaS activation for tenant: ${defaultTenantId}`);

  // 1. Seed Modules
  for (const mod of SAAS_MODULES) {
    try {
      const existing = await strapi.query('api::product-module.product-module').findOne({
        where: { key: mod.key }
      });

      if (!existing) {
        await strapi.query('api::product-module.product-module').create({
          data: {
            ...mod,
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
  // We enable all non-experimental modules for the default tenant to prevent service disruption
  for (const mod of SAAS_MODULES) {
    if (mod.tier === 'shared_core' || mod.enabled_globally) continue;

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
            notes: 'Initial SaaS hardening bootstrap — auto-enabled for default tenant.'
          }
        });
        strapi.log.info(`[SaaS] Entitled tenant ${defaultTenantId} to ${mod.key}`);
      }
    } catch (err: any) {
      strapi.log.error(`[SaaS] Failed to entitle tenant ${defaultTenantId} to ${mod.key}: ${err.message}`);
    }
  }

  strapi.log.info('SaaS activation seeding completed.');
}
