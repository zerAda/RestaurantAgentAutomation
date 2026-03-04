const hits = new Map<string, { count: number; firstHit: number }>();

import type { Core } from '@strapi/strapi';

export default (_config: any, { strapi }: { strapi: Core.Strapi }) => {
    return async (ctx: any, next: () => Promise<void>) => {
        // Only target local auth login
        if (ctx.request.path === '/api/auth/local' && ctx.request.method === 'POST') {
            const ip = ctx.request.ip;
            const now = Date.now();
            const record = hits.get(ip) || { count: 0, firstHit: now };

            // Reset after 5 minutes
            if (now - record.firstHit > 5 * 60 * 1000) {
                record.count = 1;
                record.firstHit = now;
            } else {
                record.count += 1;
            }

            hits.set(ip, record);

            // Max 5 attempts per 5 minutes per IP
            if (record.count > 5) {
                ctx.status = 429;
                ctx.body = {
                    error: {
                        status: 429,
                        name: 'TooManyRequestsError',
                        message: 'Too many login attempts, please try again in 5 minutes.',
                        details: {}
                    }
                };
                return; // Break the chain
            }
        }

        await next();
    };
};
