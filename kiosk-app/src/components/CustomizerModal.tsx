import { motion, AnimatePresence } from "framer-motion";
import { X, Plus, Check } from "lucide-react";
import type { Product } from "../services/menuService";
import { useState } from "react";
import { getTranslation } from "../utils/i18n";

interface Extra {
    name: string;
    price: number;
}

const MOCK_EXTRAS: Extra[] = [
    { name: "Cheddar", price: 100 },
    { name: "Sauce Algérienne", price: 50 },
    { name: "Oignons Grillés", price: 80 },
    { name: "Extra Viande", price: 250 },
];

interface CustomizerModalProps {
    product: Product;
    lang: any;
    onClose: () => void;
    onConfirm: (extras: Extra[]) => void;
}

export default function CustomizerModal({ product, lang, onClose, onConfirm }: CustomizerModalProps) {
    const [selectedExtras, setSelectedExtras] = useState<Extra[]>([]);

    const toggleExtra = (extra: Extra) => {
        setSelectedExtras(prev =>
            prev.find(e => e.name === extra.name)
                ? prev.filter(e => e.name !== extra.name)
                : [...prev, extra]
        );
    };

    const totalPrice = product.price + selectedExtras.reduce((sum, e) => sum + e.price, 0);

    return (
        <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[110] bg-black/80 backdrop-blur-xl flex items-center justify-center p-6"
        >
            <motion.div
                initial={{ scale: 0.9, y: 20 }}
                animate={{ scale: 1, y: 0 }}
                exit={{ scale: 0.9, y: 20 }}
                className="w-full max-w-xl bg-zinc-900 border border-white/10 rounded-[3rem] overflow-hidden flex flex-col max-h-[90vh]"
            >
                <div className="p-8 border-b border-white/5 flex justify-between items-center">
                    <div>
                        <h3 className="text-3xl font-black text-white">{getTranslation('customize', lang)}</h3>
                        <p className="text-white/40">{product.name}</p>
                    </div>
                    <button onClick={onClose} className="w-12 h-12 rounded-full bg-white/5 flex items-center justify-center hover:bg-white/10">
                        <X className="w-6 h-6 text-white" />
                    </button>
                </div>

                <div className="flex-1 overflow-y-auto p-8 space-y-6">
                    <h4 className="text-xl font-bold text-white uppercase tracking-widest">{getTranslation('extras', lang)}</h4>
                    <div className="grid grid-cols-1 gap-4">
                        {MOCK_EXTRAS.map(extra => {
                            const isSelected = selectedExtras.find(e => e.name === extra.name);
                            return (
                                <div
                                    key={extra.name}
                                    onClick={() => toggleExtra(extra)}
                                    className={`p - 6 rounded - 3xl border - 2 transition - all cursor - pointer flex justify - between items - center ${isSelected ? 'border-[#FFB800] bg-[#FFB800]/10' : 'border-white/5 bg-white/5 hover:bg-white/10'
                                        } `}
                                >
                                    <div className="flex items-center gap-4">
                                        <div className={`w - 8 h - 8 rounded - full border - 2 flex items - center justify - center ${isSelected ? 'bg-[#FFB800] border-[#FFB800]' : 'border-white/20'} `}>
                                            {isSelected && <Check className="w-5 h-5 text-black" />}
                                        </div>
                                        <span className="text-xl font-bold text-white">{extra.name}</span>
                                    </div>
                                    <span className="text-xl font-bold text-[#FFB800]">+{extra.price} DA</span>
                                </div>
                            );
                        })}
                    </div>
                </div>

                <div className="p-8 bg-black/40 border-t border-white/5">
                    <div className="flex justify-between items-center mb-6">
                        <span className="text-white/60 text-xl">{getTranslation('total', lang)}</span>
                        <span className="text-4xl font-black text-white">{totalPrice} DA</span>
                    </div>
                    <button
                        onClick={() => onConfirm(selectedExtras)}
                        className="w-full py-6 rounded-full bg-white text-black font-black text-2xl shadow-2xl hover:scale-[1.02] active:scale-[0.98] transition-all"
                    >
                        {getTranslation('add_to_cart', lang)}
                    </button>
                </div>
            </motion.div>
        </motion.div>
    );
}
