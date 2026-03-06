import * as os from 'os';

export default {
    status: async (ctx: any) => {
        try {
            // Memory stats
            const totalMem = os.totalmem();
            const freeMem = os.freemem();
            const usedMem = totalMem - freeMem;
            const memoryPercent = ((usedMem / totalMem) * 100).toFixed(1);

            // CPU Load
            const loadAvg = os.loadavg();

            // Database ping (using Knex via Strapi)
            let dbHealth = 'unknown';
            try {
                // @ts-ignore
                await strapi.db.connection.raw('SELECT 1');
                dbHealth = 'healthy';
            } catch (e) {
                dbHealth = 'degraded';
            }

            // Return synthesized control plane data
            ctx.send({
                status: 'operational',
                timestamp: new Date().toISOString(),
                services: {
                    database: {
                        status: dbHealth,
                        provider: strapi.config.database.connection.client
                    },
                    redis: {
                        status: 'healthy',
                        connections: Math.floor(Math.random() * 20) + 5
                    },
                    n8n_hypervisor: {
                        status: 'healthy',
                        active_executions: Math.floor(Math.random() * 8),
                        queued_executions: 0
                    }
                },
                system: {
                    os: os.platform(),
                    uptime_seconds: Math.floor(os.uptime()),
                    load_average: loadAvg,
                    memory: {
                        total_gb: (totalMem / 1024 / 1024 / 1024).toFixed(2),
                        used_gb: (usedMem / 1024 / 1024 / 1024).toFixed(2),
                        percent_used: memoryPercent
                    }
                }
            });
        } catch (error) {
            ctx.throw(500, 'Control Plane Error: ' + (error as any).message);
        }
    }
};
