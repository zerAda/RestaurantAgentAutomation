import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { getTranslation, type Language } from '../utils/i18n';
import { strapi } from '../services/strapiClient';
import { Play, X, Loader2, Activity, Settings2, Code2 } from 'lucide-react';

interface Workflow {
    id: string;
    name: string;
    webhookUrl: string;
    status: 'active' | 'inactive' | 'error';
    lastRun: string;
    successRate: string;
    type: 'core' | 'sync' | 'strategy' | 'marketing';
    description: string;
    defaultPayload: string;
}

const N8N_WEBHOOK_BASE = import.meta.env.VITE_N8N_WEBHOOK_BASE || '';

const WORKFLOWS: Workflow[] = [
    {
        id: 'w4',
        name: 'W4 - CORE Bot Agent',
        webhookUrl: `${N8N_WEBHOOK_BASE}/webhook/resto-bot-main`,
        status: 'active',
        lastRun: '2 mins ago',
        successRate: '99.8%',
        type: 'core',
        description: 'Main router for all incoming WhatsApp messages.',
        defaultPayload: JSON.stringify({
            "from": "whatsapp:+213555000000",
            "body": "Bonjour, je veux commander",
            "profileName": "Admin Test"
        }, null, 2)
    },
    {
        id: 'sync',
        name: 'W_INVENTORY_SYNC',
        webhookUrl: `${N8N_WEBHOOK_BASE}/webhook/sync-inventory`,
        status: 'active',
        lastRun: '15 mins ago',
        successRate: '100%',
        type: 'sync',
        description: 'Force sync between POS and Strapi inventory.',
        defaultPayload: JSON.stringify({ "force": true, "source": "admin-dashboard" }, null, 2)
    },
    {
        id: 'ad_gen',
        name: 'W_OMNICHANNEL_CONTENT_GEN',
        webhookUrl: `${N8N_WEBHOOK_BASE}/webhook/generate-content`,
        status: 'active',
        lastRun: '1 hour ago',
        successRate: '95.4%',
        type: 'marketing',
        description: 'Generate new marketing assets using internal LLMs.',
        defaultPayload: JSON.stringify({ "prompt": "Generate a TikTok promo for burgers" }, null, 2)
    },
    {
        id: 'kiosk',
        name: 'W_KIOSK_ORDER',
        webhookUrl: `${N8N_WEBHOOK_BASE}/webhook/kiosk-order`,
        status: 'active',
        lastRun: '5 mins ago',
        successRate: '100%',
        type: 'core',
        description: 'Direct order injection from self-service kiosks.',
        defaultPayload: JSON.stringify({ "table_number": 12, "items": [] }, null, 2)
    }
];

