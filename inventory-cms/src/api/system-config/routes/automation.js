module.exports = {
    routes: [
        {
            method: 'POST',
            path: '/automation/trigger',
            handler: 'automation.trigger',
            config: {
                policies: [],
                middlewares: [],
            },
        },
    ],
};
