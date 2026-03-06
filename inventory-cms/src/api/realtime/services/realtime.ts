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
            redisPub = new Redis(port, host);
            redisPub.on('error', (err) => strapi.log.error('Redis Pub Error', err));
        }
        return redisPub;
    },

    getRedisSubscriber() {
        if (!redisSub) {
            const host = process.env.REDIS_HOST || 'localhost';
            const port = parseInt(process.env.REDIS_PORT || '6379', 10);
            redisSub = new Redis(port, host);
            redisSub.on('error', (err) => strapi.log.error('Redis Sub Error', err));
        }
        return redisSub;
    },

    publishOrderUpdate(order: any, action: 'create' | 'update' | 'delete') {
        const pub = this.getRedisPublisher();
        pub.publish('order_updates', JSON.stringify({ action, order }));
    }
});
