export default {
    routes: [
        {
            method: 'POST',
            path: '/agent/chat',
            handler: 'agent-chat.chat',
            config: {
                // Uses users-permissions JWT. The controller additionally verifies
                // the token manually to populate ctx.state.user for downstream logic.
                auth: 'users-permissions',
                policies: [],
                middlewares: [],
            },
        },
    ],
};
