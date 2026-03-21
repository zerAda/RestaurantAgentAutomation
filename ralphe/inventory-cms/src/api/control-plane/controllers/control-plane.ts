import * as os from 'os';
import * as net from 'net';

/**
 * Checks Redis connectivity and returns real connection count via the INFO
 * clients command over a raw TCP connection. No extra npm dependency needed.
 */
function pingRedis(): Promise<{ status: string; connections: number }> {
    return new Promise((resolve) => {
        const host = process.env.REDIS_HOST || 'redis';
        const port = parseInt(process.env.REDIS_PORT || '6379', 10);
        const password = process.env.REDIS_PASSWORD;
        const client = net.createConnection({ host, port });
        let buf = '';

        client.setTimeout(2000);

        client.once('connect', () => {
            // Authenticate first if a password is configured, then request INFO
            if (password) {
                client.write(`*2\r\n$4\r\nAUTH\r\n$${Buffer.byteLength(password)}\r\n${password}\r\n`);
            }
            client.write('*2\r\n$4\r\nINFO\r\n$7\r\nclients\r\n');
        });

        client.on('data', (chunk) => {
            buf += chunk.toString();
            if (buf.includes('connected_clients:')) {
                const m = buf.match(/connected_clients:(\d+)/);
                client.destroy();
                resolve({ status: 'healthy', connections: m ? parseInt(m[1], 10) : 0 });
            }
        });

        client.on('error', () => resolve({ status: 'degraded', connections: 0 }));
        client.on('timeout', () => {
            client.destroy();
            resolve({ status: 'timeout', connections: 0 });
        });
    });
}

/**
 * Checks n8n availability by hitting its /healthz endpoint from inside
 * the internal Docker network. Returns execution counts as 0 when n8n
 * does not expose them via unauthenticated health endpoint.
 */
async function checkN8n(): Promise<{
    status: string;
    active_executions: number;
    queued_executions: number;
}> {
    try {
        const n8nBase = process.env.N8N_WEBHOOK_BASE || 'http://n8n-main:5678';
        const res = await fetch(`${n8nBase}/healthz`, {
            signal: AbortSignal.timeout(2000),
        });
        return {
            status: res.ok ? 'healthy' : 'degraded',
            active_executions: 0,
            queued_executions: 0,
        };
    } catch {
        return { status: 'unreachable', active_executions: 0, queued_executions: 0 };
    }
}

export default {
    status: async (ctx: any) => {
        try {
            const totalMem = os.totalmem();
            const freeMem = os.freemem();
            const usedMem = totalMem - freeMem;
            const memoryPercent = ((usedMem / totalMem) * 100).toFixed(1);
            const loadAvg = os.loadavg();

            // Database ping via Knex
            let dbHealth = 'unknown';
            try {
                // @ts-ignore
                await strapi.db.connection.raw('SELECT 1');
                dbHealth = 'healthy';
            } catch {
                dbHealth = 'degraded';
            }

            // Run Redis + n8n checks in parallel for fast response
            const [redisHealth, n8nHealth] = await Promise.all([pingRedis(), checkN8n()]);

            ctx.send({
                status: 'operational',
                timestamp: new Date().toISOString(),
                services: {
                    database: {
                        status: dbHealth,
                        provider: strapi.config.database.connection.client,
                    },
                    redis: redisHealth,
                    n8n_hypervisor: n8nHealth,
                },
                system: {
                    os: os.platform(),
                    uptime_seconds: Math.floor(os.uptime()),
                    load_average: loadAvg,
                    memory: {
                        total_gb: (totalMem / 1024 / 1024 / 1024).toFixed(2),
                        used_gb: (usedMem / 1024 / 1024 / 1024).toFixed(2),
                        percent_used: memoryPercent,
                    },
                },
            });
        } catch (error) {
            ctx.throw(500, 'Control Plane Error: ' + (error as Error).message);
        }
    },
};
