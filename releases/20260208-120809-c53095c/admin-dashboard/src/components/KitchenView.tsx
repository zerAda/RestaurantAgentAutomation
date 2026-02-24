import { useState } from 'react';

interface Order {
  id: string;
  table?: string;
  type: 'dine_in' | 'takeaway' | 'delivery';
  items: { name: string; qty: number; notes?: string }[];
  status: 'pending' | 'preparing' | 'ready';
  time: string;
}

const MOCK_ORDERS: Order[] = [
  {
    id: '#1024',
    type: 'dine_in',
    table: 'Table 4',
    items: [
      { name: 'Classic Burger', qty: 2, notes: 'No onion' },
      { name: 'Fries', qty: 2 }
    ],
    status: 'preparing',
    time: '12:45'
  },
  {
    id: '#1025',
    type: 'takeaway',
    items: [
      { name: 'Margherita Pizza', qty: 1 },
      { name: 'Cola', qty: 1 }
    ],
    status: 'pending',
    time: '12:48'
  },
  {
    id: '#1026',
    type: 'delivery',
    items: [
      { name: 'Pepperoni Pizza', qty: 2 },
      { name: 'Water', qty: 2 }
    ],
    status: 'pending',
    time: '12:52'
  }
];

export function KitchenView() {
  const [orders, setOrders] = useState<Order[]>(MOCK_ORDERS);

  const markReady = (id: string) => {
    setOrders(prev => prev.map(o => o.id === id ? { ...o, status: 'ready' } : o));
    // In real app: call API to notify user via WhatsApp
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'pending': return 'bg-orange-100 text-orange-700 border-orange-200';
      case 'preparing': return 'bg-blue-100 text-blue-700 border-blue-200';
      case 'ready': return 'bg-green-100 text-green-700 border-green-200 opacity-50';
      default: return 'bg-gray-100';
    }
  };

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      {orders.filter(o => o.status !== 'ready').map(order => (
        <div key={order.id} className={`bg-white dark:bg-zinc-800 rounded-xl shadow-sm border p-6 flex flex-col ${getStatusColor(order.status)} dark:border-zinc-700 dark:bg-zinc-800`}>
          <div className="flex justify-between items-start mb-4 pb-4 border-b border-black/5 dark:border-white/10">
            <div>
              <h3 className="text-2xl font-bold dark:text-zinc-100">{order.id}</h3>
              <p className="text-sm font-medium opacity-80 uppercase tracking-wider">{order.type} {order.table ? `• ${order.table}` : ''}</p>
            </div>
            <div className="text-xl font-mono font-bold opacity-70">{order.time}</div>
          </div>
          
          <div className="flex-1 space-y-3 mb-6">
            {order.items.map((item, idx) => (
              <div key={idx} className="flex justify-between items-start dark:text-zinc-300">
                <span className="font-bold text-lg">{item.qty}x</span>
                <div className="flex-1 px-3">
                  <div className="font-medium">{item.name}</div>
                  {item.notes && <div className="text-sm text-red-500 italic">Note: {item.notes}</div>}
                </div>
              </div>
            ))}
          </div>

          <button 
            onClick={() => markReady(order.id)}
            className="w-full py-4 rounded-lg bg-green-600 hover:bg-green-700 text-white font-bold text-lg shadow-md transition-colors flex items-center justify-center gap-2"
          >
            <span>✅</span>
            <span>Mark Ready</span>
          </button>
        </div>
      ))}
      
      {orders.filter(o => o.status !== 'ready').length === 0 && (
         <div className="col-span-full text-center py-20 text-zinc-400">
           <div className="text-6xl mb-4">👨‍🍳</div>
           <div className="text-xl">No active orders</div>
         </div>
      )}
    </div>
  );
}
