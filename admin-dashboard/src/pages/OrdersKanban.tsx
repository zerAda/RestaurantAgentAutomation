import { cn } from "@/lib/utils";
import { Clock, CheckCircle, Truck, MoreHorizontal } from "lucide-react";
import { useOrders, useUpdateOrderStatus, OrderStatus } from "@/services/orders";

const COLUMNS: { id: OrderStatus; label: string; icon: React.ElementType; color: string }[] = [
    { id: 'NEW', label: 'Nouvelles', icon: Clock, color: 'bg-blue-50 text-blue-700' },
    { id: 'PREPARING', label: 'En Cuisine', icon: Clock, color: 'bg-orange-50 text-orange-700' },
    { id: 'READY', label: 'Prêtes', icon: CheckCircle, color: 'bg-green-50 text-green-700' },
    { id: 'DELIVERING', label: 'En Livraison', icon: Truck, color: 'bg-purple-50 text-purple-700' },
];

export default function OrdersKanban() {
    const { data: orders = [] } = useOrders();
    const updateStatus = useUpdateOrderStatus();

    const moveOrder = (orderId: string, newStatus: OrderStatus) => {
        updateStatus.mutate({ id: orderId, status: newStatus });
    };

    return (
        <div className="h-full flex flex-col">
            <div className="flex items-center justify-between mb-6">
                <h2 className="text-2xl font-bold text-gray-900">Suivi des Commandes</h2>
                <div className="flex gap-2">
                    <button className="px-4 py-2 bg-white border border-gray-200 text-sm font-medium rounded-lg hover:bg-gray-50 transition">
                        Filtres
                    </button>
                    <button className="px-4 py-2 bg-slate-900 text-white text-sm font-medium rounded-lg hover:bg-slate-800 transition">
                        + Nouvelle Commande
                    </button>
                </div>
            </div>

            <div className="flex-1 overflow-x-auto">
                <div className="flex gap-6 min-w-max h-full pb-4">
                    {COLUMNS.map((col) => (
                        <div key={col.id} className="w-80 flex flex-col bg-gray-50 rounded-xl border border-gray-200 h-full max-h-[calc(100vh-12rem)]">
                            {/* Column Header */}
                            <div className="p-4 border-b border-gray-200 flex items-center justify-between bg-white rounded-t-xl sticky top-0 z-10">
                                <div className="flex items-center gap-2">
                                    <div className={cn("p-1.5 rounded-md", col.color)}>
                                        <col.icon className="h-4 w-4" />
                                    </div>
                                    <h3 className="font-semibold text-gray-700">{col.label}</h3>
                                    <span className="bg-gray-100 text-gray-600 text-xs px-2 py-0.5 rounded-full font-medium">
                                        {orders.filter(o => o.status === col.id).length}
                                    </span>
                                </div>
                                <MoreHorizontal className="h-5 w-5 text-gray-400 cursor-pointer hover:text-gray-600" />
                            </div>

                            {/* Column Content */}
                            <div className="p-3 space-y-3 overflow-y-auto flex-1 custom-scrollbar">
                                {orders.filter(o => o.status === col.id).map(order => (
                                    <div key={order.id} className="bg-white p-4 rounded-lg border border-gray-200 shadow-sm hover:shadow-md transition-shadow group">
                                        <div className="flex justify-between items-start mb-2">
                                            <span className="font-bold text-gray-900">{order.id}</span>
                                            <span className="text-xs text-gray-500 bg-gray-100 px-2 py-1 rounded-sm">{order.time}</span>
                                        </div>
                                        <p className="text-sm font-medium text-gray-800 mb-1">{order.customer}</p>
                                        <p className="text-xs text-gray-500 mb-3 truncate">{order.items.join(", ")}</p>

                                        <div className="flex items-center justify-between pt-2 border-t border-gray-100">
                                            <span className="text-sm font-bold text-slate-700">{order.total}</span>
                                            <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                                                {/* Quick Actions based on status */}
                                                {order.status === 'NEW' && (
                                                    <button
                                                        onClick={() => moveOrder(order.id, 'PREPARING')}
                                                        className="p-1.5 bg-green-50 text-green-600 rounded hover:bg-green-100" title="Accepter"
                                                    >
                                                        <CheckCircle className="h-4 w-4" />
                                                    </button>
                                                )}
                                                {order.status === 'PREPARING' && (
                                                    <button
                                                        onClick={() => moveOrder(order.id, 'READY')}
                                                        className="p-1.5 bg-blue-50 text-blue-600 rounded hover:bg-blue-100" title="Prêt"
                                                    >
                                                        <CheckCircle className="h-4 w-4" />
                                                    </button>
                                                )}
                                                {order.status === 'READY' && (
                                                    <button
                                                        onClick={() => moveOrder(order.id, 'DELIVERING')}
                                                        className="p-1.5 bg-purple-50 text-purple-600 rounded hover:bg-purple-100" title="Expédier"
                                                    >
                                                        <Truck className="h-4 w-4" />
                                                    </button>
                                                )}
                                            </div>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </div>
                    ))}
                </div>
            </div>
        </div>
    );
}
