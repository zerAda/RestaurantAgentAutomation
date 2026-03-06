export default {
    routes: [
        {
            method: 'GET',
            path: '/realtime/orders/stream',
            handler: 'realtime.streamOrders',
            config: {
                auth: false, // In production, secure this with admin token block
                // OR auth: { strategies: ['admin'] } 
                // But browsers don't send auth headers automatically in EventSource.
                // We will handle token via query params or middleware if needed.
            },
        },
    ],
};
