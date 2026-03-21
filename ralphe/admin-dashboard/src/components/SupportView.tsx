import { useState, useEffect, useCallback, useRef } from 'react';
import { getTranslation, type Language } from '../utils/i18n';
import { strapi } from '../services/strapiClient';
import { MessageSquare, Clock, ShieldAlert, CheckCircle2, RefreshCw, User, Hash, AlertCircle } from 'lucide-react';
import { cn } from '../lib/utils';

interface Ticket {
    id: string;
    customer: string;
    status: 'open' | 'assigned' | 'resolved';
    subject: string;
    time: string;
    priority: 'low' | 'medium' | 'high';
}

interface StrapiConvState {
    id: number;
    documentId: string;
    user_id: string;
    channel: string;
    status: string;
    last_message?: string;
    createdAt: string;
    priority?: string;
}

function mapPriority(p?: string): 'low' | 'medium' | 'high' {
    if (p === 'high') return 'high';
    if (p === 'medium') return 'medium';
    return 'low';
}

function mapStatus(s?: string): 'open' | 'assigned' | 'resolved' {
    if (s === 'SUPPORT_HUMAN' || s === 'HANDOFF') return 'open';
    if (s === 'ASSIGNED') return 'assigned';
    if (s === 'RESOLVED' || s === 'DONE') return 'resolved';
    return 'open';
}

