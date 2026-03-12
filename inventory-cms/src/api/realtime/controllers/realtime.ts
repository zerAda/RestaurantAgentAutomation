import { Core } from '@strapi/strapi';
import { Context } from 'koa';

export default ({ strapi }: { strapi: Core.Strapi }) => ({
    async streamOrders(ctx: Context) {
        // Secure the SSE endpoint via token query param since EventSource cannot send Authorization header
        const token = ctx.query.token as string;
        if (!token) {
            return ctx.unauthorized('Missing token for event stream');
        }

        try {
            // Verify admin JWT
            const decoded = await strapi.admin.services.token.decodeJwtToken(token);
            if (!decoded || !decoded.isValid) {
                return ctx.unauthorized('Invalid token for event stream');
            }
        } catch (e) {
            return ctx.unauthorized('Token verification failed');
        }

        // Set Koa to handle Server-Sent Events
        ctx.request.socket.setTimeout(0);
        ctx.request.socket.setNoDelay(true);
        ctx.request.socket.setKeepAlive(true);

        ctx.set({
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
            'X-Accel-Buffering': 'no', // Disable buffering on Nginx/Traefik
            'Access-Control-Allow-Origin': '*' // Handled by Strapi CORS mostly, but good to be explicit for SSE
        });

        ctx.status = 200;
        ctx.flushHeaders(); // Instruct Koa/Node to send headers immediately

        const sendEvent = (type: string, data: any) => {
            ctx.res.write(`event: ${type}\n`);
            ctx.res.write(`data: ${JSON.stringify(data)}\n\n`);
        };

        // Send initial connection payload
        sendEvent('connected', { timestamp: Date.now(), message: 'Listening for order updates' });

        // Ping every 30 seconds to keep connection alive through proxies
        const pingInterval = setInterval(() => {
            sendEvent('ping', { timestamp: Date.now() });
        }, 30000);

        const sub = strapi.service('api::realtime.realtime').getRedisSubscriber();

        // We create a duplicate subscriber connection just for this client to avoid complex muxing, 
        // OR we can multiplex. Multiplexing is better for memory. 
        // Let's use Node's EventEmitter for multiplexing from a single Redis sub.

        const onOrderMessage = async (data: any) => {
            sendEvent('order_update', data);
        };

        strapi.eventHub.on('redis.order_updates', onOrderMessage);

        // Cleanup on disconnect
        ctx.req.on('close', () => {
            clearInterval(pingInterval);
            strapi.eventHub.off('redis.order_updates', onOrderMessage);
            ctx.res.end();
        });

        // Hold the connection open
        return new Promise((resolve) => {
            ctx.req.on('close', resolve);
        });
    },

    async cortex(ctx: Context) {
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
