import type { Product } from '../services/menuService';
import { cn } from "@/lib/utils";
import { Plus, Tag } from "lucide-react";

interface MenuGridProps {
    products: Product[];
    onAddToCart: (product: Product) => void;
}

export function MenuGrid({ products, onAddToCart }: MenuGridProps) {
    return (
        <div className="grid grid-cols-2 gap-8 p-10">
            {products.map(product => (
                <div
                    key={product.id}
                    onClick={() => onAddToCart(product)}
                    className="quantum-card group cursor-pointer relative flex flex-col items-center text-center p-8 min-h-[400px] justify-between transition-all active:scale-95"
                >
                    {/* Price Badge Overlay */}
                    <div className="absolute top-6 right-6 z-10 px-4 py-2 rounded-xl bg-brand-primary text-black font-black text-sm italic tracking-widest shadow-lg shadow-brand-primary/20">
                        {product.price} DA
                    </div>

                    {/* Image with Glow */}
                    <div className="relative w-48 h-48 mb-6 group-hover:scale-110 transition-transform duration-500">
                        <div className="absolute inset-0 bg-brand-primary/20 rounded-full blur-3xl opacity-0 group-hover:opacity-100 transition-opacity" />
                        <img
                            src={product.image}
                            alt={product.name}
                            className="relative w-full h-full object-cover rounded-full shadow-2xl border-4 border-white/5"
                        />
                    </div>

                    <div className="space-y-4">
                        <div className="flex flex-col items-center gap-2">
                            <div className="flex items-center gap-2 text-[9px] font-black text-zinc-500 uppercase tracking-[0.3em]">
                                <Tag size={10} />
                                {product.category || 'Specialty'}
                            </div>
                            <h3 className="text-3xl font-black text-white uppercase italic tracking-tighter leading-none">
                                {product.name}
                            </h3>
                        </div>

                        <div className="w-12 h-1 bg-white/10 rounded-full mx-auto" />

                        <p className="text-sm text-zinc-500 font-medium line-clamp-2 italic px-4 leading-relaxed">
                            {product.preparationTime}m estimated matrix extraction
                        </p>
                    </div>

                    <div className="w-full mt-8">
                        <button className="w-full py-4 rounded-2xl bg-white/5 border border-white/10 text-white font-black text-xs uppercase tracking-widest italic group-hover:bg-brand-primary group-hover:text-black group-hover:border-transparent transition-all flex items-center justify-center gap-3">
                            <Plus size={16} />
                            Deploy Unit
                        </button>
                    </div>
                </div>
            ))}
        </div>
    );
}
