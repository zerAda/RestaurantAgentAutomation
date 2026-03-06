import { useState, useEffect, useCallback, useRef } from 'react';
import { Bell, X, ShoppingBag, AlertTriangle, Zap, TrendingUp, Package, History, CheckCheck, Loader2, Activity } from 'lucide-react';
import { strapi } from '../services/strapiClient';
import { useToast } from './ToastProvider';
import { cn } from '../lib/utils';

/* ── Types ── */
interface Notification {
    id: string;
    type: 'order' | 'stock' | 'error' | 'alert' | 'revenue';
    title: string;
    message: string;
    time: string;
    read: boolean;
}

const TYPE_CONFIG: Record<string, { icon: any; color: string; bg: string; pulse?: boolean }> = {
    order: { icon: ShoppingBag, color: 'text-brand-primary', bg: 'bg-brand-primary/10', pulse: true },
    stock: { icon: Package, color: 'text-warning', bg: 'bg-warning/10' },
    error: { icon: AlertTriangle, color: 'text-error', bg: 'bg-error/10' },
    alert: { icon: Zap, color: 'text-indigo-400', bg: 'bg-indigo-400/10' },
    revenue: { icon: TrendingUp, color: 'text-success', bg: 'bg-success/10' },
};

function timeAgo(dateStr: string): string {
    const diff = (Date.now() - new Date(dateStr).getTime()) / 60000;
    if (diff < 1) return 'maintenant';
    if (diff < 60) return `${Math.round(diff)}m`;
    if (diff < 1440) return `${Math.round(diff / 60)}h`;
    return `${Math.round(diff / 1440)}j`;
}

