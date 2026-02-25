import { motion } from "framer-motion";
import { X, Check, ChevronUp, ChevronDown } from "lucide-react";
import type { Product, ExtraOption, SauceOption, SizeOption } from "../services/menuService";
import { useState } from "react";
import { getTranslation } from "../utils/i18n";

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

    // Find how many free sauces are included
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

            // Determine if this sauce is free
            const currentFreeCount = prev.filter(s => s.is_free).length;
            const isFree = currentFreeCount < includedSauceCount;

            return [...prev, { name: sauce.name, price: isFree ? 0 : sauce.price, is_free: isFree }];
        });
    };

    const extrasTotal = selectedExtras.reduce((s, e) => s + e.price, 0);
    const saucesTotal = selectedSauces.filter(s => !s.is_free).reduce((s, sauce) => s + sauce.price, 0);
    const unitPrice = product.price + selectedSize.price_modifier + extrasTotal + saucesTotal;
    const totalPrice = unitPrice * quantity;

    return (
        <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[110] bg-zinc-950/80 backdrop-blur-3xl flex items-center justify-center p-4 sm:p-6"
        >
            <motion.div
                initial={{ scale: 0.95, y: 40, opacity: 0 }}
                animate={{ scale: 1, y: 0, opacity: 1 }}
                exit={{ scale: 0.95, y: 40, opacity: 0 }}
                transition={{ type: "spring", damping: 25, stiffness: 300 }}
                className="w-full max-w-xl diamond-glass bg-zinc-900/80 rounded-[2.5rem] overflow-hidden flex flex-col max-h-[92vh] shadow-[0_0_80px_rgba(0,0,0,0.5)] border-white/10"
            >
                {/* Header */}
                <div className="p-8 border-b border-white/5 flex justify-between items-center">
                    <div>
                        <h3 className="text-3xl font-black text-white">{getTranslation('customize', lang)}</h3>
                        <p className="text-white/40">{product.name}</p>
                    </div>
                    <button onClick={onClose} className="w-12 h-12 rounded-full bg-white/5 flex items-center justify-center hover:bg-white/10">
                        <X className="w-6 h-6 text-white" />
                    </button>
                </div>

                {/* Scrollable Content */}
                <div className="flex-1 overflow-y-auto p-8 space-y-8">

                    {/* SIZE SELECTOR */}
                    {product.sizes && product.sizes.length > 1 && (
                        <div>
                            <h4 className="text-xl font-bold text-white uppercase tracking-widest mb-4">📐 {getTranslation('size', lang) || 'Taille'}</h4>
                            <div className="grid grid-cols-2 gap-3">
                                {product.sizes.map(size => {
                                    const isActive = selectedSize.name === size.name;
                                    return (
                                        <motion.div
                                            layout
                                            key={size.name}
                                            onClick={() => setSelectedSize(size)}
                                            className={`p-5 rounded-[1.5rem] border-2 transition-all cursor-pointer text-center relative overflow-hidden ${isActive
                                                ? 'border-yellow-400 bg-yellow-400/10 shadow-[0_0_20px_rgba(250,204,21,0.2)]'
                                                : 'border-white/10 bg-white/5 hover:bg-white/10'
                                                }`}
                                        >
                                            <span className="text-xl font-black text-white block">{size.name}</span>
                                            {size.price_modifier > 0 && (
                                                <span className="text-sm text-yellow-400 font-bold mt-1 block">+{size.price_modifier} DA</span>
                                            )}
                                        </motion.div>
                                    );
                                })}
                            </div>
                        </div>
                    )}

                    {/* EXTRAS */}
                    {product.extras && product.extras.length > 0 && (
                        <div>
                            <h4 className="text-xl font-bold text-white uppercase tracking-widest mb-4">✨ {getTranslation('extras', lang)}</h4>
                            <div className="grid grid-cols-1 gap-3">
                                {product.extras.map(extra => {
                                    const isSelected = selectedExtras.find(e => e.name === extra.name);
                                    return (
                                        <motion.div
                                            layout
                                            key={extra.name}
                                            onClick={() => toggleExtra(extra)}
                                            className={`p-5 rounded-[1.5rem] border-2 transition-all cursor-pointer flex justify-between items-center ${isSelected ? 'border-yellow-400 bg-yellow-400/10 shadow-[0_0_20px_rgba(250,204,21,0.2)]' : 'border-white/5 bg-white/5 hover:bg-white/10'}`}
                                        >
                                            <div className="flex items-center gap-4">
                                                <div className={`w-8 h-8 rounded-full border-2 flex items-center justify-center transition-colors ${isSelected ? 'bg-yellow-400 border-yellow-400' : 'border-white/20'}`}>
                                                    {isSelected && <Check className="w-5 h-5 text-black" strokeWidth={3} />}
                                                </div>
                                                <span className="text-lg font-bold text-white">{extra.name}</span>
                                            </div>
                                            <span className="text-lg font-bold text-yellow-400">+{extra.price} DA</span>
                                        </motion.div>
                                    );
                                })}
                            </div>
                        </div>
                    )}

                    {/* SAUCES */}
                    {product.sauces && product.sauces.length > 0 && (
                        <div>
                            <h4 className="text-xl font-bold text-white uppercase tracking-widest mb-2">🫙 {getTranslation('sauces', lang) || 'Sauces'}</h4>
                            {includedSauceCount > 0 && (
                                <p className="text-sm text-[#FFB800] mb-4">
                                    {freeSauceSlots > 0
                                        ? `${freeSauceSlots} sauce${freeSauceSlots > 1 ? 's' : ''} gratuite${freeSauceSlots > 1 ? 's' : ''} restante${freeSauceSlots > 1 ? 's' : ''}`
                                        : 'Sauces supplémentaires payantes'}
                                </p>
                            )}
                            <div className="grid grid-cols-2 gap-3">
                                {product.sauces.map(sauce => {
                                    const selected = selectedSauces.find(s => s.name === sauce.name);
                                    const wouldBeFree = !selected && selectedSauces.filter(s => s.is_free).length < includedSauceCount;
                                    return (
                                        <motion.div
                                            layout
                                            key={sauce.name}
                                            onClick={() => toggleSauce(sauce)}
                                            className={`p-4 rounded-[1.5rem] border-2 transition-all cursor-pointer text-center ${selected ? 'border-yellow-400 bg-yellow-400/10 shadow-[0_0_20px_rgba(250,204,21,0.2)]' : 'border-white/5 bg-white/5 hover:bg-white/10'}`}
                                        >
                                            <span className="text-sm font-bold text-white block">{sauce.name}</span>
                                            <span className={`text-xs font-bold mt-1 block ${wouldBeFree || selected?.is_free ? 'text-green-400' : 'text-yellow-400'}`}>
                                                {wouldBeFree || selected?.is_free ? '✓ Gratuite' : `+${sauce.price} DA`}
                                            </span>
                                        </motion.div>
                                    );
                                })}
                            </div>
                        </div>
                    )}

                    {/* QUANTITY */}
                    <div>
                        <h4 className="text-xl font-bold text-white uppercase tracking-widest mb-4">🔢 {getTranslation('quantity', lang) || 'Quantité'}</h4>
                        <div className="flex items-center justify-center gap-6">
                            <button
                                onClick={() => setQuantity(q => Math.max(1, q - 1))}
                                className="w-14 h-14 rounded-full bg-white/10 flex items-center justify-center hover:bg-white/20 transition-all active:scale-90"
                            >
                                <ChevronDown className="w-8 h-8 text-white" />
                            </button>
                            <span className="text-5xl font-black text-white min-w-[60px] text-center">{quantity}</span>
                            <button
                                onClick={() => setQuantity(q => Math.min(20, q + 1))}
                                className="w-14 h-14 rounded-full bg-white/10 flex items-center justify-center hover:bg-white/20 transition-all active:scale-90"
                            >
                                <ChevronUp className="w-8 h-8 text-white" />
                            </button>
                        </div>
                    </div>
                </div>

                {/* Footer */}
                <div className="p-8 bg-zinc-950/50 backdrop-blur-xl border-t border-white/5">
                    <div className="flex justify-between items-center mb-6">
                        <span className="text-white/60 text-xl font-medium tracking-tight">{getTranslation('total', lang)}</span>
                        <span className="text-4xl font-black text-white tracking-tight">{totalPrice.toLocaleString()} DA</span>
                    </div>
                    <button
                        onClick={() => onConfirm(selectedExtras, selectedSauces, selectedSize, quantity)}
                        className="btn-gold w-full text-2xl h-20"
                    >
                        {getTranslation('add_to_cart', lang)} {quantity > 1 ? `(${quantity})` : ''}
                    </button>
                </div>
            </motion.div>
        </motion.div>
    );
}
