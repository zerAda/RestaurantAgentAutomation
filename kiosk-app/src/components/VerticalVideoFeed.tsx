import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ShoppingBag, Heart, ChevronDown, Plus, Search } from "lucide-react";
import { playSound } from "../utils/SoundManager";
import { useCart } from "../context/CartContext";
import { trackEvent } from "../utils/tracking";
import { getTranslation, setPageDirection, type Language } from "../utils/i18n";
import { Cart } from "./Cart";
import CustomizerModal from "./CustomizerModal";

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

const FALLBACK_FEED: ProductVideo[] = [
    {
        id: "1",
        url: "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?q=80&w=1899&auto=format&fit=crop",
        type: 'image',
        title: "Diamond Signature Burger",
        price: 1850,
        rawPrice: "1850 DA",
        desc: "24-hour aged wagyu beef, truffle aioli, gold-leaf brioche."
    },
    {
        id: "2",
        url: "https://images.unsplash.com/photo-1574071318508-1cdbab80d002?q=80&w=1899&auto=format&fit=crop",
        type: 'image',
        title: "Celestial Margherita",
        price: 2200,
        rawPrice: "2200 DA",
        desc: "San Marzano tomatoes, buffalo mozzarella, fresh basil, extra virgin olive oil."
    },
    {
        id: "3",
        url: "https://images.unsplash.com/photo-1550547660-d9450f859349?q=80&w=1899&auto=format&fit=crop",
        type: 'image',
        title: "Midnight Cheese Melt",
        price: 1400,
        rawPrice: "1400 DA",
        desc: "Triple cream brie, caramelized onions, artisan sourdough."
    }
];

function mapStrapiToFeed(data: Record<string, unknown>[]): ProductVideo[] {
    return data.map((item: Record<string, unknown>) => {
        const attrs = item.attributes || item;
        const img = attrs.image?.data?.attributes?.url;
        const imageUrl = img ? (img.startsWith('http') ? img : `${STRAPI_URL}${img}`) : FALLBACK_FEED[0].url;
        return {
            id: String(item.id),
            url: imageUrl,
            type: 'image' as const,
            title: attrs.name || attrs.title || 'Untitled',
            price: attrs.price_cents ? attrs.price_cents / 100 : (attrs.price || 0),
            rawPrice: `${attrs.price_cents ? attrs.price_cents / 100 : (attrs.price || 0)} DA`,
            desc: attrs.description || '',
        };
    });
}

function useLiveFeed() {
    const [feed, setFeed] = useState<ProductVideo[]>(FALLBACK_FEED);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let cancelled = false;
        (async () => {
            try {
                const res = await fetch(`${STRAPI_URL}/api/menu-items?populate=*&pagination[pageSize]=10&sort=createdAt:desc`);
                if (!res.ok) throw new Error(`HTTP ${res.status}`);
                const json = await res.json();
                const items = json.data;
                if (!cancelled && Array.isArray(items) && items.length > 0) {
                    setFeed(mapStrapiToFeed(items));
                }
            } catch (err) {
                console.warn('[Kiosk] Strapi fetch failed, using fallback feed:', err);
            } finally {
                if (!cancelled) setLoading(false);
            }
        })();
        return () => { cancelled = true; };
    }, []);

    return { feed, loading };
}

