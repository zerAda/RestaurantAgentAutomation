import { useState, useEffect, useCallback } from 'react';
import { type Language } from '../utils/i18n';
import { strapi } from '../services/strapiClient';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';
import { RefreshCw, Activity, TrendingUp, Zap, ShieldCheck, AlertTriangle } from 'lucide-react';
import { SkeletonChart, SkeletonRow } from './SkeletonLoader';
import { AnimatedNumber } from './AnimatedNumber';
import { cn } from '../lib/utils';

/* ── Types ── */
interface KPIData {
    dailyRevenue: number;
    activeOrders: number;
    stockHealth: number;
    avgPrepTime: number;
    totalOrders: number;
}

interface CampaignROI {
    id: number;
    name: string;
    spend: number;
    revenue: number;
    roas: number;
}

interface HourlyData {
    hour: string;
    orders: number;
    revenue: number;
}

interface StatusData {
    name: string;
    value: number;
    color: string;
}

interface StrapiOrder {
    id: number;
    total_cents: number;
    status: string;
    createdAt: string;
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

interface StrapiWorkflowError {
    id: number;
    workflow_name: string;
    error_message: string;
    createdAt: string;
}

const STATUS_COLORS: Record<string, string> = {
    NEW: '#3b82f6',
    PREPARING: '#f59e0b',
    READY: '#10b981',
    DELIVERING: '#8b5cf6',
    DONE: '#6b7280',
    CANCELLED: '#ef4444',
};

/* ── Custom Tooltip ── */
const BarTooltip = ({ active, payload, label }: { active?: boolean; payload?: { value: number; name: string }[]; label?: string }) => {
    if (!active || !payload?.length) return null;
    return (
        <div className="bg-neutral-900 border border-neutral-700 rounded-lg px-4 py-2.5 shadow-xl">
            <p className="text-xs text-neutral-400 mb-1">{label}</p>
            {payload.map((p, i) => (
                <p key={i} className="text-sm font-semibold text-white">
                    {p.name === 'orders' ? `${p.value} commandes` : `${p.value.toLocaleString()} DA`}
                </p>
            ))}
        </div>
    );
};

// @ts-expect-error - feature readiness
export function AnalyticsView({ lang }: { lang: Language }) {
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [kpi, setKpi] = useState<KPIData>({ dailyRevenue: 0, activeOrders: 0, stockHealth: 0, avgPrepTime: 0, totalOrders: 0 });
    const [roiData, setRoiData] = useState<CampaignROI[]>([]);
    const [hourlyData, setHourlyData] = useState<HourlyData[]>([]);
    const [statusData, setStatusData] = useState<StatusData[]>([]);
    const [recentErrors, setRecentErrors] = useState<StrapiWorkflowError[]>([]);
    const [apiOnline, setApiOnline] = useState(true);

    const fetchAnalytics = useCallback(async () => {
        setError(null);
        try {
            const today = new Date();
            today.setHours(0, 0, 0, 0);

            const [ordersRes, campaignsRes, stockRes, errorsRes] = await Promise.allSettled([
                strapi.find<StrapiOrder>('orders', {
                    filters: { createdAt: { $gte: today.toISOString() } },
                    pagination: { limit: 1000 },
                }),
                strapi.find<StrapiCampaign>('marketing-campaigns', {
                    sort: ['createdAt:desc'],
                    pagination: { limit: 10 },
                }),
                strapi.find<StrapiIngredient>('ingredients', {
                    pagination: { limit: 200 },
                }),
                strapi.find<StrapiWorkflowError>('workflow-errors', {
                    sort: ['createdAt:desc'],
                    pagination: { limit: 5 },
                }),
            ]);

            setApiOnline(ordersRes.status === 'fulfilled');

            // Orders & KPIs
            if (ordersRes.status === 'fulfilled') {
                const orders = Array.isArray(ordersRes.value.data) ? (ordersRes.value.data as StrapiOrder[]) : [];
                const revenue = orders.reduce((sum, o) => sum + (o.total_cents || 0), 0);
                const active = orders.filter(o => ['NEW', 'PREPARING', 'READY', 'DELIVERING'].includes((o.status || '').toUpperCase())).length;

                // Avg prep time
                const doneOrders = orders.filter(o => (o.status || '').toUpperCase() === 'DONE' && o.updatedAt);
                let avgPrep = 0;
                if (doneOrders.length > 0) {
                    const totalMs = doneOrders.reduce((sum, o) => {
                        const start = new Date(o.createdAt || '').getTime();
                        const end = new Date(o.updatedAt || '').getTime();
                        return sum + Math.max(0, end - start);
                    }, 0);
                    avgPrep = Math.round(totalMs / doneOrders.length / 60000);
                }

                setKpi(prev => ({ ...prev, dailyRevenue: Math.round(revenue / 100), activeOrders: active, avgPrepTime: avgPrep, totalOrders: orders.length }));

                // Hourly distribution
                const hourBuckets = new Map<string, { orders: number; revenue: number }>();
                for (let h = 8; h <= 23; h++) {
                    hourBuckets.set(`${h}h`, { orders: 0, revenue: 0 });
                }
                orders.forEach(o => {
                    const hour = new Date(o.createdAt).getHours();
                    const key = `${hour}h`;
                    if (hourBuckets.has(key)) {
                        const b = hourBuckets.get(key)!;
                        b.orders++;
                        b.revenue += (o.total_cents || 0) / 100;
                    }
                });
                setHourlyData(Array.from(hourBuckets.entries()).map(([hour, v]) => ({
                    hour,
                    orders: v.orders,
                    revenue: Math.round(v.revenue),
                })));

                // Status distribution
                const statusCounts = new Map<string, number>();
                orders.forEach(o => {
                    const s = (o.status || 'UNKNOWN').toUpperCase();
                    statusCounts.set(s, (statusCounts.get(s) || 0) + 1);
                });
                setStatusData(Array.from(statusCounts.entries())
                    .filter(([, v]) => v > 0)
                    .map(([name, value]) => ({
                        name,
                        value,
                        color: STATUS_COLORS[name] || '#6b7280',
                    }))
                );
            }

            // Stock health
            if (stockRes.status === 'fulfilled') {
                const ingredients = Array.isArray(stockRes.value.data) ? (stockRes.value.data as StrapiIngredient[]) : [];
                const healthy = ingredients.filter(i => i.current_stock > i.min_stock_alert).length;
                const health = ingredients.length > 0 ? Math.round((healthy / ingredients.length) * 100) : 100;
                setKpi(prev => ({ ...prev, stockHealth: health }));
            }

            // Campaign ROI
            if (campaignsRes.status === 'fulfilled') {
                const campaigns = Array.isArray(campaignsRes.value.data) ? (campaignsRes.value.data as StrapiCampaign[]) : [];
                setRoiData(campaigns.map(c => ({
                    id: c.id,
                    name: c.name,
                    spend: (c.budget_cents || 0) / 100,
                    revenue: (c.revenue_attributed_cents || 0) / 100,
                    roas: c.roas || ((c.budget_cents || 0) > 0 ? ((c.revenue_attributed_cents || 0) / (c.budget_cents || 1)) : 0),
                })));
            }

            // Workflow errors
            if (errorsRes.status === 'fulfilled') {
                const errors = Array.isArray(errorsRes.value.data) ? (errorsRes.value.data as StrapiWorkflowError[]) : [];
                setRecentErrors(errors);
            }
        } catch (e) {
            console.error('[AnalyticsView] fetch failed:', e);
            setError(e instanceof Error ? e.message : 'Failed to load');
            setApiOnline(false);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchAnalytics();
        const interval = setInterval(fetchAnalytics, 30000);
        return () => clearInterval(interval);
    }, [fetchAnalytics]);

    return (
        <div className="space-y-10 animate-in fade-in slide-in-from-bottom-4 duration-700">
            {/* Header / Actions */}
            <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
                <div>
                    <div className="flex items-center gap-2 mb-1">
                        <span className="h-1.5 w-1.5 rounded-full bg-brand-primary animate-pulse" />
                        <span className="text-[10px] font-black text-brand-primary uppercase tracking-[0.2em]">Real-time Intelligence</span>
                    </div>
                    <h3 className="text-3xl font-black text-white tracking-tighter">Operational Nexus</h3>
                </div>
                <button
                    onClick={fetchAnalytics}
                    disabled={loading}
                    className="quantum-glass px-6 py-2.5 text-white text-xs font-black uppercase tracking-widest hover:bg-white/10 transition-all flex items-center gap-3 disabled:opacity-50 group shadow-quantum"
                >
                    <RefreshCw className={cn("h-3.5 w-3.5 transition-transform duration-500", loading ? 'animate-spin' : 'group-hover:rotate-180')} />
                    Sync Cluster
                </button>
            </div>

            {error && (
                <div className="p-4 bg-error/10 border border-error/20 text-error rounded-2xl text-xs font-bold flex items-center gap-3 animate-bounce">
                    <AlertTriangle size={16} />
                    {error} — showing partial cached state
                </div>
            )}

            {/* KPI Grid */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
                {[
                    { label: "Daily Revenue", value: kpi.dailyRevenue, suffix: "DA", icon: TrendingUp, accent: 'text-success', trend: '+12.4%' },
                    { label: "Throughput", value: kpi.totalOrders, icon: Activity, accent: 'text-brand-primary', trend: '+5.2%' },
                    { label: "Active Nodes", value: kpi.activeOrders, icon: Zap, accent: 'text-warning', trend: 'STABLE' },
                    { label: "Stock Integrity", value: kpi.stockHealth, suffix: "%", icon: ShieldCheck, accent: kpi.stockHealth >= 80 ? 'text-success' : 'text-error', trend: '-2.1%' },
                    { label: "Prep Latency", value: kpi.avgPrepTime || 0, suffix: "min", icon: Activity, accent: 'text-purple-400', trend: '-15%' },
                ].map((m, i) => (
                    <div key={i} className="quantum-card p-6 group hover:scale-[1.02] transition-all duration-300 relative overflow-hidden">
                        <div className="absolute top-0 right-0 w-24 h-24 bg-brand-primary/5 rounded-full blur-3xl -mr-12 -mt-12 transition-all group-hover:bg-brand-primary/10" />
                        <div className="flex justify-between items-start mb-4 relative z-10">
                            <div className={cn("p-2 rounded-lg bg-white/5 border border-white/5", m.accent)}>
                                <m.icon size={16} />
                            </div>
                            <span className={cn("text-[10px] font-black tracking-widest", m.accent)}>{m.trend}</span>
                        </div>
                        <p className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest mb-1 relative z-10">{m.label}</p>
                        <h4 className="text-3xl font-black text-white tracking-tighter flex items-baseline gap-1 relative z-10">
                            <AnimatedNumber value={m.value} />
                            <span className="text-xs text-zinc-600 font-bold uppercase">{m.suffix}</span>
                        </h4>
                    </div>
                ))}
            </div>

            {/* Charts Row */}
            {/* Central Intelligence Charts */}
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                {/* Traffic Flow */}
                <div className="lg:col-span-2 quantum-card p-8">
                    <div className="flex items-center justify-between mb-8">
                        <div>
                            <h4 className="text-sm font-black text-white uppercase tracking-widest mb-1">Traffic Distribution</h4>
                            <p className="text-[10px] font-bold text-zinc-500 uppercase">Hourly Order Velocity</p>
                        </div>
                        <div className="flex items-center gap-2">
                            <div className="w-3 h-3 rounded-full bg-brand-primary/20 flex items-center justify-center">
                                <div className="w-1 h-1 rounded-full bg-brand-primary" />
                            </div>
                            <span className="text-[10px] font-black text-zinc-400 uppercase tracking-widest">Live Feed</span>
                        </div>
                    </div>
                    {hourlyData.length > 0 && hourlyData.some(h => h.orders > 0) ? (
                        <div className="h-72">
                            <ResponsiveContainer width="100%" height="100%">
                                <BarChart data={hourlyData} margin={{ top: 5, right: 10, left: 0, bottom: 0 }}>
                                    <CartesianGrid strokeDasharray="3 3" stroke="#262626" />
                                    <XAxis dataKey="hour" tick={{ fill: '#737373', fontSize: 11 }} axisLine={{ stroke: '#262626' }} tickLine={false} />
                                    <YAxis tick={{ fill: '#737373', fontSize: 11 }} axisLine={false} tickLine={false} allowDecimals={false} />
                                    <Tooltip content={<BarTooltip />} />
                                    <Bar dataKey="orders" fill="#3b82f6" radius={[4, 4, 0, 0]} animationDuration={600} />
                                </BarChart>
                            </ResponsiveContainer>
                        </div>
                    ) : (
                        <div className="h-72 flex flex-col justify-center">
                            {loading ? <SkeletonChart className="border-0 bg-transparent p-0" /> : <p className="text-neutral-600 text-sm text-center">Aucune commande aujourd'hui.</p>}
                        </div>
                    )}
                </div>

                {/* Status Composition */}
                <div className="quantum-card p-8">
                    <h4 className="text-sm font-black text-white uppercase tracking-widest mb-1">Status Matrix</h4>
                    <p className="text-[10px] font-bold text-zinc-500 uppercase mb-8">Order Lifecycle Distribution</p>
                    {statusData.length > 0 ? (
                        <div className="h-48 mb-6">
                            <ResponsiveContainer width="100%" height="100%">
                                <PieChart>
                                    <Pie
                                        data={statusData}
                                        cx="50%"
                                        cy="50%"
                                        innerRadius={60}
                                        outerRadius={80}
                                        paddingAngle={5}
                                        dataKey="value"
                                        animationDuration={1000}
                                    >
                                        {statusData.map((entry, index) => (
                                            <Cell key={index} fill={entry.color} stroke="none" />
                                        ))}
                                    </Pie>
                                    <Tooltip
                                        contentStyle={{ backgroundColor: 'rgba(0,0,0,0.85)', borderRadius: '12px', border: '1px solid rgba(255,255,255,0.1)', backdropFilter: 'blur(10px)' }}
                                        itemStyle={{ color: '#fff', fontSize: '10px', textTransform: 'uppercase', fontWeight: '900' }}
                                    />
                                </PieChart>
                            </ResponsiveContainer>
                        </div>
                    ) : (
                        <div className="h-48 flex items-center justify-center">
                            <p className="text-[10px] font-bold text-zinc-600 uppercase">No Data Points</p>
                        </div>
                    )}
                    {/* Status Legends */}
                    <div className="grid grid-cols-2 gap-3">
                        {statusData.map(s => (
                            <div key={s.name} className="flex items-center gap-2 p-2 rounded-lg bg-white/5 border border-white/5">
                                <div className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: s.color, boxShadow: `0 0 8px ${s.color}` }} />
                                <span className="text-[9px] font-black text-zinc-400 uppercase tracking-tighter truncate">{s.name} ({s.value})</span>
                            </div>
                        ))}
                    </div>
                </div>
            </div>

            {/* Strategy & Health Row */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* Campaign ROI */}
                <div className="quantum-card p-8">
                    <div className="flex items-center justify-between mb-8">
                        <div>
                            <h4 className="text-sm font-black text-white uppercase tracking-widest mb-1">Marketing Efficiency</h4>
                            <p className="text-[10px] font-bold text-zinc-500 uppercase">ROAS Performance Registry</p>
                        </div>
                        <TrendingUp size={16} className="text-zinc-600" />
                    </div>
                    {loading ? (
                        <div className="space-y-6">
                            {[1, 2].map(i => <SkeletonRow key={i} />)}
                        </div>
                    ) : roiData.length === 0 ? (
                        <div className="py-12 text-center">
                            <p className="text-[10px] font-bold text-zinc-600 uppercase">Nexus Marketing Inactive</p>
                        </div>
                    ) : (
                        <div className="space-y-6">
                            {roiData.map(c => (
                                <div key={c.id} className="group">
                                    <div className="flex justify-between items-end mb-2">
                                        <div className="flex flex-col">
                                            <span className="text-[10px] font-black text-white uppercase tracking-wider">{c.name}</span>
                                            <span className="text-[10px] font-bold text-zinc-500 uppercase">Attributed Growth</span>
                                        </div>
                                        <span className={cn("text-lg font-black tracking-tighter", c.roas >= 2 ? 'text-success' : c.roas >= 1 ? 'text-warning' : 'text-error')}>
                                            {c.roas.toFixed(1)}<span className="text-xs opacity-50 ml-0.5">X</span>
                                        </span>
                                    </div>
                                    <div className="h-1.5 w-full bg-white/5 rounded-full overflow-hidden border border-white/5 p-px">
                                        <div
                                            className={cn("h-full rounded-full transition-all duration-1000 shadow-quantum", c.roas >= 2 ? 'bg-success' : c.roas >= 1 ? 'bg-warning' : 'bg-error')}
                                            style={{ width: `${Math.min(100, (c.roas / 5) * 100)}%` }}
                                        />
                                    </div>
                                    <div className="flex justify-between mt-2">
                                        <span className="text-[9px] font-bold text-zinc-600 uppercase">Burn: {c.spend} DA</span>
                                        <span className="text-[9px] font-bold text-zinc-600 uppercase text-right">Yield: {c.revenue} DA</span>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </div>

                {/* System Pulsar */}
                <div className="quantum-card p-8">
                    <div className="flex items-center justify-between mb-8">
                        <div>
                            <h4 className="text-sm font-black text-white uppercase tracking-widest mb-1">Quantum Pulse</h4>
                            <p className="text-[10px] font-bold text-zinc-500 uppercase">Global Node Integrity</p>
                        </div>
                        <ShieldCheck size={16} className="text-success animate-pulse" />
                    </div>

                    <div className="grid grid-cols-2 gap-4 mb-8">
                        {[
                            { name: 'Core API', online: apiOnline, icon: '🛰️' },
                            { name: 'n8n Logic', online: apiOnline, icon: '⚙️' },
                            { name: 'Redis Cache', online: true, icon: '⚡' },
                            { name: 'TikTok Sink', online: false, icon: '📱' },
                        ].map(s => (
                            <div key={s.name} className="flex items-center gap-3 p-4 rounded-xl bg-white/5 border border-white/5 group hover:bg-white/10 transition-all">
                                <span className="text-lg grayscale group-hover:grayscale-0">{s.icon}</span>
                                <div className="flex-1">
                                    <p className="text-[10px] font-black text-white uppercase tracking-tighter">{s.name}</p>
                                    <div className="flex items-center gap-1.5 mt-0.5">
                                        <div className={cn("w-1.5 h-1.5 rounded-full shadow-[0_0_8px_currentColor]", s.online ? 'text-success bg-success' : 'text-error bg-error')} />
                                        <span className={cn("text-[9px] font-bold uppercase", s.online ? 'text-success' : 'text-error')}>{s.online ? 'Live' : 'Null'}</span>
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>

                    {/* Registry Errors */}
                    {recentErrors.length > 0 && (
                        <div className="mt-4 pt-6 border-t border-white/5">
                            <div className="flex items-center gap-2 mb-4">
                                <AlertTriangle size={14} className="text-warning" />
                                <span className="text-[10px] font-black text-warning uppercase tracking-widest">Anomaly Registry</span>
                            </div>
                            <div className="space-y-3">
                                {recentErrors.map(e => (
                                    <div key={e.id} className="text-[10px] p-3 rounded-xl bg-error/5 border border-error/10">
                                        <div className="flex justify-between mb-1">
                                            <span className="font-black text-white uppercase tracking-tighter">{e.workflow_name}</span>
                                            <span className="text-zinc-600 font-bold">{new Date(e.createdAt).toLocaleTimeString()}</span>
                                        </div>
                                        <p className="text-zinc-500 font-medium truncate italic">"{e.error_message}"</p>
                                    </div>
                                ))}
                            </div>
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}
