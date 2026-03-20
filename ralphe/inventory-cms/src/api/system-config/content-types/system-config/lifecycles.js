'use strict';

/**
 * System-config lifecycle hooks
 * Validates comma-separated fields and ensures data integrity
 */
module.exports = {
    async beforeUpdate(event) {
        const { data } = event.params;

        // Validate comma-separated keyword fields (strip whitespace, dedupe)
        const csvFields = [
            'darija_patterns',
            'handoff_keywords',
            'allowed_audio_domains',
            'allowed_admin_ips',
        ];

        for (const field of csvFields) {
            if (data[field] && typeof data[field] === 'string') {
                const cleaned = data[field]
                    .split(',')
                    .map(s => s.trim())
                    .filter(Boolean);
                const unique = [...new Set(cleaned)];
                data[field] = unique.join(', ');
            }
        }

        // Validate numeric ranges
        if (data.llm_temperature !== undefined) {
            const t = parseFloat(data.llm_temperature);
            if (isNaN(t) || t < 0 || t > 2) {
                throw new Error('llm_temperature must be between 0.0 and 2.0');
            }
        }

        if (data.content_quality_threshold !== undefined) {
            const q = parseInt(data.content_quality_threshold, 10);
            if (isNaN(q) || q < 1 || q > 10) {
                throw new Error('content_quality_threshold must be between 1 and 10');
            }
        }

        if (data.llm_max_tokens !== undefined) {
            const t = parseInt(data.llm_max_tokens, 10);
            if (isNaN(t) || t < 1 || t > 32000) {
                throw new Error('llm_max_tokens must be between 1 and 32000');
            }
        }

        // Validate lat/lng
        if (data.restaurant_lat !== undefined && data.restaurant_lat !== null) {
            const lat = parseFloat(data.restaurant_lat);
            if (isNaN(lat) || lat < -90 || lat > 90) {
                throw new Error('restaurant_lat must be between -90 and 90');
            }
        }
        if (data.restaurant_lng !== undefined && data.restaurant_lng !== null) {
            const lng = parseFloat(data.restaurant_lng);
            if (isNaN(lng) || lng < -180 || lng > 180) {
                throw new Error('restaurant_lng must be between -180 and 180');
            }
        }

        // Validate delivery radius
        if (data.delivery_radius_km !== undefined) {
            const r = parseFloat(data.delivery_radius_km);
            if (isNaN(r) || r <= 0 || r > 100) {
                throw new Error('delivery_radius_km must be between 0 and 100');
            }
        }

        // Validate surge multiplier
        if (data.surge_multiplier_max !== undefined) {
            const s = parseFloat(data.surge_multiplier_max);
            if (isNaN(s) || s < 1 || s > 5) {
                throw new Error('surge_multiplier_max must be between 1.0 and 5.0');
            }
        }

        // Log config changes for audit
        strapi.log.info(`[system-config] Config updated. Fields: ${Object.keys(data).join(', ')}`);
    },

    async afterUpdate(event) {
        const { result, params } = event;
        const ctx = strapi.requestContext.get();
        const adminUser = ctx?.state?.user;

        // 1. Audit Logging
        try {
            await strapi.db.query('api::admin-audit-log.admin-audit-log').create({
                data: {
                    action: 'UPDATE',
                    model: 'system-config',
                    model_id: result.id,
                    admin_user_id: adminUser?.id || null,
                    admin_email: adminUser?.email || 'system',
                    payload_json: params.data || {}
                }
            });
        } catch (e) {
            strapi.log.warn(`[system-config] Failed to write audit log: ${e.message}`);
        }

        // 2. Trigger n8n CMS sync webhook if configured
        const webhookUrl = result.n8n_webhook_base_url;
        if (webhookUrl) {
            try {
                await fetch(`${webhookUrl}/webhook/cms-sync`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        model: 'system-config',
                        event: 'update',
                        data: result,
                    }),
                    signal: AbortSignal.timeout(5000)
                });
                strapi.log.info('[system-config] n8n CMS sync triggered successfully');
            } catch (err) {
                strapi.log.warn(`[system-config] n8n CMS sync failed: ${err.message}`);
            }
        }
    },
};
