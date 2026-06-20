import React, { useState, useEffect, useRef, useCallback } from 'react';
import { X, Send, Bot, User, Sparkles, BarChart3, Lightbulb, Package, Rocket, CheckCircle, AlertTriangle, ChevronRight, Maximize2, Minimize2, Users, AlertOctagon, Trash2, ThumbsUp, ThumbsDown, BrainCircuit, Activity } from 'lucide-react';
import { cn } from '../lib/utils';

/* ─────────────── Types ─────────────── */

interface ChatMessage {
    id: string;
    role: 'user' | 'agent';
    content: string;
    timestamp: string;
    actions?: AgentAction[];
    needsConfirmation?: boolean;
    confirmAction?: { message: string; payload: unknown };
    ragSlices?: string[];
    feedback?: 1 | -1 | null;
}

interface AgentAction {
    type: 'update' | 'create' | 'delete' | 'info' | 'campaign' | 'alert';
    label: string;
    detail?: string;
    status?: 'success' | 'pending' | 'error';
}

// Shape of the /api/agent/chat response body (mirrors the ChatMessage field reads below).
interface AgentChatResponse {
    reply?: string;
    actions?: ChatMessage['actions'];
    needsConfirmation?: boolean;
    confirmAction?: ChatMessage['confirmAction'];
    ragSlices?: string[];
}

/* ─────────── Quick Action Presets ─────────── */

const QUICK_ACTIONS = [
    { icon: BarChart3, label: 'Quantum KPIs', message: 'Analyse mes KPIs de cette semaine et explique chaque indicateur simplement. Dis-moi ce que signifie chaque métrique et si mes chiffres sont bons.', group: 'analytics' },
    { icon: Lightbulb, label: 'Capital Growth', message: 'Utilise les données funnel, les avis clients, et les AI learnings pour me proposer 3 idées concrètes pour augmenter mon chiffre d\'affaires. Base-toi sur les vrais chiffres.', group: 'analytics' },
    { icon: Package, label: 'Inventory DNA', message: 'Analyse mon menu ET mes ingrédients : quels produits marchent, lesquels floppent, quels ingrédients sont en rupture ou proches du seuil d\'alerte.', group: 'ops' },
    { icon: Rocket, label: 'Inception Protocol', message: 'Propose-moi une campagne marketing complète basée sur les données funnel. Quel produit, quel canal, quel contenu. Utilise les creative assets existants et leurs scores de performance.', group: 'ops' },
    { icon: Users, label: 'Cluster Groups', message: 'Analyse mes clients : top clients par points, répartition par tier de fidélité, clients inactifs à relancer. Utilise les préférences IA pour des suggestions d\'upsell.', group: 'intel' },
    { icon: AlertOctagon, label: 'Neural Errors', message: 'Y a-t-il des erreurs n8n récentes ? Montre-moi les workflows qui plantent et diagnostique les problèmes.', group: 'intel' },
];

const GROUP_COLORS: Record<string, string> = {
    analytics: 'bg-brand-primary/10 border-brand-primary/20 text-brand-primary hover:bg-brand-primary hover:text-black',
    ops: 'bg-white/5 border-white/10 text-zinc-400 hover:text-white hover:bg-white/10',
    intel: 'bg-indigo-500/10 border-indigo-500/20 text-indigo-400 hover:bg-indigo-500 hover:text-white',
};

/* ─────────── LocalStorage persistence ─── */
const STORAGE_KEY = 'ralphe_agent_history';
function loadHistory(): ChatMessage[] {
    try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (!raw) return [];
        const parsed = JSON.parse(raw);
        return Array.isArray(parsed) ? parsed.slice(-50) : [];
    } catch { return []; }
}
function saveHistory(messages: ChatMessage[]) {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(messages.slice(-50))); }
    catch { /* ignore */ }
}

