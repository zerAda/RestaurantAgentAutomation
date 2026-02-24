import { type ReactNode, useState, createContext, useContext } from 'react';
import type { Product } from '../services/menuService';

export interface CartItem {
    id: string; // unique id for the entry (product + extras hash)
    product: Product;
    quantity: number;
    extras: { name: string; price: number }[];
}

interface CartContextType {
    items: CartItem[];
    addItem: (product: Product, extras: { name: string; price: number }[]) => void;
    removeItem: (id: string) => void;
    clearCart: () => void;
    total: number;
    cartCount: number;
}

const CartContext = createContext<CartContextType | undefined>(undefined);

export function CartProvider({ children }: { children: ReactNode }) {
    const [items, setItems] = useState<CartItem[]>([]);

    const addItem = (product: Product, extras: { name: string; price: number }[]) => {
        const extrasKey = extras.map(e => e.name).sort().join('|');
        const itemId = `${product.id}-${extrasKey}`;

        setItems(prev => {
            const existing = prev.find(item => item.id === itemId);
            if (existing) {
                return prev.map(item =>
                    item.id === itemId ? { ...item, quantity: item.quantity + 1 } : item
                );
            }
            return [...prev, { id: itemId, product, quantity: 1, extras }];
        });
    };

    const removeItem = (id: string) => {
        setItems(prev => prev.filter(item => item.id !== id));
    };

    const clearCart = () => setItems([]);

    const total = items.reduce((sum, item) => {
        const extrasTotal = item.extras.reduce((s, e) => s + e.price, 0);
        return sum + (item.product.price + extrasTotal) * item.quantity;
    }, 0);

    const cartCount = items.reduce((sum, item) => sum + item.quantity, 0);

    return (
        <CartContext.Provider value={{ items, addItem, removeItem, clearCart, total, cartCount }}>
            {children}
        </CartContext.Provider>
    );
}

export function useCart() {
    const context = useContext(CartContext);
    if (!context) {
        throw new Error('useCart must be used within a CartProvider');
    }
    return context;
}
