export default {
    routes: [
        {
            method: 'GET',
            path: '/control-plane/status',
            handler: 'control-plane.status',
            config: {
                auth: false // Open for the purpose of the dashboard or secured by RBAC middleware
            }
        }
    ]
};
