import type { Core } from '@strapi/strapi';
import { seedRestaurantMenu } from './bootstrap-seeds/restaurant-menu';

const MAX_PUBLIC_PERMISSIONS = 0;
const ADMIN_EMAIL = process.env.STRAPI_SUPER_ADMIN_EMAIL || 'admin@ralphe.com';
const ADMIN_PASS = process.env.STRAPI_SUPER_ADMIN_PASSWORD || 'ChangeMeNow!';

export default {
  register({ strapi }: { strapi: Core.Strapi }) {
    // S-01 FIX: Register agent-chat extension using Strapi's official extension pattern
    // Adds POST /api/agent/chat and GET /api/agent/tools endpoints
    try {
      // Register the agent-chat controller
      (strapi as any).controller('api::agent-chat.agent-chat', require('./extensions/agent-chat/controllers/agent-chat').default);

      // Register routes for the agent-chat extension
      // These will be handled by Strapi's router
      strapi.server.routes([
        {
          method: 'POST',
          path: '/api/agent/chat',
          handler: 'api::agent-chat.agent-chat.chat',
          config: {
            auth: { scope: ['api::agent-chat.agent-chat.chat'] },
            policies: [],
            middlewares: [],
          },
        },
        {
          method: 'GET',
          path: '/api/agent/tools',
          handler: 'api::agent-chat.agent-chat.tools',
          config: {
            auth: { scope: ['api::agent-chat.agent-chat.tools'] },
            policies: [],
            middlewares: [],
          },
        },
        {
          method: 'POST',
          path: '/api/agent/loyalty',
          handler: 'api::agent-chat.agent-chat.loyalty',
          config: {
            auth: { scope: ['api::agent-chat.agent-chat.loyalty'] },
            policies: [],
            middlewares: [],
          },
        },
      ]);
    } catch (err: any) {
      // Graceful degradation: log error but don't crash Strapi startup
      // The routes may already be registered via the api/ directory structure
      console.warn(`[register] agent-chat extension registration warning: ${err.message}`);
    }
  },


  async bootstrap({ strapi }: { strapi: Core.Strapi }) {
    // ── Realtime SSE (Redis Pub/Sub) ──────────────
    try {
      strapi.log.info('Realtime: Initializing Redis Subscriber for SSE...');
      const realtimeService = strapi.service('api::realtime.realtime');
      if (realtimeService && typeof realtimeService.getRedisSubscriber === 'function') {
        const sub = realtimeService.getRedisSubscriber();
        sub.subscribe('order_updates', (err: any) => {
          if (err) strapi.log.error('Redis Subscribe Error:', err);
        });
        sub.on('message', (channel: string, message: string) => {
          if (channel === 'order_updates') {
            try {
              const data = JSON.parse(message);
              strapi.eventHub.emit('redis.order_updates', data);
            } catch (e) {
              strapi.log.error('Failed to parse SSE message:', e);
            }
          }
        });
      }
    } catch (err: any) {
      strapi.log.error(`Realtime: Failed to start SSE Redis: ${err.message}`);
    }

    // ── Unified Authentication: Sync Admin & API User ──────────────
    try {
      // 1. Ensure Super Admin exists in Admin Panel
      const adminRepo = strapi.query('admin::user');
      let superAdmin = await adminRepo.findOne({ where: { email: ADMIN_EMAIL } });

      if (!superAdmin) {
        const adminRole = await strapi.query('admin::role').findOne({ where: { code: 'strapi-super-admin' } });
        superAdmin = await adminRepo.create({
          data: {
            email: ADMIN_EMAIL,
            password: ADMIN_PASS,
            firstname: 'Super',
            lastname: 'Admin',
            roles: [adminRole.id],
            isActive: true,
            registrationToken: null,
          }
        });
        strapi.log.info('Security: Created Super Admin user.');
      }

      // 2. Ensure same user exists in Users-Permissions (API) for the Dashboard
      const upRepo = strapi.query('plugin::users-permissions.user');
      const apiUser = await upRepo.findOne({ where: { email: ADMIN_EMAIL } });

      if (!apiUser) {
        const authenticatedRole = await strapi.query('plugin::users-permissions.role').findOne({
          where: { type: 'authenticated' }
        });

        await upRepo.create({
          data: {
            username: ADMIN_EMAIL,
            email: ADMIN_EMAIL,
            password: ADMIN_PASS,
            confirmed: true,
            role: authenticatedRole.id,
          }
        });
        strapi.log.info('Security: Created API user matching Admin credentials.');
      } else {
        // Update password to match if it has drifted
        await upRepo.update({
          where: { id: apiUser.id },
          data: { password: ADMIN_PASS }
        });
      }
    } catch (err: any) {
      strapi.log.error(`Security: Failed to sync credentials: ${err.message}`);
    }

    // ── Professional Seeding ────────────────────────────────────────
    try {
      const productCount = await strapi.query('api::product.product').count({});
      if (productCount === 0) {
        strapi.log.info('Seeding: No products found, initial seeding started...');
        await seedRestaurantMenu(strapi);
      }
    } catch (err: any) {
      strapi.log.error(`Seeding: Failed to seed menu: ${err.message}`);
    }

    // ── Security Audits ───────────────────────────────────────────

    // Check public role permissions
    try {
      const publicRole = await strapi
        .query('plugin::users-permissions.role')
        .findOne({
          where: { type: 'public' },
          populate: ['permissions'],
        });

      if (publicRole?.permissions?.length > MAX_PUBLIC_PERMISSIONS) {
        strapi.log.warn(
          `SECURITY: Public role has ${publicRole.permissions.length} permissions (max ${MAX_PUBLIC_PERMISSIONS}). ` +
          'Disable unnecessary public permissions in the Admin Panel.',
        );
      } else {
        strapi.log.info('Security: Public role permissions verified.');
      }
    } catch {
      strapi.log.warn('Security: Could not verify public role permissions (plugin may not be ready).');
    }

    // Disable public registration by default
    try {
      const pluginStore = strapi.store({
        type: 'plugin',
        name: 'users-permissions',
      });

      const advanced = await pluginStore.get({ key: 'advanced' });
      if (advanced && typeof advanced === 'object' && 'allow_register' in advanced) {
        if ((advanced as Record<string, unknown>).allow_register === true) {
          strapi.log.warn(
            'SECURITY: Public user registration is enabled. ' +
            'Consider disabling it in Settings > Users & Permissions > Advanced.',
          );
        }
      }
    } catch {
      strapi.log.warn('Security: Could not verify registration settings.');
    }
  },
};
