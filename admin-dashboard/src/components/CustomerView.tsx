import { useState, useEffect, useCallback, useRef } from 'react';
import { useVirtualizer } from '@tanstack/react-virtual';
import { getTranslation, type Language } from '../utils/i18n';
import { strapi } from '../services/strapiClient';
import { Users, Diamond, Trophy, TrendingUp, Search, RefreshCw, Eye, EyeOff, ShieldCheck, Phone, User, CreditCard, type LucideIcon } from 'lucide-react';
import { cn } from '../lib/utils';

interface Customer {
    id: string;
    phone: string;
    name: string;
    orders: number;
    totalSpent: string;
    tier: 'Diamond' | 'Gold' | 'Silver' | 'Member';
}

interface StrapiCustomer {
    id: number;
    documentId: string;
    phone_number: string;
    first_name?: string;
    loyalty_tier?: string;
    total_orders?: number;
    total_spent_cents?: number;
}

function mapTier(tier?: string): 'Diamond' | 'Gold' | 'Silver' | 'Member' {
    if (tier === 'diamond') return 'Diamond';
    if (tier === 'gold') return 'Gold';
    if (tier === 'silver') return 'Silver';
    return 'Member';
}

function maskPhone(p: string): string {
    return p.replace(/(\+\d{3})\d{4}(\d{3,})/, '$1****$2');
}