export default function VerticalVideoFeed() {
    const { feed, loading } = useLiveFeed();
    const [index, setIndex] = useState(0);
    const { cartCount, addItem } = useCart();
    const [showCart, setShowCart] = useState(false);
    const [showCustomizer, setShowCustomizer] = useState(false);
    const [lang, setLang] = useState<Language>('fr');
    const [flyers, setFlyers] = useState<{ id: number; x: number; y: number }[]>([]);

    useEffect(() => {
        setPageDirection(lang);
    }, [lang]);

    const nextSlide = () => {
        playSound('swipe');
        setIndex((prev) => (prev + 1) % feed.length);
    };

    const handlePreOrder = () => {
        playSound('select');
        setShowCustomizer(true);
    };

    const confirmAddition = (extras: { name: string; price: number }[], sauces: { name: string; price: number; is_free: boolean }[], size: { name: string; price_modifier: number }, quantity: number) => {
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

        // Omnichannel Funnel Tracking
        trackEvent('add_to_cart', { item_name: product.title, price: product.price, extras, sauces, size, quantity });

        setShowCustomizer(false);
        // Fly-in effect
        const id = Date.now();
        setFlyers(prev => [...prev, { id, x: window.innerWidth / 2, y: window.innerHeight / 2 }]);
        setTimeout(() => {
            setFlyers(prev => prev.filter(f => f.id !== id));
        }, 1000);
    };

    const toggleLang = () => {
        const langs: Language[] = ['en', 'fr', 'ar'];
        const next = langs[(langs.indexOf(lang) + 1) % langs.length];
        setLang(next);
    };

    if (loading) {
        return (
            <div className="w-full h-screen bg-black flex items-center justify-center">
                <div className="w-12 h-12 border-4 border-white/20 border-t-[#FFB800] rounded-full animate-spin" />
            </div>
        );
    }

    return (
        <div className="relative w-full h-screen bg-black overflow-hidden select-none">
            {/* Background Feed */}
            <AnimatePresence mode="wait">
                <motion.div
                    key={index}
                    initial={{ opacity: 0, scale: 1.1 }}
                    animate={{ opacity: 1, scale: 1 }}
                    exit={{ opacity: 0, filter: "blur(10px)" }}
                    transition={{ duration: 0.8, ease: [0.22, 1, 0.36, 1] }}
                    className="absolute inset-0 z-0"
                >
                    <div className="absolute inset-0 bg-gradient-to-b from-black/60 via-transparent to-black/80 z-10" />
                    <img
                        src={feed[index].url}
                        alt={feed[index].title}
                        className="w-full h-full object-cover"
                    />
                </motion.div>
            </AnimatePresence>

            {/* Top Bar */}
            <div className="absolute top-0 left-0 w-full p-8 z-40 flex justify-between items-center bg-gradient-to-b from-black/80 to-transparent">
                <div className="flex items-center gap-3">
                    <div className="w-12 h-12 rounded-2xl bg-white/10 backdrop-blur-xl border border-white/20 flex items-center justify-center">
                        <span className="text-white font-black text-2xl">R</span>
                    </div>
                    <span className="text-white font-bold text-xl tracking-tight uppercase">RestoBot <span className="text-[#FFB800] italic">Diamond</span></span>
                </div>
                <div className="flex gap-4">
                    <div
                        onClick={toggleLang}
                        className="w-12 h-12 rounded-full bg-white/10 backdrop-blur-md border border-white/20 flex items-center justify-center text-white cursor-pointer hover:bg-white/20"
                    >
                        <span className="font-bold text-xs uppercase">{lang}</span>
                    </div>
                    <div className="w-12 h-12 rounded-full bg-white/10 backdrop-blur-md border border-white/20 flex items-center justify-center text-white">
                        <Search className="w-5 h-5" />
                    </div>
                    <div
                        onClick={() => setShowCart(true)}
                        className="relative group cursor-pointer"
                    >
                        <div className="w-12 h-12 rounded-full bg-white text-black flex items-center justify-center shadow-xl group-hover:scale-110 transition-transform">
                            <ShoppingBag className="w-5 h-5" />
                        </div>
                        {cartCount > 0 && (
                            <motion.span
                                initial={{ scale: 0 }}
                                animate={{ scale: 1 }}
                                className="absolute -top-1 -right-1 w-6 h-6 bg-[#FFB800] text-black text-[10px] font-black rounded-full flex items-center justify-center border-2 border-black"
                            >
                                {cartCount}
                            </motion.span>
                        )}
                    </div>
                </div>
            </div>

            {/* Main Content Info */}
            <div className={`absolute bottom-32 ${lang === 'ar' ? 'right-8' : 'left-8'} z-30 max-w-lg transition-all`}>
                <motion.div
                    key={`info-${index}`}
                    initial={{ opacity: 0, x: lang === 'ar' ? 50 : -50 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: 0.2, duration: 0.5 }}
                >
                    <div className="inline-block px-3 py-1 rounded-full bg-white/20 backdrop-blur-md border border-white/30 text-xs font-bold text-white mb-4 uppercase tracking-[0.2em]">
                        {getTranslation('diamond_selection', lang)}
                    </div>
                    <h2 className="text-6xl font-black text-white mb-4 leading-tight">
                        {feed[index].title}
                    </h2>
                    <p className="text-xl text-white/70 mb-8 leading-relaxed font-light">
                        {feed[index].desc}
                    </p>
                    <div className="flex items-center gap-6">
                        <button
                            onClick={handlePreOrder}
                            className="bg-white text-black px-12 py-5 rounded-full font-black text-xl shadow-2xl hover:scale-105 active:scale-95 transition-all flex items-center gap-3"
                        >
                            <Plus className="w-6 h-6" />
                            {getTranslation('pre_order', lang)} {feed[index].rawPrice}
                        </button>
                        <div className="w-16 h-16 rounded-full border-2 border-white/30 flex items-center justify-center text-white hover:bg-white hover:text-black transition-colors cursor-pointer">
                            <Heart className="w-8 h-8" />
                        </div>
                    </div>
                </motion.div>
            </div>

            {/* Navigation Indicators */}
            <div className={`absolute ${lang === 'ar' ? 'left-8' : 'right-8'} top-1/2 -translate-y-1/2 z-30 flex flex-col gap-4`}>
                {feed.map((_, i) => (
                    <div
                        key={i}
                        onClick={() => setIndex(i)}
                        className={`w-2 rounded-full cursor-pointer transition-all duration-500 ${i === index ? 'bg-[#FFB800] h-12 shadow-[0_0_20px_rgba(255,184,0,0.5)]' : 'bg-white/20 h-2'}`}
                    />
                ))}
            </div>

            {/* Scroll Hint */}
            <div
                onClick={nextSlide}
                className="absolute bottom-8 left-1/2 -translate-x-1/2 z-30 flex flex-col items-center gap-2 cursor-pointer group"
            >
                <span className="text-[10px] font-bold text-white/40 uppercase tracking-[0.4em] translate-y-2 group-hover:translate-y-0 opacity-0 group-hover:opacity-100 transition-all">
                    {getTranslation('explore', lang)}
                </span>
                <ChevronDown className="w-10 h-10 text-white animate-bounce" />
            </div>

            {/* Fly-in Sprites */}
            {flyers.map(flyer => (
                <motion.div
                    key={flyer.id}
                    initial={{ x: flyer.x - 20, y: flyer.y - 20, opacity: 1, scale: 1.5 }}
                    animate={{
                        x: lang === 'ar' ? 40 : window.innerWidth - 60,
                        y: 40,
                        opacity: 0,
                        scale: 0.2,
                        rotate: 360
                    }}
                    transition={{ duration: 0.8, ease: "circIn" }}
                    className="fixed z-[100] text-4xl pointer-events-none"
                >
                    💎
                </motion.div>
            ))}

            <AnimatePresence>
                {showCart && (
                    <motion.div
                        initial={{ opacity: 0, x: lang === 'ar' ? -500 : 500 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0, x: lang === 'ar' ? -500 : 500 }}
                        className="fixed inset-0 z-[120] backdrop-blur-2xl"
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
            </AnimatePresence>
        </div>
    );
}
