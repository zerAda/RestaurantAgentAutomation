import { motion } from 'framer-motion';
import { getTranslation } from '../utils/i18n';

interface CreativeAsset {
    id: string;
    title: string;
    status: 'draft' | 'processing' | 'approved' | 'published';
    thumbnail: string;
    platform: 'square' | 'vertical';
    caption: string;
    score: number;
}

const MOCK_ASSETS: CreativeAsset[] = [
    {
        id: '1',
        title: 'Signature Burger Promo',
        status: 'published',
        thumbnail: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?q=80&w=300&h=533&auto=format&fit=crop',
        platform: 'vertical',
        caption: 'Le Bazooka Burger est arrivé ! 🔥 Goûtez l’exceptionnel à Alger. #RestoBot',
        score: 92
    },
    {
        id: '2',
        title: 'Weekend Special Tacos',
        status: 'approved',
        thumbnail: 'https://images.unsplash.com/photo-1599974579688-8dbdd335c7b8?q=80&w=300&h=300&auto=format&fit=crop',
        platform: 'square',
        caption: 'Un tacos, mille saveurs. 🌮 Profitez de notre promo weekend !',
        score: 85
    },
    {
        id: '3',
        title: 'New Pizza Launch',
        status: 'processing',
        thumbnail: 'https://images.unsplash.com/photo-1513104890138-7c749659a591?q=80&w=300&h=533&auto=format&fit=crop',
        platform: 'vertical',
        caption: '',
        score: 0
    }
];

export function MarketingView({ lang }: { lang: any }) {
    const t = (key: string) => getTranslation(key, lang);

    return (
        <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="flex justify-between items-center">
                <div>
                    <h3 className="text-2xl font-black">{t('creative_center')}</h3>
                    <p className="text-zinc-500 text-sm">Track and manage your AI-generated social media campaigns.</p>
                </div>
                <button className="px-6 py-3 rounded-xl bg-indigo-500 text-white font-bold shadow-lg shadow-indigo-500/20 hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center gap-2">
                    <span>✨</span> {t('generate_ad')}
                </button>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {MOCK_ASSETS.map((asset) => (
                    <motion.div
                        key={asset.id}
                        initial={{ opacity: 0, y: 20 }}
                        animate={{ opacity: 1, y: 0 }}
                        className="diamond-card p-4 rounded-3xl group"
                    >
                        <div className="relative aspect-[9/16] rounded-2xl overflow-hidden mb-4">
                            {asset.platform === 'square' && <div className="absolute inset-x-0 bottom-0 top-0 m-auto aspect-square bg-zinc-800" />}
                            <img src={asset.thumbnail} alt={asset.title} className="w-full h-full object-cover" />
                            <div className="absolute top-4 left-4 flex gap-2">
                                <span className={`px-3 py-1 rounded-full text-[10px] font-black uppercase tracking-wider ${asset.status === 'published' ? 'bg-green-500 text-white' :
                                        asset.status === 'processing' ? 'bg-indigo-500 text-white animate-pulse' :
                                            'bg-zinc-900 text-white'
                                    }`}>
                                    {asset.status}
                                </span>
                                <span className="px-3 py-1 rounded-full bg-white/20 backdrop-blur-md text-white text-[10px] font-black uppercase tracking-wider">
                                    {asset.platform}
                                </span>
                            </div>
                            {asset.score > 0 && (
                                <div className="absolute bottom-4 right-4 w-12 h-12 rounded-full bg-indigo-500 flex items-center justify-center text-white font-black text-sm shadow-xl border-2 border-white/20">
                                    {asset.score}%
                                </div>
                            )}
                        </div>

                        <div className="px-2">
                            <h4 className="font-bold text-lg mb-1">{asset.title}</h4>
                            <p className="text-zinc-500 text-xs italic line-clamp-2 h-8">
                                {asset.caption || 'AI is crafting your caption...'}
                            </p>

                            <div className="mt-4 pt-4 border-t border-zinc-100 dark:border-zinc-800 flex justify-between items-center opacity-0 group-hover:opacity-100 transition-opacity">
                                <button className="text-xs font-bold text-zinc-400 hover:text-indigo-500 transition-colors">Edit Caption</button>
                                <button className="px-4 py-2 rounded-lg bg-zinc-100 dark:bg-zinc-800 text-xs font-black">Publish Now</button>
                            </div>
                        </div>
                    </motion.div>
                ))}
            </div>
        </div>
    );
}
