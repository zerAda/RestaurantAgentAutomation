import { Clock, CheckCircle, Truck, MoreHorizontal } from "lucide-react";
import { useOrders, useUpdateOrderStatus, type OrderStatus, type Order } from "@/services/orders";
import { maskPII } from "@/utils/pii";

const COLUMNS: { id: OrderStatus; label: string; icon: React.ElementType; color: string }[] = [
    { id: 'confirmed', label: 'Nouvelles', icon: Clock, color: 'bg-blue-50 text-blue-700' },
    { id: 'preparing', label: 'En Cuisine', icon: Clock, color: 'bg-orange-50 text-orange-700' },
    { id: 'ready', label: 'Prêtes', icon: CheckCircle, color: 'bg-green-50 text-green-700' },
    { id: 'delivered', label: 'Livrées', icon: Truck, color: 'bg-purple-50 text-purple-700' },
];

export default function OrdersKanban() {
    const { data: orders = [] } = useOrders();
    const updateStatus = useUpdateOrderStatus();

    const moveOrder = (documentId: string, newStatus: OrderStatus) => {
        updateStatus.mutate({ documentId, status: newStatus });
    };

    return (
        <div className="h-full flex flex-col max-w-[1400px] mx-auto">
            <div className="flex items-center justify-between mb-8">
                <div>
                    <h2 className="text-2xl font-semibold text-white tracking-tight">Suivi des Commandes</h2>
                    <p className="text-neutral-500 text-sm mt-1">Glissez et déposez les tickets pour changer leur statut.</p>
                </div>
                <div className="flex gap-2">
                    <button className="px-4 py-2 bg-black border border-neutral-800 text-white text-sm font-medium rounded-lg hover:border-neutral-700 transition-all">
                        Filtres
                    </button>
                    <button className="px-4 py-2 bg-white text-black text-sm font-semibold rounded-lg hover:bg-neutral-200 transition-colors">
                        + Nouvelle Commande
                    </button>
                </div>
            </div>

            <div className="flex-1 overflow-x-auto">
                <div className="flex gap-4 min-w-max h-full pb-4">
                    {COLUMNS.map((col) => (
                        <div key={col.id} className="w-[320px] flex flex-col bg-[#0a0a0a] rounded-xl border border-neutral-800 h-full max-h-[calc(100vh-14rem)]">
                            {/* Column Header */}
                            <div className="p-4 border-b border-neutral-900 flex items-center justify-between bg-black rounded-t-xl sticky top-0 z-10">
                                <div className="flex items-center gap-2">
                                    <div className="flex items-center gap-2">
                                        {col.id === 'confirmed' && <div className="w-2 h-2 rounded-full bg-blue-500" />}
                                        {col.id === 'preparing' && <div className="w-2 h-2 rounded-full bg-orange-500" />}
                                        {col.id === 'ready' && <div className="w-2 h-2 rounded-full bg-green-500" />}
                                        {col.id === 'delivered' && <div className="w-2 h-2 rounded-full bg-purple-500" />}
                                        <h3 className="font-medium text-sm text-neutral-300 tracking-wide">{col.label}</h3>
                                    </div>
                                    <span className="bg-neutral-900 border border-neutral-800 text-neutral-400 text-[10px] px-2 py-0.5 rounded-full font-semibold">
                                        {orders.filter((o: Order) => o.status === col.id).length}
                                    </span>
                                </div>
                                <MoreHorizontal className="h-4 w-4 text-neutral-600 cursor-pointer hover:text-neutral-400 transition-colors" />
                            </div>

                            {/* Column Content */}
                            <div className="p-3 space-y-3 overflow-y-auto flex-1 custom-scrollbar">
                                {orders.filter((o: Order) => o.status === col.id).map((order: Order) => (
                                    <div key={order.documentId} className="bg-black p-4 rounded-lg border border-neutral-800 hover:border-neutral-600 hover:bg-neutral-900/50 transition-all group flex flex-col cursor-grab active:cursor-grabbing">
                                        <div className="flex justify-between items-start mb-3">
                                            <span className="font-semibold text-white tracking-tight">{order.id}</span>
                                            <span className="text-[10px] text-neutral-400 font-medium bg-neutral-900 border border-neutral-800 px-2 py-1 rounded-md">{order.time}</span>
                                        </div>
                                        <p className="text-sm font-medium text-neutral-300 mb-1">{maskPII(order.customer)}</p>
                                        <p className="text-xs text-neutral-500 mb-4 truncate leading-relaxed">{order.items.join(", ")}</p>

                                        <div className="flex items-center justify-between pt-3 border-t border-neutral-900 mt-auto">
                                            <span className="text-sm font-semibold text-white">{order.total}</span>
                                            <div className="flex gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                                                {/* Quick Actions */}
                                                {order.status === 'confirmed' && (
                                                    <button onClick={() => moveOrder(order.documentId, 'preparing')} className="px-3 py-1 bg-neutral-900 border border-neutral-800 text-neutral-300 text-xs font-medium rounded hover:text-white hover:border-neutral-600 transition-colors">
                                                        Préparer
                                                    </button>
                                                )}
                                                {order.status === 'preparing' && (
                                                    <button onClick={() => moveOrder(order.documentId, 'ready')} className="px-3 py-1 bg-neutral-900 border border-neutral-800 text-neutral-300 text-xs font-medium rounded hover:text-white hover:border-neutral-600 transition-colors">
                                                        Terminé
                                                    </button>
                                                )}
                                                {order.status === 'ready' && (
                                                    <button onClick={() => moveOrder(order.documentId, 'delivered')} className="px-3 py-1 bg-neutral-900 border border-neutral-800 text-neutral-300 text-xs font-medium rounded hover:text-white hover:border-neutral-600 transition-colors">
                                                        Livrer
                                                    </button>
                                                )}
                                            </div>
                                        </div>
                                    </div>
                                ))}
                                {orders.filter((o: Order) => o.status === col.id).length === 0 && (
                                    <div className="h-24 border border-dashed border-neutral-800 rounded-lg flex items-center justify-center">
                                        <p className="text-xs text-neutral-600">Aucune commande</p>
                                    </div>
                                )}
                            </div>
                        </div>
                    ))}
                </div>
            </div>
        </div>
    );
}
