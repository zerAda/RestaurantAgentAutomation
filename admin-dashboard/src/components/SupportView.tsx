import { useState, useEffect, useCallback, useRef } from 'react';
import { getTranslation, type Language } from '../utils/i18n';
import { strapi } from '../services/strapiClient';

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
    // Strapi v5 uses createdAt (camelCase), not created_at
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

    // mounted ref prevents setState calls after unmount (interval stacking guard)
    const mounted = useRef(true);
    useEffect(() => {
        mounted.current = true;
        return () => {
            mounted.current = false;
        };
    }, []);

    // fetchTickets wrapped in useCallback with [] deps so the interval reference is stable.
    const fetchTickets = useCallback(async (signal?: AbortSignal) => {
        try {
            const res = await strapi.find<StrapiConvState>('conversation-states', {
                filters: { status: { $in: ['SUPPORT_HUMAN', 'HANDOFF', 'ASSIGNED', 'RESOLVED'] } },
                sort: ['createdAt:desc'],
                pagination: { limit: 50 },
            });

            // Abort check: do not update state if the effect was cleaned up
            if (signal?.aborted) return;

            // Runtime array guard — avoids unsafe double-cast
            const data = Array.isArray(res.data) ? (res.data as unknown as StrapiConvState[]) : [];

            const mapped: Ticket[] = data.map(c => {
                // Strapi v5: createdAt (camelCase)
                const ago = Math.round((Date.now() - new Date(c.createdAt).getTime()) / 60000);
                const timeStr = ago < 60 ? `${ago}m ago` : `${Math.round(ago / 60)}h ago`;
                const safeMessage = (c.last_message || '').replace(/<[^>]*>?/gm, ''); // XSS sanitize
                return {
                    id: `T-${String(c.id).padStart(3, '0')}`,
                    // Avoid country-code assumption; fall back to generic user identifier
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
            console.error('[SupportView] Strapi fetch failed:', err);
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

        // Initial fetch
        fetchTickets(controller.signal);

        // Poll every 30 seconds; only update state if still mounted
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
        <div className="space-y-6 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div className="diamond-card p-6 rounded-2xl border-l-4 border-indigo-500">
                    <p className="text-xs font-bold text-zinc-400 uppercase tracking-widest">Open Tickets</p>
                    <h3 className="text-3xl font-black mt-1">{openCount}</h3>
                </div>
                <div className="diamond-card p-6 rounded-2xl">
                    <p className="text-xs font-bold text-zinc-400 uppercase tracking-widest">Total Active</p>
                    <h3 className="text-3xl font-black mt-1">{tickets.length}</h3>
                </div>
                <div className="diamond-card p-6 rounded-2xl">
                    <p className="text-xs font-bold text-zinc-400 uppercase tracking-widest">Resolved</p>
                    <h3 className="text-3xl font-black mt-1">{tickets.filter(t => t.status === 'resolved').length}</h3>
                </div>
            </div>

            {fetchError && (
                <div className="p-4 bg-red-500/10 text-red-400 rounded-xl">
                    {fetchError} — showing cached or partial data
                </div>
            )}

            <div className="diamond-card rounded-3xl overflow-hidden">
                <div className="p-6 border-b border-zinc-100 dark:border-zinc-800 flex justify-between items-center">
                    <h4 className="text-xl font-bold">{t('tickets')}</h4>
                    <button
                        onClick={() => fetchTickets()}
                        className="text-xs font-bold text-indigo-500 px-2 py-1 rounded hover:bg-indigo-500/10 transition-colors"
                    >
                        Refresh
                    </button>
                </div>
                <div className="overflow-x-auto">
                    {loading ? (
                        <div className="p-12 text-center text-zinc-400">Loading tickets…</div>
                    ) : tickets.length === 0 ? (
                        <div className="p-12 text-center text-zinc-400">No active support tickets.</div>
                    ) : (
                        <table className="w-full text-left border-collapse">
                            <thead>
                                <tr className="bg-zinc-50 dark:bg-zinc-900/50 text-[10px] font-black uppercase tracking-widest text-zinc-400">
                                    <th className="px-6 py-4">ID</th>
                                    <th className="px-6 py-4">Customer</th>
                                    <th className="px-6 py-4">Subject</th>
                                    <th className="px-6 py-4">Priority</th>
                                    <th className="px-6 py-4">Status</th>
                                    <th className="px-6 py-4">Time</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800">
                                {tickets.map((ticket) => (
                                    <tr key={ticket.id} className="hover:bg-zinc-50/50 dark:hover:bg-zinc-800/30 transition-colors">
                                        <td className="px-6 py-4 font-mono text-xs">{ticket.id}</td>
                                        <td className="px-6 py-4 text-sm font-medium">{ticket.customer}</td>
                                        <td className="px-6 py-4 text-sm opacity-70">{ticket.subject}</td>
                                        <td className="px-6 py-4">
                                            <span className={`px-2 py-0.5 rounded text-[10px] font-bold uppercase ${ticket.priority === 'high' ? 'bg-red-500/10 text-red-500' :
                                                ticket.priority === 'medium' ? 'bg-amber-500/10 text-amber-500' :
                                                    'bg-green-500/10 text-green-500'
                                                }`}>
                                                {ticket.priority}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-2">
                                                <div className={`w-1.5 h-1.5 rounded-full ${ticket.status === 'open' ? 'bg-indigo-500' :
                                                    ticket.status === 'assigned' ? 'bg-amber-500' :
                                                        'bg-green-500'
                                                    }`} />
                                                <span className="text-xs font-bold capitalize">{ticket.status}</span>
                                            </div>
                                        </td>
                                        <td className="px-6 py-4 text-xs text-zinc-400">{ticket.time}</td>
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
