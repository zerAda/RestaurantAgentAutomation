import { strapi } from './strapiClient';

export interface StockItem {
    id: string;
    name: string;
    category: string;
    quantity: number;
    unit: string;
    minStock: number;
    status: 'ok' | 'low' | 'critical';
}

interface StrapiIngredient {
    id: number;
    documentId: string;
    name: string;
    category: string;
    current_stock: number;
    unit: string;
    min_stock_alert: number;
    supplier?: { name: string };
}

function computeStatus(qty: number, min: number): 'ok' | 'low' | 'critical' {
    if (qty <= min / 2) return 'critical';
    if (qty <= min) return 'low';
    return 'ok';
}

function mapIngredient(item: StrapiIngredient): StockItem {
    return {
        id: String(item.id),
        name: item.name,
        category: item.category || 'Uncategorized',
        quantity: item.current_stock,
        unit: item.unit || 'units',
        minStock: item.min_stock_alert,
        status: computeStatus(item.current_stock, item.min_stock_alert),
    };
}

// Fallback mock data when Strapi is unavailable
const MOCK_DATA: StockItem[] = [
    { id: '1', name: 'Tomatoes', category: 'Vegetables', quantity: 12.5, unit: 'kg', minStock: 5, status: 'ok' },
    { id: '2', name: 'Burger Buns', category: 'Bakery', quantity: 24, unit: 'units', minStock: 50, status: 'low' },
    { id: '3', name: 'Cheddar Cheese', category: 'Dairy', quantity: 2.1, unit: 'kg', minStock: 2, status: 'ok' },
    { id: '4', name: 'Beef Patties', category: 'Meat', quantity: 15, unit: 'kg', minStock: 20, status: 'low' },
    { id: '5', name: 'Lettuce', category: 'Vegetables', quantity: 4, unit: 'kg', minStock: 2, status: 'ok' },
    { id: '6', name: 'Special Sauce', category: 'Pantry', quantity: 0.5, unit: 'L', minStock: 1, status: 'critical' },
];

export const stockService = {
    getAll: async (): Promise<StockItem[]> => {
        try {
            const res = await strapi.get<StrapiIngredient[]>('/api/ingredients?populate=supplier');
            return res.data.map(mapIngredient);
        } catch {
            console.warn('Strapi unavailable, using mock data');
            return [...MOCK_DATA];
        }
    },

    updateStock: async (id: string, delta: number): Promise<StockItem | null> => {
        try {
            const res = await strapi.get<StrapiIngredient>(`/api/ingredients/${id}`);
            const current = res.data;
            const newQty = Math.max(0, current.current_stock + delta);
            const updated = await strapi.put<StrapiIngredient>(`/api/ingredients/${id}`, {
                current_stock: newQty,
            });
            return mapIngredient(updated.data);
        } catch {
            // Fallback to mock update
            const item = MOCK_DATA.find(i => i.id === id);
            if (!item) return null;
            item.quantity = Math.max(0, item.quantity + delta);
            item.status = computeStatus(item.quantity, item.minStock);
            return { ...item };
        }
    },
};