export function NotificationCenter() {
    const [open, setOpen] = useState(false);
    const [notifications, setNotifications] = useState<Notification[]>([]);
    const [seenIds, setSeenIds] = useState<Set<string>>(new Set());
    const [loading, setLoading] = useState(false);
    const ref = useRef<HTMLDivElement>(null);
    const isFirstFetch = useRef(true);
    const knownIds = useRef<Set<string>>(new Set());
    const { addToast } = useToast();

    const fetchNotifications = useCallback(async () => {
        setLoading(true);
        try {
            const now = new Date();
            const hourAgo = new Date(now.getTime() - 3600000).toISOString();

            const [ordersRes, stockRes, errorsRes] = await Promise.allSettled([
                strapi.find<any>('orders', {
                    sort: ['createdAt:desc'],
                    pagination: { limit: 10 },
                    filters: { createdAt: { $gte: hourAgo } },
                }),
                strapi.find<any>('ingredients', { pagination: { limit: 200 } }),
                strapi.find<any>('workflow-errors', {
                    sort: ['createdAt:desc'],
                    pagination: { limit: 5 },
                    filters: { createdAt: { $gte: hourAgo } },
                }),
            ]);

            const items: Notification[] = [];

            if (ordersRes.status === 'fulfilled') {
                const orders = (ordersRes.value.data as any[]) || [];
                orders.forEach(o => {
                    items.push({
                        id: `order-${o.id}`,
                        type: 'order',
                        title: 'Command Matrix',
                        message: `#${String(o.id).padStart(4, '0')} — ${(o.total_cents / 100).toFixed(0)} DA Linked`,
                        time: o.createdAt,
                        read: seenIds.has(`order-${o.id}`),
                    });
                });
            }

            if (stockRes.status === 'fulfilled') {
                const ingredients = (stockRes.value.data as any[]) || [];
                ingredients
                    .filter(i => (i.current_stock || 0) <= (i.min_stock_alert || 10))
                    .forEach(i => {
                        items.push({
                            id: `stock-${i.id}`,
                            type: 'stock',
                            title: 'Inventory Decay',
                            message: `${i.name}: ${i.current_stock}/${i.min_stock_alert} logic units`,
                            time: now.toISOString(),
                            read: seenIds.has(`stock-${i.id}`),
                        });
                    });
            }

            if (errorsRes.status === 'fulfilled') {
                const errors = (errorsRes.value.data as any[]) || [];
                errors.forEach(e => {
                    items.push({
                        id: `error-${e.id}`,
                        type: 'error',
                        title: `Neural Drift: ${e.workflow_name}`,
                        message: e.error_message?.slice(0, 80) || 'Unidentified exception',
                        time: e.createdAt,
                        read: seenIds.has(`error-${e.id}`),
                    });
                });
            }

            const sorted = items.sort((a, b) => new Date(b.time).getTime() - new Date(a.time).getTime());
            setNotifications(sorted);

            if (isFirstFetch.current) {
                sorted.forEach(i => knownIds.current.add(i.id));
                isFirstFetch.current = false;
            } else {
                sorted.forEach(i => {
                    if (!knownIds.current.has(i.id)) {
                        knownIds.current.add(i.id);
                        addToast({
                            type: i.type === 'order' ? 'order' : i.type === 'error' ? 'error' : 'info',
                            message: i.message,
                            title: i.title
                        });
                    }
                });
            }
        } catch (err) {
            console.error('[NotificationCenter] telemetry fail');
        } finally {
            setLoading(false);
        }
    }, [seenIds, addToast]);

    useEffect(() => {
        void fetchNotifications();
        const interval = setInterval(fetchNotifications, 20000);
        return () => clearInterval(interval);
    }, [fetchNotifications]);

    useEffect(() => {
        const handler = (e: MouseEvent) => {
            if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
        };
        document.addEventListener('mousedown', handler);
        return () => document.removeEventListener('mousedown', handler);
    }, []);

    const markAllRead = () => {
        const newSeen = new Set(seenIds);
        notifications.forEach(n => newSeen.add(n.id));
        setSeenIds(newSeen);
        setNotifications(prev => prev.map(n => ({ ...n, read: true })));
    };

    const unreadCount = notifications.filter(n => !n.read).length;

    return (
        <div ref={ref} className="relative">
            <button
                onClick={() => setOpen(!open)}
                className={cn(
                    "relative w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center transition-all hover:bg-white/10 group",
                    open && "bg-white/10 border-brand-primary shadow-[0_0_15px_rgba(255,51,102,0.3)]"
                )}
            >
                <Bell size={18} className={cn("text-zinc-500 group-hover:text-white transition-colors", unreadCount > 0 && "animate-tada")} />
                {unreadCount > 0 && (
                    <span className="absolute top-[-2px] right-[-2px] w-4 h-4 bg-brand-primary rounded-full flex items-center justify-center text-[8px] font-black text-black shadow-lg">
                        {unreadCount > 9 ? '!' : unreadCount}
                    </span>
                )}
            </button>

            {open && (
                <div className="absolute right-0 top-14 w-[400px] quantum-card shadow-[0_50px_100px_rgba(0,0,0,0.8)] z-[60] overflow-hidden animate-in fade-in zoom-in duration-300 slide-in-from-top-4">
                    <div className="p-6 border-b border-white/5 bg-white/[0.02] flex items-center justify-between">
                        <div className="flex items-center gap-3">
                            <div className="w-10 h-10 rounded-xl bg-brand-primary/10 text-brand-primary flex items-center justify-center">
                                <Activity size={18} />
                            </div>
                            <div>
                                <h4 className="text-sm font-black text-white uppercase tracking-widest italic">Signal Pulse</h4>
                                <div className="flex items-center gap-2 mt-1">
                                    <div className="w-1.5 h-1.5 rounded-full bg-success animate-pulse" />
                                    <span className="text-[9px] font-black text-zinc-500 uppercase tracking-widest">Active Monitoring</span>
                                </div>
                            </div>
                        </div>
                        <div className="flex items-center gap-2">
                            {unreadCount > 0 && (
                                <button onClick={markAllRead} className="p-2 rounded-lg hover:bg-white/5 text-zinc-500 hover:text-white transition-colors">
                                    <CheckCheck size={16} />
                                </button>
                            )}
                            <button onClick={() => setOpen(false)} className="p-2 rounded-lg hover:bg-white/5 text-zinc-600 hover:text-white transition-colors">
                                <X size={16} />
                            </button>
                        </div>
                    </div>

                    <div className="max-h-[500px] overflow-y-auto no-scrollbar py-2">
                        {notifications.length === 0 ? (
                            <div className="p-20 text-center">
                                <div className="flex flex-col items-center gap-4">
                                    <Zap size={32} className="text-zinc-800" />
                                    <p className="text-[10px] font-black text-zinc-600 uppercase tracking-widest">No neural signals detected</p>
                                </div>
                            </div>
                        ) : (
                            notifications.map(n => {
                                const cfg = TYPE_CONFIG[n.type] || TYPE_CONFIG.alert;
                                const Icon = cfg.icon;
                                return (
                                    <div
                                        key={n.id}
                                        className={cn(
                                            "px-6 py-4 border-b border-white/5 flex items-start gap-4 transition-all group hover:bg-white/[0.03]",
                                            !n.read && "bg-brand-primary/[0.02]"
                                        )}
                                    >
                                        <div className={cn(
                                            "w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 border",
                                            cfg.bg, cfg.color, "border-white/5"
                                        )}>
                                            <Icon size={16} className={cn(cfg.pulse && "animate-pulse")} />
                                        </div>
                                        <div className="flex-1 min-w-0">
                                            <div className="flex items-center justify-between gap-2 mb-1">
                                                <span className="text-xs font-black text-white uppercase tracking-widest italic">{n.title}</span>
                                                <span className="text-[9px] font-bold text-zinc-600 uppercase tracking-tighter">{timeAgo(n.time)}</span>
                                            </div>
                                            <p className="text-[11px] font-medium text-zinc-400 line-clamp-2 leading-relaxed italic">{n.message}</p>
                                        </div>
                                        {!n.read && (
                                            <div className="w-1.5 h-1.5 rounded-full bg-brand-primary mt-2 shadow-[0_0_8px_#FF3366]" />
                                        )}
                                    </div>
                                );
                            })
                        )}
                    </div>

                    <button className="w-full p-4 bg-white/[0.01] hover:bg-white/[0.03] text-[9px] font-black text-zinc-500 hover:text-white uppercase tracking-[0.4em] italic transition-all border-t border-white/5 flex items-center justify-center gap-3 group">
                        <History size={12} className="group-hover:rotate-[-45deg] transition-transform" />
                        Access Signal Archive
                    </button>
                </div>
            )}
        </div>
    );
}
