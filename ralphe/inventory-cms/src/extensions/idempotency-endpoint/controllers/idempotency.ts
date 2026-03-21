/**
 * [C-03] FIX: Strapi Idempotency HTTP Endpoint for n8n
 *
 * Problem: The idempotency service exists as a Strapi service but n8n has no way
 * to call it — it needs a real HTTP endpoint to invoke before processing any message.
 *
 * Solution: A custom route + controller that wraps the idempotency service,
 * allowing n8n to call POST /api/idempotency/check with { sessionId } to dedup.
 *
 * n8n calls this endpoint, gets { isDuplicate: true|false }, and stops
 * the workflow early if it's a duplicate.
 */

import { factories } from '@strapi/strapi';

export default factories.createCoreController('api::inbound-message.inbound-message', ({ strapi }) => ({
    // Custom action — not tied to the inbound-message collection
    async checkIdempotency(ctx) {
        const { sessionId, type = 'webhook' } = ctx.request.body as any;

        if (!sessionId || typeof sessionId !== 'string' || sessionId.trim().length === 0) {
            return ctx.badRequest('[Idempotency] sessionId is required and must be a non-empty string.');
        }

        const cacheKey = `idempotency:${type}:${sessionId.trim()}`;

        try {
            const cached = await (strapi as any).cache?.get(cacheKey);
            if (cached) {
                strapi.log.warn(`[Idempotency] Duplicate ${type} detected: ${sessionId}. Blocking.`);
                ctx.body = { isDuplicate: true, sessionId, type };
                return;
            }

            // TTL: 5 min for webhooks (WhatsApp retries), 24h for kiosk sessions
            const ttl = type === 'kiosk' ? 86400 : 300;
            await (strapi as any).cache?.set(cacheKey, true, { ttl });

            ctx.body = { isDuplicate: false, sessionId, type };
        } catch (err) {
            strapi.log.error('[Idempotency] Cache error, allowing request through (fail-open):', err);
            // FAIL OPEN: If cache is unavailable, let the request through.
            // This is safer than blocking all requests on cache failure.
            ctx.body = { isDuplicate: false, sessionId, type, cache_error: true };
        }
    },
}));
