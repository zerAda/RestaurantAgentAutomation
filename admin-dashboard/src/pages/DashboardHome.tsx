import { useState, useEffect, useCallback } from 'react';
import { ShoppingBag, Users, DollarSign, Clock, TrendingUp, TrendingDown, RefreshCw, ExternalLink, AlertTriangle } from "lucide-react";
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { cn } from "@/lib/utils";
import { strapi } from "@/services/strapiClient";
import { SkeletonKPIRow, SkeletonChart, SkeletonRow } from "../components/SkeletonLoader";
import { AnimatedNumber } from "../components/AnimatedNumber";

/* ── Types ── */
interface KPICardProps {
    title: string;
    value: number;
    suffix?: string;
    change: number | null;
    icon: React.ElementType;
}

interface StrapiOrder {
    id: number;
    total_cents: number;
    status: string;
    createdAt: string;
    order_items?: { label: string; qty: number }[];
}

interface StrapiCustomer {
    id: number;
    createdAt: string;
}

interface StrapiIngredient {
    id: number;
    name: string;
    current_stock: number;
    min_stock_alert: number;
}

interface DashboardData {
    revenue: number;
    prevRevenue: number;
    activeOrders: number;
    prevActiveOrders: number;
    avgPrepMin: number;
    prevAvgPrepMin: number;
    activeCustomers: number;
    prevActiveCustomers: number;
    revenueChart: { day: string; revenue: number }[];
    topProducts: { name: string; count: number; revenue: number }[];
    lowStockAlerts: { name: string; current: number; min: number }[];
}

/* ── KPI Card ── */
const KPICard = ({ title, value, suffix = '', change, icon: Icon }: KPICardProps) => (
    <div className="bg-[#0a0a0a] p-6 rounded-xl border border-neutral-800 hover:border-neutral-700 transition-all duration-300 group">
        <div className="flex items-center justify-between mb-4">
            <div className="p-2.5 bg-neutral-900/80 rounded-lg border border-neutral-800 group-hover:border-neutral-700 transition-colors">
                <Icon className="h-4 w-4 text-neutral-400 group-hover:text-neutral-300 transition-colors" />
            </div>
            {change !== null && (
                <div className="flex items-center gap-1.5">
                    {change > 0 ? (
                        <TrendingUp className="w-3 h-3 text-emerald-400" />
                    ) : change < 0 ? (
                        <TrendingDown className="w-3 h-3 text-red-400" />
                    ) : null}
                    <span className={cn(
                        "text-xs font-semibold tracking-wider",
                        change > 0 ? "text-emerald-400" : change < 0 ? "text-red-400" : "text-neutral-500"
                    )}>
                        {change > 0 ? "+" : ""}{change}%
                    </span>
                </div>
            )}
        </div>
        <h3 className="text-3xl font-semibold text-white tracking-tight flex items-baseline gap-1">
            <AnimatedNumber value={value || 0} />
            {suffix && <span className="text-xl text-neutral-400 font-medium">{suffix}</span>}
        </h3>
        <p className="text-sm text-neutral-500 mt-2 font-medium">{title}</p>
    </div>
);

/* ── Custom Tooltip ── */
const ChartTooltip = ({ active, payload, label }: { active?: boolean; payload?: { value: number }[]; label?: string }) => {
    if (!active || !payload?.length) return null;
    return (
        <div className="bg-neutral-900 border border-neutral-700 rounded-lg px-4 py-2.5 shadow-xl">
            <p className="text-xs text-neutral-400 mb-1">{label}</p>
            <p className="text-sm font-semibold text-white">{payload[0].value.toLocaleString()} DA</p>
        </div>
    );
};

/* ── Helpers ── */
function calcChange(current: number, prev: number): number | null {
    if (prev === 0 && current === 0) return 0;
    if (prev === 0) return 100;
    return Math.round(((current - prev) / prev) * 100);
}

function getDayLabel(dateStr: string): string {
    const d = new Date(dateStr);
    return d.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric' });
}

