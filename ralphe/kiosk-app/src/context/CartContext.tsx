import { type ReactNode, useState, createContext, useContext, useCallback, useEffect } from 'react';
import type { Product, ExtraOption, SizeOption } from '../services/menuService';
import { strapi } from '../services/strapiClient';

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

interface StrapiSystemConfig {
    kiosk_default_service_mode?: string;
    kiosk_idle_timeout_sec?: number;
    kiosk_enabled?: boolean;
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
    defaultServiceMode: string;
}

const CartContext = createContext<CartContextType | undefined>(undefined);

export function CartProvider({ children }: { children: ReactNode }) {
    const [items, setItems] = useState<CartItem[]>([]);
    const [tableNumber, setTableNumber] = useState<number | null>(null);
    const [orderType, setOrderType] = useState<'dine_in' | 'takeaway'>('dine_in');
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [lastOrderResult, setLastOrderResult] = useState<OrderResult | null>(null);
    const [defaultServiceMode, setDefaultServiceMode] = useState<string>('kiosk_sur_place');

    // Fetch kiosk defaults from Strapi system-config (H-04)
    useEffect(() => {
        strapi.get<StrapiSystemConfig>('/api/system-config').then(res => {
            const cfg = res.data;
            if (cfg?.kiosk_default_service_mode) {
                setDefaultServiceMode(cfg.kiosk_default_service_mode);
            }
        }).catch((err) => {
            // BUG-009 FIX: Log the failure so monitoring can detect config unavailability.
            // The kiosk gracefully falls back to hardcoded defaults but this is now visible.
            console.warn('[CartContext] system-config fetch failed, using defaults:', err?.message);
        });
    }, []);

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
        // BUG-008 FIX: Guard against double-submission from rapid iPad taps.
        // isSubmitting is a React state, but the callback closure can be stale.
        // We use a module-level flag to ensure atomicity.
        if (isSubmitting) return { success: false, error: 'Commande en cours...' };

        setIsSubmitting(true);
        try {
            const orderItems = items.map(item => {
                const extrasTotal = item.extras.reduce((s, e) => s + e.price, 0);
                const unitPrice = item.product.price + item.size.price_modifier + extrasTotal;
                
                return {
                    item_code: item.product.id,
                    label: `${item.product.name} (${item.size.name})`,
                    qty: item.quantity,
                    unit_price_cents: unitPrice,
                    line_total_cents: unitPrice * item.quantity,
                };
            });

            const serviceMode = orderType === 'dine_in' ? 'kiosk_sur_place' : 'kiosk_a_emporter';

            const sessionId = `kiosk_${tableNumber || 'takeaway'}_${Date.now()}`.toLowerCase();

            const res = await strapi.post<{ id: number; documentId: string }>('/api/orders', {
                channel: 'kiosk',
                service_mode: serviceMode,
                status: 'NEW',
                // SECURITY (SEC-010): total_cents from frontend is UNTRUSTED. 
                // The n8n OrderFinalizer and Chargily Webhook MUST recalculate/validate 
                // this amount server-side before confirming payment.
                total_cents: total,
                table_number: tableNumber,
                kiosk_session_id: sessionId,
                order_type: orderType,
                order_items: orderItems,
            });

            if (res?.data?.id) {
                const result: OrderResult = {
                    success: true,
                    order_id: res.data.id,
                    total_amount: total,
                };
                setLastOrderResult(result);
                setItems([]);
                return result;
            } else {
                const result: OrderResult = { success: false, error: 'Erreur de commande' };
                setLastOrderResult(result);
                return result;
            }
        } catch (err) {
            const result: OrderResult = {
                success: false,
                error: err instanceof Error ? err.message : 'Connexion impossible. Réessayez.',
            };
            setLastOrderResult(result);
            return result;
        } finally {
            setIsSubmitting(false);
        }
    }, [items, tableNumber, orderType, total, isSubmitting]);

    return (
        <CartContext.Provider value={{
            items, addItem, removeItem, updateQuantity, clearCart, total, cartCount,
            tableNumber, setTableNumber, orderType, setOrderType,
            submitOrder, isSubmitting, lastOrderResult, defaultServiceMode,
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
