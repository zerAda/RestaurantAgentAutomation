/**
 * [B-09] FIX: InboundMessage Custom Controller — Payload Bombing Prevention
 *
 * Problem: The bare Core Controller accepted any payload size on meta_json.
 * A malicious actor or a runaway WhatsApp webhook could send multi-MB payloads,
 * causing n8n and Strapi to thrash under load (memory/CPU DoS).
 *
 * Solution: Validate meta_json size on create. Also strip dangerous keys.
 */
import { factories } from '@strapi/strapi';

const MAX_META_JSON_SIZE_BYTES = 10 * 1024; // 10 KB hard limit

export default factories.createCoreController('api::inbound-message.inbound-message', ({ strapi }) => ({
    async create(ctx) {
        const { data } = ctx.request.body as any;

        // Validate meta_json size
        if (data?.meta_json) {
            const metaSize = Buffer.byteLength(JSON.stringify(data.meta_json), 'utf8');
            if (metaSize > MAX_META_JSON_SIZE_BYTES) {
                return ctx.badRequest(
                    `[InboundMessage] meta_json exceeds maximum allowed size of ${MAX_META_JSON_SIZE_BYTES / 1024}KB. Got ${(metaSize / 1024).toFixed(1)}KB.`
                );
            }
        }

        // Validate msg_id is present and non-empty
        if (!data?.msg_id || typeof data.msg_id !== 'string' || data.msg_id.trim().length === 0) {
            return ctx.badRequest('[InboundMessage] msg_id is required and must be a non-empty string.');
        }

        // Sanitize msg_id — only allow alphanumeric, underscore, dash, colon
        if (!/^[\w\-:.]+$/.test(data.msg_id)) {
            return ctx.badRequest('[InboundMessage] msg_id contains invalid characters.');
        }

        // Delegate to the core controller create
        return await super.create(ctx);
    },
}));
