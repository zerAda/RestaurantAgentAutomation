import type { Product } from '../services/menuService';

interface MenuGridProps {
    products: Product[];
    onAddToCart: (product: Product) => void;
}

export function MenuGrid({ products, onAddToCart }: MenuGridProps) {
    return (
        <div className="grid grid-cols-2 md:grid-cols-3 gap-6 p-6">
            {products.map(product => (
                <div
                    key={product.id}
                    onClick={() => onAddToCart(product)}
                    className="kiosk-card flex flex-col items-center text-center h-64 justify-between cursor-pointer"
                >
                    <img
                        src={product.image}
                        alt={product.name}
                        className="w-32 h-32 object-cover rounded-full shadow-md mb-4"
                    />
                    <div>
                        <h3 className="text-xl font-bold text-gray-800">{product.name}</h3>
                        <p className="text-lg font-bold text-orange-600 mt-1">{product.price} DA</p>
                    </div>
                </div>
            ))}
        </div>
    );
}
