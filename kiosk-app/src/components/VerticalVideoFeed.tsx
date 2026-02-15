import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ShoppingBag, Heart, ChevronDown } from "lucide-react";
import { playSound } from "../utils/SoundManager";

interface ProductVideo {
    id: string;
    url: string; // URL to video/image
    type: 'video' | 'image';
    title: string;
    price: string;
    desc: string;
}

const MOCK_FEED: ProductVideo[] = [
    {
        id: "1",
        url: "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?q=80&w=1899&auto=format&fit=crop", // Burger
        type: "image", // Mocking as image for now, would be <video>
        title: "Le Ralphé Signature",
        price: "850 DA",
        desc: "Double steak, cheddar fondant, sauce secrète."
    },
    {
        id: "2",
        url: "https://images.unsplash.com/photo-1513104890138-7c749659a591?q=80&w=2070&auto=format&fit=crop", // Pizza
        type: "image",
        title: "Pizza 4 Fromages",
        price: "1200 DA",
        desc: "Mozzarella, Gorgonzola, Chèvre, Parmesan."
    },
    {
        id: "3",
        url: "https://images.unsplash.com/photo-1623653387945-2fd25214 f8fc?q=80&w=2070&auto=format&fit=crop", // Tacos
        type: "image",
        title: "Tacos XL",
        price: "950 DA",
        desc: "Sauce fromagère maison, frites croustillantes."
    }
];


export default function VerticalVideoFeed() {
    const [index, setIndex] = useState(0);

    const nextSlide = () => {
        playSound('swipe');
        setIndex((prev) => (prev + 1) % MOCK_FEED.length);
    };

    // prevSlide removed as it was unused in this vertical feed MVP
    // const prevSlide = () => {
    //     setIndex((prev) => (prev === 0 ? MOCK_FEED.length - 1 : prev - 1));
    // };


    // Basic swipe handler (mouse/touch)
    // implementing via buttons for MVP stability

    const currentItem = MOCK_FEED[index];

    return (
        <div className="relative w-full h-screen bg-black overflow-hidden flex flex-col justify-center items-center">

            {/* Background Media */}
            <AnimatePresence mode="wait">
                <motion.div
                    key={currentItem.id}
                    initial={{ opacity: 0, scale: 1.1 }}
                    animate={{ opacity: 1, scale: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.5 }}
                    className="absolute inset-0 z-0"
                >
                    <div className="absolute inset-0 bg-gradient-to-b from-black/30 via-transparent to-black/80 z-10" />
                    <img src={currentItem.url} alt={currentItem.title} className="w-full h-full object-cover" />
                </motion.div>
            </AnimatePresence>

            {/* Product Info Overlay */}
            <div className="absolute bottom-20 left-6 right-6 z-20 text-white">
                <motion.h2
                    key={currentItem.title}
                    initial={{ y: 20, opacity: 0 }}
                    animate={{ y: 0, opacity: 1 }}
                    transition={{ delay: 0.2 }}
                    className="text-4xl font-bold mb-2 font-display"
                >
                    {currentItem.title}
                </motion.h2>
                <motion.p
                    key={currentItem.desc}
                    initial={{ y: 20, opacity: 0 }}
                    animate={{ y: 0, opacity: 1 }}
                    transition={{ delay: 0.3 }}
                    className="text-lg text-gray-200 mb-4"
                >
                    {currentItem.desc}
                </motion.p>

                <div className="flex items-center justify-between mt-6">
                    <span className="text-3xl font-bold text-yellow-400">{currentItem.price}</span>
                    <button className="bg-white text-black px-8 py-3 rounded-full font-bold text-lg flex items-center gap-2 hover:scale-105 transition-transform">
                        <ShoppingBag className="w-5 h-5" />
                        Commander
                    </button>
                </div>
            </div>

            {/* Floating Actions */}
            <div className="absolute right-4 bottom-40 z-20 flex flex-col gap-6">
                <div className="flex flex-col items-center gap-1">
                    <div className="w-12 h-12 bg-gray-800/60 backdrop-blur-md rounded-full flex items-center justify-center cursor-pointer hover:bg-red-500/20 transition">
                        <Heart className="w-6 h-6 text-white" />
                    </div>
                    <span className="text-xs text-white font-medium">1.2k</span>
                </div>
            </div>

            {/* Navigation Indicators */}
            <div className="absolute right-4 top-1/2 -translate-y-1/2 z-30 flex flex-col gap-2">
                {MOCK_FEED.map((_, i) => (
                    <div
                        key={i}
                        onClick={() => setIndex(i)}
                        className={`w-1.5 h-1.5 rounded-full cursor-pointer transition-all ${i === index ? 'bg-white h-6' : 'bg-white/40'}`}
                    />
                ))}
            </div>

            {/* Scroll Hint */}
            <div
                onClick={nextSlide}
                className="absolute bottom-6 left-1/2 -translate-x-1/2 z-30 animate-bounce cursor-pointer p-2"
            >
                <ChevronDown className="w-8 h-8 text-white/70" />
            </div>

        </div>
    );
}
