export default {
    routes: [
        {
            method: 'POST',
            path: '/automation/trigger',
            handler: 'automation.trigger',
            config: {
                auth: 'users-permissions',
                policies: [],
                middlewares: [],
            },
        },
    ],
};
