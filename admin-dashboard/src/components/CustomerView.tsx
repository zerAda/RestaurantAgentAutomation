import { getTranslation, type Language } from '../utils/i18n';

interface Customer {
    id: string;
    phone: string;
    name: string;
    orders: number;
    totalSpent: string;
    tier: 'Diamond' | 'Gold' | 'Silver' | 'Member';
}

const MOCK_CUSTOMERS: Customer[] = [
    { id: 'C-1', phone: '+213 555 12 34 56', name: 'Zaki B.', orders: 12, totalSpent: '18.400 DA', tier: 'Diamond' },
    { id: 'C-2', phone: '+213 666 98 76 54', name: 'Leila K.', orders: 5, totalSpent: '4.200 DA', tier: 'Gold' },
    { id: 'C-3', phone: '+213 777 44 33 22', name: 'Omar M.', orders: 2, totalSpent: '1.800 DA', tier: 'Silver' },
];

export function CustomerView({ lang }: { lang: Language }) {
    const t = (key: string) => getTranslation(key, lang);

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                <MetricSmall label="Total Customers" value="1,280" icon="👥" />
                <MetricSmall label="Loyalty Enrollment" value="84%" icon="🎁" />
                <MetricSmall label="Avg. LTV" value="4.500 DA" icon="💎" />
                <MetricSmall label="New this week" value="+42" icon="📈" />
            </div>

            <div className="diamond-card rounded-3xl overflow-hidden">
                <div className="p-6 border-b border-zinc-100 dark:border-zinc-800 flex justify-between items-center">
                    <h4 className="text-xl font-bold">{t('customers')}</h4>
                    <div className="flex gap-2">
                        <input type="text" placeholder="Search phone..." className="bg-zinc-50 dark:bg-zinc-800 border-none rounded-lg px-4 py-1.5 text-xs w-48 focus:ring-1 focus:ring-indigo-500" />
                    </div>
                </div>
                <div className="overflow-x-auto">
                    <table className="w-full text-left border-collapse">
                        <thead>
                            <tr className="bg-zinc-50 dark:bg-zinc-900/50 text-[10px] font-black uppercase tracking-widest text-zinc-400">
                                <th className="px-6 py-4">Status</th>
                                <th className="px-6 py-4">Phone</th>
                                <th className="px-6 py-4">Name</th>
                                <th className="px-6 py-4">Orders</th>
                                <th className="px-6 py-4">Total Spent</th>
                                <th className="px-6 py-4">Action</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800">
                            {MOCK_CUSTOMERS.map((cust) => (
                                <tr key={cust.id} className="hover:bg-zinc-50/50 dark:hover:bg-zinc-800/30 transition-colors">
                                    <td className="px-6 py-4">
                                        <span className={`px-2 py-0.5 rounded text-[10px] font-black uppercase tracking-tighter ${cust.tier === 'Diamond' ? 'bg-indigo-500 text-white shadow-lg shadow-indigo-500/20' :
                                            cust.tier === 'Gold' ? 'bg-amber-500 text-white' :
                                                'bg-zinc-100 dark:bg-zinc-800 text-zinc-500'
                                            }`}>
                                            {cust.tier}
                                        </span>
                                    </td>
                                    <td className="px-6 py-4 font-mono text-xs">{cust.phone}</td>
                                    <td className="px-6 py-4 text-sm font-medium">{cust.name}</td>
                                    <td className="px-6 py-4 text-sm">{cust.orders}</td>
                                    <td className="px-6 py-4 text-sm font-bold">{cust.totalSpent}</td>
                                    <td className="px-6 py-4">
                                        <button className="w-8 h-8 rounded-lg bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center hover:bg-indigo-500 hover:text-white transition-all">
                                            👁️
                                        </button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
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
