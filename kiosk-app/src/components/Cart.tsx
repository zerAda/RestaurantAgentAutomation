import { Product } from '../services/menuService';

interface CartProps {
    items: { product: Product; qty: number }[];
    onRemove: (id: string) => void;
    onClear: () => void;
}

export function Cart({ items, onRemove, onClear }: CartProps) {
    const total = items.reduce((sum, item) => sum + item.product.price * item.qty, 0);

    return (
        <div className="flex flex-col h-full bg-white border-l border-gray-200 shadow-xl">
            <div className="p-6 bg-gray-50 border-b border-gray-200">
                <h2 className="text-2xl font-bold text-gray-800">Votre Panier</h2>
            </div>

            <div className="flex-1 overflow-y-auto p-6 space-y-4">
                {items.length === 0 ? (
                    <div className="text-center text-gray-400 mt-10">Panier vide</div>
                ) : (
                    items.map(({ product, qty }) => (
                        <div key={product.id} className="flex justify-between items-center bg-white p-4 rounded-xl shadow-sm border border-gray-100">
                            <div>
                                <div className="font-bold text-gray-800">{product.name}</div>
                                <div className="text-sm text-gray-500">x{qty}</div>
                            </div>
                            <div className="flex items-center gap-4">
                                <span className="font-bold text-gray-900">{product.price * qty} DA</span>
                                <button
                                    onClick={() => onRemove(product.id)}
                                    className="w-8 h-8 flex items-center justify-center bg-red-100 text-red-600 rounded-lg hover:bg-red-200"
                                >
                                    ✕
                                </button>
                            </div>
                        </div>
                    ))
                )}
            </div>

            <div className="p-6 bg-gray-50 border-t border-gray-200">
                <div className="flex justify-between text-2xl font-bold mb-6 text-gray-900">
                    <span>Total</span>
                    <span>{total} DA</span>
                </div>
                <button className="w-full btn-primary text-xl">
                    Commander
                </button>
            </div>
        </div>
    );
}
