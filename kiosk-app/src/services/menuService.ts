import { strapi } from './strapiClient';

export interface ExtraOption {
    name: string;
    price: number;
    category?: string;
}

export interface SauceOption {
    name: string;
    price: number;
    included_count?: number;
}

export interface SizeOption {
    name: string;
    price_modifier: number;
}

export interface Product {
    id: string;
    name: string;
    price: number;
    category: string;
    image: string;
    inStock: boolean;
    extras: ExtraOption[];
    sauces: SauceOption[];
    sizes: SizeOption[];
    preparationTime: number;
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
    current_stock?: number;
    min_stock_alert?: number;
    available_extras?: ExtraOption[];
    available_sauces?: SauceOption[];
    available_sizes?: SizeOption[];
    preparation_time_min?: number;
    is_kiosk_visible?: boolean;
    ingredients?: { data?: { attributes?: { current_stock?: number; min_stock_alert?: number } }[] };
}

const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || '';

const DEFAULT_SAUCES: SauceOption[] = [
    { name: 'Algérienne', price: 50, included_count: 2 },
    { name: 'Samurai', price: 50 },
    { name: 'Biggy Burger', price: 50 },
    { name: 'Ketchup', price: 30 },
    { name: 'Mayonnaise', price: 30 },
    { name: 'BBQ', price: 50 },
];

const DEFAULT_EXTRAS: ExtraOption[] = [
    { name: 'Cheddar', price: 100, category: 'fromage' },
    { name: 'Sauce Algérienne', price: 50, category: 'sauce' },
    { name: 'Oignons Grillés', price: 80, category: 'légumes' },
    { name: 'Extra Viande', price: 250, category: 'viande' },
    { name: 'Bacon', price: 200, category: 'viande' },
    { name: 'Oeuf', price: 80, category: 'autre' },
];

const DEFAULT_SIZES: SizeOption[] = [
    { name: 'Normal', price_modifier: 0 },
    { name: 'Maxi', price_modifier: 200 },
];

function mapProduct(item: StrapiProduct): Product {
    const asset = item.creative_assets?.[0];
    const image = asset?.url
        ? (asset.url.startsWith('http') ? asset.url : `${STRAPI_URL}${asset.url}`)
        : 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=500&q=80';

    let inStock = true;
    if (item.current_stock !== undefined && item.current_stock !== null) {
        inStock = item.current_stock > (item.min_stock_alert || 0);
    }
    if (item.ingredients?.data) {
        const anyIngredientLow = item.ingredients.data.some(ing => {
            const stock = ing.attributes?.current_stock ?? Infinity;
            const minAlert = ing.attributes?.min_stock_alert ?? 0;
            return stock <= minAlert;
        });
        if (anyIngredientLow) inStock = false;
    }

    return {
        id: String(item.id),
        name: item.marketing_name || item.name,
        price: item.price,
        category: item.category,
        image,
        inStock,
        extras: item.available_extras?.length ? item.available_extras : DEFAULT_EXTRAS,
        sauces: item.available_sauces?.length ? item.available_sauces : DEFAULT_SAUCES,
        sizes: item.available_sizes?.length ? item.available_sizes : DEFAULT_SIZES,
        preparationTime: item.preparation_time_min || 10,
    };
}

// Fallback mock data
const MOCK_PRODUCTS: Product[] = [
    { id: '1', name: 'Classic Burger', price: 550, category: 'burgers', image: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=500&q=80', inStock: true, extras: DEFAULT_EXTRAS, sauces: DEFAULT_SAUCES, sizes: DEFAULT_SIZES, preparationTime: 10 },
    { id: '2', name: 'Cheese Burger', price: 650, category: 'burgers', image: 'https://images.unsplash.com/photo-1550547660-d9450f859349?w=500&q=80', inStock: true, extras: DEFAULT_EXTRAS, sauces: DEFAULT_SAUCES, sizes: DEFAULT_SIZES, preparationTime: 10 },
    { id: '3', name: 'Margherita', price: 800, category: 'pizzas', image: 'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?w=500&q=80', inStock: true, extras: DEFAULT_EXTRAS, sauces: [], sizes: [{ name: 'Normal', price_modifier: 0 }, { name: 'Familiale', price_modifier: 400 }], preparationTime: 15 },
    { id: '4', name: 'Pepperoni', price: 950, category: 'pizzas', image: 'https://images.unsplash.com/photo-1628840042765-356cda07504e?w=500&q=80', inStock: true, extras: DEFAULT_EXTRAS, sauces: [], sizes: [{ name: 'Normal', price_modifier: 0 }, { name: 'Familiale', price_modifier: 400 }], preparationTime: 15 },
    { id: '5', name: 'Cola', price: 150, category: 'boissons', image: 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?w=500&q=80', inStock: true, extras: [], sauces: [], sizes: [], preparationTime: 1 },
    { id: '6', name: 'Water', price: 50, category: 'boissons', image: 'https://images.unsplash.com/photo-1548839140-29a749e1cf4d?w=500&q=80', inStock: true, extras: [], sauces: [], sizes: [], preparationTime: 1 },
];

export const menuService = {
    getProducts: async (category?: string): Promise<Product[]> => {
        const cacheKey = `menu_cache_${category || 'all'}`;

        try {
            const filter = category ? `&filters[category][$eq]=${category}` : '';
            const res = await strapi.get<StrapiProduct[]>(`/api/products?populate=creative_assets,ingredients&filters[is_kiosk_visible][$eq]=true${filter}`);
            const products = res.data.map(mapProduct);

            localStorage.setItem(cacheKey, JSON.stringify({
                data: products,
                timestamp: Date.now()
            }));

            return products;
        } catch {
            console.warn('Strapi unavailable, entering Survival Mode fallback');

            const cached = localStorage.getItem(cacheKey);
            if (cached) {
                const { data } = JSON.parse(cached);
                return data;
            }

            if (category) {
                return MOCK_PRODUCTS.filter(p => p.category === category);
            }
            return [...MOCK_PRODUCTS];
        }
    },
};
