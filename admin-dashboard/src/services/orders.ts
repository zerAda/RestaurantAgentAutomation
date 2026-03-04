import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { strapi } from "./strapiClient";

export type OrderStatus = 'NEW' | 'PREPARING' | 'READY' | 'DELIVERING' | 'DONE' | 'CANCELLED';

export interface Order {
    id: string;
    documentId: string;
    customer: string;
    items: string[];
    total: string;
    status: OrderStatus;
    time: string;
    method: 'DELIVERY' | 'TAKEOUT' | 'DINE_IN';
    rawCreatedAt: string;
}

interface StrapiOrder {
    id: number;
    documentId: string;
    user_id: string;
    status: string;
    total_cents: number;
    service_mode: string;
    channel: string;
    // Strapi v5 uses camelCase system fields — snake_case (created_at) returns undefined
    createdAt: string;
    order_items?: { label: string; qty: number }[];
}

function mapOrder(item: StrapiOrder): Order {
    const methodMap: Record<string, 'DELIVERY' | 'TAKEOUT' | 'DINE_IN'> = {
        livraison: 'DELIVERY',
        a_emporter: 'TAKEOUT',
        sur_place: 'DINE_IN',
        kiosk_sur_place: 'DINE_IN',
        kiosk_a_emporter: 'TAKEOUT',
    };
    const ago = Math.round((Date.now() - new Date(item.createdAt).getTime()) / 60000);
    return {
        id: `#${String(item.id).padStart(4, '0')}`,
        documentId: item.documentId,
        customer: item.user_id?.slice(0, 12) || 'Unknown',
        items: item.order_items?.map(oi => `${oi.label} x${oi.qty}`) || [],
        total: `${(item.total_cents / 100).toFixed(0)} DA`,
        status: (item.status || 'NEW').toUpperCase() as OrderStatus,
        time: `${ago} min`,
        method: methodMap[item.service_mode] || 'TAKEOUT',
        rawCreatedAt: item.createdAt,
    };
}

export const useOrders = () => {
    return useQuery({
        queryKey: ["orders"],
        queryFn: async (): Promise<Order[]> => {
            const res = await strapi.find<StrapiOrder>('orders', {
                sort: ['createdAt:desc'],
                pagination: { limit: 50 },
                populate: ['order_items'],
            });
            const items = Array.isArray(res.data) ? res.data : [];
            return items.map(mapOrder);
        },
        refetchInterval: 15000,
    });
};

export const useUpdateOrderStatus = () => {
    const queryClient = useQueryClient();
    return useMutation({
        mutationFn: async ({ documentId, status }: { documentId: string; status: OrderStatus }) => {
            return strapi.put(`/api/orders/${documentId}`, { status });
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ["orders"] });
        },
        onError: (err) => {
            console.error('[KitchenView] Failed to update order status:', err);
        },
    });
};
