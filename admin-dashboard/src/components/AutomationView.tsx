import { motion } from 'framer-motion';
import { getTranslation } from '../utils/i18n';

interface Workflow {
    id: string;
    name: string;
    status: 'active' | 'inactive' | 'error';
    lastRun: string;
    successRate: string;
    type: 'core' | 'sync' | 'strategy';
}

const WORKFLOWS: Workflow[] = [
    {
        id: 'w4',
        name: 'W4 - CORE Bot Agent',
        status: 'active',
        lastRun: '2 mins ago',
        successRate: '99.8%',
        type: 'core'
    },
    {
        id: 'sync',
        name: 'W_INVENTORY_SYNC',
        status: 'active',
        lastRun: '15 mins ago',
        successRate: '100%',
        type: 'sync'
    },
    {
        id: 'asset',
        name: 'W20_ASSET_ENHANCER',
        status: 'active',
        lastRun: 'Never',
        successRate: 'N/A',
        type: 'strategy'
    },
    {
        id: 'advisor',
        name: 'W_AI_STRATEGY_ADVISOR',
        status: 'active',
        lastRun: '1 hour ago',
        successRate: '95.4%',
        type: 'strategy'
    }
];

export function AutomationView({ lang }: { lang: any }) {
    const t = (key: string) => getTranslation(key, lang);

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="flex justify-between items-center">
                <div>
                    <h3 className="text-2xl font-black">{t('automation')}</h3>
                    <p className="text-zinc-500 text-sm">Monitor and trigger your backend n8n automation workflows.</p>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {WORKFLOWS.map((wf) => (
                    <motion.div
                        key={wf.id}
                        initial={{ opacity: 0, x: -20 }}
                        animate={{ opacity: 1, x: 0 }}
                        className="diamond-card p-6 rounded-3xl flex items-center gap-6"
                    >
                        <div className={`w-14 h-14 rounded-2xl flex items-center justify-center text-2xl ${wf.type === 'core' ? 'bg-indigo-500/10 text-indigo-500' :
                                wf.type === 'sync' ? 'bg-green-500/10 text-green-500' :
                                    'bg-purple-500/10 text-purple-500'
                            }`}>
                            {wf.type === 'core' ? '🤖' : wf.type === 'sync' ? '🔄' : '🧠'}
                        </div>

                        <div className="flex-1">
                            <div className="flex items-center gap-2 mb-1">
                                <h4 className="font-bold">{wf.name}</h4>
                                <span className="w-2 h-2 rounded-full bg-green-500 shadow-[0_0_8px_rgba(34,197,94,0.5)]" />
                            </div>
                            <div className="flex gap-4 text-[10px] font-bold text-zinc-400 uppercase tracking-wider">
                                <span>Last: {wf.lastRun}</span>
                                <span>SR: {wf.successRate}</span>
                            </div>
                        </div>

                        <div className="flex gap-2">
                            <button className="w-10 h-10 rounded-xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center hover:bg-zinc-200 dark:hover:bg-zinc-700 transition-colors" title={t('check_health')}>
                                📡
                            </button>
                            <button className="h-10 px-4 rounded-xl bg-indigo-500 text-white text-xs font-black shadow-lg shadow-indigo-500/20 hover:scale-[1.05] active:scale-[0.95] transition-all">
                                {wf.type === 'sync' ? t('run_sync') : 'Trigger'}
                            </button>
                        </div>
                    </motion.div>
                ))}
            </div>

            <div className="diamond-card p-8 rounded-3xl bg-zinc-900 border-none text-white overflow-hidden relative">
                <div className="absolute top-0 right-0 p-8 opacity-10">
                    <span className="text-9xl">⚙️</span>
                </div>
                <div className="relative z-10">
                    <h4 className="text-2xl font-black mb-2">n8n Instance Status</h4>
                    <p className="opacity-60 text-sm mb-6 max-w-md">Your automation engine is healthy. 42 active workflows processed 1,240 events today.</p>
                    <div className="flex gap-4">
                        <div className="px-4 py-2 rounded-xl bg-white/10 backdrop-blur-md text-xs font-bold border border-white/10 uppercase tracking-widest">
                            CPU: 12%
                        </div>
                        <div className="px-4 py-2 rounded-xl bg-white/10 backdrop-blur-md text-xs font-bold border border-white/10 uppercase tracking-widest">
                            RAM: 1.4GB
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
