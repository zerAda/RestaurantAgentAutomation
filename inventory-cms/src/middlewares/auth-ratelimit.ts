const authHits = new Map<string, { count: number; firstHit: number }>();
const apiHits = new Map<string, { count: number; firstHit: number }>();

import type { Core } from '@strapi/strapi';

export default (_config: any, { strapi }: { strapi: Core.Strapi }) => {
    return async (ctx: any, next: () => Promise<void>) => {
        const ip = ctx.request.ip;
        const now = Date.now();
        const path = ctx.request.path;

        // 1. Strict limit for local auth login (5 attempts / 5 mins)
        if (path === '/api/auth/local' && ctx.request.method === 'POST') {
            const record = authHits.get(ip) || { count: 0, firstHit: now };

            if (now - record.firstHit > 5 * 60 * 1000) {
                record.count = 1;
                record.firstHit = now;
            } else {
                record.count += 1;
            }

            authHits.set(ip, record);

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

        // 2. General limit for all other /api/ routes (300 requests / 1 min)
        if (path.startsWith('/api/') && path !== '/api/auth/local') {
            const record = apiHits.get(ip) || { count: 0, firstHit: now };

            // Reset after 1 minute
            if (now - record.firstHit > 60 * 1000) {
                record.count = 1;
                record.firstHit = now;
            } else {
                record.count += 1;
            }

            apiHits.set(ip, record);

            if (record.count > 300) {
                ctx.status = 429;
                ctx.body = {
                    error: {
                        status: 429,
                        name: 'TooManyRequestsError',
                        message: 'Global API rate limit exceeded.',
                        details: {}
                    }
                };
                return; // Break the chain
            }
        }

        await next();
    };
};
