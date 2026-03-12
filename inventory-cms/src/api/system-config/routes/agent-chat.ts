export default {
    routes: [
        {
            method: 'POST',
            path: '/agent/chat',
            handler: 'agent-chat.chat',
            config: {
                // auth: false — Strapi 5 does not accept string values for auth.
                // JWT verification is done manually inside the controller.
                auth: false,
                policies: [],
                middlewares: [],
            },
        },
    ],
};
