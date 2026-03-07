export default {
    routes: [
        {
            method: 'GET',
            path: '/metrics',
            handler: 'metric.index',
            config: {
                auth: 'users-permissions',
                policies: [],
            }
        }
    ]
};
