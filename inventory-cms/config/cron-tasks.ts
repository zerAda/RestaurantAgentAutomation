export default {
    /**
     * Abandoned Carts Garbage Collector
     * Runs every 15 minutes to delete carts older than 60 minutes
     */
    '*/15 * * * *': async ({ strapi }: { strapi: any }) => {
        try {
            const now = new Date();
            const cutoffTime = new Date(now.getTime() - 60 * 60 * 1000); // 60 minutes ago

            const cartsToDelete = await strapi.db.query('api::order.order').findMany({
                where: {
                    status: 'cart',
                    updatedAt: {
                        $lt: cutoffTime,
                    },
                },
                select: ['id'],
            });

            if (cartsToDelete.length > 0) {
                const ids = cartsToDelete.map((c: any) => c.id);

                await strapi.db.query('api::order.order').deleteMany({
                    where: {
                        id: {
                            $in: ids,
                        },
                    },
                });

                strapi.log.info(`[GarbageCollector] Deleted ${cartsToDelete.length} abandoned carts (older than 60m).`);
            }
        } catch (error) {
            strapi.log.error(`[GarbageCollector] Failed to delete abandoned carts:`, error);
        }
    },
};
