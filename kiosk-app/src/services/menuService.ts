// =============================================================================
// PRODUCTION FIX (P4.1): Real API Integration - Menu/Products
// =============================================================================
// Replaced MOCK_DATA with real Strapi CMS API calls.
// Tenant isolation enforced via restaurant_id from kiosk configuration.
// Only published products are shown to customers.
// =============================================================================

export interface Product {
    id: string;
    name: string;
    price: number;
    category: string;
    image: string;
    description?: string;
    available?: boolean;
}

// Configuration
const API_BASE_URL = import.meta.env.VITE_STRAPI_URL || 'http://localhost:1337';
const API_TOKEN = import.meta.env.VITE_STRAPI_API_TOKEN || '';

// Dynamic categories loaded from API
export let CATEGORIES: string[] = [];

// Helper: Get auth headers
function getHeaders(): HeadersInit {
    const headers: HeadersInit = {
        'Content-Type': 'application/json'
    };
    if (API_TOKEN) {
        headers['Authorization'] = `Bearer ${API_TOKEN}`;
    }
    return headers;
}

// Helper: Get restaurant ID from kiosk config (localStorage, URL param, or config file)
function getRestaurantId(): string {
    // Priority: URL param > localStorage > environment variable
    const urlParams = new URLSearchParams(window.location.search);
    const urlRestaurantId = urlParams.get('restaurant_id');

    const restaurantId =
        urlRestaurantId ||
        localStorage.getItem('kiosk_restaurant_id') ||
        import.meta.env.VITE_RESTAURANT_ID ||
        '';

    if (!restaurantId) {
        console.warn('SECURITY WARNING: No restaurant_id found. Tenant isolation may be compromised.');
    }

    return restaurantId;
}

// Strapi API response types (handles both v3 flat and v4 nested formats)
interface StrapiProductAttributes {
    id?: number | string;
    marketing_name?: string;
    name?: string;
    price?: number;
    category?: string;
    image_url?: string;
    image?: { data?: { attributes?: { url?: string } } };
    description_multilang?: { fr?: string };
    description?: string;
    stock_quantity?: number;
}

type StrapiProductData = StrapiProductAttributes & {
    id?: number | string;
    attributes?: StrapiProductAttributes;
};

// Helper: Transform Strapi product to Product interface
function transformProduct(data: StrapiProductData): Product {
    const attr: StrapiProductAttributes = data.attributes || data;
    return {
        id: data.id?.toString() || attr.id?.toString() || '',
        name: attr.marketing_name || attr.name || 'Unnamed Product',
        price: attr.price || 0,
        category: attr.category || 'Other',
        image: attr.image_url || attr.image?.data?.attributes?.url || '/placeholder-product.png',
        description: attr.description_multilang?.fr || attr.description || '',
        available: (attr.stock_quantity || 0) > 0
    };
}

export const menuService = {
    /**
     * Fetch all published products for the kiosk's restaurant
     * SECURITY: Tenant isolation enforced via restaurant_id filter
     * Only published products (publishedAt != null) are shown
     */
    getProducts: async (category?: string): Promise<Product[]> => {
        try {
            const restaurantId = getRestaurantId();
            if (!restaurantId) {
                throw new Error('Kiosk configuration error: restaurant_id not set');
            }

            // Build tenant-isolated API call with published filter
            let url = `${API_BASE_URL}/api/products?filters[restaurant_id][$eq]=${restaurantId}&filters[publishedAt][$notNull]=true&populate=*`;

            if (category) {
                url += `&filters[category][$eq]=${encodeURIComponent(category)}`;
            }

            const response = await fetch(url, {
                method: 'GET',
                headers: getHeaders()
            });

            if (!response.ok) {
                throw new Error(`API error: ${response.status} ${response.statusText}`);
            }

            const json = await response.json();
            const products = (json.data || []).map(transformProduct);

            // Update categories dynamically (deduplicated)
            const uniqueCategories = ([...new Set(products.map((p: Product) => p.category))].filter(Boolean)) as string[];
            CATEGORIES = uniqueCategories.sort();

            return products;
        } catch (error) {
            console.error('Failed to fetch products:', error);
            // Return empty array on error (don't leak mock data in production)
            return [];
        }
    },

    /**
     * Fetch unique categories for the restaurant's menu
     */
    getCategories: async (): Promise<string[]> => {
        try {
            const restaurantId = getRestaurantId();
            if (!restaurantId) {
                return [];
            }

            const url = `${API_BASE_URL}/api/products?filters[restaurant_id][$eq]=${restaurantId}&filters[publishedAt][$notNull]=true&fields[0]=category`;
            const response = await fetch(url, {
                method: 'GET',
                headers: getHeaders()
            });

            if (!response.ok) {
                throw new Error(`API error: ${response.status}`);
            }

            const json = await response.json();
            const categories = [...new Set(
                (json.data || [])
                    .map((item: StrapiProductData) => item.attributes?.category)
                    .filter(Boolean)
            )].sort();

            const typedCategories = categories as string[];
            CATEGORIES = typedCategories;
            return typedCategories;
        } catch (error) {
            console.error('Failed to fetch categories:', error);
            return [];
        }
    }
};
