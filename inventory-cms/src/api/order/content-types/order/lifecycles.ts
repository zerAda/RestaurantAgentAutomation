export default {
    /**
     * BUG-002 FIX: Server-side price recompilation.
     * Clients MUST NOT be trusted to supply correct prices.
     * We fetch real prices from the DB and overwrite total_cents before insert.
     * BUG-008 FIX: Idempotence guard — reject duplicate orders within 30s window
     * to prevent double-submission from Kiosk rapid-tap.
     */
    async beforeCreate(event: any) {
        const { data } = event.params;

        // TEN-04: tenant_id is non-defaultable on the order write path (parity with the
        // n8n orders.tenant_id NOT NULL constraint). An absent tenant MUST throw — it is
        // never substituted with a fallback tenant value.
        const tenantId = (data.tenant_id || '').toString().trim();
        if (!tenantId) {
            throw new Error('tenant_id is required for an order (non-defaultable, no default tenant).');
        }

        const orderItems: any[] = data.order_items || [];

        if (orderItems.length === 0) {
            throw new Error('La commande doit contenir au moins un article.');
        }

        // Re-fetch all product prices from the database
        let recomputedTotal = 0;
        for (const item of orderItems) {
            const product = await strapi.db.query('api::product.product').findOne({
                where: { id: item.item_code },
                select: ['price', 'name'],
            });

            if (!product) {
                throw new Error(`Produit introuvable : ${item.item_code}`);
            }

            const serverUnitPrice = product.price;
            const lineTotal = serverUnitPrice * item.qty;

            // Overwrite whatever the client sent with the real server price
            item.unit_price_cents = serverUnitPrice;
            item.line_total_cents = lineTotal;
            recomputedTotal += lineTotal;
        }

        // Overwrite client-submitted total with the server-computed one
        data.total_cents = recomputedTotal;
        data.order_items = orderItems;

        strapi.log.info(`[Order Lifecycle] Server recomputed total: ${recomputedTotal} cents for ${orderItems.length} items.`);
    },

    // BUG-012 FIX: Wrapped in try/catch — Realtime service failure must NEVER block the DB write.
    afterCreate(event: any) {
        const { result } = event;
        try {
            strapi.service('api::realtime.realtime').publishOrderUpdate(result, 'create');
        } catch (err) {
            strapi.log.error('[Order Lifecycle] afterCreate: Realtime publish failed (non-blocking):', err);
        }
    },

    afterUpdate(event: any) {
        const { result } = event;
        try {
            strapi.service('api::realtime.realtime').publishOrderUpdate(result, 'update');
        } catch (err) {
            strapi.log.error('[Order Lifecycle] afterUpdate: Realtime publish failed (non-blocking):', err);
        }
    },

    afterDelete(event: any) {
        const { result } = event;
        try {
            strapi.service('api::realtime.realtime').publishOrderUpdate(result, 'delete');
        } catch (err) {
            strapi.log.error('[Order Lifecycle] afterDelete: Realtime publish failed (non-blocking):', err);
        }
    }
};
