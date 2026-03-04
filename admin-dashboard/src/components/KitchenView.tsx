import { useOrders, useUpdateOrderStatus, type OrderStatus } from '../services/orders';

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
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-8">
            {activeOrders.map(order => {
                const kStatus = mapToKitchenStatus(order.status);
                const isReady = kStatus === 'ready';

                return (
                    <div
                        key={order.id}
                        className="diamond-card relative overflow-hidden group hover:scale-[1.01]"
                    >
                        <div className={`absolute inset-0 bg-gradient-to-br ${kStatus === 'preparing' ? 'from-indigo-500/10' : 'from-amber-500/10'} to-transparent pointer-events-none`} />

                        <div className="p-8 relative z-10">
                            <div className="flex justify-between items-start mb-6">
                                <div>
                                    <div className="flex items-center gap-3 mb-1">
                                        <h3 className="text-3xl font-black tracking-tighter">{order.id}</h3>
                                        <span className={`px-2 py-0.5 rounded-md text-[10px] font-bold uppercase tracking-widest ${kStatus === 'pending' ? 'bg-amber-500 text-black' :
                                            kStatus === 'preparing' ? 'bg-indigo-600 text-white' :
                                                'bg-green-600 text-white'
                                            }`}>
                                            {kStatus}
                                        </span>
                                    </div>
                                    <p className="text-xs font-bold text-zinc-500 uppercase tracking-widest">
                                        {order.method} · {order.customer}
                                    </p>
                                </div>
                                <div className="text-right">
                                    <div className="text-xl font-mono font-bold text-zinc-400">{order.time}</div>
                                    <div className="text-xs font-bold text-indigo-500">{order.total}</div>
                                </div>
                            </div>

                            <div className="space-y-3 mb-8">
                                {order.items.length > 0 ? order.items.map((item, idx) => (
                                    <div key={idx} className="flex items-center gap-3">
                                        <span className="w-7 h-7 rounded-lg bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center font-bold text-xs">
                                            {idx + 1}
                                        </span>
                                        <span className="text-sm font-medium">{item}</span>
                                    </div>
                                )) : (
                                    <p className="text-xs text-zinc-400 italic">No item details</p>
                                )}
                            </div>

                            {!isReady && (
                                <button
                                    onClick={() => markReady(order.documentId, order.id, order.status)}
                                    disabled={updateStatus.isPending}
                                    className={`w-full py-4 rounded-xl font-black text-lg shadow-xl transition-all flex items-center justify-center gap-3 ${kStatus === 'pending'
                                        ? 'bg-zinc-100 dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 hover:bg-zinc-200 dark:hover:bg-zinc-700'
                                        : 'bg-green-600 text-white hover:bg-green-700 shadow-green-600/20'
                                        } disabled:opacity-50`}
                                >
                                    {kStatus === 'pending' ? 'Start Preparing' : 'Mark as Ready'}
                                </button>
                            )}
                        </div>
                    </div>
                );
            })}

            {activeOrders.length === 0 && (
                <div className="col-span-full diamond-card p-20 text-center rounded-3xl">
                    <div className="text-7xl mb-6">👨‍🍳</div>
                    <h3 className="text-2xl font-bold mb-2">Kitchen is Clear</h3>
                    <p className="text-zinc-500">Wait for new orders to appear here.</p>
                </div>
            )}
        </div>
    );
}