/* ── Main Component ── */
export default function DashboardHome() {
    const [data, setData] = useState<DashboardData | null>(null);
    const [loading, setLoading] = useState(true);
    const [lastRefresh, setLastRefresh] = useState<Date>(new Date());

    const fetchDashboard = useCallback(async () => {
        setLoading(true);
        try {
            const now = new Date();
            const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
            const weekAgo = new Date(now.getTime() - 7 * 86400000).toISOString();
            const twoWeeksAgo = new Date(now.getTime() - 14 * 86400000).toISOString();
            const monthAgo = new Date(now.getTime() - 30 * 86400000).toISOString();

            // Fetch all data in parallel
            const [ordersRes, prevOrdersRes, customersRes, prevCustomersRes, ingredientsRes] = await Promise.all([
                strapi.find<StrapiOrder>('orders', {
                    sort: ['createdAt:desc'],
                    pagination: { limit: 500 },
                    filters: { createdAt: { $gte: weekAgo } },
                }),
                strapi.find<StrapiOrder>('orders', {
                    pagination: { limit: 500 },
                    filters: { createdAt: { $gte: twoWeeksAgo, $lt: weekAgo } },
                }),
                strapi.find<StrapiCustomer>('customers', {
                    pagination: { limit: 500 },
                    filters: { createdAt: { $gte: monthAgo } },
                }),
                strapi.find<StrapiCustomer>('customers', {
                    pagination: { limit: 500 },
                    filters: { createdAt: { $gte: new Date(now.getTime() - 60 * 86400000).toISOString(), $lt: monthAgo } },
                }),
                strapi.find<StrapiIngredient>('ingredients', {
                    pagination: { limit: 200 },
                }),
            ]);

            const orders = Array.isArray(ordersRes.data) ? ordersRes.data : [];
            const prevOrders = Array.isArray(prevOrdersRes.data) ? prevOrdersRes.data : [];
            const customers = Array.isArray(customersRes.data) ? customersRes.data : [];
            const prevCustomers = Array.isArray(prevCustomersRes.data) ? prevCustomersRes.data : [];
            const ingredients = Array.isArray(ingredientsRes.data) ? ingredientsRes.data : [];

            // Revenue
            const revenue = orders.reduce((s, o) => s + (o.total_cents || 0), 0) / 100;
            const prevRevenue = prevOrders.reduce((s, o) => s + (o.total_cents || 0), 0) / 100;

            // Active orders (not DONE/CANCELLED)
            const activeOrders = orders.filter(o => !['done', 'cancelled', 'DONE', 'CANCELLED'].includes(o.status || '')).length;
            const prevActiveOrders = prevOrders.filter(o => !['done', 'cancelled', 'DONE', 'CANCELLED'].includes(o.status || '')).length;

            // Avg prep time (mock based on time between creation and now for active orders)
            const todayOrders = orders.filter(o => o.createdAt >= todayStart);
            const avgPrepMin = todayOrders.length > 0
                ? Math.round(todayOrders.reduce((s, o) => s + Math.min(60, (now.getTime() - new Date(o.createdAt).getTime()) / 60000), 0) / todayOrders.length)
                : 0;

            // Revenue chart (last 7 days)
            const dayMap = new Map<string, number>();
            for (let i = 6; i >= 0; i--) {
                const d = new Date(now.getTime() - i * 86400000);
                const key = d.toISOString().split('T')[0];
                dayMap.set(key, 0);
            }
            orders.forEach(o => {
                const key = o.createdAt?.split('T')[0];
                if (key && dayMap.has(key)) {
                    dayMap.set(key, (dayMap.get(key) || 0) + (o.total_cents || 0) / 100);
                }
            });
            const revenueChart = Array.from(dayMap.entries()).map(([date, rev]) => ({
                day: getDayLabel(date),
                revenue: Math.round(rev),
            }));

            // Top products
            const productCounts = new Map<string, { count: number; revenue: number }>();
            orders.forEach(o => {
                o.order_items?.forEach(item => {
                    const existing = productCounts.get(item.label) || { count: 0, revenue: 0 };
                    existing.count += item.qty;
                    existing.revenue += (o.total_cents || 0) / 100 / (o.order_items?.length || 1);
                    productCounts.set(item.label, existing);
                });
            });
            const topProducts = Array.from(productCounts.entries())
                .map(([name, v]) => ({ name, count: v.count, revenue: Math.round(v.revenue) }))
                .sort((a, b) => b.count - a.count)
                .slice(0, 5);

            // Low stock alerts
            const lowStockAlerts = ingredients
                .filter(i => (i.current_stock || 0) <= (i.min_stock_alert || 10))
                .map(i => ({ name: i.name, current: i.current_stock, min: i.min_stock_alert }))
                .slice(0, 5);

            setData({
                revenue,
                prevRevenue,
                activeOrders,
                prevActiveOrders,
                avgPrepMin,
                prevAvgPrepMin: avgPrepMin, // no historical data for this
                activeCustomers: customers.length,
                prevActiveCustomers: prevCustomers.length,
                revenueChart,
                topProducts,
                lowStockAlerts,
            });
            setLastRefresh(new Date());
        } catch (err) {
            console.error('[DashboardHome] Fetch failed:', err);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchDashboard();
        const interval = setInterval(fetchDashboard, 30000); // Refresh every 30s
        return () => clearInterval(interval);
    }, [fetchDashboard]);

    const revenueChange = data ? calcChange(data.revenue, data.prevRevenue) : null;
    const ordersChange = data ? calcChange(data.activeOrders, data.prevActiveOrders) : null;
    const customerChange = data ? calcChange(data.activeCustomers, data.prevActiveCustomers) : null;

    return (
        <div className="space-y-6 max-w-7xl">
            {/* Header */}
            <div className="flex items-center justify-between">
                <div>
                    <h2 className="text-2xl font-semibold text-white tracking-tight">Vue d'ensemble</h2>
                    <p className="text-neutral-500 text-sm mt-1">
                        Données en direct — actualisé {lastRefresh.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                    </p>
                </div>
                <div className="flex gap-2">
                    <button
                        onClick={fetchDashboard}
                        className="px-4 py-2 bg-neutral-900 border border-neutral-800 text-white text-sm font-medium rounded-lg hover:border-neutral-700 transition-all flex items-center gap-2"
                    >
                        <RefreshCw className={cn("h-3.5 w-3.5", loading && "animate-spin")} />
                        Actualiser
                    </button>
                    <a
                        href="/kiosk"
                        target="_blank"
                        rel="noreferrer"
                        className="px-4 py-2 bg-white text-black text-sm font-semibold rounded-lg hover:bg-neutral-200 transition-colors flex items-center gap-2"
                    >
                        <ExternalLink className="h-3.5 w-3.5" />
                        Ouvrir Kiosque
                    </a>
                </div>
            </div>

            {/* KPI Grid */}
            {loading && !data ? (
                <SkeletonKPIRow count={4} />
            ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                    <KPICard
                        title="Chiffre d'Affaires (7j)"
                        value={data?.revenue || 0}
                        suffix="DA"
                        change={revenueChange}
                        icon={DollarSign}
                    />
                    <KPICard
                        title="Commandes Actives"
                        value={data?.activeOrders || 0}
                        change={ordersChange}
                        icon={ShoppingBag}
                    />
                    <KPICard
                        title="Temps de Préparation Moy."
                        value={data?.avgPrepMin || 0}
                        suffix="min"
                        change={null} // Need historical active orders to calc
                        icon={Clock}
                    />
                    <KPICard
                        title="Nouveaux Clients (30j)"
                        value={data?.activeCustomers || 0}
                        change={customerChange}
                        icon={Users}
                    />
                </div>
            )}

            {/* Charts Section */}
            {loading && !data ? (
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    <SkeletonChart className="lg:col-span-2" />
                    <div className="bg-[#0a0a0a] rounded-xl border border-neutral-800 p-6">
                        <div className="w-24 h-3 rounded bg-neutral-800 mb-6" />
                        <div className="space-y-3">
                            {[1, 2, 3, 4, 5].map(i => <SkeletonRow key={i} />)}
                        </div>
                    </div>
                </div>
            ) : (
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    {/* Revenue Chart */}
                    <div className="lg:col-span-2 bg-[#0a0a0a] rounded-xl border border-neutral-800 p-6 flex flex-col">
                        <h3 className="text-sm font-medium text-neutral-400 mb-4">Revenus — 7 derniers jours</h3>
                        {data && data.revenueChart.length > 0 ? (
                            <div className="flex-1 min-h-[280px]">
                                <ResponsiveContainer width="100%" height="100%">
                                    <AreaChart data={data.revenueChart} margin={{ top: 5, right: 10, left: 0, bottom: 0 }}>
                                        <defs>
                                            <linearGradient id="revenueGrad" x1="0" y1="0" x2="0" y2="1">
                                                <stop offset="5%" stopColor="#10b981" stopOpacity={0.3} />
                                                <stop offset="95%" stopColor="#10b981" stopOpacity={0} />
                                            </linearGradient>
                                        </defs>
                                        <CartesianGrid strokeDasharray="3 3" stroke="#262626" />
                                        <XAxis
                                            dataKey="day"
                                            tick={{ fill: '#737373', fontSize: 12 }}
                                            axisLine={{ stroke: '#262626' }}
                                            tickLine={false}
                                        />
                                        <YAxis
                                            tick={{ fill: '#737373', fontSize: 12 }}
                                            axisLine={false}
                                            tickLine={false}
                                            tickFormatter={(v: number) => v >= 1000 ? `${(v / 1000).toFixed(0)}K` : String(v)}
                                        />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Area
                                            type="monotone"
                                            dataKey="revenue"
                                            stroke="#10b981"
                                            strokeWidth={2}
                                            fill="url(#revenueGrad)"
                                            animationDuration={800}
                                        />
                                    </AreaChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <div className="flex-1 flex items-center justify-center min-h-[280px]">
                                <p className="text-neutral-600 text-sm">Aucune commande cette semaine.</p>
                            </div>
                        )}
                    </div>

                    {/* Top Products */}
                    <div className="bg-[#0a0a0a] rounded-xl border border-neutral-800 p-6 flex flex-col">
                        <h3 className="text-sm font-medium text-neutral-400 mb-4">Top Produits (7j)</h3>
                        {data && data.topProducts.length > 0 ? (
                            <div className="space-y-3 flex-1">
                                {data.topProducts.map((p, i) => (
                                    <div key={p.name} className="flex items-center gap-3">
                                        <span className={cn(
                                            "w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold",
                                            i === 0 ? "bg-amber-500/20 text-amber-400" :
                                                i === 1 ? "bg-neutral-400/20 text-neutral-300" :
                                                    i === 2 ? "bg-orange-600/20 text-orange-400" :
                                                        "bg-neutral-800 text-neutral-500",
                                        )}>
                                            {i + 1}
                                        </span>
                                        <div className="flex-1 min-w-0">
                                            <p className="text-sm text-white font-medium truncate">{p.name}</p>
                                            <p className="text-xs text-neutral-500">{p.count} vendus</p>
                                        </div>
                                        <span className="text-sm font-semibold text-neutral-300">{p.revenue.toLocaleString()} DA</span>
                                    </div>
                                ))}
                            </div>
                        ) : (
                            <div className="flex-1 flex items-center justify-center">
                                <p className="text-neutral-600 text-sm">Aucune donnée.</p>
                            </div>
                        )}
                    </div>
                </div>
            )}

            {/* Low Stock Alerts */}
            {data && data.lowStockAlerts.length > 0 && (
                <div className="bg-red-500/5 rounded-xl border border-red-500/20 p-5">
                    <div className="flex items-center gap-2 mb-3">
                        <AlertTriangle className="w-4 h-4 text-red-400" />
                        <h3 className="text-sm font-semibold text-red-400">Alertes Stock Bas ({data.lowStockAlerts.length})</h3>
                    </div>
                    <div className="flex flex-wrap gap-3">
                        {data.lowStockAlerts.map(a => (
                            <div key={a.name} className="px-3 py-2 bg-red-500/10 rounded-lg border border-red-500/15">
                                <span className="text-sm text-red-300 font-medium">{a.name}</span>
                                <span className="text-xs text-red-400/70 ml-2">{a.current}/{a.min}</span>
                            </div>
                        ))}
                    </div>
                </div>
            )}
        </div>
    );
}
