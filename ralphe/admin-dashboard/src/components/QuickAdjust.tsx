import { useEffect, useState } from 'react';
import type { StockItem } from '../services/stockService';
import { stockService } from '../services/stockService';
import { Plus, Minus, Hash, AlertTriangle, Package, Layers } from 'lucide-react';
import { cn } from '../lib/utils';
import { SkeletonRow } from './SkeletonLoader';

export function QuickAdjust() {
    const [items, setItems] = useState<StockItem[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const loadData = async () => {
            setLoading(true);
            const data = await stockService.getAll();
            setItems(data);
            setLoading(false);
        };
        loadData();
    }, []);

    const handleAdjust = async (id: string, delta: number) => {
        const item = items.find(i => i.id === id);
        if (!item) return;

        // Optimistic update
        const newQty = Math.max(0, item.quantity + delta);
        setItems(prev => prev.map(i => i.id === id ? { ...i, quantity: newQty } : i));

        const updated = await stockService.updateStock(id, delta);
        if (!updated) {
            // Revert on failure
            const original = await stockService.getAll();
            setItems(original);
        }
    };

    if (loading) return (
        <div className="space-y-4 p-6 bg-white/[0.02] rounded-3xl border border-white/5">
            <SkeletonRow />
            <SkeletonRow />
            <SkeletonRow />
        </div>
    );

    return (
        <div className="quantum-card overflow-hidden">
            <div className="overflow-x-auto no-scrollbar">
                <table className="w-full text-left border-collapse">
                    <thead>
                        <tr className="bg-white/[0.03] border-b border-white/5">
                            <th className="px-6 py-5 text-[10px] font-black text-zinc-500 uppercase tracking-widest italic">Inventory DNA</th>
                            <th className="px-6 py-5 text-[10px] font-black text-zinc-500 uppercase tracking-widest italic">Current Logic</th>
                            <th className="px-6 py-5 text-[10px] font-black text-zinc-500 uppercase tracking-widest italic text-right">Adjust Protocol</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-white/5">
                        {items.length === 0 ? (
                            <tr>
                                <td colSpan={3} className="px-6 py-20 text-center">
                                    <div className="flex flex-col items-center gap-4">
                                        <Package size={40} className="text-zinc-800" />
                                        <p className="text-[10px] font-black text-zinc-600 uppercase tracking-widest">Inventory nodes empty</p>
                                    </div>
                                </td>
                            </tr>
                        ) : (
                            items.map(item => (
                                <tr key={item.id} className="group hover:bg-white/[0.02] transition-colors">
                                    <td className="px-6 py-5">
                                        <div className="flex items-center gap-4">
                                            <div className="w-10 h-10 rounded-xl bg-white/5 border border-white/5 flex items-center justify-center text-zinc-500 group-hover:text-brand-primary transition-colors">
                                                <Layers size={18} />
                                            </div>
                                            <div className="min-w-0">
                                                <div className="text-sm font-black text-white tracking-tighter uppercase italic">{item.name}</div>
                                                <div className="text-[9px] font-bold text-zinc-600 uppercase tracking-widest mt-0.5">{item.category}</div>
                                            </div>
                                        </div>
                                    </td>
                                    <td className="px-6 py-5">
                                        <div className="flex items-center gap-2">
                                            <span className={cn(
                                                "px-3 py-1 rounded-lg font-mono text-xs font-black shadow-inner",
                                                item.status === 'critical'
                                                    ? 'bg-error/10 text-error border border-error/20 animate-pulse'
                                                    : item.status === 'warning'
                                                        ? 'bg-warning/10 text-warning border border-warning/20'
                                                        : 'bg-white/5 text-zinc-400 border border-white/5'
                                            )}>
                                                {item.quantity} {item.unit}
                                            </span>
                                            {item.status === 'critical' && <AlertTriangle size={12} className="text-error" />}
                                        </div>
                                    </td>
                                    <td className="px-6 py-5 text-right">
                                        <div className="flex justify-end items-center gap-2">
                                            <button
                                                onClick={() => handleAdjust(item.id, -1)}
                                                className="w-10 h-10 rounded-xl bg-error/5 border border-error/10 text-error hover:bg-error hover:text-black transition-all flex items-center justify-center shadow-lg group/btn"
                                            >
                                                <Minus size={16} strokeWidth={3} className="group-hover/btn:scale-125 transition-transform" />
                                            </button>
                                            <button
                                                onClick={() => handleAdjust(item.id, 1)}
                                                className="w-10 h-10 rounded-xl bg-success/5 border border-success/10 text-success hover:bg-success hover:text-black transition-all flex items-center justify-center shadow-lg group/btn"
                                            >
                                                <Plus size={16} strokeWidth={3} className="group-hover/btn:scale-125 transition-transform" />
                                            </button>
                                            <button
                                                onClick={() => handleAdjust(item.id, 10)}
                                                className="h-10 px-4 rounded-xl bg-white/5 border border-white/10 text-white hover:bg-white hover:text-black transition-all text-[10px] font-black tracking-widest shadow-lg flex items-center gap-2"
                                            >
                                                <Hash size={12} /> +10
                                            </button>
                                        </div>
                                    </td>
                                </tr>
                            ))
                        )}
                    </tbody>
                </table>
            </div>
            <div className="p-4 bg-white/[0.01] border-t border-white/5 flex items-center justify-center gap-6">
                <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-error" />
                    <span className="text-[8px] font-black text-zinc-600 uppercase tracking-widest">Critical Alert</span>
                </div>
                <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-warning" />
                    <span className="text-[8px] font-black text-zinc-600 uppercase tracking-widest">Low Stock</span>
                </div>
                <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-zinc-800" />
                    <span className="text-[8px] font-black text-zinc-600 uppercase tracking-widest">Optimized Nodes</span>
                </div>
            </div>
        </div>
    );
}
