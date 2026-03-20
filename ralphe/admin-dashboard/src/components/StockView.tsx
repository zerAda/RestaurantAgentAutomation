import { useEffect, useState } from 'react';
import type { StockItem } from '../services/stockService';
import { stockService } from '../services/stockService';
import { cn } from '../lib/utils';
import { AlertCircle, CheckCircle2, MoreHorizontal, ArrowUpRight, Boxes, ChefHat } from 'lucide-react';

export function StockView() {
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

    if (loading) return <div className="p-32 text-center quantum-card rounded-quantum text-zinc-500 font-black uppercase tracking-[0.3em] animate-pulse">Synchronizing Inventory...</div>;

    return (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6 animate-in fade-in slide-in-from-bottom-4 duration-700">
            {items.map(item => (
                <div key={item.id} className="quantum-card group hover:scale-[1.02] transition-all duration-500 overflow-hidden">
                    {/* Status Accent Bar */}
                    <div className={cn(
                        "absolute top-0 left-0 right-0 h-1.5 shadow-quantum-glow",
                        item.status === 'critical' ? 'bg-error' : item.status === 'low' ? 'bg-warning' : 'bg-success'
                    )} />

                    <div className="p-6">
                        <div className="flex justify-between items-start mb-6">
                            <div>
                                <h3 className="text-lg font-black text-white tracking-tighter mb-1">{item.name}</h3>
                                <div className="flex items-center gap-2">
                                    <span className="text-[10px] font-black text-zinc-500 uppercase tracking-widest">{item.category}</span>
                                    <div className={cn(
                                        "px-2 py-0.5 rounded-full text-[9px] font-black uppercase tracking-widest shadow-sm",
                                        item.status === 'critical' ? 'bg-error/10 text-error border border-error/20' :
                                            item.status === 'low' ? 'bg-warning/10 text-warning border border-warning/20' :
                                                'bg-success/10 text-success border border-success/20'
                                    )}>
                                        {item.status}
                                    </div>
                                </div>
                            </div>
                            <button className="w-8 h-8 rounded-lg bg-white/5 border border-white/5 flex items-center justify-center text-zinc-500 hover:text-white hover:bg-white/10 transition-all">
                                <MoreHorizontal size={14} />
                            </button>
                        </div>

                        <div className="flex items-end gap-2 mb-6">
                            <div className="flex flex-col">
                                <span className="text-4xl font-black text-white tracking-tighter">
                                    {item.quantity}
                                </span>
                                {item.reservedStock > 0 && (
                                    <span className="text-[10px] font-black text-warning uppercase tracking-widest flex items-center gap-1">
                                        <div className="w-1.5 h-1.5 rounded-full bg-warning animate-pulse" />
                                        {item.reservedStock} Reserved
                                    </span>
                                )}
                            </div>
                            <span className="text-xs font-black text-zinc-500 uppercase tracking-widest mb-2 italic">
                                {item.unit}
                            </span>
                            <div className="ml-auto mb-2 flex flex-col items-end gap-1">
                                <div className="flex items-center gap-1 text-[10px] font-black text-zinc-600 italic">
                                    <ArrowUpRight size={10} />
                                    Cluster A1
                                </div>
                            </div>
                        </div>

                        <div className="space-y-2 mb-4">
                            <div className="flex justify-between items-end text-[10px] font-black uppercase tracking-widest">
                                <span className="text-zinc-500">Utilization</span>
                                <span className={item.status === 'critical' ? 'text-error' : 'text-zinc-400'}>
                                    {Math.round((item.quantity / (item.minStock * 2)) * 100)}%
                                </span>
                            </div>
                            <div className="w-full bg-white/5 rounded-full h-1.5 overflow-hidden border border-white/5 shadow-inner">
                                <div
                                    className={cn(
                                        "h-full rounded-full transition-all duration-1000 ease-out shadow-quantum-glow",
                                        item.status === 'critical' ? 'bg-error' : item.status === 'low' ? 'bg-warning' : 'bg-brand-primary'
                                    )}
                                    style={{ width: `${Math.min(100, (item.quantity / (item.minStock * 2)) * 100)}%` }}
                                />
                            </div>
                        </div>

                        <div className="flex justify-between items-center bg-white/5 border border-white/5 rounded-xl p-3">
                            <div className="flex items-center gap-2">
                                <Boxes size={14} className="text-zinc-500" />
                                <div className="flex flex-col">
                                    <span className="text-[9px] font-black text-zinc-600 uppercase tracking-tighter">Threshold</span>
                                    <span className="text-[11px] font-black text-white leading-none">Min: {item.minStock} {item.unit}</span>
                                </div>
                            </div>
                            {item.status === 'critical' ? (
                                <AlertCircle size={16} className="text-error animate-pulse" />
                            ) : (
                                <CheckCircle2 size={16} className="text-success/50" />
                            )}
                        </div>
                    </div>
                </div>
            ))}

            {items.length === 0 && !loading && (
                <div className="col-span-full quantum-card p-32 text-center rounded-quantum flex flex-col items-center justify-center">
                    <div className="w-24 h-24 rounded-full bg-success/5 border border-success/10 flex items-center justify-center mb-8 shadow-quantum-glow text-success">
                        <ChefHat size={48} />
                    </div>
                    <h3 className="text-3xl font-black text-white tracking-tighter mb-2 italic">Stock Depleted</h3>
                    <p className="text-zinc-500 font-bold uppercase text-[10px] tracking-[0.3em]">No Assets Detected in Local Cluster</p>
                </div>
            )}
        </div>
    );
}
