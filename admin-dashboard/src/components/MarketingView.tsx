import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { getTranslation, type Language } from '../utils/i18n';
import { strapi } from '../services/strapiClient';
import { Sparkles, X, Loader2, Send } from 'lucide-react';

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
            const { data } = await strapi.find('content-libraries', {
                sort: ['createdAt:desc'],
                pagination: { limit: 12 }
            });
            setAssets(data);
        } catch (error) {
            console.error('Error fetching marketing assets:', error);
            // Fallback to empty if Strapi is unreachable
            setAssets([]);
        } finally {
            setLoading(false);
        }
    };

    const handleGenerate = async () => {
        if (!prompt) return;
        setIsGenerating(true);
        try {
            await fetch('http://localhost:5678/webhook/generate-content', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ prompt, timestamp: new Date().toISOString() })
            });
            setShowModal(false);
            setPrompt('');
            // Optimistically poll for new assets after 5 seconds
            setTimeout(fetchAssets, 5000);
        } catch (err) {
            console.error('Failed to trigger generation workflow', err);
        } finally {
            setIsGenerating(false);
        }
    };

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
                <div>
                    <h3 className="text-2xl font-black">{t('creative_center') || 'Creative Center'}</h3>
                    <p className="text-zinc-500 text-sm">Track real-time AI-generated social media campaigns.</p>
                </div>
                <button
                    onClick={() => setShowModal(true)}
                    className="px-6 py-3 rounded-xl bg-indigo-500 text-white font-bold shadow-lg shadow-indigo-500/20 hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center gap-2 group"
                >
                    <Sparkles size={18} className="group-hover:animate-pulse" />
                    {t('generate_ad') || 'Generate Ad'}
                </button>
            </div>

            {loading ? (
                <div className="flex justify-center py-20">
                    <Loader2 className="animate-spin text-zinc-400" size={32} />
                </div>
            ) : assets.length === 0 ? (
                <div className="text-center py-20 diamond-card rounded-3xl">
                    <span className="text-6xl mb-4 block opacity-50">🤖</span>
                    <h4 className="text-xl font-bold mb-2">No Creative Assets Yet</h4>
                    <p className="text-zinc-500 max-w-sm mx-auto">Generate your first AI-driven marketing campaign by clicking the Generate Ad button.</p>
                </div>
            ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
                    {assets.map((asset) => {
                        const attr = asset.attributes;
                        const thumbnail = attr.image_vertical_url || attr.image_square_url || 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400';
                        return (
                            <motion.div
                                key={asset.id}
                                initial={{ opacity: 0, y: 20 }}
                                animate={{ opacity: 1, y: 0 }}
                                className="diamond-card p-4 rounded-3xl group"
                            >
                                <div className="relative aspect-[9/16] rounded-2xl overflow-hidden mb-4 bg-zinc-100 dark:bg-zinc-800">
                                    <img src={thumbnail} alt={attr.dish_name} className="w-full h-full object-cover transition-transform duration-700 group-hover:scale-105" />

                                    <div className="absolute top-4 inset-x-4 flex justify-between items-start">
                                        <span className={`px-3 py-1 rounded-full text-[10px] font-black uppercase tracking-wider shadow-lg backdrop-blur-md ${attr.status === 'published' ? 'bg-green-500/90 text-white' :
                                            attr.status === 'draft' || attr.status === 'ready' ? 'bg-indigo-500/90 text-white animate-pulse' :
                                                'bg-zinc-900/90 text-white'
                                            }`}>
                                            {attr.status}
                                        </span>
                                        {attr.video_url && (
                                            <span className="px-2 py-1 rounded-md bg-white/20 backdrop-blur-md text-white text-[10px] font-black tracking-wider border border-white/20">
                                                VIDEO
                                            </span>
                                        )}
                                    </div>

                                    {(attr.quality_score > 0) && (
                                        <div className="absolute bottom-4 right-4 w-12 h-12 rounded-full bg-zinc-900/80 backdrop-blur-md flex flex-col items-center justify-center text-white font-black shadow-xl border border-white/10">
                                            <span className="text-sm leading-none">{attr.quality_score}</span>
                                            <span className="text-[8px] opacity-70 leading-none mt-0.5">SCORE</span>
                                        </div>
                                    )}
                                </div>

                                <div className="px-2">
                                    <h4 className="font-bold text-lg mb-1 leading-tight">{attr.dish_name || 'AI Concept'}</h4>
                                    <p className="text-zinc-500 dark:text-zinc-400 text-xs italic line-clamp-2 h-8">
                                        {attr.caption_a || attr.caption_b || 'Caption being generated...'}
                                    </p>

                                    <div className="mt-4 pt-4 border-t border-zinc-100 dark:border-zinc-800 flex justify-between items-center opacity-0 group-hover:opacity-100 transition-opacity">
                                        <button className="text-xs font-bold text-zinc-500 hover:text-indigo-500 transition-colors">Edit Asset</button>
                                        <button className="px-4 py-2 rounded-lg bg-indigo-500 text-white text-xs font-black hover:bg-indigo-600 transition-colors">Publish Now</button>
                                    </div>
                                </div>
                            </motion.div>
                        );
                    })}
                </div>
            )}

            {/* Generation Modal */}
            <AnimatePresence>
                {showModal && (
                    <motion.div
                        initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
                        className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm"
                    >
                        <motion.div
                            initial={{ scale: 0.95, y: 20 }} animate={{ scale: 1, y: 0 }} exit={{ scale: 0.95, y: 20 }}
                            className="bg-zinc-950 border border-zinc-800 w-full max-w-lg rounded-3xl p-6 shadow-2xl relative overflow-hidden"
                        >
                            <button onClick={() => setShowModal(false)} className="absolute top-6 right-6 text-zinc-500 hover:text-white">
                                <X size={20} />
                            </button>

                            <h3 className="text-xl font-bold mb-2 flex items-center gap-2">
                                <Sparkles className="text-indigo-500" size={20} />
                                Omnichannel AI Generation
                            </h3>
                            <p className="text-sm text-zinc-400 mb-6">Describe the promotion, menu item, or brand message you want the AI to create assets for. It will generate text and images instantly.</p>

                            <div className="space-y-4">
                                <div>
                                    <label className="text-xs font-bold text-zinc-500 uppercase tracking-widest mb-2 block">AI Prompt</label>
                                    <textarea
                                        value={prompt}
                                        onChange={e => setPrompt(e.target.value)}
                                        placeholder="e.g. Generate an aggressive TikTok campaign for our new Spicy Tacos, emphasize the melting cheese and cheap price."
                                        className="w-full bg-zinc-900 border border-zinc-800 rounded-xl p-4 text-sm text-white focus:outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 transition-all h-32 resize-none"
                                    />
                                </div>
                                <button
                                    onClick={handleGenerate}
                                    disabled={!prompt || isGenerating}
                                    className="w-full h-12 rounded-xl bg-indigo-500 text-white font-bold flex items-center justify-center gap-2 hover:bg-indigo-600 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                                >
                                    {isGenerating ? <Loader2 className="animate-spin" size={18} /> : <Send size={18} />}
                                    {isGenerating ? 'Waking up the AI...' : 'Fire W_OMNICHANNEL_CONTENT_GEN Workflow'}
                                </button>
                            </div>
                        </motion.div>
                    </motion.div>
                )}
            </AnimatePresence>
        </div>
    );
}
