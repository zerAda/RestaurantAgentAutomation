import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api";

export type OrderStatus = 'NEW' | 'PREPARING' | 'READY' | 'DELIVERING' | 'DONE';

export interface Order {
    id: string;
    customer: string;
    items: string[];
    total: string;
    status: OrderStatus;
    time: string;
    method: 'DELIVERY' | 'TAKEOUT' | 'DINE_IN';
}

// Mock Data for fallback
const MOCK_ORDERS: Order[] = [
    { id: "#1001", customer: "Amine K.", items: ["Burger Ralphé", "Frites"], total: "1200 DA", status: 'NEW', time: "10 min", method: 'DELIVERY' },
    { id: "#1002", customer: "Sarah B.", items: ["Pizza 4 Fromages"], total: "800 DA", status: 'PREPARING', time: "25 min", method: 'TAKEOUT' },
    { id: "#1003", customer: "Karim Z.", items: ["Tacos XL", "Coca"], total: "950 DA", status: 'READY', time: "40 min", method: 'DELIVERY' },
];

export const useOrders = () => {
    return useQuery({
        queryKey: ["orders"],
        queryFn: async () => {
            try {
                const { data } = await api.get("/orders");
                return data as Order[];
            } catch (error) {
                console.warn("Backend unavailable, using mock data", error);
                return MOCK_ORDERS;
            }
        },
    });
};

export const useUpdateOrderStatus = () => {
    const queryClient = useQueryClient();
    return useMutation({
        mutationFn: async ({ id, status }: { id: string; status: OrderStatus }) => {
            return api.post(`/orders/${id}/status`, { status });
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ["orders"] });
        },
    });
};
