export default {
    routes: [
        {
            method: 'GET',
            path: '/control-plane/status',
            handler: 'control-plane.status',
            config: {
                auth: false,
                policies: [],
            }
        }
    ]
};
