import type { Core } from '@strapi/strapi';

const MAX_PUBLIC_PERMISSIONS = 0;

export default {
  register(/* { strapi }: { strapi: Core.Strapi } */) {},

  async bootstrap({ strapi }: { strapi: Core.Strapi }) {
    // ── Security: Verify public role permissions ───────────────────
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

    // ── Security: Disable public registration by default ──────────
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

    // ── Security: Log admin user count ────────────────────────────
    try {
      const adminCount = await strapi.query('admin::user').count({});
      if (adminCount === 0) {
        strapi.log.warn('SECURITY: No admin users exist. Create one immediately via strapi admin:create-user.');
      } else {
        strapi.log.info(`Security: ${adminCount} admin user(s) configured.`);
      }
    } catch {
      // Admin user query may not be available in all contexts
    }
  },
};