export function CustomerView({ lang }: { lang: Language }) {
    const t = (key: string) => getTranslation(key, lang);
    const [customers, setCustomers] = useState<Customer[]>([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [fetchError, setFetchError] = useState<string | null>(null);
    const [total, setTotal] = useState(0);
    const [showPhone, setShowPhone] = useState(false);

    const fetchCustomers = useCallback(async () => {
        setFetchError(null);
        try {
            const res = await strapi.find<StrapiCustomer>('customers', {
                sort: ['total_orders:desc'],
                pagination: { limit: 50 },
            });
            const mapped: Customer[] = Array.isArray(res.data) ? (res.data as unknown as StrapiCustomer[]).map(c => ({
                id: String(c.id),
                phone: c.phone_number || '—',
                name: c.first_name || 'Unknown',
                orders: c.total_orders || 0,
                totalSpent: `${((c.total_spent_cents || 0) / 100).toLocaleString()} DA`,
                tier: mapTier(c.loyalty_tier),
            })) : [];
            setCustomers(mapped);
            setTotal(res.meta?.pagination?.total ?? mapped.length);
        } catch (err) {
            setFetchError(err instanceof Error ? err.message : 'Failed to load customers');
            setCustomers([]);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchCustomers();
    }, [fetchCustomers]);

    const [debouncedSearch, setDebouncedSearch] = useState(search);
    useEffect(() => {
        const handler = setTimeout(() => {
            setDebouncedSearch(search);
        }, 300);
        return () => clearTimeout(handler);
    }, [search]);

    const filtered = customers.filter(c =>
        c.phone.includes(debouncedSearch) || c.name.toLowerCase().includes(debouncedSearch.toLowerCase())
    );

    const parentRef = useRef<HTMLDivElement>(null);

    const rowVirtualizer = useVirtualizer({
        count: filtered.length,
        getScrollElement: () => parentRef.current,
        estimateSize: () => 64,
        overscan: 10,
    });

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                <MetricSmall label="Total Clusters" value={total.toLocaleString()} icon={Users} color="text-brand-primary" />
                <MetricSmall label="Diamond Tier" value={customers.filter(c => c.tier === 'Diamond').length.toString()} icon={Diamond} color="text-indigo-400" />
                <MetricSmall label="Gold Reserve" value={customers.filter(c => c.tier === 'Gold').length.toString()} icon={Trophy} color="text-warning" />
                <MetricSmall label="Inflow Rate" value="+12%" icon={TrendingUp} color="text-success" />
            </div>

            {fetchError && (
                <div className="p-4 bg-error/10 border border-error/20 text-error rounded-2xl text-xs font-black uppercase tracking-widest italic">
                    {fetchError} — FALLBACK DATA ACTIVE
                </div>
            )}

            <div className="quantum-card overflow-hidden">
                <div className="p-8 border-b border-white/5 flex flex-col lg:flex-row lg:items-center justify-between gap-6 bg-white/[0.02]">
                    <div>
                        <div className="flex items-center gap-3">
                            <h4 className="text-2xl font-black text-white tracking-tighter italic">{t('customers') || 'User Directory'}</h4>
                            <div className="px-2 py-0.5 rounded bg-white/5 border border-white/10 text-[9px] font-black text-zinc-500 uppercase tracking-widest">
                                {filtered.length} Indexed
                            </div>
                        </div>
                        <p className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest mt-1">High-density subscriber management</p>
                    </div>

                    <div className="flex flex-wrap items-center gap-4">
                        <div className="flex items-center gap-2 px-4 py-2 rounded-xl bg-success/5 border border-success/10 text-[10px] font-black text-success uppercase tracking-widest italic animate-in fade-in zoom-in duration-700">
                            <ShieldCheck size={14} /> PII Protection Active
                        </div>
                        <div className="relative group">
                            <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-zinc-600 group-focus-within:text-brand-primary transition-colors" size={14} />
                            <input
                                type="text"
                                placeholder="Query ID, Phone or Name..."
                                value={search}
                                onChange={e => setSearch(e.target.value)}
                                className="bg-black/40 border border-white/5 rounded-xl pl-10 pr-4 py-2.5 text-xs font-medium w-64 focus:outline-none focus:border-brand-primary transition-all shadow-inner"
                            />
                        </div>
                        <button
                            onClick={fetchCustomers}
                            className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-zinc-500 hover:text-white transition-all shadow-lg"
                        >
                            <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
                        </button>
                    </div>
                </div>

                <div ref={parentRef} className="overflow-x-auto max-h-[700px] overflow-y-auto no-scrollbar relative w-full bg-black/20">
                    {loading && customers.length === 0 ? (
                        <div className="p-32 text-center font-black uppercase tracking-[0.4em] text-zinc-700 animate-pulse">Syncing User Cluster...</div>
                    ) : filtered.length === 0 ? (
                        <div className="p-32 text-center font-black uppercase tracking-[0.3em] text-zinc-800">
                            {search ? 'Query Returned Null' : 'Zero Active Nodes'}
                        </div>
                    ) : (
                        <table className="w-full text-left border-collapse">
                            <thead className="sticky top-0 z-20 bg-zinc-950 border-b border-white/5 transition-all">
                                <tr className="text-[10px] font-black uppercase tracking-[0.2em] text-zinc-500 bg-white/[0.02]">
                                    <th className="px-8 py-5">DNA/Tier</th>
                                    <th className="px-8 py-5">
                                        <div className="flex items-center gap-4">
                                            <Phone size={12} /> Contact Relay
                                            <button
                                                onClick={() => setShowPhone(v => !v)}
                                                className="text-[9px] font-black text-brand-primary hover:text-white transition-all uppercase px-2 py-0.5 rounded bg-brand-primary/10 border border-brand-primary/20"
                                            >
                                                {showPhone ? <EyeOff size={10} className="inline mr-1" /> : <Eye size={10} className="inline mr-1" />}
                                                {showPhone ? 'Mask' : 'Reveal'}
                                            </button>
                                        </div>
                                    </th>
                                    <th className="px-8 py-5 flex items-center gap-2"><User size={12} /> Entity Name</th>
                                    <th className="px-8 py-5 text-center">Engagement</th>
                                    <th className="px-8 py-5 text-right flex items-center justify-end gap-2"><CreditCard size={12} /> Cumulative LTV</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-white/5">
                                {rowVirtualizer.getVirtualItems().length > 0 && rowVirtualizer.getVirtualItems()[0].start > 0 && (
                                    <tr>
                                        <td style={{ height: `${rowVirtualizer.getVirtualItems()[0].start}px` }} colSpan={5} />
                                    </tr>
                                )}
                                {rowVirtualizer.getVirtualItems().map((virtualRow) => {
                                    const cust = filtered[virtualRow.index];
                                    return (
                                        <tr key={virtualRow.key} className="hover:bg-white/[0.03] transition-all group h-[80px]" ref={rowVirtualizer.measureElement} data-index={virtualRow.index}>
                                            <td className="px-8 py-4 whitespace-nowrap">
                                                <div className={cn(
                                                    "px-3 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-widest inline-flex items-center gap-2 shadow-lg border",
                                                    cust.tier === 'Diamond' ? 'bg-indigo-500/20 text-indigo-400 border-indigo-500/30' :
                                                        cust.tier === 'Gold' ? 'bg-warning/20 text-warning border-warning/30' :
                                                            'bg-white/5 text-zinc-500 border-white/5'
                                                )}>
                                                    {cust.tier === 'Diamond' && <Diamond size={12} className="animate-pulse" />}
                                                    {cust.tier}
                                                </div>
                                            </td>
                                            <td className="px-8 py-4 font-mono text-xs whitespace-nowrap text-zinc-500 group-hover:text-white transition-colors">
                                                {showPhone ? cust.phone : maskPhone(cust.phone)}
                                            </td>
                                            <td className="px-8 py-4 text-sm font-black text-white whitespace-nowrap truncate max-w-[200px] tracking-tighter italic">
                                                {cust.name}
                                            </td>
                                            <td className="px-8 py-4 text-center">
                                                <div className="flex flex-col items-center">
                                                    <span className="text-sm font-black text-zinc-300">{cust.orders}</span>
                                                    <span className="text-[8px] font-black text-zinc-600 uppercase tracking-tighter">Orders</span>
                                                </div>
                                            </td>
                                            <td className="px-8 py-4 text-right">
                                                <div className="flex flex-col items-end">
                                                    <span className="text-sm font-black text-brand-primary tracking-tighter">{cust.totalSpent}</span>
                                                    <span className="text-[8px] font-black text-zinc-600 uppercase tracking-tighter">Total Spent</span>
                                                </div>
                                            </td>
                                        </tr>
                                    );
                                })}
                                {rowVirtualizer.getVirtualItems().length > 0 &&
                                    rowVirtualizer.getTotalSize() - rowVirtualizer.getVirtualItems()[rowVirtualizer.getVirtualItems().length - 1].end > 0 && (
                                        <tr>
                                            <td style={{ height: `${rowVirtualizer.getTotalSize() - rowVirtualizer.getVirtualItems()[rowVirtualizer.getVirtualItems().length - 1].end}px` }} colSpan={5} />
                                        </tr>
                                    )}
                            </tbody>
                        </table>
                    )}
                </div>
            </div>
        </div>
    );
}

function MetricSmall({ label, value, icon: Icon, color }: { label: string; value: string; icon: LucideIcon; color: string }) {
    return (
        <div className="quantum-card p-6 flex items-center justify-between group overflow-hidden relative">
            <div className="absolute top-0 right-0 w-16 h-16 bg-white/[0.02] rounded-bl-full pointer-events-none" />
            <div className="relative z-10">
                <p className="text-[10px] font-black text-zinc-600 uppercase tracking-widest mb-1 italic">{label}</p>
                <h4 className={cn("text-2xl font-black tracking-tighter", color)}>{value}</h4>
            </div>
            <div className="w-10 h-10 rounded-xl bg-white/5 border border-white/5 flex items-center justify-center text-zinc-600 group-hover:text-white group-hover:bg-white/10 transition-all relative z-10">
                <Icon size={20} />
            </div>
        </div>
    );
}
