import { getTranslation, type Language } from '../utils/i18n';
import { Fingerprint, Palette, Mic2, Megaphone, Sparkles, Globe, ShieldCheck, Save } from 'lucide-react';
import { cn } from '../lib/utils';

export function BrandView({ lang }: { lang: Language }) {
    const t = (key: string) => getTranslation(key, lang);

    return (
        <div className="max-w-5xl space-y-10 animate-in fade-in slide-in-from-bottom-8 duration-1000 pb-20">
            <div className="p-10 quantum-card relative overflow-hidden group">
                <div className="absolute top-0 right-0 w-64 h-64 bg-brand-primary/5 rounded-bl-full blur-3xl pointer-events-none group-hover:bg-brand-primary/10 transition-all duration-1000" />

                <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-8 mb-12">
                    <div className="flex items-center gap-5">
                        <div className="w-16 h-16 rounded-2xl bg-brand-primary/20 text-brand-primary flex items-center justify-center shadow-inner border border-brand-primary/20">
                            <Fingerprint size={32} />
                        </div>
                        <div>
                            <h3 className="text-4xl font-black text-white tracking-tighter italic">{t('brand_dna') || 'Identity Core'}</h3>
                            <p className="text-[11px] font-bold text-zinc-500 uppercase tracking-[0.3em] mt-1">Multi-tenant brand orchestration</p>
                        </div>
                    </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-10">
                    <div className="space-y-8">
                        <div className="space-y-3">
                            <label className="text-[10px] font-black text-zinc-600 uppercase tracking-[0.2em] flex items-center gap-2 italic">
                                <Globe size={12} /> System Identity (Restaurant Name)
                            </label>
                            <input
                                type="text"
                                defaultValue="RestoBot Diamond"
                                className="w-full bg-black/40 border border-white/5 rounded-2xl px-6 py-4 text-sm font-black text-white focus:outline-none focus:border-brand-primary transition-all shadow-inner tracking-tight italic"
                            />
                        </div>

                        <div className="space-y-3">
                            <label className="text-[10px] font-black text-zinc-600 uppercase tracking-[0.2em] flex items-center gap-2 italic">
                                <Mic2 size={12} /> Narrative Protocol (Voice Tone)
                            </label>
                            <select className="w-full bg-black/40 border border-white/5 rounded-2xl px-6 py-4 text-sm font-black text-white focus:outline-none focus:border-brand-primary transition-all appearance-none italic">
                                <option>Bold Streetfood (Aggressive & Urban)</option>
                                <option>Friendly Casual (Warm & Welcoming)</option>
                                <option>Professional Elegant (High-end Gastronomy)</option>
                                <option>Trendy Gen-Z (Meme-aware & Fast)</option>
                            </select>
                        </div>

                        <div className="space-y-3">
                            <label className="text-[10px] font-black text-zinc-600 uppercase tracking-[0.2em] flex items-center gap-2 italic">
                                <Megaphone size={12} /> Core DNA Sequence (Brand Story)
                            </label>
                            <textarea
                                rows={5}
                                className="w-full bg-black/40 border border-white/5 rounded-2xl px-6 py-4 text-sm font-medium text-zinc-400 focus:outline-none focus:border-brand-primary transition-all resize-none shadow-inner leading-relaxed italic"
                                defaultValue="Providing the finest burger experience in Algiers with AI-powered hospitality and real-time omnichannel orchestration."
                            />
                        </div>
                    </div>

                    <div className="space-y-8">
                        <div className="p-8 rounded-3xl bg-white/[0.02] border border-white/5 space-y-8 shadow-inner">
                            <div className="flex items-center gap-3 mb-2">
                                <Palette size={18} className="text-brand-primary" />
                                <h4 className="text-[10px] font-black text-white uppercase tracking-[0.36em]">Chromatic Engine</h4>
                            </div>

                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-8">
                                <div className="space-y-4">
                                    <label className="text-[9px] font-bold text-zinc-500 uppercase tracking-widest">Primary Vector</label>
                                    <div className="flex items-center gap-4">
                                        <div className="w-14 h-14 rounded-2xl bg-brand-primary shadow-[0_10px_30px_rgba(255,51,102,0.3)] ring-4 ring-white/5" />
                                        <div className="flex-1">
                                            <input type="text" defaultValue="#FF3366" className="w-full bg-black/40 border border-white/5 rounded-xl px-4 py-3 text-[11px] font-mono text-white focus:outline-none focus:border-brand-primary transition-all" />
                                        </div>
                                    </div>
                                </div>
                                <div className="space-y-4">
                                    <label className="text-[9px] font-bold text-zinc-500 uppercase tracking-widest">Accent Modulation</label>
                                    <div className="flex items-center gap-4">
                                        <div className="w-14 h-14 rounded-2xl bg-indigo-500 shadow-[0_10px_30px_rgba(99,102,241,0.3)] ring-4 ring-white/5" />
                                        <div className="flex-1">
                                            <input type="text" defaultValue="#6366F1" className="w-full bg-black/40 border border-white/5 rounded-xl px-4 py-3 text-[11px] font-mono text-white focus:outline-none focus:border-brand-primary transition-all" />
                                        </div>
                                    </div>
                                </div>
                            </div>

                            <div className="space-y-4 pt-4">
                                <label className="text-[9px] font-bold text-zinc-500 uppercase tracking-widest">Identity Aesthetic Protocol</label>
                                <div className="grid grid-cols-2 gap-3">
                                    {['Luxury Minimal', 'Neon Cyber', 'Urban Rustic', 'Glassmorphic'].map((t) => (
                                        <div key={t} className={cn(
                                            "px-4 py-3 rounded-xl border text-[10px] font-black uppercase tracking-widest cursor-pointer transition-all flex items-center justify-center gap-2",
                                            t === 'Glassmorphic' ? 'bg-brand-primary/10 border-brand-primary/30 text-brand-primary shadow-lg' : 'bg-white/5 border-white/5 text-zinc-500 hover:text-white hover:bg-white/10'
                                        )}>
                                            {t === 'Glassmorphic' && <Sparkles size={12} />}
                                            {t}
                                        </div>
                                    ))}
                                </div>
                            </div>
                        </div>

                        <div className="flex items-center gap-3 px-6 py-4 rounded-2xl bg-success/5 border border-success/10 text-[10px] font-black text-success uppercase tracking-widest italic animate-pulse">
                            <ShieldCheck size={16} /> Identity integrity verified across nodes
                        </div>
                    </div>
                </div>

                <div className="mt-12 pt-10 border-t border-white/5 flex items-center justify-between">
                    <p className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest italic">Last modified: {new Date().toLocaleDateString()} — System Admin</p>
                    <button className="px-10 py-4 rounded-2xl bg-white text-black font-black uppercase text-[11px] tracking-[0.3em] shadow-2xl hover:bg-zinc-200 hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center gap-3">
                        <Save size={16} /> Commit DNA Changes
                    </button>
                </div>
            </div>
        </div>
    );
}
