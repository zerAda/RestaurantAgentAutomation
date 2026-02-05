export interface StockItem {
    id: string;
    name: string;
    category: string;
    quantity: number;
    unit: string;
    minStock: number;
    status: 'ok' | 'low' | 'critical';
}

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
        // Simulate API delay
        return new Promise((resolve) => {
            setTimeout(() => resolve([...MOCK_DATA]), 500);
        });
    },

    updateStock: async (id: string, delta: number): Promise<StockItem | null> => {
        return new Promise((resolve) => {
            setTimeout(() => {
                const item = MOCK_DATA.find(i => i.id === id);
                if (item) {
                    item.quantity = Math.max(0, item.quantity + delta);
                    // Recalculate status
                    if (item.quantity <= item.minStock / 2) item.status = 'critical';
                    else if (item.quantity <= item.minStock) item.status = 'low';
                    else item.status = 'ok';
                    resolve({ ...item });
                } else {
                    resolve(null);
                }
            }, 300);
        });
    }
};
