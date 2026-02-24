import { getTranslation } from '../utils/i18n';

interface Ticket {
    id: string;
    customer: string;
    status: 'open' | 'assigned' | 'resolved';
    subject: string;
    time: string;
    priority: 'low' | 'medium' | 'high';
}

const MOCK_TICKETS: Ticket[] = [
    { id: 'T-101', customer: '+213 555 12 34 56', status: 'open', subject: 'Address ambiguity on delivery', time: '5m ago', priority: 'high' },
    { id: 'T-102', customer: '+213 666 98 76 54', status: 'assigned', subject: 'Payment confirmation help', time: '12m ago', priority: 'medium' },
    { id: 'T-103', customer: '+213 777 44 33 22', status: 'resolved', subject: 'Order modification request', time: '1h ago', priority: 'low' },
];

export function SupportView({ lang }: { lang: any }) {
    const t = (key: string) => getTranslation(key, lang);

    return (
        <div className="space-y-6 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div className="diamond-card p-6 rounded-2xl border-l-4 border-indigo-500">
                    <p className="text-xs font-bold text-zinc-400 uppercase tracking-widest">Open Tickets</p>
                    <h3 className="text-3xl font-black mt-1">4</h3>
                </div>
                <div className="diamond-card p-6 rounded-2xl">
                    <p className="text-xs font-bold text-zinc-400 uppercase tracking-widest">Avg. Response</p>
                    <h3 className="text-3xl font-black mt-1">2.5m</h3>
                </div>
                <div className="diamond-card p-6 rounded-2xl">
                    <p className="text-xs font-bold text-zinc-400 uppercase tracking-widest">Satisfaction</p>
                    <h3 className="text-3xl font-black mt-1">98%</h3>
                </div>
            </div>

            <div className="diamond-card rounded-3xl overflow-hidden">
                <div className="p-6 border-b border-zinc-100 dark:border-zinc-800 flex justify-between items-center">
                    <h4 className="text-xl font-bold">{t('tickets')}</h4>
                    <button className="text-xs font-bold text-indigo-500">Filter Status</button>
                </div>
                <div className="overflow-x-auto">
                    <table className="w-full text-left border-collapse">
                        <thead>
                            <tr className="bg-zinc-50 dark:bg-zinc-900/50 text-[10px] font-black uppercase tracking-widest text-zinc-400">
                                <th className="px-6 py-4">ID</th>
                                <th className="px-6 py-4">Customer</th>
                                <th className="px-6 py-4">Subject</th>
                                <th className="px-6 py-4">Priority</th>
                                <th className="px-6 py-4">Status</th>
                                <th className="px-6 py-4">Action</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800">
                            {MOCK_TICKETS.map((ticket) => (
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
                                    <td className="px-6 py-4">
                                        <button className="px-3 py-1 rounded bg-indigo-500 text-white text-[10px] font-black hover:scale-105 transition-transform">
                                            INTERVENE
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
