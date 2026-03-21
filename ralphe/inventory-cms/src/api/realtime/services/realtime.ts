import { Core } from '@strapi/strapi';
import Redis from 'ioredis';

// Shared publisher
let redisPub: Redis | null = null;
let redisSub: Redis | null = null;

export default ({ strapi }: { strapi: Core.Strapi }) => ({
    getRedisPublisher() {
        if (!redisPub) {
            const host = process.env.REDIS_HOST || 'localhost';
            const port = parseInt(process.env.REDIS_PORT || '6379', 10);
            const password = process.env.REDIS_PASSWORD || undefined;
            redisPub = new Redis(port, host, { password, lazyConnect: false, maxRetriesPerRequest: 3 });
            redisPub.on('error', (err) => strapi.log.error('Redis Pub Error', err));
        }
        return redisPub;
    },

    getRedisSubscriber() {
        if (!redisSub) {
            const host = process.env.REDIS_HOST || 'localhost';
            const port = parseInt(process.env.REDIS_PORT || '6379', 10);
            const password = process.env.REDIS_PASSWORD || undefined;
            redisSub = new Redis(port, host, { password, lazyConnect: false, maxRetriesPerRequest: 3 });
            redisSub.on('error', (err) => strapi.log.error('Redis Sub Error', err));
        }
        return redisSub;
    },

    publishOrderUpdate(order: any, action: 'create' | 'update' | 'delete') {
        const pub = this.getRedisPublisher();
        pub.publish('order_updates', JSON.stringify({ action, order }));
    },

    async getCortexData(keys: string[]) {
        const redis = this.getRedisPublisher();
        const results: Record<string, any> = {};
        
        for (const key of keys) {
            try {
                const val = await redis.get(key);
                if (val) {
                    try {
                        results[key] = JSON.parse(val);
                    } catch {
                        results[key] = val;
                    }
                }
            } catch (e) {
                strapi.log.error(`Cortex Fetch Error for ${key}`, e);
            }
        }
        return results;
    }
});
