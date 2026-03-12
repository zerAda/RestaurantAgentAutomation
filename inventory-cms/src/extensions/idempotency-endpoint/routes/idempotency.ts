/**
 * [C-03] Custom route for the idempotency endpoint.
 * Exposes: POST /api/idempotency/check
 *
 * Auth: Requires valid Strapi API token (used only by n8n internally).
 */
export default {
    routes: [
        {
            method: 'POST',
            path: '/idempotency/check',
            handler: 'inbound-message.checkIdempotency',
            config: {
                policies: [],
                // Requires authenticated request (n8n uses STRAPI_API_TOKEN bearer)
                auth: {},
            },
        },
    ],
};
