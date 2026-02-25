import { useCart } from '../context/CartContext';
import { getTranslation } from '../utils/i18n';
import { X, Trash2, ChevronUp, ChevronDown, Check, Loader2 } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { useState } from "react";
import { trackEvent } from '../utils/tracking';

type Language = 'en' | 'fr' | 'ar';

interface CartProps {
    lang: Language;
    onClose: () => void;
}

export function Cart({ lang, onClose }: CartProps) {
    const {
        items, removeItem, updateQuantity, clearCart, total,
        tableNumber, setTableNumber, orderType, setOrderType,
        submitOrder, isSubmitting, lastOrderResult
    } = useCart();
    const [showReceipt, setShowReceipt] = useState(false);

    const handleOrderNow = async () => {
        trackEvent('checkout_start', { total, item_count: items.length, table: tableNumber, type: orderType });
        const result = await submitOrder();
        if (result.success) {
            setShowReceipt(true);
            trackEvent('order_confirmed', { order_id: result.order_id, total: result.total_amount });
        }
    };

    // ORDER CONFIRMATION RECEIPT (DOPAMINE HIT)
    if (showReceipt && lastOrderResult?.success) {
        return (
            <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                className="flex flex-col h-full bg-zinc-950 text-white items-center justify-center p-10 relative overflow-hidden"
            >
                {/* Background Glow */}
                <div className="absolute inset-0 bg-gradient-to-b from-yellow-500/10 to-transparent opacity-50" />

                <motion.div
                    initial={{ scale: 0, rotate: -180 }}
                    animate={{ scale: 1, rotate: 0 }}
                    transition={{ type: "spring", stiffness: 200, damping: 20, delay: 0.1 }}
                    className="relative w-40 h-40 rounded-full bg-gradient-to-br from-yellow-300 to-amber-500 flex items-center justify-center mb-10 z-10 shadow-[0_0_80px_rgba(250,204,21,0.6)]"
                >
                    <div className="absolute inset-0 rounded-full border-4 border-white/30 animate-ping opacity-50" />
                    <Check className="w-20 h-20 text-black" strokeWidth={3} />
                </motion.div>

                <motion.div
                    initial={{ opacity: 0, y: 30 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.3, type: "spring" }}
                    className="z-10 text-center w-full max-w-sm"
                >
                    <h2 className="text-5xl font-black mb-2 text-transparent bg-clip-text bg-gradient-to-r from-white to-zinc-400 tracking-tight">
                        {lastOrderResult.is_merge ? 'Ajouté !' : 'Confirmée !'}
                    </h2>
                    <p className="text-2xl font-bold text-yellow-400 mb-8 uppercase tracking-widest">
                        Commande N° {lastOrderResult.order_id}
                    </p>

                    <div className="diamond-glass p-8 rounded-[2rem] space-y-6 mb-12 relative overflow-hidden">
                        <div className="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-yellow-400 to-amber-500" />
                        {tableNumber && (
                            <div className="flex justify-between items-center text-xl">
                                <span className="text-zinc-400">Emplacement</span>
                                <span className="font-black text-white">Table {tableNumber}</span>
                            </div>
                        )}
                        <div className="flex justify-between items-center text-xl">
                            <span className="text-zinc-400">Temps estimé</span>
                            <span className="font-black text-white">{lastOrderResult.estimated_ready_time} min</span>
                        </div>
                        <div className="pt-6 border-t border-white/10 flex justify-between items-center">
                            <span className="text-zinc-400 text-2xl">Total</span>
                            <span className="text-4xl font-black text-yellow-400">{lastOrderResult.total_amount.toLocaleString()} DA</span>
                        </div>
                    </div>

                    <motion.button
                        whileHover={{ scale: 1.05 }}
                        whileTap={{ scale: 0.95 }}
                        onClick={() => { setShowReceipt(false); onClose(); }}
                        className="btn-gold w-full text-2xl h-20 shadow-[0_0_40px_rgba(250,204,21,0.3)]"
                    >
                        Nouvelle commande
                    </motion.button>
                </motion.div>
            </motion.div>
        );
    }

    return (
        <div className="flex flex-col h-full bg-zinc-950 text-white">
            {/* Header */}
            <div className="p-10 flex justify-between items-center border-b border-white/10">
                <h3 className="text-4xl font-black">{getTranslation('diamond_session', lang)}</h3>
                <button
                    onClick={onClose}
                    className="w-16 h-16 rounded-full bg-white/10 flex items-center justify-center hover:bg-white/20 transition-colors"
                >
                    <X className="w-8 h-8" />
                </button>
            </div>

            {/* Table & Order Type */}
            <div className="px-10 pt-6 pb-4 border-b border-white/5 flex gap-4">
                <div className="flex-1">
                    <label className="text-sm text-white/40 uppercase tracking-widest block mb-2">🪑 Table</label>
                    <input
                        type="number"
                        value={tableNumber || ''}
                        onChange={e => setTableNumber(e.target.value ? Number(e.target.value) : null)}
                        placeholder="N°"
                        className="w-full bg-white/5 border border-white/10 rounded-2xl px-5 py-4 text-xl text-white font-bold text-center outline-none focus:border-[#FFB800] transition-colors"
                    />
                </div>
                <div className="flex-1">
                    <label className="text-sm text-white/40 uppercase tracking-widest block mb-2">📦 Type</label>
                    <div className="flex gap-2">
                        <button
                            onClick={() => setOrderType('dine_in')}
                            className={`flex-1 py-4 rounded-2xl font-bold text-sm transition-all ${orderType === 'dine_in'
                                ? 'bg-yellow-400 text-black shadow-[0_0_20px_rgba(250,204,21,0.2)]'
                                : 'bg-white/5 text-white/60 border border-white/10'
                                }`}
                        >
                            🍽️ Sur place
                        </button>
                        <button
                            onClick={() => setOrderType('takeaway')}
                            className={`flex-1 py-4 rounded-2xl font-bold text-sm transition-all ${orderType === 'takeaway'
                                ? 'bg-yellow-400 text-black shadow-[0_0_20px_rgba(250,204,21,0.2)]'
                                : 'bg-white/5 text-white/60 border border-white/10'
                                }`}
                        >
                            🥡 Emporter
                        </button>
                    </div>
                </div>
            </div>

            {/* Items */}
            <div className="flex-1 overflow-y-auto p-10 space-y-4">
                {items.length === 0 ? (
                    <div className="h-full flex flex-col items-center justify-center opacity-20">
                        <Trash2 className="w-32 h-32 mb-4" />
                        <p className="text-2xl font-bold uppercase tracking-widest">{getTranslation('cart_empty', lang)}</p>
                    </div>
                ) : (
                    <AnimatePresence>
                        {items.map((item) => {
                            const extrasTotal = item.extras.reduce((s, e) => s + e.price, 0);
                            const saucesTotal = item.sauces.filter(s => !s.is_free).reduce((s, sauce) => s + sauce.price, 0);
                            const unitPrice = item.product.price + item.size.price_modifier + extrasTotal + saucesTotal;

                            return (
                                <motion.div
                                    layout
                                    initial={{ opacity: 0, y: 20 }}
                                    animate={{ opacity: 1, y: 0 }}
                                    exit={{ opacity: 0, x: -100 }}
                                    key={item.id}
                                    className="p-5 rounded-[2rem] bg-white/5 border border-white/10"
                                >
                                    <div className="flex justify-between items-start">
                                        <div className="flex-1">
                                            <div className="text-xl font-black mb-1">
                                                {item.product.name}
                                                {item.size.name !== 'Normal' && (
                                                    <span className="text-[#FFB800] text-sm ml-2">({item.size.name})</span>
                                                )}
                                            </div>
                                            {item.extras.length > 0 && (
                                                <div className="text-white/40 text-xs">
                                                    ✨ {item.extras.map(e => e.name).join(", ")}
                                                </div>
                                            )}
                                            {item.sauces.length > 0 && (
                                                <div className="text-white/40 text-xs">
                                                    🫙 {item.sauces.map(s => s.name + (s.is_free ? ' ✓' : '')).join(", ")}
                                                </div>
                                            )}
                                        </div>
                                        <button
                                            onClick={() => removeItem(item.id)}
                                            className="w-10 h-10 rounded-full bg-red-500/10 text-red-500 flex items-center justify-center hover:bg-red-500/20 shrink-0 ml-4"
                                        >
                                            <X className="w-4 h-4" />
                                        </button>
                                    </div>

                                    <div className="flex justify-between items-center mt-3">
                                        <div className="flex items-center gap-3">
                                            <button
                                                onClick={() => updateQuantity(item.id, -1)}
                                                className="w-9 h-9 rounded-full bg-white/10 flex items-center justify-center hover:bg-white/20"
                                            >
                                                <ChevronDown className="w-5 h-5" />
                                            </button>
                                            <span className="text-xl font-black min-w-[30px] text-center">{item.quantity}</span>
                                            <button
                                                onClick={() => updateQuantity(item.id, 1)}
                                                className="w-9 h-9 rounded-full bg-white/10 flex items-center justify-center hover:bg-white/20"
                                            >
                                                <ChevronUp className="w-5 h-5" />
                                            </button>
                                        </div>
                                        <span className="text-xl font-bold text-[#FFB800]">
                                            {unitPrice * item.quantity} DA
                                        </span>
                                    </div>
                                </motion.div>
                            );
                        })}
                    </AnimatePresence>
                )}
            </div>

            {/* Footer */}
            <div className="p-10 border-t border-white/10 bg-black/40">
                <div className="flex justify-between items-center mb-6">
                    <span className="text-white/40 text-2xl uppercase tracking-[0.2em]">{getTranslation('total', lang)}</span>
                    <span className="text-5xl font-black text-white">{total} DA</span>
                </div>
                <div className="flex gap-4">
                    <button
                        onClick={clearCart}
                        disabled={isSubmitting}
                        className="px-8 py-5 rounded-full border border-white/10 text-white/60 font-bold hover:bg-white/5 transition-all disabled:opacity-30"
                    >
                        {getTranslation('empty_cart', lang)}
                    </button>
                    <button
                        onClick={handleOrderNow}
                        disabled={isSubmitting || items.length === 0}
                        className="flex-1 py-5 rounded-full bg-[#FFB800] text-black font-black text-2xl shadow-2xl hover:scale-[1.02] active:scale-[0.98] transition-all disabled:opacity-50 disabled:scale-100 flex items-center justify-center gap-3"
                    >
                        {isSubmitting ? (
                            <>
                                <Loader2 className="w-6 h-6 animate-spin" />
                                Envoi...
                            </>
                        ) : (
                            getTranslation('order_now', lang)
                        )}
                    </button>
                </div>
            </div>
        </div>
    );
}
