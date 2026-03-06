export default {
    routes: [
        {
            method: 'POST',
            path: '/agent/chat',
            handler: 'agent-chat.chat',
            config: {
                policies: [],
                middlewares: [],
                auth: false, // Uses JWT from admin-dashboard (Bearer token) — Strapi validates via ctx.state.user
            },
        },
    ],
};
