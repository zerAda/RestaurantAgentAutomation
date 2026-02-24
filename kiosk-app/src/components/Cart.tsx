import { useCart } from '../context/CartContext';
import { getTranslation } from '../utils/i18n';
import { X, Trash2 } from "lucide-react";
import { motion } from "framer-motion";

interface CartProps {
    lang: any;
    onClose: () => void;
}

export function Cart({ lang, onClose }: CartProps) {
    const { items, removeItem, clearCart, total } = useCart();

    return (
        <div className="flex flex-col h-full bg-zinc-950 text-white">
            <div className="p-10 flex justify-between items-center border-b border-white/10">
                <h3 className="text-4xl font-black">{getTranslation('diamond_session', lang)}</h3>
                <button
                    onClick={onClose}
                    className="w-16 h-16 rounded-full bg-white/10 flex items-center justify-center hover:bg-white/20 transition-colors"
                >
                    <X className="w-8 h-8" />
                </button>
            </div>

            <div className="flex-1 overflow-y-auto p-10 space-y-6">
                {items.length === 0 ? (
                    <div className="h-full flex flex-col items-center justify-center opacity-20">
                        <Trash2 className="w-32 h-32 mb-4" />
                        <p className="text-2xl font-bold uppercase tracking-widest">{getTranslation('cart_empty', lang)}</p>
                    </div>
                ) : (
                    items.map((item) => (
                        <motion.div
                            layout
                            initial={{ opacity: 0, y: 20 }}
                            animate={{ opacity: 1, y: 0 }}
                            key={item.id}
                            className="p-6 rounded-[2rem] bg-white/5 border border-white/10 flex justify-between items-center"
                        >
                            <div className="flex-1">
                                <div className="text-2xl font-black mb-1">{item.product.name}</div>
                                {item.extras.length > 0 && (
                                    <div className="text-white/40 text-sm">
                                        {item.extras.map(e => e.name).join(", ")}
                                    </div>
                                )}
                                <div className="text-white/60 mt-2">x{item.quantity}</div>
                            </div>
                            <div className="flex items-center gap-6">
                                <span className="text-2xl font-bold text-[#FFB800]">
                                    {(item.product.price + item.extras.reduce((s, e) => s + e.price, 0)) * item.quantity} DA
                                </span>
                                <button
                                    onClick={() => removeItem(item.id)}
                                    className="w-12 h-12 rounded-full bg-red-500/10 text-red-500 flex items-center justify-center hover:bg-red-500/20"
                                >
                                    <X className="w-5 h-5" />
                                </button>
                            </div>
                        </motion.div>
                    ))
                )}
            </div>

            <div className="p-10 border-t border-white/10 bg-black/40">
                <div className="flex justify-between items-center mb-8">
                    <span className="text-white/40 text-2xl uppercase tracking-[0.2em]">{getTranslation('total', lang)}</span>
                    <span className="text-5xl font-black text-white">{total} DA</span>
                </div>
                <div className="flex gap-4">
                    <button
                        onClick={clearCart}
                        className="px-8 py-5 rounded-full border border-white/10 text-white/60 font-bold hover:bg-white/5 transition-all"
                    >
                        {getTranslation('empty_cart', lang)}
                    </button>
                    <button className="flex-1 py-5 rounded-full bg-[#FFB800] text-black font-black text-2xl shadow-2xl hover:scale-[1.02] active:scale-[0.98] transition-all">
                        {getTranslation('order_now', lang)}
                    </button>
                </div>
            </div>
        </div>
    );
}
