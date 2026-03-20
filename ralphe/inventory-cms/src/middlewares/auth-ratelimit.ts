/**
 * [C-04] NOTE: These Maps are in-memory. Counters reset on Strapi restart.
 * An attacker can trigger a DoS-forced-restart to reset auth blacklisting.
 * MIGRATION PATH: Replace Maps with Redis via strapi-plugin-redis when scaling.
 * See: https://github.com/strapi-community/strapi-plugin-redis
 *
 * [C-05] FIX: n8n internal requests are excluded from the general 300 req/min limit.
 * The n8n container can legitimately make hundreds of API calls per minute during
 * workflow execution. Without this, it auto-throttles itself.
 * Configure N8N_INTERNAL_IPS as a comma-separated list in the Strapi .env file.
 * Example: N8N_INTERNAL_IPS=172.20.0.5,172.20.0.6
 */

import type { Core } from '@strapi/strapi';

const authHits = new Map<string, { count: number; firstHit: number }>();
const apiHits = new Map<string, { count: number; firstHit: number }>();

// Parse trusted internal IPs from env (n8n, CI runners, internal services)
const TRUSTED_INTERNAL_IPS: Set<string> = new Set(
    (process.env.N8N_INTERNAL_IPS || '')
        .split(',')
        .map(ip => ip.trim())
        .filter(Boolean)
);

// Always trust Docker internal loopback and localhost
TRUSTED_INTERNAL_IPS.add('127.0.0.1');
TRUSTED_INTERNAL_IPS.add('::1');
TRUSTED_INTERNAL_IPS.add('::ffff:127.0.0.1');

// Garbage collection to prevent Memory Leaks (OOM) on the Maps
setInterval(() => {
    const now = Date.now();
    for (const [ip, record] of authHits.entries()) {
        if (now - record.firstHit > 5 * 60 * 1000) authHits.delete(ip);
    }
    for (const [ip, record] of apiHits.entries()) {
        if (now - record.firstHit > 60 * 1000) apiHits.delete(ip);
    }
}, 5 * 60 * 1000); // Run every 5 minutes

export default (_config: any, { strapi }: { strapi: Core.Strapi }) => {
    return async (ctx: any, next: () => Promise<void>) => {
        const ip = ctx.request.ip;
        const now = Date.now();
        const path = ctx.request.path;

        // [C-05] Skip ALL rate limiting for trusted internal IPs (n8n, CI, etc.)
        if (TRUSTED_INTERNAL_IPS.has(ip)) {
            return await next();
        }

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
                strapi.log.warn(`[AUTH-RATELIMIT] Login brute-force blocked — IP: ${ip}, attempts: ${record.count}`);
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
                strapi.log.warn(`[AUTH-RATELIMIT] API flood blocked — IP: ${ip}, hits: ${record.count}/min`);
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

