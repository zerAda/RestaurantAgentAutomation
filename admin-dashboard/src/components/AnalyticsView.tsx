import { useState, useEffect, useCallback } from 'react';
import { getTranslation, type Language } from '../utils/i18n';
import { strapi } from '../services/strapiClient';

interface KPIData {
    dailyRevenue: number;
    activeOrders: number;
    stockHealth: number;
    avgPrepTime: number;
}

interface CampaignROI {
    id: number;
    name: string;
    spend: number;
    revenue: number;
    roas: number;
}

interface StrapiOrder {
    id: number;
    total_cents: number;
    status: string;
    created_at: string;
    updatedAt?: string;
}

interface StrapiCampaign {
    id: number;
    name: string;
    budget_cents?: number;
    revenue_attributed_cents?: number;
    roas?: number;
}

interface StrapiIngredient {
    id: number;
    current_stock: number;
    min_stock_alert: number;
}

export function AnalyticsView({ lang }: { lang: Language }) {
    const t = (key: string) => getTranslation(key, lang);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [kpi, setKpi] = useState<KPIData>({ dailyRevenue: 0, activeOrders: 0, stockHealth: 0, avgPrepTime: 0 });
    const [roiData, setRoiData] = useState<CampaignROI[]>([]);
    const [apiOnline, setApiOnline] = useState(true);

    // Wrapped in useCallback with [] deps — fetchAnalytics uses no state/props from closure.
    const fetchAnalytics = useCallback(async () => {
        setError(null);
        try {
            const today = new Date();
            today.setHours(0, 0, 0, 0);

            const [ordersRes, campaignsRes, stockRes] = await Promise.allSettled([
                strapi.find<StrapiOrder>('orders', {
                    filters: { createdAt: { $gte: today.toISOString() } },
                    // limit: -1 is capped by default maxLimit in Strapi. Using high limit.
                    pagination: { limit: 1000 },
                }),
                strapi.find<StrapiCampaign>('marketing-campaigns', {
                    sort: ['createdAt:desc'],
                    pagination: { limit: 10 },
                }),
                strapi.find<StrapiIngredient>('ingredients', {
                    pagination: { limit: 100 },
                }),
            ]);

            setApiOnline(ordersRes.status === 'fulfilled');

            // KPI: Revenue + active orders + avg prep time
            if (ordersRes.status === 'fulfilled') {
                // Runtime array guard — avoids unsafe double-cast
                const orders = Array.isArray(ordersRes.value.data) ? (ordersRes.value.data as StrapiOrder[]) : [];
                const revenue = orders.reduce((sum, o) => sum + (o.total_cents || 0), 0);
                const active = orders.filter(o => ['NEW', 'PREPARING'].includes(o.status?.toUpperCase() || '')).length;

                // Calculate avg prep time based on DONE orders (updatedAt - createdAt)
                const doneOrders = orders.filter(o => o.status?.toUpperCase() === 'DONE' && o.updatedAt);
                let avgPrep = 0;
                if (doneOrders.length > 0) {
                    const totalPrepMs = doneOrders.reduce((sum, o) => {
                        const start = new Date(o.created_at || o.createdAt || '').getTime();
                        const end = new Date(o.updatedAt || '').getTime();
                        return sum + Math.max(0, end - start);
                    }, 0);
                    avgPrep = Math.round(totalPrepMs / doneOrders.length / 60000); // in minutes
                }

                setKpi(prev => ({ ...prev, dailyRevenue: Math.round(revenue / 100), activeOrders: active, avgPrepTime: avgPrep }));
            }

            // KPI: Stock health
            if (stockRes.status === 'fulfilled') {
                // Runtime array guard — avoids unsafe double-cast
                const ingredients = Array.isArray(stockRes.value.data) ? (stockRes.value.data as StrapiIngredient[]) : [];
                const healthy = ingredients.filter(i => i.current_stock > i.min_stock_alert).length;
                const health = ingredients.length > 0 ? Math.round((healthy / ingredients.length) * 100) : 100;
                setKpi(prev => ({ ...prev, stockHealth: health }));
            }

            // Campaign ROI
            if (campaignsRes.status === 'fulfilled') {
                // Runtime array guard — avoids unsafe double-cast
                const campaigns = Array.isArray(campaignsRes.value.data) ? (campaignsRes.value.data as StrapiCampaign[]) : [];
                const roi: CampaignROI[] = campaigns.map(c => {
                    const spend = (c.budget_cents || 0) / 100;
                    const revenue = (c.revenue_attributed_cents || 0) / 100;
                    const roas = c.roas || (spend > 0 ? revenue / spend : 0);
                    return { id: c.id, name: c.name, spend, revenue, roas };
                });
                setRoiData(roi);
            }
        } catch (e) {
            console.error('[AnalyticsView] fetch failed:', e);
            setError(e instanceof Error ? e.message : 'Failed to load analytics data');
            setApiOnline(false);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchAnalytics();
    }, [fetchAnalytics]);

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="flex justify-between items-center mb-6">
                <div>
                    <h3 className="text-2xl font-black">{t('operational_intelligence') || 'Operational Intelligence'}</h3>
                    <p className="text-zinc-500 text-sm">Real-time KPIs from Strapi.</p>
                </div>
                {!loading && (
                    <button onClick={fetchAnalytics} className="text-xs font-bold text-indigo-500">Refresh</button>
                )}
            </div>

            {error && (
                <div className="p-4 bg-red-500/10 text-red-400 rounded-xl mb-4">
                    {error} — showing cached or partial data
                </div>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
                <MetricCard label="Daily Revenue" value={loading ? '…' : `${kpi.dailyRevenue.toLocaleString()} DA`} delta="Today" icon="💰" />
                <MetricCard label="Active Orders" value={loading ? '…' : kpi.activeOrders.toString()} delta="Live" icon="🔥" />
                <MetricCard label="Stock Health" value={loading ? '…' : `${kpi.stockHealth}%`} delta={kpi.stockHealth >= 80 ? 'Good' : 'Attention'} icon="🌡️" />
                <MetricCard label="Avg. Prep Time" value={loading ? '…' : kpi.avgPrepTime ? `${kpi.avgPrepTime}m` : '—'} delta={kpi.avgPrepTime ? 'Measured' : 'No Data'} icon="⏱️" />
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
                <div className="diamond-card p-8 rounded-3xl">
                    <div className="flex justify-between items-center mb-8">
                        <h4 className="text-xl font-bold">Marketing ROI (ROAS)</h4>
                    </div>
                    {loading ? (
                        <div className="text-center py-8 text-zinc-400">Loading campaigns…</div>
                    ) : roiData.length === 0 ? (
                        <div className="text-center py-8 text-zinc-400">No campaign data yet.</div>
                    ) : (
                        <div className="space-y-6">
                            {roiData.map(campaign => (
                                <div key={campaign.id} className="flex flex-col gap-2">
                                    <div className="flex justify-between items-center">
                                        <span className="font-bold text-sm">{campaign.name}</span>
                                        <span className="text-indigo-500 font-black">{campaign.roas.toFixed(1)}x ROAS</span>
                                    </div>
                                    <div className="flex gap-4 text-xs text-zinc-500">
                                        <span>Spend: {campaign.spend.toLocaleString()} DA</span>
                                        <span>Revenue: {campaign.revenue.toLocaleString()} DA</span>
                                    </div>
                                    <div className="h-2 w-full bg-zinc-100 dark:bg-zinc-800 rounded-full overflow-hidden">
                                        <div
                                            className="h-full bg-gradient-to-r from-indigo-500 to-purple-500 rounded-full"
                                            style={{ width: `${Math.min(100, (campaign.roas / 10) * 100)}%` }}
                                        />
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </div>

                <div className="diamond-card p-8 rounded-3xl">
                    <h4 className="text-xl font-bold mb-8">System &amp; Bot Health</h4>
                    <div className="grid grid-cols-2 gap-4">
                        <BotHealthCard name="Strapi API" status={apiOnline ? 'online' : 'offline'} latency={apiOnline ? 'OK' : 'FAIL'} />
                        <BotHealthCard name="Order Bot (WA)" status={apiOnline ? 'online' : 'offline'} latency="Linked to API" />
                        <BotHealthCard name="Driver Bot (WA)" status={apiOnline ? 'online' : 'offline'} latency="Linked to API" />
                        <BotHealthCard name="TikTok Integration" status="warning" latency="Check Logs" />
                    </div>
                </div>
            </div>
        </div>
    );
}

function MetricCard({ label, value, delta, icon }: { label: string, value: string, delta: string, icon: string }) {
    const isLive = delta === 'Live';
    return (
        <div className="diamond-card p-6 rounded-2xl">
            <div className="flex justify-between items-start mb-4">
                <div className="w-10 h-10 rounded-xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center text-xl">{icon}</div>
                <span className={`text-[10px] font-black px-2 py-1 rounded-md ${isLive ? 'bg-red-500 text-white animate-pulse' : 'bg-zinc-100 dark:bg-zinc-800 text-zinc-500'}`}>
                    {delta}
                </span>
            </div>
            <p className="text-xs font-bold text-zinc-400 uppercase tracking-widest">{label}</p>
            <h4 className="text-2xl font-black mt-1">{value}</h4>
        </div>
    );
}

function BotHealthCard({ name, status, latency }: { name: string, status: 'online' | 'warning' | 'offline', latency: string }) {
    return (
        <div className="p-4 rounded-xl border border-zinc-100 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900/50 flex flex-col gap-3">
            <div className="flex justify-between items-center">
                <span className="font-bold text-sm">{name}</span>
                <div className={`w-2 h-2 rounded-full ${status === 'online' ? 'bg-green-500 animate-pulse shadow-[0_0_8px_rgba(34,197,94,0.5)]' : status === 'warning' ? 'bg-yellow-500' : 'bg-red-500'}`} />
            </div>
            <div className="text-xs text-zinc-500 font-mono">Ping: {latency}</div>
        </div>
    );
}
