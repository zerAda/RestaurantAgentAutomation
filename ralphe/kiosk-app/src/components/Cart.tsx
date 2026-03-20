import { useCart } from '../context/CartContext';
import { getTranslation } from '../utils/i18n';
import { X, Trash2, ChevronUp, ChevronDown, Check, Loader2, CreditCard, ShoppingBag, MapPin, Clock, Activity } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { useState } from "react";
import { trackEvent } from '../utils/tracking';
import { cn } from "@/lib/utils";

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
        trackEvent('checkout_start', { total, item_count: items.length });
        const result = await submitOrder();
        if (result.success) {
            setShowReceipt(true);
            trackEvent('order_confirmed', { order_id: result.order_id });
        }
    };

    if (showReceipt && lastOrderResult?.success) {
        return (
            <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                className="flex flex-col h-full bg-black text-white items-center justify-center p-12 relative overflow-hidden"
            >
                <div className="absolute inset-0 bg-brand-primary/5 blur-[120px] rounded-full translate-y-1/2" />

                <motion.div
                    initial={{ scale: 0, rotate: -20 }}
                    animate={{ scale: 1, rotate: 0 }}
                    transition={{ type: "spring", stiffness: 260, damping: 20 }}
                    className="relative w-48 h-48 rounded-[3rem] bg-brand-primary flex items-center justify-center mb-12 z-10 shadow-[0_0_100px_rgba(255,51,102,0.4)]"
                >
                    <Check className="w-24 h-24 text-black" strokeWidth={4} />
                    <div className="absolute inset-0 rounded-[3rem] border-4 border-white/20 animate-ping opacity-30" />
                </motion.div>

                <div className="z-10 text-center w-full max-w-md">
                    <h2 className="text-7xl font-black mb-4 uppercase italic tracking-tighter leading-none">
                        {lastOrderResult.is_merge ? 'Linked' : 'Deployed'}
                    </h2>
                    <p className="text-xl font-black text-brand-primary mb-12 uppercase tracking-[0.4em] italic opacity-80">
                        Matrix Unit #{lastOrderResult.order_id}
                    </p>

                    <div className="quantum-card p-10 space-y-8 mb-12 relative">
                        <div className="flex justify-between items-center">
                            <div className="flex items-center gap-3 text-zinc-500">
                                <MapPin size={18} />
                                <span className="text-xs font-black uppercase tracking-widest">Sector</span>
                            </div>
                            <span className="text-xl font-black text-white italic">Table {tableNumber || 'Main'}</span>
                        </div>
                        <div className="flex justify-between items-center">
                            <div className="flex items-center gap-3 text-zinc-500">
                                <Clock size={18} />
                                <span className="text-xs font-black uppercase tracking-widest">Extraction</span>
                            </div>
                            <span className="text-xl font-black text-white italic">{lastOrderResult.estimated_ready_time}m</span>
                        </div>
                        <div className="pt-8 border-t border-white/5 flex justify-between items-end">
                            <span className="text-sm font-black text-zinc-500 uppercase tracking-widest">Credits</span>
                            <span className="text-5xl font-black text-white italic tracking-tighter">{lastOrderResult.total_amount?.toLocaleString('fr-DZ')} DA</span>
                        </div>
                    </div>

                    <button
                        onClick={() => { setShowReceipt(false); onClose(); }}
                        className="btn-quantum w-full"
                    >
                        New Interaction
                    </button>
                </div>
            </motion.div>
        );
    }

    return (
        <div className="flex flex-col h-full bg-black/95 backdrop-blur-3xl text-white selection:bg-brand-primary/30">
            {/* Header */}
            <div className="p-12 flex justify-between items-center border-b border-white/5">
                <div className="flex items-center gap-6">
                    <div className="w-16 h-16 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center text-zinc-400">
                        <ShoppingBag size={28} />
                    </div>
                    <div>
                        <h3 className="text-4xl font-black uppercase italic tracking-tighter leading-none">{getTranslation('diamond_session', lang)}</h3>
                        <p className="text-[10px] font-black text-zinc-500 uppercase tracking-[0.3em] mt-2">Active Buffer Allocation</p>
                    </div>
                </div>
                <button
                    onClick={onClose}
                    className="w-16 h-16 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center hover:bg-white/10 transition-all active:scale-90"
                >
                    <X size={28} />
                </button>
            </div>

            {/* Config Panel */}
            <div className="px-12 py-8 border-b border-white/5 flex gap-8">
                <div className="w-32">
                    <label className="text-[10px] font-black text-zinc-500 uppercase tracking-widest block mb-3 italic">Sector ID</label>
                    <input
                        type="number"
                        value={tableNumber || ''}
                        onChange={e => setTableNumber(e.target.value ? Number(e.target.value) : null)}
                        placeholder="N°"
                        className="w-full h-16 bg-white/5 border border-white/10 rounded-2xl text-2xl text-white font-black text-center outline-none focus:border-brand-primary transition-all"
                    />
                </div>
                <div className="flex-1">
                    <label className="text-[10px] font-black text-zinc-500 uppercase tracking-widest block mb-3 italic">Protocol Type</label>
                    <div className="flex gap-4 h-16">
                        <button
                            onClick={() => setOrderType('dine_in')}
                            className={cn(
                                "flex-1 rounded-2xl font-black text-xs uppercase tracking-widest italic transition-all border",
                                orderType === 'dine_in'
                                    ? 'bg-white text-black border-transparent shadow-[0_0_30px_rgba(255,255,255,0.1)]'
                                    : 'bg-white/5 text-zinc-500 border-white/5'
                            )}
                        >
                            Internal
                        </button>
                        <button
                            onClick={() => setOrderType('takeaway')}
                            className={cn(
                                "flex-1 rounded-2xl font-black text-xs uppercase tracking-widest italic transition-all border",
                                orderType === 'takeaway'
                                    ? 'bg-white text-black border-transparent shadow-[0_0_30px_rgba(255,255,255,0.1)]'
                                    : 'bg-white/5 text-zinc-500 border-white/5'
                            )}
                        >
                            External
                        </button>
                    </div>
                </div>
            </div>

            {/* Line Items */}
            <div className="flex-1 overflow-y-auto p-12 space-y-6 no-scrollbar">
                {items.length === 0 ? (
                    <div className="h-full flex flex-col items-center justify-center gap-8 opacity-20">
                        <Trash2 size={80} strokeWidth={1} />
                        <p className="text-sm font-black uppercase tracking-[0.5em] italic">{getTranslation('cart_empty', lang)}</p>
                    </div>
                ) : (
                    <AnimatePresence>
                        {items.map((item) => {
                            const unitPrice = item.product.price + item.size.price_modifier +
                                item.extras.reduce((s, e) => s + e.price, 0) +
                                item.sauces.filter(s => !s.is_free).reduce((s, sc) => s + sc.price, 0);

                            return (
                                <motion.div
                                    layout
                                    initial={{ opacity: 0, scale: 0.9 }}
                                    animate={{ opacity: 1, scale: 1 }}
                                    exit={{ opacity: 0, x: -100 }}
                                    key={item.id}
                                    className="p-8 rounded-[2.5rem] bg-white/[0.03] border border-white/10 flex items-center gap-8 group"
                                >
                                    <div className="w-24 h-24 rounded-3xl overflow-hidden border border-white/10 shrink-0">
                                        <img src={item.product.image} alt="" className="w-full h-full object-cover grayscale group-hover:grayscale-0 transition-all duration-500 shadow-2xl" />
                                    </div>
                                    <div className="flex-1 min-w-0">
                                        <div className="flex items-center justify-between mb-2">
                                            <h4 className="text-2xl font-black text-white italic truncate tracking-tight">{item.product.name}</h4>
                                            <button onClick={() => removeItem(item.id)} className="p-3 rounded-xl hover:bg-red-500/20 text-zinc-600 hover:text-red-500 transition-all">
                                                <X size={18} />
                                            </button>
                                        </div>
                                        <div className="flex gap-2 flex-wrap mb-4">
                                            {item.size.name !== 'Normal' && <span className="px-2 py-0.5 rounded bg-brand-primary/10 text-brand-primary text-[8px] font-black uppercase tracking-widest">{item.size.name}</span>}
                                            {item.extras.map(e => <span key={e.name} className="px-2 py-0.5 rounded bg-zinc-800 text-zinc-400 text-[8px] font-black uppercase tracking-widest">{e.name}</span>)}
                                        </div>
                                        <div className="flex justify-between items-center">
                                            <div className="flex items-center gap-1 bg-white/5 rounded-xl p-1">
                                                <button onClick={() => updateQuantity(item.id, -1)} className="w-10 h-10 rounded-lg hover:bg-white/10 flex items-center justify-center text-zinc-400"><ChevronDown size={18} /></button>
                                                <span className="text-lg font-black w-10 text-center italic">{item.quantity}</span>
                                                <button onClick={() => updateQuantity(item.id, 1)} className="w-10 h-10 rounded-lg hover:bg-white/10 flex items-center justify-center text-zinc-400"><ChevronUp size={18} /></button>
                                            </div>
                                            <span className="text-2xl font-black text-zinc-400 group-hover:text-white transition-colors italic tracking-tighter">
                                                {unitPrice * item.quantity} DA
                                            </span>
                                        </div>
                                    </div>
                                </motion.div>
                            );
                        })}
                    </AnimatePresence>
                )}
            </div>

            {/* Footer Summary */}
            <div className="p-12 border-t border-white/5 bg-white/[0.01] backdrop-blur-3xl">
                <div className="flex justify-between items-end mb-10">
                    <div>
                        <span className="text-[10px] font-black text-zinc-500 uppercase tracking-[0.4em] italic block mb-2">{getTranslation('total', lang)}</span>
                        <div className="flex items-center gap-3">
                            <Activity size={20} className="text-brand-primary" />
                            <span className="text-8xl font-black text-white italic tracking-tighter leading-none">{total.toLocaleString('fr-DZ')}</span>
                            <span className="text-2xl font-black text-zinc-500 uppercase italic">DA</span>
                        </div>
                    </div>
                </div>
                <div className="flex gap-6">
                    <button
                        onClick={clearCart}
                        disabled={isSubmitting || items.length === 0}
                        className="w-20 h-20 rounded-[2rem] border border-white/10 flex items-center justify-center text-zinc-600 hover:text-red-500 hover:border-red-500/30 transition-all"
                    >
                        <Trash2 size={24} />
                    </button>
                    <button
                        onClick={handleOrderNow}
                        disabled={isSubmitting || items.length === 0}
                        className="flex-1 btn-quantum group"
                    >
                        {isSubmitting ? <Loader2 size={32} className="animate-spin text-black" /> : (
                            <>
                                <CreditCard size={28} />
                                {getTranslation('order_now', lang)}
                            </>
                        )}
                    </button>
                </div>
            </div>
        </div>
    );
}
