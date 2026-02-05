export interface Product {
    id: string;
    name: string;
    price: number;
    category: string;
    image: string;
}

export const CATEGORIES = ['Burgers', 'Pizzas', 'Drinks', 'Desserts'];

const MOCK_PRODUCTS: Product[] = [
    { id: '1', name: 'Classic Burger', price: 550, category: 'Burgers', image: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=500&q=80' },
    { id: '2', name: 'Cheese Burger', price: 650, category: 'Burgers', image: 'https://images.unsplash.com/photo-1550547660-d9450f859349?w=500&q=80' },
    { id: '3', name: 'Margherita', price: 800, category: 'Pizzas', image: 'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?w=500&q=80' },
    { id: '4', name: 'Pepperoni', price: 950, category: 'Pizzas', image: 'https://images.unsplash.com/photo-1628840042765-356cda07504e?w=500&q=80' },
    { id: '5', name: 'Cola', price: 150, category: 'Drinks', image: 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?w=500&q=80' },
    { id: '6', name: 'Water', price: 50, category: 'Drinks', image: 'https://images.unsplash.com/photo-1548839140-29a749e1cf4d?w=500&q=80' },
];

export const menuService = {
    getProducts: async (category?: string): Promise<Product[]> => {
        return new Promise((resolve) => {
            setTimeout(() => {
                if (category) {
                    resolve(MOCK_PRODUCTS.filter(p => p.category === category));
                } else {
                    resolve(MOCK_PRODUCTS);
                }
            }, 300);
        });
    }
};
