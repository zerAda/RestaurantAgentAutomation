import { useEffect, useState } from 'react';
import type { StockItem } from '../services/stockService';
import { stockService } from '../services/stockService';

export function StockView() {
    const [items, setItems] = useState<StockItem[]>([]);
    const [loading, setLoading] = useState(true);

    const loadData = async () => {
        setLoading(true);
        const data = await stockService.getAll();
        setItems(data);
        setLoading(false);
    };

    useEffect(() => {
        loadData();
    }, []);

    const getStatusColor = (status: string) => {
        switch (status) {
            case 'critical': return 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400';
            case 'low': return 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400';
            default: return 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400';
        }
    };

    const getProgressColor = (status: string) => {
        switch (status) {
            case 'critical': return 'bg-red-500';
            case 'low': return 'bg-yellow-500';
            default: return 'bg-green-500';
        }
    };

    if (loading) return <div className="p-8 text-zinc-500">Loading inventory...</div>;

    return (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {items.map(item => (
                <div key={item.id} className="card">
                    <div className="flex justify-between items-start mb-4">
                        <div>
                            <h3 className="font-semibold text-lg">{item.name}</h3>
                            <p className="text-sm text-zinc-500 dark:text-zinc-400">{item.category}</p>
                        </div>
                        <span className={`px-2 py-1 text-xs rounded-full font-medium uppercase ${getStatusColor(item.status)}`}>
                            {item.status}
                        </span>
                    </div>

                    <div className="text-3xl font-bold mb-2">
                        {item.quantity} <span className="text-base font-normal text-zinc-400">{item.unit}</span>
                    </div>

                    <div className="w-full bg-zinc-100 dark:bg-zinc-700 rounded-full h-2 mb-2">
                        <div
                            className={`h-2 rounded-full transition-all duration-500 ${getProgressColor(item.status)}`}
                            style={{ width: `${Math.min(100, (item.quantity / (item.minStock * 2)) * 100)}%` }}
                        ></div>
                    </div>
                    <div className="flex justify-between text-xs text-zinc-400 mb-4">
                        <span>0</span>
                        <span>Ref: {item.minStock}</span>
                    </div>
                </div>
            ))}
        </div>
    );
}
