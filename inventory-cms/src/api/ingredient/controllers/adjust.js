'use strict';

/**
 * Custom controller to adjust stock atomically and prevent race conditions.
 */
module.exports = {
    async adjustStock(ctx) {
        const { id } = ctx.params;
        const { delta } = ctx.request.body;

        if (typeof delta !== 'number') {
            return ctx.badRequest('Delta must be a number');
        }

        try {
            // Use Strapi DB API to perform raw atomic update using knex transaction
            await strapi.db.connection.raw(
                `UPDATE ingredients SET current_stock = GREATEST(0, current_stock + ?) WHERE document_id = ? OR id = ?;`,
                [delta, id, Number(id) || 0]
            );

            // Fetch the updated item to return it
            const updated = await strapi.entityService.findMany('api::ingredient.ingredient', {
                filters: { $or: [{ id: Number(id) || 0 }, { documentId: id }] },
                populate: ['supplier'],
            });

            if (!updated || updated.length === 0) {
                return ctx.notFound('Ingredient not found');
            }

            ctx.send({ data: updated[0] });
        } catch (err) {
            ctx.badRequest(`Adjustment failed: ${err.message}`);
        }
    }
};
