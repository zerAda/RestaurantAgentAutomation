import { strapi } from './strapiClient';

export interface Product {
    id: string;
    name: string;
    price: number;
    category: string;
    image: string;
}

export const CATEGORIES = ['burgers', 'pizzas', 'tacos', 'salades', 'boissons', 'desserts', 'specials'];

interface StrapiProduct {
    id: number;
    documentId: string;
    name: string;
    marketing_name?: string;
    price: number;
    category: string;
    creative_assets?: { url: string }[];
}

const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || '';

function mapProduct(item: StrapiProduct): Product {
    const asset = item.creative_assets?.[0];
    const image = asset?.url
        ? (asset.url.startsWith('http') ? asset.url : `${STRAPI_URL}${asset.url}`)
        : 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=500&q=80';
    return {
        id: String(item.id),
        name: item.marketing_name || item.name,
        price: item.price,
        category: item.category,
        image,
    };
}

// Fallback mock data when Strapi is unavailable
const MOCK_PRODUCTS: Product[] = [
    { id: '1', name: 'Classic Burger', price: 550, category: 'burgers', image: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=500&q=80' },
    { id: '2', name: 'Cheese Burger', price: 650, category: 'burgers', image: 'https://images.unsplash.com/photo-1550547660-d9450f859349?w=500&q=80' },
    { id: '3', name: 'Margherita', price: 800, category: 'pizzas', image: 'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?w=500&q=80' },
    { id: '4', name: 'Pepperoni', price: 950, category: 'pizzas', image: 'https://images.unsplash.com/photo-1628840042765-356cda07504e?w=500&q=80' },
    { id: '5', name: 'Cola', price: 150, category: 'boissons', image: 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?w=500&q=80' },
    { id: '6', name: 'Water', price: 50, category: 'boissons', image: 'https://images.unsplash.com/photo-1548839140-29a749e1cf4d?w=500&q=80' },
];

export const menuService = {
    getProducts: async (category?: string): Promise<Product[]> => {
        const cacheKey = `menu_cache_${category || 'all'}`;

        try {
            const filter = category ? `&filters[category][$eq]=${category}` : '';
            const res = await strapi.get<StrapiProduct[]>(`/api/products?populate=creative_assets${filter}`);
            const products = res.data.map(mapProduct);

            // Persist for survival mode
            localStorage.setItem(cacheKey, JSON.stringify({
                data: products,
                timestamp: Date.now()
            }));

            return products;
        } catch (error) {
            console.warn('Strapi unavailable, entering Survival Mode fallback');

            // Try local storage first
            const cached = localStorage.getItem(cacheKey);
            if (cached) {
                const { data } = JSON.parse(cached);
                return data;
            }

            // Absolute fallback to hardcoded mocks
            if (category) {
                return MOCK_PRODUCTS.filter(p => p.category === category);
            }
            return [...MOCK_PRODUCTS];
        }
    },
};
