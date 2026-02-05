// import type { Core } from '@strapi/strapi';

export default {
  /**
   * An asynchronous register function that runs before
   * your application is initialized.
   */
  register(/* { strapi }: { strapi: Core.Strapi } */) { },

  /**
   * An asynchronous bootstrap function that runs before
   * your application gets started.
   */
  async bootstrap(/* { strapi }: { strapi: Core.Strapi } */) {
    // SECURITY HARDENING: Verify Public Permissions at startup
    try {
      // Note: We use the generic query method to avoid depending on specific types if not strict yet
      const publicRole = await strapi.query('plugin::users-permissions.role').findOne({
        where: { type: 'public' },
        populate: ['permissions']
      });

      if (publicRole && publicRole.permissions && publicRole.permissions.length > 0) {
        strapi.log.warn(`⚠️ SECURITY WARNING: Public role has ${publicRole.permissions.length} enabled permissions. Review Admin Panel settings.`);
      } else {
        strapi.log.info('🔐 Security: Verified Public Role has limited/no permissions.');
      }
    } catch (error) {
      strapi.log.error('❌ Failed to verify security permissions during bootstrap:', error);
    }
  },
};
