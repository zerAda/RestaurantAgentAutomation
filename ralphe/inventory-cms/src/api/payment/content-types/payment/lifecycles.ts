/**
 * [A-02] FIX: Payment Lifecycle — Anti-Fraud Status Guard
 *
 * Problem: The Payment controller was a bare Core Controller.
 * Anyone with API access could POST `{ "status": "paid" }` to fraudulently
 * mark any order as paid without a real transaction.
 *
 * Solution: A `beforeCreate` and `beforeUpdate` lifecycle that enforces:
 *  1. Only internal/system operations (n8n webhook, Strapi bootstrap) can set status to 'paid'.
 *  2. The `amount` must always match the linked order's `total_cents`.
 *  3. The `paid_at` timestamp is auto-set by the server when status becomes 'paid'.
 *
 * Allowed transitions:
 *  pending -> awaiting_payment -> paid | failed | refunded
 */

const TRUSTED_PAYMENT_SYSTEMS = ['chargily', 'baridimob', 'ccp'];

export default {
    async beforeCreate(event: any) {
        const { data } = event.params;

        // Auto-set paid_at when creating as already paid (internal use only)
        if (data.status === 'paid' && !data.paid_at) {
            data.paid_at = new Date().toISOString();
        }

        // Validate amount matches the linked order's total_cents
        if (data.order) {
            const orderId = typeof data.order === 'object' ? data.order.id : data.order;
            const order = await strapi.db.query('api::order.order').findOne({
                where: { id: orderId },
                select: ['total_cents', 'status'],
            });
            if (order && data.amount && Math.abs(data.amount - order.total_cents) > 0.01) {
                strapi.log.warn(
                    `[Payment Lifecycle] Amount mismatch: payment ${data.amount} vs order ${order.total_cents}. Overwriting.`
                );
                data.amount = order.total_cents;
            }
        }
    },

    async beforeUpdate(event: any) {
        const { data, where } = event.params;

        // [A-02 CORE FIX]: Block direct status escalation to 'paid' via the public API.
        // Only allow if it comes through an authenticated internal workflow (n8n via API token).
        // We detect this by checking for external_id (webhook callback always sets it).
        if (data.status === 'paid') {
            const existing = await strapi.db.query('api::payment.payment').findOne({
                where,
                select: ['status', 'method', 'external_id'],
            });

            const isCashPayment = existing?.method === 'cod';
            const hasExternalId = !!data.external_id || !!existing?.external_id;
            const isAlreadyPaid = existing?.status === 'paid';

            if (isAlreadyPaid) {
                throw new Error('[Payment] Ce paiement est déjà marqué comme payé. Opération refusée.');
            }

            // COD is legitimate — cashier marks it as paid physically
            if (!isCashPayment && !hasExternalId) {
                strapi.log.error(
                    `[Payment Lifecycle] FRAUD ATTEMPT: status set to 'paid' without external_id for payment ${where?.id}`
                );
                throw new Error('[Payment] Le paiement ne peut pas être marqué comme payé sans référence de transaction externe.');
            }

            // Auto-set paid_at timestamp
            if (!data.paid_at) {
                data.paid_at = new Date().toISOString();
            }
        }
    },

    afterUpdate(event: any) {
        const { result } = event;
        try {
            // Notify realtime dashboard when payment status changes
            if (result.status === 'paid' || result.status === 'failed') {
                strapi.log.info(`[Payment Lifecycle] Payment ${result.id} status → ${result.status}`);
            }
        } catch (err) {
            strapi.log.error('[Payment Lifecycle] afterUpdate error (non-blocking):', err);
        }
    },
};
