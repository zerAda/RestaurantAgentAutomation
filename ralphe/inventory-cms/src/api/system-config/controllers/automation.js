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
        
        let targetUrl;
        let baseUrl;
        try {
            targetUrl = new URL(webhookUrl);
            baseUrl = new URL(n8nBase);
        } catch (e) {
            return ctx.badRequest('Invalid URL format');
        }

        // Strict SSRF mitigation: hostname, port, and protocol must match EXACTLY, and pathname must start with the base pathname.
        const isSafeHost = targetUrl.hostname === baseUrl.hostname && targetUrl.port === baseUrl.port && targetUrl.protocol === baseUrl.protocol;
        const isSafePath = targetUrl.pathname.startsWith(baseUrl.pathname);

        if (!isSafeHost || !isSafePath) {
            return ctx.badRequest('Invalid webhook target for this proxy');
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
