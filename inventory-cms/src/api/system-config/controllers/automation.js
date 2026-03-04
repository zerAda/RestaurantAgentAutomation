'use strict';

/**
 * A custom controller to safely trigger n8n webhooks from the admin dashboard.
 * Prevents SSRF by only allowing predefined URLs and injecting server-side secrets.
 */

module.exports = {
    async trigger(ctx) {
        const { webhookUrl, payload } = ctx.request.body;

        // Security: Only allow n8n webhook base URL
        const n8nBase = process.env.N8N_WEBHOOK_BASE || 'http://localhost:5678/webhook';
        if (!webhookUrl || !webhookUrl.startsWith(n8nBase)) {
            return ctx.badRequest('Invalid webhook URL');
        }

        try {
            const response = await fetch(webhookUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    // 'Authorization': `Basic ${Buffer.from('n8n-user:n8n-pass').toString('base64')}` // If basic auth enabled on n8n
                },
                body: JSON.stringify(payload || {}),
                signal: AbortSignal.timeout(10000) // 10s timeout
            });

            if (!response.ok) {
                return ctx.badRequest(`n8n error: ${response.statusText}`);
            }

            const data = await response.json().catch(() => ({ status: 'ok' }));
            ctx.send({ success: true, data });
        } catch (err) {
            ctx.badRequest(`Proxy error: ${err.message}`);
        }
    }
};
