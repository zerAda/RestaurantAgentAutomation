import { motion } from "framer-motion";
import { X, Check, ChevronUp, ChevronDown, Sparkles, Zap, Package, Layers } from "lucide-react";
import type { Product, ExtraOption, SauceOption, SizeOption } from "../services/menuService";
import { useState } from "react";
import { getTranslation } from "../utils/i18n";
import { cn } from "@/lib/utils";

interface SelectedSauce {
    name: string;
    price: number;
    is_free: boolean;
}

type Language = 'en' | 'fr' | 'ar';

interface CustomizerModalProps {
    product: Product;
    lang: Language;
    onClose: () => void;
    onConfirm: (extras: ExtraOption[], sauces: SelectedSauce[], size: SizeOption, quantity: number) => void;
}

export default function CustomizerModal({ product, lang, onClose, onConfirm }: CustomizerModalProps) {
    const [selectedExtras, setSelectedExtras] = useState<ExtraOption[]>([]);
    const [selectedSauces, setSelectedSauces] = useState<SelectedSauce[]>([]);
    const [selectedSize, setSelectedSize] = useState<SizeOption>(
        product.sizes?.[0] || { name: 'Normal', price_modifier: 0 }
    );
    const [quantity, setQuantity] = useState(1);

    const includedSauceCount = product.sauces?.[0]?.included_count || 0;
    const freeSauceSlots = Math.max(0, includedSauceCount - selectedSauces.filter(s => s.is_free).length);

    const toggleExtra = (extra: ExtraOption) => {
        setSelectedExtras(prev =>
            prev.find(e => e.name === extra.name)
                ? prev.filter(e => e.name !== extra.name)
                : [...prev, extra]
        );
    };

    const toggleSauce = (sauce: SauceOption) => {
        setSelectedSauces(prev => {
            const existing = prev.find(s => s.name === sauce.name);
            if (existing) return prev.filter(s => s.name !== sauce.name);
            const currentFreeCount = prev.filter(s => s.is_free).length;
            const isFree = currentFreeCount < includedSauceCount;
            return [...prev, { name: sauce.name, price: isFree ? 0 : sauce.price, is_free: isFree }];
        });
    };

    const unitPrice = product.price + selectedSize.price_modifier +
        selectedExtras.reduce((s, e) => s + e.price, 0) +
        selectedSauces.filter(s => !s.is_free).reduce((s, sc) => s + sc.price, 0);
    const totalPrice = unitPrice * quantity;

    return (
        <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[130] bg-black/60 backdrop-blur-3xl flex items-center justify-center p-8"
        >
            <motion.div
                initial={{ scale: 0.95, y: 40, opacity: 0 }}
                animate={{ scale: 1, y: 0, opacity: 1 }}
                exit={{ scale: 0.95, y: 40, opacity: 0 }}
                transition={{ type: "spring", damping: 30, stiffness: 200 }}
                className="w-full max-w-3xl quantum-card flex flex-col max-h-[90vh] shadow-[0_50px_100px_rgba(0,0,0,0.8)]"
            >
                {/* Header Matrix */}
                <div className="p-10 border-b border-white/5 flex justify-between items-center bg-white/[0.01]">
                    <div className="flex items-center gap-6">
                        <div className="w-16 h-16 rounded-2xl bg-brand-primary/10 border border-brand-primary/20 flex items-center justify-center text-brand-primary">
                            <Layers size={32} />
                        </div>
                        <div>
                            <h3 className="text-4xl font-black text-white uppercase italic tracking-tighter leading-none">{getTranslation('customize', lang)}</h3>
                            <div className="flex items-center gap-2 mt-2">
                                <span className="text-[10px] font-black text-zinc-500 uppercase tracking-widest italic">{product.name}</span>
                                <div className="w-1 h-1 rounded-full bg-brand-primary" />
                                <span className="text-[10px] font-black text-brand-primary uppercase tracking-widest italic">Unit Configuration</span>
                            </div>
                        </div>
                    </div>
                    <button onClick={onClose} className="w-16 h-16 rounded-2xl bg-white/5 flex items-center justify-center hover:bg-white/10 transition-all active:scale-90">
                        <X size={28} className="text-zinc-400" />
                    </button>
                </div>

                {/* Configuration Zones */}
                <div className="flex-1 overflow-y-auto p-10 space-y-12 no-scrollbar">

                    {/* Sizing Protocol */}
                    {product.sizes && product.sizes.length > 1 && (
                        <div className="space-y-6">
                            <div className="flex items-center gap-3">
                                <Package size={18} className="text-zinc-500" />
                                <h4 className="text-xs font-black text-zinc-500 uppercase tracking-[0.4em] italic">{getTranslation('size', lang) || 'Scale Protocol'}</h4>
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                                {product.sizes.map(size => {
                                    const active = selectedSize.name === size.name;
                                    return (
                                        <button
                                            key={size.name}
                                            onClick={() => setSelectedSize(size)}
                                            className={cn(
                                                "p-6 rounded-3xl border-2 transition-all flex flex-col items-center gap-2",
                                                active ? "border-white bg-white text-black shadow-2xl scale-105" : "border-white/5 bg-white/[0.02] text-zinc-500"
                                            )}
                                        >
                                            <span className="text-2xl font-black uppercase italic tracking-tighter">{size.name}</span>
                                            {size.price_modifier > 0 && <span className={cn("text-xs font-bold", active ? "text-zinc-600" : "text-brand-primary")}>+{size.price_modifier} DA</span>}
                                        </button>
                                    );
                                })}
                            </div>
                        </div>
                    )}

                    {/* Synthesis Modules (Extras) */}
                    {product.extras && product.extras.length > 0 && (
                        <div className="space-y-6">
                            <div className="flex items-center gap-3">
                                <Sparkles size={18} className="text-zinc-500" />
                                <h4 className="text-xs font-black text-zinc-500 uppercase tracking-[0.4em] italic">{getTranslation('extras', lang) || 'Synthesis Modules'}</h4>
                            </div>
                            <div className="space-y-3">
                                {product.extras.map(extra => {
                                    const active = selectedExtras.find(e => e.name === extra.name);
                                    return (
                                        <button
                                            key={extra.name}
                                            onClick={() => toggleExtra(extra)}
                                            className={cn(
                                                "w-full p-6 rounded-3xl border transition-all flex justify-between items-center group",
                                                active ? "border-brand-primary bg-brand-primary/10" : "border-white/5 bg-white/[0.02] hover:bg-white/[0.05]"
                                            )}
                                        >
                                            <div className="flex items-center gap-5">
                                                <div className={cn("w-8 h-8 rounded-xl border flex items-center justify-center transition-all", active ? "bg-brand-primary border-brand-primary" : "border-white/10 group-hover:border-white/30")}>
                                                    {active && <Check size={18} className="text-black" strokeWidth={4} />}
                                                </div>
                                                <span className={cn("text-xl font-black uppercase italic tracking-tighter transition-colors", active ? "text-white" : "text-zinc-500")}>{extra.name}</span>
                                            </div>
                                            <span className="text-lg font-black text-brand-primary italic">+{extra.price} DA</span>
                                        </button>
                                    );
                                })}
                            </div>
                        </div>
                    )}

                    {/* Fluid Matrices (Sauces) */}
                    {product.sauces && product.sauces.length > 0 && (
                        <div className="space-y-6">
                            <div className="flex items-center justify-between">
                                <div className="flex items-center gap-3">
                                    <Zap size={18} className="text-zinc-500" />
                                    <h4 className="text-xs font-black text-zinc-500 uppercase tracking-[0.4em] italic">Fluid Matrices</h4>
                                </div>
                                {includedSauceCount > 0 && (
                                    <span className="text-[10px] font-black text-success uppercase tracking-widest">
                                        {freeSauceSlots} Units Included
                                    </span>
                                )}
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                                {product.sauces.map(sauce => {
                                    const active = selectedSauces.find(s => s.name === sauce.name);
                                    const free = active?.is_free || (!active && selectedSauces.filter(s => s.is_free).length < includedSauceCount);
                                    return (
                                        <button
                                            key={sauce.name}
                                            onClick={() => toggleSauce(sauce)}
                                            className={cn(
                                                "p-6 rounded-3xl border transition-all flex flex-col items-start gap-1 group",
                                                active ? "border-indigo-500 bg-indigo-500/10" : "border-white/5 bg-white/[0.02]"
                                            )}
                                        >
                                            <span className={cn("text-lg font-black uppercase italic tracking-tighter truncate w-full text-left", active ? "text-white" : "text-zinc-500")}>{sauce.name}</span>
                                            <span className={cn("text-[9px] font-black uppercase italic tracking-widest", free ? "text-success" : "text-zinc-600")}>
                                                {free ? "System Credit" : `+${sauce.price} DA`}
                                            </span>
                                        </button>
                                    );
                                })}
                            </div>
                        </div>
                    )}

                    {/* Replication Quantity */}
                    <div className="space-y-8 pt-4">
                        <h4 className="text-xs font-black text-zinc-500 uppercase tracking-[0.4em] italic text-center">Replication Count</h4>
                        <div className="flex items-center justify-center gap-10">
                            <button
                                onClick={() => setQuantity(q => Math.max(1, q - 1))}
                                className="w-20 h-20 rounded-[2rem] bg-white/5 border border-white/10 flex items-center justify-center transition-all active:scale-90 hover:bg-white/10"
                            >
                                <ChevronDown size={32} />
                            </button>
                            <span className="text-8xl font-black text-white italic tracking-tighter leading-none min-w-[120px] text-center">{quantity}</span>
                            <button
                                onClick={() => setQuantity(q => Math.min(20, q + 1))}
                                className="w-20 h-20 rounded-[2rem] bg-white/5 border border-white/10 flex items-center justify-center transition-all active:scale-90 hover:bg-white/10"
                            >
                                <ChevronUp size={32} />
                            </button>
                        </div>
                    </div>
                </div>

                {/* Confirm Layer */}
                <div className="p-10 bg-black/40 backdrop-blur-3xl border-t border-white/5 flex items-center justify-between">
                    <div>
                        <span className="text-[10px] font-black text-zinc-500 uppercase tracking-[0.4em] italic block mb-2">Aggregate Value</span>
                        <div className="flex items-center gap-3">
                            <span className="text-6xl font-black text-white italic tracking-tighter">{totalPrice.toLocaleString()}</span>
                            <span className="text-xl font-black text-zinc-500 uppercase italic">Credits</span>
                        </div>
                    </div>
                    <button
                        onClick={() => onConfirm(selectedExtras, selectedSauces, selectedSize, quantity)}
                        className="btn-quantum px-16 py-7"
                    >
                        Deploy Unit {quantity > 1 && `x${quantity}`}
                    </button>
                </div>
            </motion.div>
        </motion.div>
    );
}
