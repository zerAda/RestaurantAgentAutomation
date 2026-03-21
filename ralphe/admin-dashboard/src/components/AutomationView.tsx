import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { type Language } from '../utils/i18n';
import { strapi } from '../services/strapiClient';
import { Play, X, Loader2, Activity, Code2, Zap, Cpu, HardDrive, CheckCircle2, AlertCircle } from 'lucide-react';
import { cn } from '../lib/utils';

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

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function AutomationView({ lang: _lang }: { lang: Language }) {
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
            const parsed = JSON.parse(payload);
            await strapi.post<{ success: boolean; data: unknown }>('/api/automation/trigger', {
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
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 p-8 quantum-card relative overflow-hidden">
                <div className="absolute top-0 right-0 w-64 h-64 bg-brand-primary/10 rounded-full blur-3xl -mr-32 -mt-32" />
                <div className="relative z-10">
                    <h4 className="text-2xl font-black text-white tracking-tighter mb-2 italic">n8n Cluster Status</h4>
                    <p className="text-zinc-500 text-sm font-medium max-w-lg italic">Hyper-responsive automation engine. 14 live workflows processed 4,820 operations today.</p>
                </div>
                <div className="flex gap-4 relative z-10">
                    <div className="quantum-glass px-5 py-3 rounded-2xl flex items-center gap-3">
                        <Cpu size={18} className="text-brand-primary" />
                        <div className="flex flex-col">
                            <span className="text-[10px] font-black text-zinc-600 uppercase tracking-widest leading-none">CPU LOAD</span>
                            <span className="text-lg font-black text-white tracking-tighter">12%</span>
                        </div>
                    </div>
                    <div className="quantum-glass px-5 py-3 rounded-2xl flex items-center gap-3">
                        <HardDrive size={18} className="text-success" />
                        <div className="flex flex-col">
                            <span className="text-[10px] font-black text-zinc-600 uppercase tracking-widest leading-none">MEMORY usage</span>
                            <span className="text-lg font-black text-white tracking-tighter">1.4<span className="text-xs opacity-50">GB</span></span>
                        </div>
                    </div>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {WORKFLOWS.map((wf) => (
                    <div key={wf.id} className="quantum-card p-6 group transition-all duration-500 hover:scale-[1.02] flex flex-col justify-between h-full bg-gradient-to-br from-white/[0.03] to-transparent">
                        <div>
                            <div className="flex items-start justify-between mb-6">
                                <div className={cn(
                                    "w-12 h-12 rounded-2xl flex items-center justify-center shadow-lg",
                                    wf.type === 'core' ? 'bg-indigo-500/20 text-indigo-400' :
                                        wf.type === 'sync' ? 'bg-success/20 text-success' :
                                            wf.type === 'marketing' ? 'bg-brand-primary/20 text-brand-primary' :
                                                'bg-purple-500/20 text-purple-400'
                                )}>
                                    {wf.type === 'core' ? <Zap size={22} /> :
                                        wf.type === 'sync' ? <Activity size={22} /> :
                                            wf.type === 'marketing' ? <Palette size={22} /> :
                                                <Code2 size={22} />}
                                </div>
                                <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-white/5 border border-white/5 shadow-inner">
                                    <span className="w-2 h-2 rounded-full bg-success animate-pulse shadow-[0_0_8px_var(--color-success)]" />
                                    <span className="text-[10px] font-black text-zinc-500 uppercase tracking-widest italic">{wf.status}</span>
                                </div>
                            </div>

                            <h4 className="text-xl font-black text-white tracking-tighter mb-2">{wf.name}</h4>
                            <p className="text-sm text-zinc-500 font-medium leading-relaxed mb-6 line-clamp-2 italic">{wf.description}</p>

                            <div className="grid grid-cols-2 gap-4 mb-8">
                                <div className="p-3 rounded-xl bg-white/5 border border-white/5">
                                    <span className="text-[9px] font-black text-zinc-600 uppercase tracking-widest block mb-1">SUCCESS RATE</span>
                                    <span className="text-sm font-black text-white">{wf.successRate}</span>
                                </div>
                                <div className="p-3 rounded-xl bg-white/5 border border-white/5">
                                    <span className="text-[9px] font-black text-zinc-600 uppercase tracking-widest block mb-1">LATENCY</span>
                                    <span className="text-sm font-black text-white">{wf.lastRun}</span>
                                </div>
                            </div>
                        </div>

                        <div className="flex gap-3">
                            <button className="flex-1 h-12 rounded-2xl bg-white/5 border border-white/10 text-[11px] font-black text-zinc-400 uppercase tracking-widest hover:bg-white/10 hover:text-white transition-all flex items-center justify-center gap-3">
                                <Activity size={14} /> telemetry
                            </button>
                            <button
                                onClick={() => openTriggerModal(wf)}
                                className="flex-1 h-12 rounded-2xl bg-indigo-500 text-white text-[11px] font-black uppercase tracking-widest shadow-[0_4px_20px_rgba(99,102,241,0.3)] hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center justify-center gap-3 group"
                            >
                                <Play size={14} className="group-hover:translate-x-0.5 transition-transform" /> Trigger
                            </button>
                        </div>
                    </div>
                ))}
            </div>

            <AnimatePresence>
                {selectedWf && (
                    <div className="fixed inset-0 z-[100] flex items-center justify-center p-6 sm:p-12 overflow-hidden">
                        <motion.div
                            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
                            className="absolute inset-0 bg-black/80 backdrop-blur-xl"
                            onClick={() => setSelectedWf(null)}
                        />
                        <motion.div
                            initial={{ opacity: 0, scale: 0.9, y: 40 }}
                            animate={{ opacity: 1, scale: 1, y: 0 }}
                            exit={{ opacity: 0, scale: 0.9, y: 40 }}
                            className="w-full max-w-3xl quantum-card relative z-10 flex flex-col max-h-full overflow-hidden"
                        >
                            <div className="p-8 border-b border-white/5 flex items-center justify-between">
                                <div className="flex items-center gap-4">
                                    <div className="w-12 h-12 rounded-2xl bg-indigo-500/20 text-indigo-400 flex items-center justify-center shadow-inner">
                                        <Zap size={24} />
                                    </div>
                                    <div>
                                        <h3 className="text-2xl font-black text-white tracking-tighter leading-none">{selectedWf.name}</h3>
                                        <p className="text-xs font-black text-zinc-500 uppercase tracking-widest mt-1 italic">Cluster Node Activation</p>
                                    </div>
                                </div>
                                <button
                                    onClick={() => setSelectedWf(null)}
                                    className="w-10 h-10 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-zinc-500 hover:text-white hover:bg-white/10 transition-all"
                                >
                                    <X size={20} />
                                </button>
                            </div>

                            <div className="p-8 space-y-8 overflow-y-auto">
                                <div className="space-y-3">
                                    <div className="flex items-center justify-between">
                                        <label className="text-[10px] font-black text-zinc-600 uppercase tracking-[0.2em] flex items-center gap-2 italic">
                                            <Code2 size={12} /> Execution Payload (JSON)
                                        </label>
                                        <span className="text-[10px] font-black text-zinc-800 uppercase tracking-widest">Read-Write Mode</span>
                                    </div>
                                    <div className="relative group">
                                        <div className="absolute inset-0 bg-brand-primary/5 rounded-2xl blur-xl group-focus-within:bg-brand-primary/10 transition-all" />
                                        <textarea
                                            value={payload}
                                            onChange={e => setPayload(e.target.value)}
                                            className="w-full h-80 font-mono text-[13px] bg-black/50 border border-white/10 rounded-2xl p-6 text-emerald-400 focus:outline-none focus:border-brand-primary transition-all resize-none relative z-10 shadow-inner"
                                            spellCheck={false}
                                        />
                                    </div>
                                </div>

                                {result && (
                                    <div className={cn(
                                        "p-5 rounded-2xl border flex items-center gap-4 animate-in zoom-in-95 duration-300 shadow-lg",
                                        result.success
                                            ? 'bg-success/5 border-success/20 text-success'
                                            : 'bg-error/5 border-error/20 text-error'
                                    )}>
                                        {result.success ? <CheckCircle2 size={20} /> : <AlertCircle size={20} />}
                                        <span className="text-[11px] font-black uppercase tracking-widest">{result.message}</span>
                                    </div>
                                )}
                            </div>

                            <div className="p-8 border-t border-white/5 flex gap-4">
                                <button
                                    onClick={() => setSelectedWf(null)}
                                    className="flex-1 h-14 rounded-2xl bg-white/5 border border-white/5 text-[11px] font-black text-zinc-500 uppercase tracking-widest hover:text-white transition-all"
                                >
                                    Cancel Request
                                </button>
                                <button
                                    onClick={handleTrigger}
                                    disabled={isTriggering}
                                    className="flex-[2] h-14 rounded-2xl bg-brand-primary text-black text-[11px] font-black uppercase tracking-[0.2em] flex items-center justify-center gap-3 hover:scale-[1.02] active:scale-[0.98] disabled:opacity-50 transition-all shadow-[0_10px_30px_rgba(255,51,102,0.3)]"
                                >
                                    {isTriggering ? <Loader2 className="animate-spin" size={18} /> : <Zap size={18} />}
                                    {isTriggering ? 'Transmitting...' : 'Fire Webhook'}
                                </button>
                            </div>
                        </motion.div>
                    </div>
                )}
            </AnimatePresence>
        </div>
    );
}
