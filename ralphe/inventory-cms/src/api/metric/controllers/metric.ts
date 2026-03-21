import { getMetricsData } from '../../../middlewares/prometheus-tracker';

export default {
    index: async (ctx: any) => {
        const metrics = getMetricsData();
        ctx.type = 'text/plain; version=0.0.4';
        ctx.send(metrics);
    }
};
