module.exports = {
    routes: [
        {
            method: 'POST',
            path: '/ingredients/:id/adjust',
            handler: 'adjust.adjustStock',
            config: {
                policies: [],
                middlewares: [],
            },
        },
    ],
};
