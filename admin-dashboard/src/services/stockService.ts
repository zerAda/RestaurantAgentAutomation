import { strapi } from './strapiClient';

export interface StockItem {
    id: string;
    name: string;
    category: string;
    quantity: number;
    reservedStock: number;
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
    reserved_stock?: number;
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
        reservedStock: item.reserved_stock || 0,
        unit: item.unit || 'units',
        minStock: item.min_stock_alert,
        status: computeStatus(item.current_stock, item.min_stock_alert),
    };
}

export const stockService = {
    getAll: async (): Promise<StockItem[]> => {
        // Fetch with high limit to handle pagination truncation (fixes M-audit issue)
        const res = await strapi.get<StrapiIngredient[]>('/api/ingredients?populate=supplier&pagination[limit]=1000');
        // Handle Strapi v5 array wrapping
        const data = Array.isArray(res.data) ? res.data : [];
        return data.map(mapIngredient);
    },

    updateStock: async (id: string, delta: number): Promise<StockItem | null> => {
        // Calls the custom atomic endpoint
        const updated = await strapi.post<StrapiIngredient>(`/api/ingredients/${id}/adjust`, {
            delta: delta,
        });
        return mapIngredient(updated.data);
    },
};
