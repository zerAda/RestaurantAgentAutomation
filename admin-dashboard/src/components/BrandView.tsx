import { getTranslation, type Language } from '../utils/i18n';

export function BrandView({ lang }: { lang: Language }) {
    const t = (key: string) => getTranslation(key, lang);

    return (
        <div className="max-w-4xl space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
            <div className="diamond-card p-8 rounded-3xl">
                <h4 className="text-2xl font-black mb-6">{t('brand_dna')}</h4>

                <div className="space-y-6">
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                        <div className="space-y-2">
                            <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">Restaurant Name</label>
                            <input type="text" defaultValue="RestoBot Diamond" className="w-full bg-zinc-50 dark:bg-zinc-800 border-none rounded-xl px-4 py-3 focus:ring-2 focus:ring-indigo-500" />
                        </div>
                        <div className="space-y-2">
                            <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">Voice Tone</label>
                            <select className="w-full bg-zinc-50 dark:bg-zinc-800 border-none rounded-xl px-4 py-3 focus:ring-2 focus:ring-indigo-500">
                                <option>Bold Streetfood</option>
                                <option>Friendly Casual</option>
                                <option>Professional Elegant</option>
                                <option>Trendy Gen-Z</option>
                            </select>
                        </div>
                    </div>

                    <div className="space-y-2">
                        <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">Brand Story & Mission</label>
                        <textarea rows={4} className="w-full bg-zinc-50 dark:bg-zinc-800 border-none rounded-2xl px-4 py-3 focus:ring-2 focus:ring-indigo-500" defaultValue="Providing the finest burger experience in Algiers with AI-powered hospitality." />
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                        <div className="space-y-2">
                            <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">Primary Color</label>
                            <div className="flex gap-3">
                                <div className="w-10 h-10 rounded-lg bg-indigo-500 shadow-lg" />
                                <input type="text" defaultValue="#6366F1" className="flex-1 bg-zinc-50 dark:bg-zinc-800 border-none rounded-xl px-4 py-2 text-xs font-mono" />
                            </div>
                        </div>
                        <div className="space-y-2">
                            <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">Secondary Color</label>
                            <div className="flex gap-3">
                                <div className="w-10 h-10 rounded-lg bg-purple-600 shadow-lg" />
                                <input type="text" defaultValue="#9333EA" className="flex-1 bg-zinc-50 dark:bg-zinc-800 border-none rounded-xl px-4 py-2 text-xs font-mono" />
                            </div>
                        </div>
                        <div className="space-y-2">
                            <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">Preferred Aesthetic</label>
                            <select className="w-full bg-zinc-50 dark:bg-zinc-800 border-none rounded-xl px-4 py-3 text-xs">
                                <option>Luxury Minimalist</option>
                                <option>Warm Rustic</option>
                                <option>Neon Streetfood</option>
                            </select>
                        </div>
                    </div>
                </div>

                <div className="mt-10 pt-8 border-t border-zinc-100 dark:border-zinc-800 flex justify-end">
                    <button className="px-8 py-3 rounded-xl bg-indigo-500 text-white font-bold shadow-xl shadow-indigo-500/20 hover:scale-[1.02] active:scale-[0.98] transition-all">
                        Update Brand DNA
                    </button>
                </div>
            </div>
        </div>
    );
}
