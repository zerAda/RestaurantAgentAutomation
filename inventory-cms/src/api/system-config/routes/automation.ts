export default {
    routes: [
        {
            method: 'POST',
            path: '/automation/trigger',
            handler: 'automation.trigger',
            config: {
                auth: true,
                policies: [],
                middlewares: [],
            },
        },
    ],
};
