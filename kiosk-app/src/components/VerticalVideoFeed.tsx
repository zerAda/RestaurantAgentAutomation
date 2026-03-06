import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ShoppingBag, ChevronDown, Plus, Search, Globe, Activity, Star, Sparkles, Navigation, Heart } from "lucide-react";
import { playSound } from "../utils/SoundManager";
import { useCart } from "../context/CartContext";
import { trackEvent } from "../utils/tracking";
import { getTranslation, setPageDirection, type Language } from "../utils/i18n";
import { Cart } from "./Cart";
import CustomizerModal from "./CustomizerModal";
import LanguageSelector from "./LanguageSelector";
import { cn } from "@/lib/utils";

interface ProductVideo {
    id: string;
    url: string;
    type: 'video' | 'image';
    title: string;
    price: number;
    rawPrice: string;
    desc: string;
}

const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || 'https://cms.' + (import.meta.env.VITE_DOMAIN || 'localhost');
const STRAPI_PLACEHOLDER = `${STRAPI_URL}/uploads/placeholder_menu_item.png`;

const FALLBACK_FEED: ProductVideo[] = [
    {
        id: "fallback-1",
        url: STRAPI_PLACEHOLDER,
        type: 'image',
        title: "Initializing Matrix...",
        price: 0,
        rawPrice: "—",
        desc: "Establishing neural link to menu system."
    }
];

function mapStrapiToFeed(data: any[]): ProductVideo[] {
    return data.map((item: any) => {
        const attrs = item.attributes || item;
        const assets = attrs.creative_assets;
        const assetUrl = Array.isArray(assets) ? assets[0]?.url : assets?.url;
        const imageUrl = assetUrl
            ? (assetUrl.startsWith('http') ? assetUrl : `${STRAPI_URL}${assetUrl}`)
            : STRAPI_PLACEHOLDER;
        const price = typeof attrs.price === 'number' ? attrs.price : 0;
        return {
            id: String(item.id),
            url: imageUrl,
            type: 'image' as const,
            title: String(attrs.marketing_name || attrs.name || 'Untitled Item'),
            price,
            rawPrice: `${price} DA`,
            desc: String(attrs.description || ''),
        };
    });
}

