export default {
    routes: [
        {
            method: 'GET',
            path: '/realtime/orders/stream',
            handler: 'realtime.streamOrders',
            config: {
                // SSE: browsers cannot send Authorization headers with EventSource.
                // Authentication is enforced manually inside the controller via ?token query param
                // using strapi.admin.services.token.decodeJwtToken(token).
                // auth: false is intentional here — do NOT change without updating the controller.
                auth: false,
                policies: [],
            },
        },
    ],
};
