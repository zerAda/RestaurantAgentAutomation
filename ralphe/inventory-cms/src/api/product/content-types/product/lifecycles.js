'use strict';

/**
 * Product lifecycle hooks
 * Tracks mutations for audit logging
 */

async function logAudit(action, event) {
    const { result, params } = event;
    const ctx = strapi.requestContext.get();
    const adminUser = ctx?.state?.user;

    try {
        await strapi.db.query('api::admin-audit-log.admin-audit-log').create({
            data: {
                action: action,
                model: 'product',
                model_id: result?.id || params?.where?.id,
                admin_user_id: adminUser?.id || null,
                admin_email: adminUser?.email || 'system',
                payload_json: params?.data || {}
            }
        });
    } catch (e) {
        strapi.log.warn(`[product] Failed to write audit log: ${e.message}`);
    }
}

module.exports = {
    async afterCreate(event) {
        await logAudit('CREATE', event);
    },

    async afterUpdate(event) {
        await logAudit('UPDATE', event);
    },

    async afterDelete(event) {
        await logAudit('DELETE', event);
    }
};