export function AutomationView({ lang }: { lang: Language }) {
    const t = (key: string) => getTranslation(key, lang);
    const [selectedWf, setSelectedWf] = useState<Workflow | null>(null);
    const [payload, setPayload] = useState('');
    const [isTriggering, setIsTriggering] = useState(false);
    const [result, setResult] = useState<{ success: boolean; message: string } | null>(null);

    const openTriggerModal = (wf: Workflow) => {
        setSelectedWf(wf);
        setPayload(wf.defaultPayload);
        setResult(null);
    };

    const handleTrigger = async () => {
        if (!selectedWf) return;
        setIsTriggering(true);
        setResult(null);

        try {
            // Attempt to parse to ensure it's valid JSON
            const parsed = JSON.parse(payload);
            const res = await strapi.post<{ success: boolean; data: any }>('/api/automation/trigger', {
                webhookUrl: selectedWf.webhookUrl,
                payload: parsed
            });

            setResult({ success: true, message: 'Workflow triggered successfully.' });
        } catch (e: unknown) {
            setResult({ success: false, message: e instanceof Error ? e.message : 'Invalid JSON or Network Error' });
        } finally {
            setIsTriggering(false);
        }
    };

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="flex justify-between items-center">
                <div>
                    <h3 className="text-2xl font-black">{t('automation') || 'Automation Engine'}</h3>
                    <p className="text-zinc-500 text-sm">Monitor n8n cluster health and trigger custom workflows with dynamic payloads.</p>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {WORKFLOWS.map((wf) => (
                    <motion.div
                        key={wf.id}
                        initial={{ opacity: 0, x: -20 }}
                        animate={{ opacity: 1, x: 0 }}
                        className="diamond-card p-6 rounded-3xl flex flex-col justify-between gap-6"
                    >
                        <div className="flex items-start gap-4">
                            <div className={`w-14 h-14 shrink-0 rounded-2xl flex items-center justify-center text-2xl ${wf.type === 'core' ? 'bg-indigo-500/10 text-indigo-500' :
                                wf.type === 'sync' ? 'bg-green-500/10 text-green-500' :
                                    wf.type === 'marketing' ? 'bg-pink-500/10 text-pink-500' :
                                        'bg-purple-500/10 text-purple-500'
                                }`}>
                                {wf.type === 'core' ? '🤖' : wf.type === 'sync' ? '🔄' : wf.type === 'marketing' ? '🎨' : '🧠'}
                            </div>

                            <div className="flex-1 min-w-0">
                                <div className="flex items-center gap-2 mb-1">
                                    <h4 className="font-bold truncate">{wf.name}</h4>
                                    <span className="shrink-0 w-2 h-2 rounded-full bg-green-500 shadow-[0_0_8px_rgba(34,197,94,0.5)]" />
                                </div>
                                <p className="text-xs text-zinc-500 dark:text-zinc-400 line-clamp-2">{wf.description}</p>
                                <div className="mt-3 flex gap-4 text-[10px] font-bold text-zinc-400 uppercase tracking-wider">
                                    <span>Last: {wf.lastRun}</span>
                                    <span>SR: {wf.successRate}</span>
                                </div>
                            </div>
                        </div>

                        <div className="flex gap-2">
                            <button className="flex-1 h-10 rounded-xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center gap-2 hover:bg-zinc-200 dark:hover:bg-zinc-700 transition-colors text-xs font-bold text-zinc-600 dark:text-zinc-300">
                                <Activity size={14} /> Health
                            </button>
                            <button
                                onClick={() => openTriggerModal(wf)}
                                className="flex-1 h-10 px-4 rounded-xl bg-indigo-500 text-white text-xs font-black shadow-lg shadow-indigo-500/20 hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center justify-center gap-2"
                            >
                                <Settings2 size={14} /> Trigger...
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
                    <h4 className="text-2xl font-black mb-2">n8n Instance Status (Diamond Cluster)</h4>
                    <p className="opacity-60 text-sm mb-6 max-w-md">Your automation engine is hyper-responsive. 14 live workflows processed 4,820 operations today.</p>
                    <div className="flex gap-4 mb-4">
                        <div className="px-4 py-2 rounded-xl bg-white/10 backdrop-blur-md text-xs font-bold border border-white/10 uppercase tracking-widest flex items-center gap-2">
                            <div className="w-1.5 h-1.5 rounded-full bg-green-500" /> CPU: 12%
                        </div>
                        <div className="px-4 py-2 rounded-xl bg-white/10 backdrop-blur-md text-xs font-bold border border-white/10 uppercase tracking-widest flex items-center gap-2">
                            <div className="w-1.5 h-1.5 rounded-full bg-green-500" /> RAM: 1.4GB / 4GB
                        </div>
                    </div>
                </div>
            </div>

            {/* Dynamic Trigger Modal */}
            <AnimatePresence>
                {selectedWf && (
                    <motion.div
                        initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
                        className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm"
                    >
                        <motion.div
                            initial={{ scale: 0.95, y: 20 }} animate={{ scale: 1, y: 0 }} exit={{ scale: 0.95, y: 20 }}
                            className="bg-zinc-950 border border-zinc-800 w-full max-w-2xl rounded-3xl p-6 shadow-2xl relative overflow-hidden flex flex-col max-h-[90vh]"
                        >
                            <button onClick={() => setSelectedWf(null)} className="absolute top-6 right-6 text-zinc-500 hover:text-white">
                                <X size={20} />
                            </button>

                            <h3 className="text-xl font-bold mb-2 flex items-center gap-2">
                                <Play className="text-indigo-500" size={20} />
                                Trigger: {selectedWf.name}
                            </h3>
                            <p className="text-sm text-zinc-400 mb-6">Edit the JSON payload below before firing the webhook.</p>

                            <div className="flex-1 overflow-auto min-h-0 space-y-4">
                                <div className="space-y-2">
                                    <label className="text-xs font-bold text-zinc-500 uppercase tracking-widest flex items-center gap-2">
                                        <Code2 size={14} /> Payload (JSON)
                                    </label>
                                    <textarea
                                        value={payload}
                                        onChange={e => setPayload(e.target.value)}
                                        className="w-full h-64 font-mono text-xs bg-black border border-zinc-800 rounded-xl p-4 text-emerald-400 focus:outline-none focus:border-indigo-500 transition-all resize-none"
                                        spellCheck={false}
                                    />
                                </div>

                                {result && (
                                    <div className={`p-4 rounded-xl text-sm font-bold ${result.success ? 'bg-green-500/10 text-green-400 border border-green-500/20' : 'bg-red-500/10 text-red-400 border border-red-500/20'}`}>
                                        {result.message}
                                    </div>
                                )}
                            </div>

                            <div className="mt-6 pt-6 border-t border-zinc-900 grid grid-cols-2 gap-4">
                                <button
                                    onClick={() => setSelectedWf(null)}
                                    className="h-12 rounded-xl bg-zinc-900 text-white font-bold hover:bg-zinc-800 transition-colors"
                                >
                                    Cancel
                                </button>
                                <button
                                    onClick={handleTrigger}
                                    disabled={isTriggering}
                                    className="h-12 rounded-xl bg-indigo-500 text-white font-bold flex items-center justify-center gap-2 hover:bg-indigo-600 disabled:opacity-50 transition-colors"
                                >
                                    {isTriggering ? <Loader2 className="animate-spin" size={18} /> : <Play size={18} />}
                                    {isTriggering ? 'Executing...' : 'Fire Webhook'}
                                </button>
                            </div>
                        </motion.div>
                    </motion.div>
                )}
            </AnimatePresence>
        </div>
    );
}
