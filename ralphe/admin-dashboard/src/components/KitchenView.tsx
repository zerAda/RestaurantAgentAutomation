import { useOrders, useUpdateOrderStatus, type OrderStatus } from '../services/orders';
import { cn } from '../lib/utils';
import { ChefHat, Timer, Hash, User } from 'lucide-react';

type KitchenStatus = 'pending' | 'preparing' | 'ready';

function mapToKitchenStatus(s: OrderStatus): KitchenStatus {
    if (s === 'NEW') return 'pending';
    if (s === 'PREPARING') return 'preparing';
    if (s === 'READY' || s === 'DELIVERING' || s === 'DONE') return 'ready';
    return 'pending';
}

export function KitchenView() {
    const { data: orders = [], isLoading } = useOrders();
    const updateStatus = useUpdateOrderStatus();

    const markReady = (documentId: string, orderId: string, currentStatus: OrderStatus) => {
        const nextStatus: OrderStatus = currentStatus === 'NEW' ? 'PREPARING' : 'READY';
        updateStatus.mutate({ documentId, status: nextStatus });

        if (nextStatus === 'READY' && window.speechSynthesis) {
            const msg = new SpeechSynthesisUtterance(`Order ${orderId.replace('#', '')} is ready for pickup`);
            msg.rate = 0.9;
            msg.pitch = 1.1;
            window.speechSynthesis.speak(msg);
        }
    };

    const activeOrders = orders.filter(o => o.status !== 'DONE' && o.status !== 'CANCELLED');

    if (isLoading) {
        return (
            <div className="flex items-center justify-center py-20 text-zinc-400">
                Loading kitchen orders…
            </div>
        );
    }

    return (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6 animate-in fade-in slide-in-from-bottom-4 duration-700">
            {activeOrders.map(order => {
                const kStatus = mapToKitchenStatus(order.status);
                const isReady = kStatus === 'ready';

                return (
                    <div
                        key={order.id}
                        className="quantum-card group hover:scale-[1.02] transition-all duration-500 overflow-hidden"
                    >
                        {/* Status Accent Bar */}
                        <div className={cn(
                            "absolute top-0 left-0 right-0 h-1.5 shadow-quantum-glow",
                            kStatus === 'pending' ? 'bg-warning' : kStatus === 'preparing' ? 'bg-brand-primary' : 'bg-success'
                        )} />

                        <div className="p-6">
                            <div className="flex justify-between items-start mb-6">
                                <div>
                                    <div className="flex items-center gap-2 mb-1">
                                        <Hash size={12} className="text-zinc-600" />
                                        <h3 className="text-2xl font-black text-white tracking-tighter">{order.id.replace('#', '')}</h3>
                                    </div>
                                    <div className="flex items-center gap-2">
                                        <div className={cn(
                                            "w-1.5 h-1.5 rounded-full shadow-[0_0_8px_currentColor]",
                                            kStatus === 'pending' ? 'text-warning bg-warning' : kStatus === 'preparing' ? 'text-brand-primary bg-brand-primary' : 'text-success bg-success'
                                        )} />
                                        <span className={cn(
                                            "text-[10px] font-black uppercase tracking-widest",
                                            kStatus === 'pending' ? 'text-warning' : kStatus === 'preparing' ? 'text-brand-primary' : 'text-success'
                                        )}>
                                            {kStatus}
                                        </span>
                                    </div>
                                </div>
                                <div className="text-right">
                                    <div className="flex items-center gap-1.5 justify-end text-zinc-500 mb-1">
                                        <Timer size={12} />
                                        <span className="text-[10px] font-black font-mono">{order.time}</span>
                                    </div>
                                    <div className="text-sm font-black text-white">{order.total}</div>
                                </div>
                            </div>

                            <div className="flex items-center gap-2 mb-6 px-3 py-1.5 rounded-lg bg-white/5 border border-white/5">
                                <User size={10} className="text-zinc-500" />
                                <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-tight truncate">{order.customer}</span>
                                <div className="ml-auto flex items-center gap-1">
                                    <span className="text-[9px] font-black text-zinc-600 uppercase italic">{order.method}</span>
                                </div>
                            </div>

                            <div className="space-y-2 mb-8 min-h-[120px]">
                                {order.items.length > 0 ? order.items.map((item, idx) => (
                                    <div key={idx} className="flex items-center gap-3 p-2 rounded-lg hover:bg-white/5 border border-transparent hover:border-white/5 transition-all text-zinc-300">
                                        <div className="w-5 h-5 rounded bg-zinc-800 flex items-center justify-center text-[9px] font-black">{idx + 1}</div>
                                        <span className="text-xs font-bold tracking-tight">{item}</span>
                                    </div>
                                )) : (
                                    <div className="h-full flex flex-col items-center justify-center opacity-20">
                                        <ChefHat size={32} />
                                        <p className="text-[10px] font-black uppercase mt-2">No Ingredients</p>
                                    </div>
                                )}
                            </div>

                            {!isReady && (
                                <button
                                    onClick={() => markReady(order.documentId, order.id, order.status)}
                                    disabled={updateStatus.isPending}
                                    className={cn(
                                        "w-full py-4 rounded-xl font-black text-xs uppercase tracking-[0.2em] shadow-quantum transition-all duration-300 flex items-center justify-center gap-3",
                                        kStatus === 'pending'
                                            ? 'bg-zinc-800 text-white hover:bg-zinc-700'
                                            : 'bg-success text-black hover:bg-success/90'
                                    )}
                                >
                                    {kStatus === 'pending' ? 'Initiate Sequence' : 'Finalize Delivery'}
                                </button>
                            )}
                        </div>
                    </div>
                );
            })}

            {activeOrders.length === 0 && (
                <div className="col-span-full quantum-card p-32 text-center rounded-quantum flex flex-col items-center justify-center">
                    <div className="w-24 h-24 rounded-full bg-success/5 border border-success/10 flex items-center justify-center mb-8 shadow-quantum-glow text-success animate-float">
                        <ChefHat size={48} />
                    </div>
                    <h3 className="text-3xl font-black text-white tracking-tighter mb-2 italic">Kitchen Clear</h3>
                    <p className="text-zinc-500 font-bold uppercase text-[10px] tracking-[0.3em]">All Node Orders Synchronized</p>
                </div>
            )}
        </div>
    );
}