export function AIChatBubble() {
    const [isOpen, setIsOpen] = useState(false);
    const [isExpanded, setIsExpanded] = useState(false);
    const [messages, setMessages] = useState<ChatMessage[]>([]);
    const [input, setInput] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const messagesEndRef = useRef<HTMLDivElement>(null);
    const inputRef = useRef<HTMLTextAreaElement>(null);
    const initialized = useRef(false);

    useEffect(() => {
        if (!initialized.current) {
            const history = loadHistory();
            if (history.length > 0) setMessages(history);
            initialized.current = true;
        }
    }, []);

    useEffect(() => {
        if (messages.length > 0 && messages[0]?.id !== 'welcome') saveHistory(messages);
    }, [messages]);

    useEffect(() => {
        messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }, [messages]);

    useEffect(() => {
        if (isOpen) inputRef.current?.focus();
    }, [isOpen]);

    useEffect(() => {
        if (isOpen && messages.length === 0) {
            setMessages([{
                id: 'welcome',
                role: 'agent',
                content: 'Quantum Connection Established. I am **Ralphé**, your Neural Copilot.\n\nI have real-time visibility across the entire DNS architecture:\n• 📊 **Relational Logic**: 28 Strapi Tables\n• ⚙️ **Process Orchestration**: 90 n8n Workflows\n• 🧠 **Cognitive Insight**: Funnel Analytics + AI Learning Context\n• 🎨 **Creative DNA**: Inception Prompts (Strategy/Image/Video)\n\nSystem is ready. Awaiting directive.',
                timestamp: new Date().toISOString(),
            }]);
        }
    }, [isOpen, messages.length]);

    const sendMessage = useCallback(async (text: string, isConfirmation = false) => {
        if (!text.trim() || isLoading) return;

        const userMsg: ChatMessage = {
            id: Date.now().toString(),
            role: 'user',
            content: text,
            timestamp: new Date().toISOString(),
        };

        setMessages(prev => [...prev, userMsg]);
        setInput('');
        setIsLoading(true);

        try {
            const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || '';
            const token = sessionStorage.getItem('admin_jwt') || localStorage.getItem('admin_jwt');
            const agentController = new AbortController();
            const agentTimeout = setTimeout(() => agentController.abort(), 50000);

            const rawRes = await fetch(`${STRAPI_URL}/api/agent/chat`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
                },
                body: JSON.stringify({ data: { message: text, sessionId: 'admin-dashboard-session', confirm: isConfirmation } }),
                signal: agentController.signal,
            });
            clearTimeout(agentTimeout);

            if (!rawRes.ok) throw new Error(`Strapi ${rawRes.status}`);
            const resJson = await rawRes.json();

            const data = (resJson?.data ?? resJson ?? {}) as AgentChatResponse;

            const agentMsg: ChatMessage = {
                id: (Date.now() + 1).toString(),
                role: 'agent',
                content: data.reply || 'Directive processed.',
                timestamp: new Date().toISOString(),
                actions: data.actions,
                needsConfirmation: data.needsConfirmation,
                confirmAction: data.confirmAction,
                ragSlices: data.ragSlices,
            };

            setMessages(prev => [...prev, agentMsg]);
        } catch {
            setMessages(prev => [...prev, {
                id: (Date.now() + 1).toString(),
                role: 'agent',
                content: '⚠️ **Communication Link Severed**. Neural gateway is currently unresponsive. Re-attempt protocol or verify node status.',
                timestamp: new Date().toISOString(),
            }]);
        } finally {
            setIsLoading(false);
        }
    }, [isLoading]);

    const handleKeyDown = (e: React.KeyboardEvent) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage(input);
        }
    };

    const clearHistory = () => {
        localStorage.removeItem(STORAGE_KEY);
        setMessages([]);
        initialized.current = false;
    };

    const sendFeedback = useCallback(async (msgId: string, score: 1 | -1) => {
        setMessages(prev => prev.map(m => m.id === msgId ? { ...m, feedback: score } : m));
        try {
            const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || '';
            const token = sessionStorage.getItem('admin_jwt') || localStorage.getItem('admin_jwt');
            await fetch(`${STRAPI_URL}/api/agent/chat`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', ...(token ? { 'Authorization': `Bearer ${token}` } : {}) },
                body: JSON.stringify({ data: { message: 'feedback', sessionId: 'admin-dashboard-session', feedbackScore: score } }),
            });
        } catch { /* ignore */ }
    }, []);

    const renderActions = (actions: AgentAction[]) => (
        <div className="mt-4 space-y-2">
            {actions.map((action, i) => (
                <div key={i} className="flex items-start gap-3 px-4 py-3 rounded-2xl bg-white/[0.03] border border-white/5 shadow-inner">
                    <div className={cn(
                        "mt-0.5 w-6 h-6 rounded-lg flex items-center justify-center flex-shrink-0 border",
                        action.status === 'success' ? 'bg-success/10 text-success border-success/20 shadow-[0_0_15px_rgba(16,185,129,0.2)]' :
                            action.status === 'error' ? 'bg-error/10 text-error border-error/20' :
                                'bg-brand-primary/10 text-brand-primary border-brand-primary/20'
                    )}>
                        {action.status === 'success' ? <CheckCircle size={12} /> :
                            action.status === 'error' ? <AlertTriangle size={12} /> :
                                <ChevronRight size={12} />}
                    </div>
                    <div className="min-w-0">
                        <p className="text-[11px] font-black text-white uppercase tracking-widest leading-none">{action.label}</p>
                        {action.detail && <p className="text-[10px] font-bold text-zinc-500 mt-1.5 italic leading-tight">{action.detail}</p>}
                    </div>
                </div>
            ))}
        </div>
    );

    const panelClasses = isExpanded
        ? 'fixed inset-4 max-w-none max-h-none'
        : 'fixed bottom-6 right-6 w-full max-w-[440px] h-[720px] max-h-[88vh]';

    return (
        <>
            <button
                onClick={() => setIsOpen(true)}
                className={cn(
                    "fixed bottom-6 right-6 w-16 h-16 rounded-full bg-white text-black shadow-2xl flex items-center justify-center hover:scale-110 active:scale-95 transition-all z-50 group overflow-hidden",
                    isOpen ? 'scale-0 opacity-0 pointer-events-none' : 'scale-100 opacity-100'
                )}
            >
                <div className="absolute inset-0 bg-brand-primary/20 animate-pulse group-hover:bg-brand-primary/40 transition-colors" />
                <Bot className="w-7 h-7 relative z-10" />
                <Sparkles size={12} className="absolute top-4 right-4 text-brand-primary animate-bounce delay-300" />
            </button>

            <div className={cn(
                panelClasses,
                "quantum-card flex flex-col overflow-hidden z-[100] transition-all duration-500 origin-bottom-right shadow-[0_50px_100px_rgba(0,0,0,0.8)]",
                isOpen ? 'scale-100 opacity-100' : 'scale-90 opacity-0 pointer-events-none'
            )}>
                {/* Header */}
                <div className="p-6 flex items-center justify-between border-b border-white/5 bg-white/[0.02] relative">
                    <div className="flex items-center gap-4">
                        <div className="w-11 h-11 rounded-2xl bg-brand-primary text-black flex items-center justify-center shadow-[0_0_30px_rgba(255,51,102,0.3)]">
                            <BrainCircuit size={20} />
                        </div>
                        <div>
                            <h3 className="font-black text-lg text-white tracking-widest uppercase italic leading-none">Ralphé AI</h3>
                            <div className="flex items-center gap-2 mt-1.5">
                                <div className="w-2 h-2 rounded-full bg-success animate-pulse" />
                                <span className="text-[9px] font-black text-zinc-500 uppercase tracking-widest">Neural Link v4.2 Stable</span>
                            </div>
                        </div>
                    </div>
                    <div className="flex items-center gap-2">
                        <button onClick={clearHistory} className="w-9 h-9 rounded-xl hover:bg-white/5 flex items-center justify-center text-zinc-600 hover:text-error transition-colors"><Trash2 size={16} /></button>
                        <button onClick={() => setIsExpanded(!isExpanded)} className="w-9 h-9 rounded-xl hover:bg-white/5 flex items-center justify-center text-zinc-500 hover:text-white transition-colors">
                            {isExpanded ? <Minimize2 size={18} /> : <Maximize2 size={18} />}
                        </button>
                        <button onClick={() => { setIsOpen(false); setIsExpanded(false); }} className="w-9 h-9 rounded-xl hover:bg-white/5 flex items-center justify-center text-zinc-400 hover:text-white transition-colors"><X size={20} /></button>
                    </div>
                </div>

                {/* Messages */}
                <div className="flex-1 overflow-y-auto p-6 space-y-6 no-scrollbar bg-black/40">
                    {messages.map(msg => (
                        <div key={msg.id} className={cn("flex items-start gap-4", msg.role === 'user' ? 'flex-row-reverse' : '')}>
                            <div className={cn(
                                "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0 shadow-lg border",
                                msg.role === 'user' ? 'bg-zinc-900 border-white/5 text-zinc-500' : 'bg-brand-primary/20 border-brand-primary/20 text-brand-primary'
                            )}>
                                {msg.role === 'user' ? <User size={14} /> : <Bot size={14} />}
                            </div>
                            <div className={cn("max-w-[85%]", msg.role === 'user' ? 'text-right' : 'text-left')}>
                                <div className={cn(
                                    "px-5 py-3.5 rounded-2xl text-[13px] font-medium leading-relaxed shadow-xl",
                                    msg.role === 'user'
                                        ? 'bg-white text-black rounded-tr-none'
                                        : 'bg-white/[0.04] border border-white/5 text-zinc-200 rounded-tl-none backdrop-blur-md italic'
                                )}>
                                    {msg.content}
                                </div>
                                {msg.actions && renderActions(msg.actions)}
                                {msg.role === 'agent' && msg.id !== 'welcome' && (
                                    <div className="mt-3 flex items-center gap-2 px-1">
                                        <button onClick={() => sendFeedback(msg.id, 1)} className={cn("w-8 h-8 rounded-lg flex items-center justify-center transition-all border", msg.feedback === 1 ? 'bg-success/20 border-success/30 text-success' : 'bg-white/5 border-white/5 text-zinc-600 hover:text-success')}><ThumbsUp size={12} /></button>
                                        <button onClick={() => sendFeedback(msg.id, -1)} className={cn("w-8 h-8 rounded-lg flex items-center justify-center transition-all border", msg.feedback === -1 ? 'bg-error/20 border-error/30 text-error' : 'bg-white/5 border-white/5 text-zinc-600 hover:text-error')}><ThumbsDown size={12} /></button>
                                    </div>
                                )}
                            </div>
                        </div>
                    ))}
                    {isLoading && (
                        <div className="flex items-start gap-4">
                            <div className="w-8 h-8 rounded-xl bg-brand-primary/20 border border-brand-primary/20 text-brand-primary flex items-center justify-center shadow-lg"><Bot size={14} /></div>
                            <div className="px-6 py-4 rounded-2xl bg-white/[0.04] border border-white/5 flex gap-2 items-center">
                                <span className="w-1.5 h-1.5 bg-brand-primary rounded-full animate-bounce shadow-[0_0_10px_#FF3366]" />
                                <span className="w-1.5 h-1.5 bg-brand-primary rounded-full animate-bounce delay-150 shadow-[0_0_10px_#FF3366]" />
                                <span className="w-1.5 h-1.5 bg-brand-primary rounded-full animate-bounce delay-300 shadow-[0_0_10px_#FF3366]" />
                            </div>
                        </div>
                    )}
                    <div ref={messagesEndRef} />
                </div>

                {/* Footer Controls */}
                <div className="p-6 border-t border-white/5 bg-white/[0.01]">
                    {/* TODO: Phase 14 - Fetch Quick Actions dynamically from Strapi 'Inception Prompts' collection */}
                    {messages.length === 1 && messages[0].id === 'welcome' && (
                        <div className="grid grid-cols-2 gap-2 mb-6">
                            {QUICK_ACTIONS.map((qa, i) => (
                                <button
                                    key={i}
                                    onClick={() => sendMessage(qa.message)}
                                    disabled={isLoading}
                                    className={cn(
                                        "px-3 py-3 rounded-xl border text-[10px] font-black uppercase tracking-widest transition-all flex items-center gap-3",
                                        GROUP_COLORS[qa.group] || GROUP_COLORS.ops
                                    )}
                                >
                                    <qa.icon size={14} strokeWidth={2.5} />
                                    {qa.label}
                                </button>
                            ))}
                        </div>
                    )}

                    <div className="flex items-end gap-3 bg-black/40 border border-white/10 rounded-2xl p-2 focus-within:border-brand-primary transition-all shadow-inner">
                        <textarea
                            ref={inputRef}
                            value={input}
                            onChange={e => setInput(e.target.value)}
                            onKeyDown={handleKeyDown}
                            placeholder="Awaiting DNA directive..."
                            className="flex-1 bg-transparent border-none focus:ring-0 focus:outline-none resize-none max-h-32 min-h-[44px] px-4 py-3 text-[13px] text-white placeholder-zinc-700 italic font-medium leading-relaxed"
                            rows={1}
                        />
                        <button
                            onClick={() => sendMessage(input)}
                            disabled={!input.trim() || isLoading}
                            className="w-11 h-11 flex-shrink-0 bg-white text-black rounded-xl flex items-center justify-center disabled:opacity-20 hover:scale-105 active:scale-95 transition-all shadow-2xl"
                        >
                            <Send size={18} fill="currentColor" />
                        </button>
                    </div>
                    <div className="flex items-center justify-center gap-4 mt-4">
                        <div className="flex items-center gap-2">
                            <Activity size={10} className="text-brand-primary" />
                            <span className="text-[9px] font-black text-brand-primary uppercase tracking-widest">Neural Link v4.2</span>
                        </div>
                        <div className="w-1 h-1 rounded-full bg-zinc-800" />
                        <span className="text-[9px] font-black text-success uppercase tracking-widest border border-success/20 px-2 py-0.5 rounded-full bg-success/10">System Optimal</span>
                    </div>
                </div>
            </div>
        </>
    );
}