export default function VerticalVideoFeed() {
    const [feed, setFeed] = useState<ProductVideo[]>(FALLBACK_FEED);
    const [loading, setLoading] = useState(true);
    const [index, setIndex] = useState(0);
    const { cartCount, addItem } = useCart();
    const [showCart, setShowCart] = useState(false);
    const [showCustomizer, setShowCustomizer] = useState(false);
    const [lang, setLang] = useState<Language>('fr');
    const [showLangSelector, setShowLangSelector] = useState(false);
    const [flyers, setFlyers] = useState<{ id: number; x: number; y: number }[]>([]);

    useEffect(() => {
        let cancelled = false;
        (async () => {
            try {
                const res = await fetch(`${STRAPI_URL}/api/products?populate=creative_assets&filters[is_kiosk_visible][$eq]=true&pagination[pageSize]=10&sort=createdAt:desc`);
                const json = await res.json();
                if (!cancelled && json.data?.length > 0) {
                    setFeed(mapStrapiToFeed(json.data));
                }
            } catch (err) {
                console.warn('[Kiosk] Signal drift: using fallback');
            } finally {
                if (!cancelled) setLoading(false);
            }
        })();
        return () => { cancelled = true; };
    }, []);

    useEffect(() => {
        setPageDirection(lang);
    }, [lang]);

    const nextSlide = () => {
        playSound('swipe');
        setIndex((prev) => (prev + 1) % feed.length);
    };

    const confirmAddition = (extras: any[], sauces: any[], size: any, quantity: number) => {
        const product = feed[index];
        addItem({
            id: product.id,
            name: product.title,
            price: product.price,
            category: 'specials',
            image: product.url,
            inStock: true,
            extras: [],
            sauces: [],
            sizes: [{ name: 'Normal', price_modifier: 0 }],
            preparationTime: 10
        }, extras, sauces, size, quantity);

        trackEvent('add_to_cart', { item_name: product.title, price: product.price });
        setShowCustomizer(false);

        const id = Date.now();
        setFlyers(prev => [...prev, { id, x: window.innerWidth / 2, y: window.innerHeight / 2 }]);
        setTimeout(() => setFlyers(prev => prev.filter(f => f.id !== id)), 1000);
    };

    const openLangSelector = () => {
        playSound('swipe');
        setShowLangSelector(true);
    };

    if (loading) {
        return (
            <div className="w-full h-screen bg-black flex items-center justify-center">
                <Activity size={48} className="text-brand-primary animate-pulse" />
            </div>
        );
    }

    return (
        <div className="relative w-full h-screen bg-black overflow-hidden select-none touch-none">

            {/* Cinematic Background Feed */}
            <AnimatePresence mode="wait">
                <motion.div
                    key={index}
                    initial={{ opacity: 0, scale: 1.15, filter: 'blur(20px)' }}
                    animate={{ opacity: 1, scale: 1, filter: 'blur(0px)' }}
                    exit={{ opacity: 0, scale: 0.9, filter: 'blur(40px)' }}
                    transition={{ duration: 1.2, ease: [0.22, 1, 0.36, 1] }}
                    className="absolute inset-0 z-0"
                >
                    <div className="absolute inset-0 bg-gradient-to-b from-black/80 via-transparent to-black/90 z-10" />
                    <img
                        src={feed[index].url}
                        alt={feed[index].title}
                        className="w-full h-full object-cover"
                    />
                </motion.div>
            </AnimatePresence>

            {/* Top Bar - High Density Glass */}
            <div className="absolute top-0 left-0 w-full p-10 z-50 flex justify-between items-center scrim-top">
                <div className="flex items-center gap-4">
                    <div className="w-14 h-14 rounded-2xl bg-brand-primary/20 backdrop-blur-3xl border border-brand-primary/30 flex items-center justify-center shadow-[0_0_20px_rgba(255,51,102,0.3)]">
                        <Navigation size={28} className="text-brand-primary animate-spin-slow" />
                    </div>
                    <div>
                        <h4 className="text-2xl font-black text-white tracking-widest uppercase italic leading-none">Ralphé <span className="text-zinc-500">Kiosk</span></h4>
                        <div className="flex items-center gap-2 mt-1.5 px-2 py-0.5 rounded bg-white/5 border border-white/10 max-w-fit">
                            <Activity size={10} className="text-success animate-pulse" />
                            <span className="text-[9px] font-black text-zinc-400 uppercase tracking-widest">Network Secure</span>
                        </div>
                    </div>
                </div>

                <div className="flex gap-4">
                    <button
                        onClick={openLangSelector}
                        className="w-14 h-14 rounded-2xl bg-white/5 backdrop-blur-2xl border border-white/10 flex items-center justify-center text-zinc-400 hover:text-white transition-all group"
                    >
                        <Globe size={20} className="group-hover:rotate-45 transition-transform" />
                        <span className="absolute -bottom-1 -right-1 bg-brand-primary text-[8px] px-1.5 py-0.5 rounded font-black text-black uppercase">{lang}</span>
                    </button>
                    <button className="w-14 h-14 rounded-2xl bg-white/5 backdrop-blur-2xl border border-white/10 flex items-center justify-center text-zinc-400">
                        <Search size={20} />
                    </button>
                    <button
                        onClick={() => setShowCart(true)}
                        className="relative w-14 h-14 rounded-2xl bg-white text-black flex items-center justify-center shadow-2xl hover:scale-110 active:scale-90 transition-transform"
                    >
                        <ShoppingBag size={24} />
                        {cartCount > 0 && (
                            <motion.span
                                initial={{ scale: 0 }}
                                animate={{ scale: 1 }}
                                className="absolute -top-2 -right-2 w-7 h-7 bg-brand-primary text-black text-[11px] font-black rounded-full flex items-center justify-center border-4 border-black"
                            >
                                {cartCount}
                            </motion.span>
                        )}
                    </button>
                </div>
            </div>

            {/* Product Info Matrix */}
            <div className={cn(
                "absolute bottom-40 z-30 max-w-xl transition-all",
                lang === 'ar' ? 'right-12 text-right' : 'left-12'
            )}>
                <AnimatePresence mode="wait">
                    <motion.div
                        key={`info-${index}`}
                        initial={{ opacity: 0, y: 30, x: lang === 'ar' ? 50 : -50 }}
                        animate={{ opacity: 1, y: 0, x: 0 }}
                        exit={{ opacity: 0, y: -20 }}
                        transition={{ delay: 0.1, duration: 0.6 }}
                        className="space-y-6"
                    >
                        <div className="flex items-center gap-3">
                            <div className="px-4 py-1.5 rounded-full bg-brand-primary/20 backdrop-blur-xl border border-brand-primary/30 text-[10px] font-black text-brand-primary uppercase tracking-[0.3em] flex items-center gap-2 shadow-[0_0_15px_rgba(255,51,102,0.2)]">
                                <Star size={10} fill="currentColor" />
                                {getTranslation('diamond_selection', lang)}
                            </div>
                            <div className="px-4 py-1.5 rounded-full bg-white/5 backdrop-blur-xl border border-white/10 text-[10px] font-black text-zinc-400 uppercase tracking-[0.3em] flex items-center gap-2">
                                <Sparkles size={10} />
                                Limited Release
                            </div>
                        </div>

                        <h2 className="text-8xl font-black text-white leading-[0.9] tracking-tighter uppercase italic select-none">
                            {feed[index].title}
                        </h2>

                        <p className="text-xl text-zinc-400 leading-relaxed font-medium italic opacity-80 max-w-md">
                            {feed[index].desc}
                        </p>

                        <div className="flex items-center gap-6 pt-4">
                            <button
                                onClick={() => setShowCustomizer(true)}
                                className="btn-quantum px-14 py-6 group"
                            >
                                <Plus size={24} className="group-hover:rotate-90 transition-transform" />
                                {getTranslation('pre_order', lang)} — {feed[index].rawPrice}
                            </button>
                            <button className="w-20 h-20 rounded-[2rem] bg-white/5 backdrop-blur-xl border border-white/10 flex items-center justify-center text-white hover:bg-brand-primary hover:text-black transition-all hover:scale-105 active:scale-95 group">
                                <Heart size={32} className="group-active:fill-current" />
                            </button>
                        </div>
                    </motion.div>
                </AnimatePresence>
            </div>

            {/* Navigation Pulse Indicators */}
            <div className={cn(
                "absolute top-1/2 -translate-y-1/2 z-30 flex flex-col gap-4",
                lang === 'ar' ? 'left-12' : 'right-12'
            )}>
                {feed.map((_, i) => (
                    <button
                        key={i}
                        onClick={() => setIndex(i)}
                        className={cn(
                            "w-1 transition-all duration-700 rounded-full",
                            i === index
                                ? "bg-brand-primary h-20 shadow-[0_0_25px_#FF3366]"
                                : "bg-white/10 h-3 hover:bg-white/30"
                        )}
                    />
                ))}
            </div>

            {/* Scroll Interaction Hint */}
            <button
                onClick={nextSlide}
                className="absolute bottom-10 left-1/2 -translate-x-1/2 z-30 flex flex-col items-center gap-4 group cursor-pointer"
            >
                <div className="flex flex-col items-center gap-1 opacity-40 group-hover:opacity-100 transition-opacity">
                    <div className="w-1 h-1 bg-white rounded-full animate-bounce" />
                    <div className="w-1 h-3 bg-white/30 rounded-full" />
                </div>
                <span className="text-[10px] font-black text-white/30 uppercase tracking-[0.6em] italic group-hover:text-white transition-colors">
                    {getTranslation('explore', lang)}
                </span>
                <ChevronDown className="w-6 h-6 text-white/50 group-hover:text-white group-active:translate-y-2 transition-all" />
            </button>

            {/* Add to Cart Sprites */}
            {flyers.map(flyer => (
                <motion.div
                    key={flyer.id}
                    initial={{ x: flyer.x, y: flyer.y, opacity: 1, scale: 2 }}
                    animate={{
                        x: lang === 'ar' ? 60 : window.innerWidth - 80,
                        y: 80,
                        opacity: 0,
                        scale: 0.1,
                        rotate: 720
                    }}
                    transition={{ duration: 0.8, ease: "circIn" }}
                    className="fixed z-[100] pointer-events-none"
                >
                    <div className="w-10 h-10 bg-brand-primary rounded-full flex items-center justify-center shadow-[0_0_20px_#FF3366]">
                        <Plus className="text-black" size={24} />
                    </div>
                </motion.div>
            ))}

            <AnimatePresence>
                {showCart && (
                    <motion.div
                        initial={{ opacity: 0, backdropFilter: 'blur(0px)' }}
                        animate={{ opacity: 1, backdropFilter: 'blur(40px)' }}
                        exit={{ opacity: 0, backdropFilter: 'blur(0px)' }}
                        className="fixed inset-0 z-[120] bg-black/40"
                    >
                        <Cart lang={lang} onClose={() => setShowCart(false)} />
                    </motion.div>
                )}

                {showCustomizer && (
                    <CustomizerModal
                        product={{
                            id: feed[index].id,
                            name: feed[index].title,
                            price: feed[index].price,
                            category: 'specials',
                            image: feed[index].url,
                            inStock: true,
                            extras: [],
                            sauces: [],
                            sizes: [{ name: 'Normal', price_modifier: 0 }],
                            preparationTime: 10
                        }}
                        lang={lang}
                        onClose={() => setShowCustomizer(false)}
                        onConfirm={confirmAddition}
                    />
                )}

                {showLangSelector && (
                    <LanguageSelector
                        currentLang={lang}
                        onSelect={(l) => setLang(l)}
                        onClose={() => setShowLangSelector(false)}
                    />
                )}
            </AnimatePresence>
        </div>
    );
}
