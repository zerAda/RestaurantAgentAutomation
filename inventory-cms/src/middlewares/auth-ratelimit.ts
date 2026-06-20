/**
 * [C-04] Rate Limiter Middleware — Hybrid Redis/Memory
 * 
 * P0 FIX: In production with REDIS_URL set, uses Redis for distributed rate limiting.
 * Falls back to in-memory Maps for development or when Redis is unavailable.
 * 
 * [C-05] FIX: n8n internal requests are excluded from rate limiting.
 */

import type { Core } from '@strapi/strapi';
import Redis from 'ioredis';

// ── In-memory fallback stores ──
const authHits = new Map<string, { count: number; firstHit: number }>();
const apiHits = new Map<string, { count: number; firstHit: number }>();

// Parse trusted internal IPs from env
const TRUSTED_INTERNAL_IPS: Set<string> = new Set(
    (process.env.N8N_INTERNAL_IPS || '')
        .split(',')
        .map(ip => ip.trim())
        .filter(Boolean)
);
TRUSTED_INTERNAL_IPS.add('127.0.0.1');
TRUSTED_INTERNAL_IPS.add('::1');
TRUSTED_INTERNAL_IPS.add('::ffff:127.0.0.1');

// ── Redis rate limiter (production) ──
let redisClient: any = null;
const USE_REDIS = !!process.env.REDIS_URL || !!process.env.REDIS_HOST;

async function getRedisClient() {
    if (redisClient) return redisClient;
    if (!USE_REDIS) return null;
    try {
        const url = process.env.REDIS_URL || `redis://${process.env.REDIS_HOST || 'localhost'}:${process.env.REDIS_PORT || '6379'}`;
        redisClient = new Redis(url, { maxRetriesPerRequest: 1, lazyConnect: true });
        await redisClient.connect();
        redisClient.on('error', () => { redisClient = null; });
        return redisClient;
    } catch {
        return null;
    }
}

async function redisRateCheck(key: string, limit: number, windowSec: number): Promise<boolean> {
    const redis = await getRedisClient();
    if (!redis) return true; // Redis unavailable → allow (fallback to memory)
    try {
        const current = await redis.incr(key);
        if (current === 1) await redis.expire(key, windowSec);
        return current <= limit;
    } catch {
        return true; // Redis error → allow
    }
}

// Garbage collection for in-memory fallback
setInterval(() => {
    const now = Date.now();
    for (const [ip, record] of authHits.entries()) {
        if (now - record.firstHit > 5 * 60 * 1000) authHits.delete(ip);
    }
    for (const [ip, record] of apiHits.entries()) {
        if (now - record.firstHit > 60 * 1000) apiHits.delete(ip);
    }
}, 5 * 60 * 1000);

function memoryRateCheck(store: Map<string, { count: number; firstHit: number }>, ip: string, limit: number, windowMs: number): boolean {
    const now = Date.now();
    const record = store.get(ip) || { count: 0, firstHit: now };
    if (now - record.firstHit > windowMs) {
        record.count = 1;
        record.firstHit = now;
    } else {
        record.count += 1;
    }
    store.set(ip, record);
    return record.count <= limit;
}

const RATE_LIMIT_RESPONSE = {
    error: {
        status: 429,
        name: 'TooManyRequestsError',
        message: 'Rate limit exceeded. Please try again later.',
        details: {}
    }
};

export default (_config: any, { strapi }: { strapi: Core.Strapi }) => {
    return async (ctx: any, next: () => Promise<void>) => {
        const ip = ctx.request.ip;
        const path = ctx.request.path;

        // Skip for trusted internal IPs
        if (TRUSTED_INTERNAL_IPS.has(ip)) {
            return await next();
        }

        // 1. Strict auth login limit (5 attempts / 5 mins)
        if ((path === '/api/auth/local' || path === '/admin/login') && ctx.request.method === 'POST') {
            let allowed: boolean;
            if (USE_REDIS) {
                allowed = await redisRateCheck(`rl:auth:${ip}`, 5, 300);
            } else {
                allowed = memoryRateCheck(authHits, ip, 5, 5 * 60 * 1000);
            }
            if (!allowed) {
                ctx.status = 429;
                ctx.body = { ...RATE_LIMIT_RESPONSE, error: { ...RATE_LIMIT_RESPONSE.error, message: 'Too many login attempts. Try again in 5 minutes.' } };
                return;
            }
        }

        // 2. General API limit (300 req / 1 min)
        if ((path.startsWith('/api/') || path.startsWith('/admin/')) && path !== '/api/auth/local' && path !== '/admin/login') {
            let allowed: boolean;
            if (USE_REDIS) {
                allowed = await redisRateCheck(`rl:api:${ip}`, 300, 60);
            } else {
                allowed = memoryRateCheck(apiHits, ip, 300, 60 * 1000);
            }
            if (!allowed) {
                ctx.status = 429;
                ctx.body = RATE_LIMIT_RESPONSE;
                return;
            }
        }

        await next();
    };
};
