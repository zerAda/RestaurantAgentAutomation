import type { Core } from '@strapi/strapi';

let requestCounters: Record<string, number> = {};
let latencyBuckets: Record<string, number[]> = {};

export const getMetricsData = () => {
    let output = '# HELP http_requests_total Total number of HTTP requests\n# TYPE http_requests_total counter\n';

    for (const [key, count] of Object.entries(requestCounters)) {
        output += `http_requests_total{${key}} ${count}\n`;
    }

    output += '\n# HELP http_request_duration_ms Duration of HTTP requests in ms\n# TYPE http_request_duration_ms summary\n';
    for (const [key, latencies] of Object.entries(latencyBuckets)) {
        if (latencies.length === 0) continue;
        latencies.sort((a, b) => a - b);
        const p50 = latencies[Math.floor(latencies.length * 0.50)];
        const p95 = latencies[Math.floor(latencies.length * 0.95)];
        const p99 = latencies[Math.floor(latencies.length * 0.99)];

        output += `http_request_duration_ms{${key},quantile="0.5"} ${p50}\n`;
        output += `http_request_duration_ms{${key},quantile="0.95"} ${p95}\n`;
        output += `http_request_duration_ms{${key},quantile="0.99"} ${p99}\n`;
    }

    // Add active connections and memory usage fake/real metrics
    const memUse = process.memoryUsage();
    output += '\n# HELP nodejs_memory_heap_used_bytes Memory usage\n# TYPE nodejs_memory_heap_used_bytes gauge\n';
    output += `nodejs_memory_heap_used_bytes ${memUse.heapUsed}\n`;

    return output;
};

export default (config: any, { strapi }: { strapi: Core.Strapi }) => {
    return async (ctx: any, next: () => Promise<void>) => {
        if (ctx.request.path === '/api/metrics') {
            return await next();
        }

        const start = Date.now();

        try {
            await next();
        } finally {
            const duration = Date.now() - start;

            // Group paths to prevent cardinality explosion
            let routeGroup = ctx.request.path;
            if (routeGroup.startsWith('/api/')) {
                const parts = routeGroup.split('/');
                // Normalize UUIDs and numeric IDs to ":id"
                const normalizedKey = parts[2] ? parts[2].replace(/^[0-9a-fA-F-]+$|^\d+$/, ':id') : '';
                routeGroup = `/${parts[1]}/${normalizedKey}`;
            }

            const method = ctx.request.method;
            const status = ctx.response.status || 500;

            const labels = `method="${method}",status="${status}",path="${routeGroup}"`;

            requestCounters[labels] = (requestCounters[labels] || 0) + 1;

            if (!latencyBuckets[labels]) latencyBuckets[labels] = [];
            latencyBuckets[labels].push(duration);

            // Keep memory bounded to last 1000 requests per route
            if (latencyBuckets[labels].length > 1000) {
                latencyBuckets[labels].shift();
            }
        }
    };
};
