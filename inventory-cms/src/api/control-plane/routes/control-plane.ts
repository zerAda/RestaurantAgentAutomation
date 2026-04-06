/**
 * Control Plane Routes
 * 
 * P0 SECURITY FIX: /control-plane/status was previously auth: false, exposing
 * OS info, memory %, DB health, Redis state, and n8n reachability to the public internet.
 * 
 * Now split into:
 *   GET /control-plane/health  — public, minimal (just "ok" + timestamp)
 *   GET /control-plane/status  — admin-only, full diagnostics
 */
export default {
    routes: [
        {
            method: 'GET',
            path: '/control-plane/health',
            handler: 'control-plane.health',
            config: {
                auth: false,
                policies: [],
                description: 'Public health check — returns minimal ok/error status',
            }
        },
        {
            method: 'GET',
            path: '/control-plane/status',
            handler: 'control-plane.status',
            config: {
                auth: {
                    scope: ['api::control-plane.control-plane.find'],
                },
                policies: [],
                description: 'Admin-only full diagnostics — requires authenticated admin JWT',
            }
        }
    ]
};
