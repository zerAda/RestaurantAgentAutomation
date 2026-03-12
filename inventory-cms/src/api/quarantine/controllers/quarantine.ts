/**
 * [B-10] FIX: Quarantine Custom Controller — Privilege Escalation Prevention
 *
 * Problem: The bare Core Controller exposed full CRUD on the quarantine table.
 * A resourceful attacker with any API access could attempt to PUT/DELETE their
 * own quarantine record to un-quarantine themselves.
 *
 * Solution: Restrict all mutations (create/update/delete) to authenticated
 * admin_staff only. Regular users and public requests can only read their status.
 */
import { factories } from '@strapi/strapi';

const ADMIN_ROLES = ['admin_staff', 'superadmin', 'system'];

function isAdminUser(ctx: any): boolean {
    const user = ctx.state?.user;
    if (!user) return false;
    const roleName = user?.role?.type || user?.role?.name || '';
    return ADMIN_ROLES.some(r => roleName.toLowerCase().includes(r));
}

export default factories.createCoreController('api::quarantine.quarantine', ({ strapi }) => ({
    async create(ctx) {
        if (!isAdminUser(ctx)) {
            return ctx.forbidden('[Quarantine] Only admin staff can create quarantine entries.');
        }
        return await super.create(ctx);
    },

    async update(ctx) {
        if (!isAdminUser(ctx)) {
            strapi.log.warn(
                `[Quarantine] PRIVILEGE ESCALATION ATTEMPT: user ${ctx.state?.user?.id} tried to modify quarantine ${ctx.params?.id}`
            );
            return ctx.forbidden('[Quarantine] Only admin staff can modify quarantine entries.');
        }
        return await super.update(ctx);
    },

    async delete(ctx) {
        if (!isAdminUser(ctx)) {
            strapi.log.warn(
                `[Quarantine] PRIVILEGE ESCALATION ATTEMPT: user ${ctx.state?.user?.id} tried to delete quarantine ${ctx.params?.id}`
            );
            return ctx.forbidden('[Quarantine] Only admin staff can delete quarantine entries.');
        }
        return await super.delete(ctx);
    },
}));
