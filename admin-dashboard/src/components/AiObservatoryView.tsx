import { useState, useEffect, useCallback } from 'react';
import { strapi } from '../services/strapiClient';
import { BarChart as ReBarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, LineChart, Line } from 'recharts';
import { RefreshCw, BrainCircuit, Zap, Clock, ThumbsUp, ThumbsDown, MessageSquare, Activity, Cpu, ShieldCheck, Database, Layout } from 'lucide-react';
import { SkeletonCard, SkeletonRow } from './SkeletonLoader';
import { AnimatedNumber } from './AnimatedNumber';
import { cn } from '../lib/utils';

/* ── Types ── */
interface LLMUsageLog {
    id: number;
    workflow_id: string;
    model: string;
    tokens_in: number;
    tokens_out: number;
    cost_usd: number;
    latency_ms: number;
    success: boolean;
    error_message: string;
    session_id: string;
    createdAt: string;
}

interface AgentSession {
    id: number;
    session_id: string;
    admin_user: string;
    summary: string;
    messages_count: number;
    last_message: string;
    last_reply: string;
    feedback_score: number;
    rag_slices_used: string[];
    createdAt: string;
    updatedAt: string;
}

interface DailyCost {
    day: string;
    cost: number;
    calls: number;
    tokens: number;
}

interface ModelUsage {
    model: string;
    calls: number;
    totalCost: number;
    avgLatency: number;
}

/* ── Custom Tooltip ── */
const CostTooltip = ({ active, payload, label }: { active?: boolean; payload?: { value: number; name: string }[]; label?: string }) => {
    if (!active || !payload?.length) return null;
    return (
        <div className="bg-black/80 backdrop-blur-xl border border-white/10 rounded-xl p-4 shadow-2xl">
            <p className="text-[10px] font-black text-zinc-500 uppercase tracking-widest mb-2 italic">{label}</p>
            {payload.map((p, i) => (
                <div key={i} className="flex items-center justify-between gap-4">
                    <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-tighter">{p.name === 'cost' ? 'Inference Cost' : 'Payload Frequency'}</span>
                    <span className="text-sm font-black text-white">
                        {p.name === 'cost' ? `$${p.value.toFixed(4)}` : p.value.toLocaleString()}
                    </span>
                </div>
            ))}
        </div>
    );
};

