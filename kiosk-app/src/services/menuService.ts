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

const PLACEHOLDER_IMG = `${STRAPI_URL}/uploads/placeholder_menu_item.png`;

function mapProduct(item: StrapiProduct): Product {
    const asset = item.creative_assets?.[0];
    const image = asset?.url
        ? (asset.url.startsWith('http') ? asset.url : `${STRAPI_URL}${asset.url}`)
        : PLACEHOLDER_IMG;

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
        extras: item.available_extras || [],
        sauces: item.available_sauces || [],
        sizes: item.available_sizes || [],
        preparationTime: item.preparation_time_min || 10,
    };
}

// Menu cache with TTL
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

function getCachedMenu(cacheKey: string): Product[] | null {
    try {
        const cached = localStorage.getItem(cacheKey);
        if (!cached) return null;
        const { data, timestamp } = JSON.parse(cached);
        if (Date.now() - timestamp > CACHE_TTL_MS) {
            localStorage.removeItem(cacheKey);
            return null;
        }
        return data;
    } catch {
        return null;
    }
}

export const menuService = {
    getCategories: async (): Promise<string[]> => {
        const res = await strapi.get<StrapiProduct[]>('/api/products?fields[0]=category&filters[is_kiosk_visible][$eq]=true');
        const cats = res.data.map((p: StrapiProduct) => p.category);
        return [...new Set(cats)].sort();
    },

    getProducts: async (category?: string): Promise<Product[]> => {
        const cacheKey = `menu_cache_${category || 'all'}`;

        // Check TTL-aware cache first
        const cached = getCachedMenu(cacheKey);
        if (cached) return cached;

        const filter = category ? `&filters[category][$eq]=${category}` : '';
        const res = await strapi.get<StrapiProduct[]>(
            `/api/products?populate=creative_assets,ingredients&filters[is_kiosk_visible][$eq]=true${filter}`
        );
        const products = res.data.map(mapProduct);

        // Store with timestamp for TTL
        localStorage.setItem(cacheKey, JSON.stringify({
            data: products,
            timestamp: Date.now()
        }));

        return products;
    },
};
