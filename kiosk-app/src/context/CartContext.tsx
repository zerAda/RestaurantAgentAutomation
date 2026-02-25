import { type ReactNode, useState, createContext, useContext, useCallback } from 'react';
import type { Product, ExtraOption, SizeOption } from '../services/menuService';

interface SelectedSauce {
    name: string;
    price: number;
    is_free: boolean;
}

export interface CartItem {
    id: string;
    product: Product;
    quantity: number;
    extras: ExtraOption[];
    sauces: SelectedSauce[];
    size: SizeOption;
}

interface OrderResult {
    success: boolean;
    order_id?: number;
    is_merge?: boolean;
    total_amount?: number;
    estimated_ready_time?: number;
    message?: string;
    error?: string;
}

interface CartContextType {
    items: CartItem[];
    addItem: (product: Product, extras: ExtraOption[], sauces: SelectedSauce[], size: SizeOption, quantity: number) => void;
    removeItem: (id: string) => void;
    updateQuantity: (id: string, delta: number) => void;
    clearCart: () => void;
    total: number;
    cartCount: number;
    tableNumber: number | null;
    setTableNumber: (n: number | null) => void;
    orderType: 'dine_in' | 'takeaway';
    setOrderType: (t: 'dine_in' | 'takeaway') => void;
    submitOrder: () => Promise<OrderResult>;
    isSubmitting: boolean;
    lastOrderResult: OrderResult | null;
}

const CartContext = createContext<CartContextType | undefined>(undefined);

const N8N_URL = import.meta.env.VITE_N8N_URL || 'http://localhost:5678';

export function CartProvider({ children }: { children: ReactNode }) {
    const [items, setItems] = useState<CartItem[]>([]);
    const [tableNumber, setTableNumber] = useState<number | null>(null);
    const [orderType, setOrderType] = useState<'dine_in' | 'takeaway'>('dine_in');
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [lastOrderResult, setLastOrderResult] = useState<OrderResult | null>(null);

    const addItem = useCallback((product: Product, extras: ExtraOption[], sauces: SelectedSauce[], size: SizeOption, quantity: number) => {
        const extrasKey = extras.map(e => e.name).sort().join('|');
        const saucesKey = sauces.map(s => s.name).sort().join('|');
        const itemId = `${product.id}-${size.name}-${extrasKey}-${saucesKey}`;

        setItems(prev => {
            const existing = prev.find(item => item.id === itemId);
            if (existing) {
                return prev.map(item =>
                    item.id === itemId ? { ...item, quantity: item.quantity + quantity } : item
                );
            }
            return [...prev, { id: itemId, product, quantity, extras, sauces, size }];
        });
    }, []);

    const removeItem = useCallback((id: string) => {
        setItems(prev => prev.filter(item => item.id !== id));
    }, []);

    const updateQuantity = useCallback((id: string, delta: number) => {
        setItems(prev => prev.map(item => {
            if (item.id !== id) return item;
            const newQty = item.quantity + delta;
            return newQty < 1 ? item : { ...item, quantity: newQty };
        }).filter(item => item.quantity > 0));
    }, []);

    const clearCart = useCallback(() => setItems([]), []);

    const total = items.reduce((sum, item) => {
        const extrasTotal = item.extras.reduce((s, e) => s + e.price, 0);
        const saucesTotal = item.sauces.filter(s => !s.is_free).reduce((s, sauce) => s + sauce.price, 0);
        return sum + (item.product.price + item.size.price_modifier + extrasTotal + saucesTotal) * item.quantity;
    }, 0);

    const cartCount = items.reduce((sum, item) => sum + item.quantity, 0);

    const submitOrder = useCallback(async (): Promise<OrderResult> => {
        if (items.length === 0) return { success: false, error: 'Panier vide' };

        setIsSubmitting(true);
        try {
            const payload = {
                items: items.map(item => ({
                    product_id: item.product.id,
                    name: item.product.name,
                    quantity: item.quantity,
                    size: item.size,
                    extras: item.extras.map(e => ({ name: e.name, price: e.price })),
                    sauces: item.sauces.map(s => ({ name: s.name, price: s.price, is_free: s.is_free })),
                })),
                table_number: tableNumber,
                order_type: orderType,
                kiosk_session_id: `kiosk_${Date.now()}`,
                payment_method: 'cash',
            };

            const res = await fetch(`${N8N_URL}/webhook/kiosk-order`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
            });

            const data = await res.json();

            if (data.success) {
                const result: OrderResult = {
                    success: true,
                    order_id: data.order_id,
                    is_merge: data.is_merge,
                    total_amount: data.total_amount,
                    estimated_ready_time: data.estimated_ready_time,
                    message: data.message,
                };
                setLastOrderResult(result);
                setItems([]);
                return result;
            } else {
                const result: OrderResult = { success: false, error: data.message || 'Erreur de commande' };
                setLastOrderResult(result);
                return result;
            }
        } catch {
            const result: OrderResult = { success: false, error: 'Connexion impossible. Réessayez.' };
            setLastOrderResult(result);
            return result;
        } finally {
            setIsSubmitting(false);
        }
    }, [items, tableNumber, orderType]);

    return (
        <CartContext.Provider value={{
            items, addItem, removeItem, updateQuantity, clearCart, total, cartCount,
            tableNumber, setTableNumber, orderType, setOrderType,
            submitOrder, isSubmitting, lastOrderResult
        }}>
            {children}
        </CartContext.Provider>
    );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useCart() {
    const context = useContext(CartContext);
    if (!context) throw new Error('useCart must be used within a CartProvider');
    return context;
}
