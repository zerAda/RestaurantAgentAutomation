/**
 * BUG-014 FIX: n8n Webhook Idempotency Service
 *
 * Problem: If the n8n webhook times out or Ollama takes too long, WhatsApp
 * retries up to 3 times. Without deduplication, the same customer message is
 * processed 3 times — generating 3 LLM responses and 3 database entries.
 *
 * Solution: Store processed message IDs in Strapi's cache with a TTL of 5 minutes.
 * n8n should call `POST /api/webhook-idempotency/check` before processing any message.
 */
import type { Core } from '@strapi/strapi';

export default ({ strapi }: { strapi: Core.Strapi }) => ({
    /**
     * Check if a webhook message has already been processed.
     * Returns { isDuplicate: true } if the message_id was seen within the last 5 minutes.
     */
    async check(messageId: string): Promise<{ isDuplicate: boolean }> {
        if (!messageId) return { isDuplicate: false };

        const cacheKey = `webhook:idempotency:${messageId}`;

        // Use in-memory cache if available (Strapi v4+)
        const cached = await strapi.cache?.get(cacheKey);
        if (cached) {
            strapi.log.warn(`[IdempotencyService] Duplicate webhook detected: ${messageId}. Ignoring.`);
            return { isDuplicate: true };
        }

        // Mark as processed with 5-minute TTL
        await strapi.cache?.set(cacheKey, true, { ttl: 300 });

        return { isDuplicate: false };
    },

    /**
     * Explicitly mark a message as processed (call after successful LLM processing).
     */
    async markProcessed(messageId: string): Promise<void> {
        if (!messageId) return;
        const cacheKey = `webhook:idempotency:${messageId}`;
        await strapi.cache?.set(cacheKey, true, { ttl: 300 });
        strapi.log.info(`[IdempotencyService] Marked as processed: ${messageId}`);
    },
});
