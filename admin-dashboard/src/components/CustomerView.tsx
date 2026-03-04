import { useState, useEffect, useCallback } from 'react';
import { getTranslation, type Language } from '../utils/i18n';
import { strapi } from '../services/strapiClient';

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

// Masks middle digits of a phone number for PII protection.
// e.g. +213 0555 123456 -> +213****23456
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

    // Wrapped in useCallback with [] deps — fetchCustomers uses no state/props from closure.
    const fetchCustomers = useCallback(async () => {
        setFetchError(null);
        try {
            const res = await strapi.find<StrapiCustomer>('customers', {
                sort: ['total_orders:desc'],
                pagination: { limit: 50 },
            });
            // Runtime array guard — avoids unsafe double-cast
            const mapped: Customer[] = Array.isArray(res.data) ? (res.data as unknown as StrapiCustomer[]).map(c => ({
                id: String(c.id),
                phone: c.phone_number || '—',
                name: c.first_name || 'Unknown',
                orders: c.total_orders || 0,
                totalSpent: `${((c.total_spent_cents || 0) / 100).toLocaleString()} DA`,
                tier: mapTier(c.loyalty_tier),
            })) : [];
            setCustomers(mapped);
            // Read total from Strapi pagination meta, fall back to local array length
            setTotal(res.meta?.pagination?.total ?? mapped.length);
        } catch (err) {
            console.error('[CustomerView] Strapi fetch failed:', err);
            setFetchError(err instanceof Error ? err.message : 'Failed to load customers');
            setCustomers([]);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchCustomers();
    }, [fetchCustomers]);

    // Simple manual debounce for search to reduce lag
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

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                <MetricSmall label="Total Customers" value={customers.length.toLocaleString()} icon="👥" />
                <MetricSmall label="Diamond Tier" value={customers.filter(c => c.tier === 'Diamond').length.toString()} icon="💎" />
                <MetricSmall label="Gold Tier" value={customers.filter(c => c.tier === 'Gold').length.toString()} icon="🥇" />
                <MetricSmall label="New this week" value="—" icon="📈" />
            </div>

            {fetchError && (
                <div className="p-4 bg-red-500/10 text-red-400 rounded-xl mb-4">
                    {fetchError} — showing cached or partial data
                </div>
            )}

            <div className="diamond-card rounded-3xl overflow-hidden">
                <div className="p-6 border-b border-zinc-100 dark:border-zinc-800 flex justify-between items-center">
                    <div className="flex flex-col gap-0.5">
                        <h4 className="text-xl font-bold">{t('customers')}</h4>
                        {!loading && (
                            <p className="text-xs text-zinc-400">
                                Showing {filtered.length} of {total} customers
                            </p>
                        )}
                    </div>
                    <div className="flex gap-2 items-center">
                        <button
                            onClick={fetchCustomers}
                            className="text-xs font-bold text-indigo-500 px-2 py-1 rounded hover:bg-indigo-500/10 transition-colors"
                        >
                            Refresh
                        </button>
                        <input
                            type="text"
                            placeholder="Search phone or name..."
                            value={search}
                            onChange={e => setSearch(e.target.value)}
                            className="bg-zinc-50 dark:bg-zinc-800 border-none rounded-lg px-4 py-1.5 text-xs w-48 focus:ring-1 focus:ring-indigo-500"
                        />
                    </div>
                </div>
                <div className="overflow-x-auto">
                    {loading ? (
                        <div className="p-12 text-center text-zinc-400">Loading customers…</div>
                    ) : filtered.length === 0 ? (
                        <div className="p-12 text-center text-zinc-400">
                            {search ? 'No results found.' : 'No customers yet.'}
                        </div>
                    ) : (
                        <table className="w-full text-left border-collapse">
                            <thead>
                                <tr className="bg-zinc-50 dark:bg-zinc-900/50 text-[10px] font-black uppercase tracking-widest text-zinc-400">
                                    <th className="px-6 py-4">Status</th>
                                    <th className="px-6 py-4">
                                        <div className="flex items-center gap-2">
                                            Phone
                                            <button
                                                onClick={() => setShowPhone(v => !v)}
                                                className="text-[9px] font-bold text-indigo-400 hover:text-indigo-500 transition-colors normal-case tracking-normal"
                                            >
                                                {showPhone ? 'Hide' : 'Show'}
                                            </button>
                                        </div>
                                    </th>
                                    <th className="px-6 py-4">Name</th>
                                    <th className="px-6 py-4">Orders</th>
                                    <th className="px-6 py-4">Total Spent</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800">
                                {filtered.map((cust) => (
                                    <tr key={cust.id} className="hover:bg-zinc-50/50 dark:hover:bg-zinc-800/30 transition-colors">
                                        <td className="px-6 py-4">
                                            <span className={`px-2 py-0.5 rounded text-[10px] font-black uppercase tracking-tighter ${cust.tier === 'Diamond' ? 'bg-indigo-500 text-white shadow-lg shadow-indigo-500/20' :
                                                cust.tier === 'Gold' ? 'bg-amber-500 text-white' :
                                                    'bg-zinc-100 dark:bg-zinc-800 text-zinc-500'
                                                }`}>
                                                {cust.tier}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 font-mono text-xs">
                                            {showPhone ? cust.phone : maskPhone(cust.phone)}
                                        </td>
                                        <td className="px-6 py-4 text-sm font-medium">{cust.name}</td>
                                        <td className="px-6 py-4 text-sm">{cust.orders}</td>
                                        <td className="px-6 py-4 text-sm font-bold">{cust.totalSpent}</td>
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

function MetricSmall({ label, value, icon }: { label: string, value: string, icon: string }) {
    return (
        <div className="diamond-card p-4 rounded-xl">
            <div className="flex items-center gap-3">
                <div className="text-xl">{icon}</div>
                <div>
                    <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">{label}</p>
                    <h4 className="text-lg font-black">{value}</h4>
                </div>
            </div>
        </div>
    );
}
