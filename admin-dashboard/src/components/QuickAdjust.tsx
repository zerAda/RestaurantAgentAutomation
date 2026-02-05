import { useEffect, useState } from 'react';
import { StockItem, stockService } from '../services/stockService';

export function QuickAdjust() {
    const [items, setItems] = useState<StockItem[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        loadData();
    }, []);

    const loadData = async () => {
        setLoading(true);
        const data = await stockService.getAll();
        setItems(data);
        setLoading(false);
    };

    const handleAdjust = async (id: string, delta: number) => {
        const updated = await stockService.updateStock(id, delta);
        if (updated) {
            setItems(prev => prev.map(i => i.id === id ? updated : i)); // Optimistic UI update could be faster
        }
    };

    if (loading) return <div className="p-8 text-zinc-500">Loading...</div>;

    return (
        <div className="bg-white dark:bg-zinc-800 rounded-xl shadow-sm border border-zinc-200 dark:border-zinc-700 overflow-hidden">
            <table className="w-full text-left">
                <thead className="bg-zinc-50 dark:bg-zinc-900/50 border-b border-zinc-200 dark:border-zinc-700">
                    <tr>
                        <th className="p-4 font-medium text-zinc-500 dark:text-zinc-400 text-sm">Item Name</th>
                        <th className="p-4 font-medium text-zinc-500 dark:text-zinc-400 text-sm">Current Stock</th>
                        <th className="p-4 font-medium text-zinc-500 dark:text-zinc-400 text-sm text-right">Quick Actions</th>
                    </tr>
                </thead>
                <tbody className="divide-y divide-zinc-100 dark:divide-zinc-700">
                    {items.map(item => (
                        <tr key={item.id} className="hover:bg-zinc-50 dark:hover:bg-zinc-700/30 transition-colors">
                            <td className="p-4">
                                <div className="font-medium text-zinc-900 dark:text-zinc-100">{item.name}</div>
                                <div className="text-xs text-zinc-500">{item.category}</div>
                            </td>
                            <td className="p-4">
                                <span className={`font-mono font-bold ${item.status === 'critical' ? 'text-red-600' : ''}`}>
                                    {item.quantity} {item.unit}
                                </span>
                            </td>
                            <td className="p-4 text-right">
                                <div className="flex justify-end gap-2">
                                    <button
                                        onClick={() => handleAdjust(item.id, -1)}
                                        className="w-8 h-8 flex items-center justify-center rounded-lg bg-red-50 hover:bg-red-100 text-red-600 dark:bg-red-900/20 dark:hover:bg-red-900/40 transition-colors"
                                    >-</button>
                                    <button
                                        onClick={() => handleAdjust(item.id, 1)}
                                        className="w-8 h-8 flex items-center justify-center rounded-lg bg-green-50 hover:bg-green-100 text-green-600 dark:bg-green-900/20 dark:hover:bg-green-900/40 transition-colors"
                                    >+</button>
                                    <button
                                        onClick={() => handleAdjust(item.id, 10)}
                                        className="h-8 px-3 flex items-center justify-center rounded-lg bg-zinc-100 hover:bg-zinc-200 text-zinc-600 dark:bg-zinc-700 dark:hover:bg-zinc-600 transition-colors text-xs font-bold"
                                    >+10</button>
                                </div>
                            </td>
                        </tr>
                    ))}
                </tbody>
            </table>
        </div>
    );
}
