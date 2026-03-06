import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { getTranslation, type Language } from '../utils/i18n';
import { strapi } from '../services/strapiClient';
import { Sparkles, X, Loader2, Send, Play, BarChart, Image as ImageIcon, Video, Layers, BrainCircuit } from 'lucide-react';
import { cn } from '../lib/utils';

interface ContentAsset {
    id: number;
    attributes: {
        dish_name: string;
        brand_name: string;
        image_square_url: string;
        image_vertical_url: string;
        video_url: string;
        caption_a: string;
        caption_b: string;
        quality_score: number;
        status: 'draft' | 'ready' | 'published' | 'failed' | 'retry';
        platforms_published: string[] | null;
    };
}

export function MarketingView({ lang }: { lang: Language }) {
    const t = (key: string) => getTranslation(key, lang);
    const [assets, setAssets] = useState<ContentAsset[]>([]);
    const [loading, setLoading] = useState(true);
    const [isGenerating, setIsGenerating] = useState(false);
    const [showModal, setShowModal] = useState(false);
    const [prompt, setPrompt] = useState('');

    useEffect(() => {
        fetchAssets();
    }, []);

    const fetchAssets = async () => {
        try {
            const res = await strapi.find<ContentAsset>('content-libraries', {
                sort: ['createdAt:desc'],
                pagination: { limit: 12 },
            });
            setAssets(res.data as unknown as ContentAsset[]);
        } catch (error) {
            console.error('Error fetching marketing assets:', error);
            setAssets([]);
        } finally {
            setLoading(false);
        }
    };

    const handleGenerate = async () => {
        if (!prompt) return;
        setIsGenerating(true);
        try {
            await strapi.post<{ status: string }>('/api/proxy/n8n/webhook/generate-content', {
                prompt,
                timestamp: new Date().toISOString()
            });
            setShowModal(false);
            setPrompt('');
            setTimeout(fetchAssets, 5000);
        } catch (err) {
            console.error('Failed to trigger generation workflow', err);
        } finally {
            setIsGenerating(false);
        }
    };

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="p-8 quantum-card relative overflow-hidden flex flex-col md:flex-row items-center justify-between gap-8 group">
                <div className="absolute inset-0 bg-gradient-to-r from-brand-primary/10 to-transparent opacity-50 transition-opacity group-hover:opacity-100" />
                <div className="relative z-10">
                    <div className="flex items-center gap-3 mb-3">
                        <div className="w-10 h-10 rounded-xl bg-brand-primary/20 text-brand-primary flex items-center justify-center shadow-inner">
                            <BrainCircuit size={20} />
                        </div>
                        <h3 className="text-3xl font-black text-white tracking-tighter italic">Creative DNA Hub</h3>
                    </div>
                    <p className="text-zinc-500 font-medium max-w-xl italic leading-relaxed">
                        Orchestrate real-time AI-driven marketing across WhatsApp, TikTok, and Meta. High-fidelity asset generation with predictive quality scoring.
                    </p>
                </div>
                <button
                    onClick={() => setShowModal(true)}
                    className="relative z-10 px-8 py-4 rounded-2xl bg-brand-primary text-black font-black uppercase text-[11px] tracking-[0.2em] shadow-[0_10px_30px_rgba(255,51,102,0.3)] hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center gap-3"
                >
                    <Sparkles size={16} />
                    {t('generate_ad') || 'Inception Protocol'}
                </button>
            </div>

            {loading ? (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                    {[1, 2, 3].map(i => (
                        <div key={i} className="quantum-card aspect-[9/16] animate-pulse bg-white/[0.02]" />
                    ))}
                </div>
            ) : assets.length === 0 ? (
                <div className="text-center py-32 quantum-card rounded-quantum flex flex-col items-center justify-center">
                    <div className="w-24 h-24 rounded-full bg-white/5 border border-white/10 flex items-center justify-center mb-8 shadow-quantum-glow text-zinc-600">
                        <Layers size={48} />
                    </div>
                    <h3 className="text-3xl font-black text-white tracking-tighter mb-2 italic">No Assets Synthesized</h3>
                    <p className="text-zinc-500 font-bold uppercase text-[10px] tracking-[0.3em]">Trigger the Inception Protocol to populate library</p>
                </div>
            ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-8">
                    {assets.map((asset) => {
                        const attr = asset.attributes;
                        const thumbnail = attr.image_vertical_url || attr.image_square_url || 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400';
                        return (
                            <motion.div
                                key={asset.id}
                                layout
                                initial={{ opacity: 0, scale: 0.9 }}
                                animate={{ opacity: 1, scale: 1 }}
                                className="quantum-card p-4 group"
                            >
                                <div className="relative aspect-[9/16] rounded-2xl overflow-hidden mb-6 bg-black shadow-2xl border border-white/5">
                                    <img src={thumbnail} alt={attr.dish_name} className="w-full h-full object-cover transition-transform duration-1000 group-hover:scale-110 opacity-80 group-hover:opacity-100" />

                                    <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent opacity-60 group-hover:opacity-40 transition-opacity" />

                                    <div className="absolute top-5 left-5 right-5 flex justify-between items-start">
                                        <div className={cn(
                                            "px-3 py-1.5 rounded-full text-[9px] font-black uppercase tracking-widest backdrop-blur-md border",
                                            attr.status === 'published' ? 'bg-success/20 text-success border-success/30' :
                                                attr.status === 'draft' || attr.status === 'ready' ? 'bg-brand-primary/20 text-brand-primary border-brand-primary/30 animate-pulse' :
                                                    'bg-zinc-900/40 text-zinc-400 border-white/10'
                                        )}>
                                            {attr.status}
                                        </div>
                                        <div className="flex gap-2">
                                            {attr.video_url && (
                                                <div className="w-8 h-8 rounded-lg bg-white/10 backdrop-blur-md flex items-center justify-center text-white border border-white/10">
                                                    <Video size={14} />
                                                </div>
                                            )}
                                            <div className="w-8 h-8 rounded-lg bg-white/10 backdrop-blur-md flex items-center justify-center text-white border border-white/10">
                                                <ImageIcon size={14} />
                                            </div>
                                        </div>
                                    </div>

                                    <div className="absolute bottom-5 inset-x-5 space-y-4">
                                        <div className="flex items-end justify-between">
                                            <div className="flex-1 min-w-0">
                                                <h4 className="text-xl font-black text-white tracking-tighter truncate">{attr.dish_name || 'AI Concept'}</h4>
                                                <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest italic">{attr.brand_name || 'Generic'}</p>
                                            </div>
                                            <div className="flex flex-col items-center">
                                                <span className="text-2xl font-black text-brand-primary leading-none">{attr.quality_score}</span>
                                                <span className="text-[8px] font-black text-zinc-500 tracking-tighter">SCORE</span>
                                            </div>
                                        </div>
                                    </div>
                                </div>

                                <div className="space-y-6">
                                    <p className="text-xs text-zinc-500 font-medium leading-relaxed line-clamp-2 h-10 italic px-2">
                                        "{attr.caption_a || attr.caption_b || 'Core DNA sequence pending synthesis...'}"
                                    </p>

                                    <div className="flex gap-3 px-1">
                                        <button className="flex-1 h-11 rounded-xl bg-white/5 border border-white/5 text-[10px] font-black text-zinc-500 uppercase tracking-widest hover:text-white hover:bg-white/10 transition-all flex items-center justify-center gap-2">
                                            <BarChart size={12} /> Analytics
                                        </button>
                                        <button className="flex-[2] h-11 rounded-xl bg-white text-black text-[10px] font-black uppercase tracking-widest hover:bg-zinc-200 transition-all flex items-center justify-center gap-2 shadow-xl">
                                            <Play size={12} fill="black" /> Deploy Now
                                        </button>
                                    </div>
                                </div>
                            </motion.div>
                        );
                    })}
                </div>
            )}

            <AnimatePresence>
                {showModal && (
                    <div className="fixed inset-0 z-[100] flex items-center justify-center p-6 sm:p-12 overflow-hidden">
                        <motion.div
                            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
                            className="absolute inset-0 bg-black/80 backdrop-blur-xl"
                            onClick={() => setShowModal(false)}
                        />
                        <motion.div
                            initial={{ opacity: 0, scale: 0.9, y: 40 }}
                            animate={{ opacity: 1, scale: 1, y: 0 }}
                            exit={{ opacity: 0, scale: 0.9, y: 40 }}
                            className="w-full max-w-xl quantum-card relative z-10 flex flex-col max-h-full overflow-hidden"
                        >
                            <div className="p-8 border-b border-white/5 flex items-center justify-between">
                                <div className="flex items-center gap-4">
                                    <div className="w-12 h-12 rounded-2xl bg-brand-primary/20 text-brand-primary flex items-center justify-center shadow-inner">
                                        <Sparkles size={24} />
                                    </div>
                                    <div>
                                        <h3 className="text-2xl font-black text-white tracking-tighter leading-none">Inception Protocol</h3>
                                        <p className="text-xs font-black text-zinc-500 uppercase tracking-widest mt-1 italic">Omnichannel Synthesis Engine</p>
                                    </div>
                                </div>
                                <button
                                    onClick={() => setShowModal(false)}
                                    className="w-10 h-10 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-zinc-500 hover:text-white hover:bg-white/10 transition-all"
                                >
                                    <X size={20} />
                                </button>
                            </div>

                            <div className="p-8 space-y-8">
                                <div className="space-y-3">
                                    <label className="text-[10px] font-black text-zinc-600 uppercase tracking-[0.2em] flex items-center gap-2 italic">
                                        <Send size={12} /> Synthesis Directive (Prompt)
                                    </label>
                                    <div className="relative group">
                                        <div className="absolute inset-0 bg-brand-primary/5 rounded-2xl blur-xl group-focus-within:bg-brand-primary/10 transition-all" />
                                        <textarea
                                            value={prompt}
                                            onChange={e => setPrompt(e.target.value)}
                                            placeholder="e.g. Synthesize a TikTok blitz for 'Spicy Tacos'—focus on melting textures and high-energy transitions..."
                                            className="w-full h-40 bg-black/50 border border-white/10 rounded-2xl p-6 text-sm text-white focus:outline-none focus:border-brand-primary transition-all resize-none relative z-10 shadow-inner italic"
                                        />
                                    </div>
                                </div>
                            </div>

                            <div className="p-8 border-t border-white/5 flex gap-4">
                                <button
                                    onClick={() => setShowModal(null)}
                                    className="flex-1 h-14 rounded-2xl bg-white/5 border border-white/5 text-[11px] font-black text-zinc-500 uppercase tracking-widest hover:text-white transition-all"
                                >
                                    Abort synthesis
                                </button>
                                <button
                                    onClick={handleGenerate}
                                    disabled={!prompt || isGenerating}
                                    className="flex-[2] h-14 rounded-2xl bg-brand-primary text-black text-[11px] font-black uppercase tracking-[0.2em] flex items-center justify-center gap-3 hover:scale-[1.02] active:scale-[0.98] disabled:opacity-50 transition-all shadow-[0_10px_30px_rgba(255,51,102,0.3)]"
                                >
                                    {isGenerating ? <Loader2 className="animate-spin" size={18} /> : <BrainCircuit size={18} />}
                                    {isGenerating ? 'Synthesizing...' : 'Initialize Inception'}
                                </button>
                            </div>
                        </motion.div>
                    </div>
                )}
            </AnimatePresence>
        </div>
    );
}