export function SupportView({ lang }: { lang: Language }) {
    const t = (key: string) => getTranslation(key, lang);
    const [tickets, setTickets] = useState<Ticket[]>([]);
    const [loading, setLoading] = useState(true);
    const [fetchError, setFetchError] = useState<string | null>(null);

    const mounted = useRef(true);
    useEffect(() => {
        mounted.current = true;
        return () => {
            mounted.current = false;
        };
    }, []);

    const fetchTickets = useCallback(async (signal?: AbortSignal) => {
        try {
            const res = await strapi.find<StrapiConvState>('conversation-states', {
                filters: { status: { $in: ['SUPPORT_HUMAN', 'HANDOFF', 'ASSIGNED', 'RESOLVED'] } },
                sort: ['createdAt:desc'],
                pagination: { limit: 50 },
            });

            if (signal?.aborted) return;
            const data = Array.isArray(res.data) ? (res.data as unknown as StrapiConvState[]) : [];

            const mapped: Ticket[] = data.map(c => {
                const ago = Math.round((Date.now() - new Date(c.createdAt).getTime()) / 60000);
                const timeStr = ago < 60 ? `${ago}m ago` : `${Math.round(ago / 60)}h ago`;
                const safeMessage = (c.last_message || '').replace(/<[^>]*>?/gm, '');
                return {
                    id: `T-${String(c.id).padStart(3, '0')}`,
                    customer: c.user_id || `User #${c.id}`,
                    status: mapStatus(c.status),
                    subject: safeMessage.slice(0, 60) || 'Support request',
                    time: timeStr,
                    priority: mapPriority(c.priority),
                };
            });

            if (mounted.current) {
                setTickets(mapped);
                setFetchError(null);
            }
        } catch (err) {
            if (signal?.aborted) return;
            if (mounted.current) {
                setFetchError(err instanceof Error ? err.message : 'Failed to load tickets');
                setTickets([]);
            }
        } finally {
            if (mounted.current) {
                setLoading(false);
            }
        }
    }, []);

    useEffect(() => {
        const controller = new AbortController();
        fetchTickets(controller.signal);
        const interval = setInterval(() => {
            if (mounted.current) {
                fetchTickets(controller.signal);
            }
        }, 30000);

        return () => {
            controller.abort();
            clearInterval(interval);
        };
    }, [fetchTickets]);

    const openCount = tickets.filter(t => t.status === 'open').length;

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                {[
                    { label: 'Active Relays', value: openCount, sub: 'Needs Attention', color: 'text-error', icon: AlertCircle },
                    { label: 'Total Handlers', value: tickets.length, sub: 'Active Sessions', color: 'text-brand-primary', icon: MessageSquare },
                    { label: 'Resolved', value: tickets.filter(t => t.status === 'resolved').length, sub: 'Successful Handoffs', color: 'text-success', icon: CheckCircle2 }
                ].map((stat, i) => (
                    <div key={i} className="quantum-card p-6 flex items-start justify-between group">
                        <div>
                            <p className="text-[10px] font-black text-zinc-600 uppercase tracking-widest mb-1 italic">{stat.label}</p>
                            <h3 className={cn("text-4xl font-black tracking-tighter", stat.color)}>{stat.value}</h3>
                            <p className="text-[10px] font-bold text-zinc-500 mt-2 uppercase tracking-tighter">{stat.sub}</p>
                        </div>
                        <div className="w-10 h-10 rounded-xl bg-white/5 border border-white/5 flex items-center justify-center text-zinc-500 group-hover:text-white transition-colors">
                            <stat.icon size={20} />
                        </div>
                    </div>
                ))}
            </div>

            {fetchError && (
                <div className="p-4 bg-error/10 border border-error/20 text-error rounded-2xl flex items-center gap-3">
                    <ShieldAlert size={18} />
                    <span className="text-xs font-black uppercase tracking-widest">{fetchError} — RESTORED FROM LOGS</span>
                </div>
            )}

            <div className="quantum-card overflow-hidden">
                <div className="p-8 border-b border-white/5 flex justify-between items-center bg-white/[0.02]">
                    <div className="flex items-center gap-4">
                        <div className="w-10 h-10 rounded-xl bg-indigo-500/20 text-indigo-400 flex items-center justify-center shadow-inner">
                            <RefreshCw size={20} className={loading ? 'animate-spin' : ''} />
                        </div>
                        <div>
                            <h4 className="text-xl font-black text-white tracking-tighter italic">{t('tickets') || 'Communication Relays'}</h4>
                            <p className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest mt-1">Real-time omnichannel sync</p>
                        </div>
                    </div>
                </div>

                <div className="overflow-x-auto">
                    {loading && tickets.length === 0 ? (
                        <div className="p-20 text-center font-black uppercase tracking-[0.3em] text-zinc-600 animate-pulse">Scanning Relays...</div>
                    ) : tickets.length === 0 ? (
                        <div className="p-20 text-center font-black uppercase tracking-[0.3em] text-zinc-700">No Active Relays Detected</div>
                    ) : (
                        <table className="w-full text-left border-collapse">
                            <thead>
                                <tr className="text-[10px] font-black uppercase tracking-widest text-zinc-500 border-b border-white/5 bg-white/[0.01]">
                                    <th className="px-8 py-5 flex items-center gap-2"><Hash size={12} /> ID</th>
                                    <th className="px-8 py-5">Customer Cluster</th>
                                    <th className="px-8 py-5">DNA / Subject</th>
                                    <th className="px-8 py-5 text-center">Protocol / Status</th>
                                    <th className="px-8 py-5 text-right"><Clock size={12} className="inline mr-2" /> Latency</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-white/5">
                                {tickets.map((ticket) => (
                                    <tr key={ticket.id} className="hover:bg-white/[0.03] transition-all group">
                                        <td className="px-8 py-5 font-mono text-[11px] font-bold text-zinc-500 italic">#{ticket.id}</td>
                                        <td className="px-8 py-5">
                                            <div className="flex items-center gap-3">
                                                <div className="w-8 h-8 rounded-lg bg-zinc-900 border border-white/5 flex items-center justify-center text-zinc-600 group-hover:text-white transition-colors">
                                                    <User size={14} />
                                                </div>
                                                <span className="text-sm font-black text-white tracking-tighter">{ticket.customer}</span>
                                            </div>
                                        </td>
                                        <td className="px-8 py-5">
                                            <div className="flex flex-col">
                                                <span className="text-sm font-medium text-zinc-300 line-clamp-1 italic">"{ticket.subject}"</span>
                                                <div className="mt-1 flex items-center gap-2">
                                                    <span className={cn(
                                                        "text-[9px] font-black uppercase tracking-widest px-1.5 py-0.5 rounded",
                                                        ticket.priority === 'high' ? 'text-error bg-error/10 border border-error/20' :
                                                            ticket.priority === 'medium' ? 'text-warning bg-warning/10 border border-warning/20' :
                                                                'text-success bg-success/10 border border-success/20'
                                                    )}>
                                                        {ticket.priority} priority
                                                    </span>
                                                </div>
                                            </div>
                                        </td>
                                        <td className="px-8 py-5">
                                            <div className="flex items-center justify-center gap-3">
                                                <div className={cn(
                                                    "px-4 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-widest shadow-lg flex items-center gap-2",
                                                    ticket.status === 'open' ? 'bg-indigo-500/20 text-indigo-400 border border-indigo-500/30' :
                                                        ticket.status === 'assigned' ? 'bg-warning/20 text-warning border border-warning/30' :
                                                            'bg-success/20 text-success border border-success/30'
                                                )}>
                                                    <span className={cn(
                                                        "w-1.5 h-1.5 rounded-full",
                                                        ticket.status === 'open' ? 'bg-indigo-500 animate-pulse' :
                                                            ticket.status === 'assigned' ? 'bg-warning' :
                                                                'bg-success'
                                                    )} />
                                                    {ticket.status}
                                                </div>
                                            </div>
                                        </td>
                                        <td className="px-8 py-5 text-right text-[10px] font-black text-zinc-600 uppercase tracking-widest italic group-hover:text-zinc-400 transition-colors">
                                            {ticket.time}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    )}
                </div>
            </div>
        </div>
    );
}