export function AiObservatoryView() {
    const [loading, setLoading] = useState(true);
    const [sessions, setSessions] = useState<AgentSession[]>([]);
    const [dailyCosts, setDailyCosts] = useState<DailyCost[]>([]);
    const [modelUsage, setModelUsage] = useState<ModelUsage[]>([]);

    const [stats, setStats] = useState({
        totalCost: 0,
        totalCalls: 0,
        avgLatency: 0,
        successRate: 100,
        totalSessions: 0,
        positiveRate: 0,
        totalTokens: 0,
    });

    const fetchData = useCallback(async () => {
        setLoading(true);
        try {
            const weekAgo = new Date(Date.now() - 7 * 86400000).toISOString();

            const [logsRes, sessionsRes] = await Promise.all([
                strapi.find<LLMUsageLog>('llm-usage-logs', {
                    sort: ['createdAt:desc'],
                    pagination: { limit: 500 },
                    filters: { createdAt: { $gte: weekAgo } },
                }),
                strapi.find<AgentSession>('agent-sessions', {
                    sort: ['updatedAt:desc'],
                    pagination: { limit: 100 },
                }),
            ]);

            const logData = Array.isArray(logsRes.data) ? logsRes.data : [];
            const sessionData = Array.isArray(sessionsRes.data) ? sessionsRes.data : [];

            setSessions(sessionData);

            const totalCost = logData.reduce((s, l) => s + (l.cost_usd || 0), 0);
            const totalCalls = logData.length;
            const totalLatency = logData.reduce((s, l) => s + (l.latency_ms || 0), 0);
            const successCount = logData.filter(l => l.success).length;
            const totalTokens = logData.reduce((s, l) => s + (l.tokens_in || 0) + (l.tokens_out || 0), 0);
            const positiveCount = sessionData.filter(s => s.feedback_score === 1).length;
            const feedbackCount = sessionData.filter(s => s.feedback_score !== undefined && s.feedback_score !== null && s.feedback_score !== 0).length;

            setStats({
                totalCost,
                totalCalls,
                avgLatency: totalCalls > 0 ? Math.round(totalLatency / totalCalls) : 0,
                successRate: totalCalls > 0 ? Math.round((successCount / totalCalls) * 100) : 100,
                totalSessions: sessionData.length,
                positiveRate: feedbackCount > 0 ? Math.round((positiveCount / feedbackCount) * 100) : 0,
                totalTokens,
            });

            const dayMap = new Map<string, { cost: number; calls: number; tokens: number }>();
            for (let i = 6; i >= 0; i--) {
                const d = new Date(Date.now() - i * 86400000);
                const key = d.toISOString().split('T')[0];
                dayMap.set(key, { cost: 0, calls: 0, tokens: 0 });
            }
            logData.forEach(l => {
                const key = l.createdAt?.split('T')[0];
                if (key && dayMap.has(key)) {
                    const b = dayMap.get(key)!;
                    b.cost += l.cost_usd || 0;
                    b.calls++;
                    b.tokens += (l.tokens_in || 0) + (l.tokens_out || 0);
                }
            });
            setDailyCosts(Array.from(dayMap.entries()).map(([date, v]) => ({
                day: new Date(date).toLocaleDateString('fr-FR', { weekday: 'short' }),
                cost: Number(v.cost.toFixed(4)),
                calls: v.calls,
                tokens: v.tokens,
            })));

            const modelMap = new Map<string, { calls: number; totalCost: number; totalLatency: number }>();
            logData.forEach(l => {
                const m = l.model || 'unknown';
                const existing = modelMap.get(m) || { calls: 0, totalCost: 0, totalLatency: 0 };
                existing.calls++;
                existing.totalCost += l.cost_usd || 0;
                existing.totalLatency += l.latency_ms || 0;
                modelMap.set(m, existing);
            });
            setModelUsage(Array.from(modelMap.entries()).map(([model, v]) => ({
                model,
                calls: v.calls,
                totalCost: Number(v.totalCost.toFixed(4)),
                avgLatency: v.calls > 0 ? Math.round(v.totalLatency / v.calls) : 0,
            })).sort((a, b) => b.calls - a.calls));

        } catch (err) {
            console.error('[AiObservatoryView] fetch failed:', err);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        void fetchData();
        const interval = setInterval(fetchData, 60000);
        return () => clearInterval(interval);
    }, [fetchData]);

    return (
        <div className="space-y-8 animate-in fade-in duration-1000 pb-20">
            {/* Header / OS Control Bar */}
            <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-6">
                <div className="flex items-center gap-4">
                    <div className="w-12 h-12 rounded-2xl bg-brand-primary/20 text-brand-primary flex items-center justify-center shadow-inner border border-brand-primary/20">
                        <BrainCircuit size={24} />
                    </div>
                    <div>
                        <h3 className="text-2xl font-black text-white tracking-tighter italic uppercase flex items-center gap-3">
                            AI Observatory
                            <div className="px-2 py-0.5 rounded bg-success/10 border border-success/20 text-[8px] font-black text-success animate-pulse">LIVE TELEMETRY</div>
                        </h3>
                        <p className="text-[10px] font-bold text-zinc-500 uppercase tracking-[0.3em] mt-1">Real-time model inference & cost monitoring</p>
                    </div>
                </div>
                <div className="flex items-center gap-3">
                    <div className="px-4 py-2 rounded-xl bg-white/5 border border-white/10 flex items-center gap-3 text-[10px] font-black text-zinc-400 uppercase tracking-widest italic">
                        <Activity size={12} className="text-brand-primary" /> System Pulsing
                    </div>
                    <button
                        onClick={fetchData}
                        disabled={loading}
                        className="w-10 h-10 rounded-xl bg-brand-primary/10 border border-brand-primary/20 text-brand-primary flex items-center justify-center hover:bg-brand-primary hover:text-black transition-all shadow-lg disabled:opacity-50"
                    >
                        <RefreshCw size={18} className={loading ? 'animate-spin' : ''} />
                    </button>
                </div>
            </div>

            {/* Metric Cloud */}
            <div className="grid grid-cols-2 lg:grid-cols-4 xl:grid-cols-7 gap-4">
                {[
                    { label: 'Cloud Cost (7d)', value: stats.totalCost, prefix: '$', suffix: '', decimals: 3, icon: Zap, color: 'text-brand-primary' },
                    { label: 'Total Inferences', value: stats.totalCalls, prefix: '', suffix: '', icon: Cpu, color: 'text-indigo-400' },
                    { label: 'Inference Latency', value: stats.avgLatency, prefix: '', suffix: 'ms', icon: Clock, color: 'text-warning' },
                    { label: 'Success Ratio', value: stats.successRate, prefix: '', suffix: '%', icon: ShieldCheck, color: stats.successRate >= 98 ? 'text-success' : 'text-error' },
                    { label: 'Active Sessions', value: stats.totalSessions, prefix: '', suffix: '', icon: MessageSquare, color: 'text-purple-400' },
                    { label: 'Positive Feedback', value: stats.positiveRate, prefix: '', suffix: '%', icon: ThumbsUp, color: 'text-success' },
                    { label: 'Token Payload', value: stats.totalTokens >= 1000 ? stats.totalTokens / 1000 : stats.totalTokens, prefix: '', suffix: stats.totalTokens >= 1000 ? 'K' : '', decimals: 1, icon: Database, color: 'text-zinc-500' },
                ].map((m, i) => (
                    <div key={i} className="quantum-card p-5 group flex flex-col justify-between min-h-[120px] relative overflow-hidden">
                        <div className="absolute top-0 right-0 w-12 h-12 bg-white/[0.02] rounded-bl-full pointer-events-none group-hover:bg-white/[0.05] transition-colors" />
                        <div className="flex items-center gap-2 mb-3">
                            <m.icon size={14} className={cn("opacity-50 group-hover:opacity-100 transition-opacity", m.color)} />
                            <span className="text-[9px] font-black text-zinc-500 uppercase tracking-widest leading-none">{m.label}</span>
                        </div>
                        <h4 className="text-2xl font-black text-white tracking-tighter flex items-baseline gap-1">
                            {m.prefix && <span className="text-sm font-bold text-zinc-500">{m.prefix}</span>}
                            <AnimatedNumber value={m.value} />
                            {m.suffix && <span className="text-xs font-bold text-zinc-500">{m.suffix}</span>}
                        </h4>
                    </div>
                ))}
            </div>

            {/* Analytics Surface */}
            <div className="grid grid-cols-1 xl:grid-cols-2 gap-8">
                {/* Cost Distribution */}
                <div className="quantum-card p-8">
                    <div className="flex items-center justify-between mb-8">
                        <div>
                            <h4 className="text-xl font-black text-white tracking-tighter italic tracking-tight">Financial Telemetry</h4>
                            <p className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest mt-1">Inference cost per 24h cycle</p>
                        </div>
                        <div className="w-10 h-10 rounded-xl bg-white/5 flex items-center justify-center text-zinc-400">
                            <Zap size={18} />
                        </div>
                    </div>
                    <div className="h-[300px] w-full mt-4">
                        <ResponsiveContainer width="100%" height="100%">
                            <ReBarChart data={dailyCosts} margin={{ top: 0, right: 0, left: -20, bottom: 0 }}>
                                <defs>
                                    <linearGradient id="barGradient" x1="0" y1="0" x2="0" y2="1">
                                        <stop offset="0%" stopColor="#FF3366" stopOpacity={0.8} />
                                        <stop offset="100%" stopColor="#FF3366" stopOpacity={0.1} />
                                    </linearGradient>
                                </defs>
                                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" vertical={false} />
                                <XAxis dataKey="day" tick={{ fill: '#52525b', fontSize: 10, fontWeight: 900 }} axisLine={false} tickLine={false} dy={10} />
                                <YAxis tick={{ fill: '#52525b', fontSize: 10, fontWeight: 900 }} axisLine={false} tickLine={false} tickFormatter={(v: number) => `$${v}`} />
                                <Tooltip content={<CostTooltip />} cursor={{ fill: 'rgba(255,255,255,0.03)' }} />
                                <Bar dataKey="cost" fill="url(#barGradient)" radius={[6, 6, 0, 0]} barSize={40} />
                            </ReBarChart>
                        </ResponsiveContainer>
                    </div>
                </div>

                {/* Inference Frequency */}
                <div className="quantum-card p-8">
                    <div className="flex items-center justify-between mb-8">
                        <div>
                            <h4 className="text-xl font-black text-white tracking-tighter italic tracking-tight">System Pulsar</h4>
                            <p className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest mt-1">Inference frequency trend (7d)</p>
                        </div>
                        <div className="w-10 h-10 rounded-xl bg-white/5 flex items-center justify-center text-zinc-400">
                            <Activity size={18} />
                        </div>
                    </div>
                    <div className="h-[300px] w-full mt-4">
                        <ResponsiveContainer width="100%" height="100%">
                            <LineChart data={dailyCosts} margin={{ top: 0, right: 0, left: -20, bottom: 0 }}>
                                <XAxis dataKey="day" tick={{ fill: '#52525b', fontSize: 10, fontWeight: 900 }} axisLine={false} tickLine={false} dy={10} />
                                <YAxis tick={{ fill: '#52525b', fontSize: 10, fontWeight: 900 }} axisLine={false} tickLine={false} />
                                <Tooltip content={<CostTooltip />} />
                                <Line
                                    type="monotone"
                                    dataKey="calls"
                                    stroke="#FF3366"
                                    strokeWidth={4}
                                    dot={{ fill: '#FF3366', r: 4, strokeWidth: 2, stroke: '#000' }}
                                    activeDot={{ r: 8, strokeWidth: 0, fill: '#fff shadow-lg' }}
                                />
                            </LineChart>
                        </ResponsiveContainer>
                    </div>
                </div>
            </div>

            {/* Model Breakdown + Log Matrix */}
            <div className="grid grid-cols-1 xl:grid-cols-3 gap-8">
                {/* Model Breakdown */}
                <div className="quantum-card p-8 xl:col-span-1">
                    <div className="flex items-center gap-4 mb-8">
                        <div className="w-10 h-10 rounded-xl bg-indigo-500/20 text-indigo-400 flex items-center justify-center">
                            <Cpu size={20} />
                        </div>
                        <div>
                            <h4 className="text-lg font-black text-white tracking-tighter italic uppercase">Model DNA</h4>
                            <p className="text-[9px] font-bold text-zinc-600 uppercase tracking-widest">Inference distribution by provider</p>
                        </div>
                    </div>

                    {loading ? (
                        <div className="space-y-4">
                            {[1, 2, 3].map(i => <SkeletonRow key={i} />)}
                        </div>
                    ) : (
                        <div className="space-y-4">
                            {modelUsage.map(m => (
                                <div key={m.model} className="p-4 rounded-2xl bg-white/[0.02] border border-white/5 flex items-center justify-between group hover:bg-white/[0.04] transition-all">
                                    <div className="flex-1 min-w-0 pr-4">
                                        <span className="text-sm font-black text-white tracking-tighter font-mono italic truncate block">{m.model}</span>
                                        <div className="mt-1 flex items-center gap-3">
                                            <span className="text-[9px] font-bold text-zinc-500 uppercase tracking-widest">{m.calls} Inferences</span>
                                            <span className="w-1 h-1 rounded-full bg-zinc-800" />
                                            <span className="text-[9px] font-bold text-zinc-500 uppercase tracking-widest">{m.avgLatency}ms (Avg)</span>
                                        </div>
                                    </div>
                                    <div className="text-right">
                                        <span className="text-sm font-black text-brand-primary tracking-tighter italic">${m.totalCost.toFixed(4)}</span>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </div>

                {/* Session Matrix */}
                <div className="quantum-card p-8 xl:col-span-2">
                    <div className="flex items-center justify-between mb-8">
                        <div className="flex items-center gap-4">
                            <div className="w-10 h-10 rounded-xl bg-purple-500/20 text-purple-400 flex items-center justify-center">
                                <Layout size={20} />
                            </div>
                            <div>
                                <h4 className="text-lg font-black text-white tracking-tighter italic uppercase">Session Matrix</h4>
                                <p className="text-[9px] font-bold text-zinc-600 uppercase tracking-widest">Recent high-fidelity interactions</p>
                            </div>
                        </div>
                    </div>

                    <div className="space-y-3 max-h-[460px] overflow-y-auto no-scrollbar">
                        {loading && sessions.length === 0 ? (
                            [1, 2, 3, 4, 5].map(i => <SkeletonRow key={i} />)
                        ) : (
                            sessions.slice(0, 12).map(s => {
                                const ago = Math.round((Date.now() - new Date(s.updatedAt).getTime()) / 3600000);
                                return (
                                    <div key={s.id} className="p-4 rounded-2xl bg-white/[0.01] border border-white/5 hover:bg-white/[0.03] transition-all flex items-start justify-between gap-6 group">
                                        <div className="flex-1 min-w-0">
                                            <div className="flex items-center gap-3 mb-2">
                                                <span className="text-[10px] font-black text-white uppercase tracking-[0.2em]">{s.admin_user}</span>
                                                <span className="text-[9px] font-bold text-zinc-600 uppercase tracking-widest italic">{ago} hours ago</span>
                                            </div>
                                            <p className="text-sm text-zinc-400 font-medium italic truncate">"{s.summary || s.last_message || 'Neural sequence incomplete...'}"</p>
                                        </div>
                                        <div className="flex flex-col items-end gap-2">
                                            <div className="flex items-center gap-2">
                                                {s.feedback_score === 1 && <div className="w-8 h-8 rounded-lg bg-success/10 text-success flex items-center justify-center shadow-lg"><ThumbsUp size={12} /></div>}
                                                {s.feedback_score === -1 && <div className="w-8 h-8 rounded-lg bg-error/10 text-error flex items-center justify-center shadow-lg"><ThumbsDown size={12} /></div>}
                                            </div>
                                            <span className="text-[9px] font-black text-zinc-600 uppercase tracking-tighter">{s.messages_count || 0} MESSAGES</span>
                                        </div>
                                    </div>
                                );
                            })
                        )}
                    </div>
                </div>
            </div>
        </div>
    );
}
