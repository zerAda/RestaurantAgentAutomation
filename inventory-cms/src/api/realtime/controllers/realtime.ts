import { Core } from '@strapi/strapi';
import { Context } from 'koa';

/**
 * Realtime SSE Controller
 * 
 * P0 SECURITY FIX:
 * - Added cookie-based auth as primary method (SSE EventSource can't send Auth headers)
 * - Token-in-query-string kept for backward compat but logs deprecation warning
 * - Removed Access-Control-Allow-Origin: * — uses configured CORS origin only
 */

const ALLOWED_ORIGINS = (process.env.ADMIN_DASHBOARD_ORIGINS || 'http://localhost:5173')
    .split(',')
    .map((o: string) => o.trim());

async function verifySSEAuth(ctx: Context, strapi: Core.Strapi): Promise<boolean> {
    // Check if Strapi core already authenticated the request (via Authorization header)
    if (ctx.state && ctx.state.user) {
        return true;
    }

    // Since EventSource can't send Auth headers, check for cookie or query param
    // We must use the users-permissions JWT service because admin-dashboard uses /api/auth/local
    const jwtService = strapi.plugin('users-permissions').service('jwt');

    // Method 1: Cookie-based auth (set by admin-cookie-auth.ts)
    const cookieToken = ctx.cookies.get('adminJwt');
    if (cookieToken) {
        try {
            const decoded = await jwtService.verify(cookieToken);
            if (decoded && decoded.id) return true;
        } catch { /* fall through to query param */ }
    }

    // Method 2: Query param (legacy, logs warning)
    const queryToken = ctx.query.token as string;
    if (queryToken) {
        strapi.log.warn(
            `[SSE] DEPRECATED: Token-in-query-string auth used from ${ctx.request.ip}. ` +
            'Migrate to cookie-based auth or Authorization headers. This will be removed in v2.'
        );
        try {
            const decoded = await jwtService.verify(queryToken);
            if (decoded && decoded.id) return true;
        } catch { /* fall through */ }
    }

    // Method 3: Authorization header (fallback if ctx.state.user is missing but header is present)
    const headerToken = ctx.request.header.authorization;
    if (headerToken && headerToken.startsWith('Bearer ')) {
        try {
            const decoded = await jwtService.verify(headerToken.substring(7));
            if (decoded && decoded.id) return true;
        } catch { /* fall through */ }
    }

    return false;
}

function getSSEHeaders(ctx: Context): Record<string, string> {
    const origin = ctx.get('Origin') || '';
    const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];

    return {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no',
        'Access-Control-Allow-Origin': allowedOrigin,
        'Access-Control-Allow-Credentials': 'true',
    };
}

export default ({ strapi }: { strapi: Core.Strapi }) => ({
    async streamOrders(ctx: Context) {
        const isAuthed = await verifySSEAuth(ctx, strapi);
        if (!isAuthed) {
            return ctx.unauthorized('Authentication required for event stream');
        }

        ctx.request.socket.setTimeout(0);
        ctx.request.socket.setNoDelay(true);
        ctx.request.socket.setKeepAlive(true);
        ctx.set(getSSEHeaders(ctx));
        ctx.status = 200;
        ctx.flushHeaders();

        const sendEvent = (type: string, data: any) => {
            ctx.res.write(`event: ${type}\n`);
            ctx.res.write(`data: ${JSON.stringify(data)}\n\n`);
        };

        sendEvent('connected', { timestamp: Date.now(), message: 'Listening for order updates' });

        const pingInterval = setInterval(() => {
            sendEvent('ping', { timestamp: Date.now() });
        }, 30000);

        const onOrderMessage = async (data: any) => {
            sendEvent('order_update', data);
        };

        strapi.eventHub.on('redis.order_updates', onOrderMessage);

        ctx.req.on('close', () => {
            clearInterval(pingInterval);
            strapi.eventHub.off('redis.order_updates', onOrderMessage);
            ctx.res.end();
        });

        return new Promise((resolve) => {
            ctx.req.on('close', resolve);
        });
    },

    async cortex(ctx: Context) {
        const isAuthed = await verifySSEAuth(ctx, strapi);
        if (!isAuthed) {
            return ctx.unauthorized('Authentication required for cortex bridge');
        }

        const queryKeys = ctx.query.keys as string;
        if (!queryKeys) {
            return ctx.badRequest('Missing keys parameter');
        }

        const keys = queryKeys.split(',');
        try {
            const data = await strapi.service('api::realtime.realtime').getCortexData(keys);
            ctx.send(data);
        } catch (error) {
            ctx.throw(500, 'Cortex Bridge Error');
        }
    }
});
