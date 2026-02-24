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
    // In a real app: calling the n8n webhook to notify user via WhatsApp
    setOrders(prev => prev.map(o => o.id === id ? { ...o, status: 'ready' } : o));

    // Voice alert for the kitchen staff
    if (window.speechSynthesis) {
      const msg = new SpeechSynthesisUtterance(`Order ${id.replace('#', '')} is ready for pickup`);
      msg.rate = 0.9;
      msg.pitch = 1.1;
      window.speechSynthesis.speak(msg);
    }

    console.log(`Order ${id} marked as ready. Triggering WhatsApp notification...`);
  };

  const getStatusOverlay = (status: string) => {
    switch (status) {
      case 'preparing': return 'from-indigo-500/10 to-transparent';
      default: return 'from-amber-500/10 to-transparent';
    }
  };

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-8">
      {orders.filter(o => o.status !== 'ready').map(order => (
        <div
          key={order.id}
          className={`diamond-card relative overflow-hidden group hover:scale-[1.01]`}
        >
          <div className={`absolute inset-0 bg-gradient-to-br ${getStatusOverlay(order.status)} pointer-events-none`} />

          <div className="p-8 relative z-10">
            <div className="flex justify-between items-start mb-6">
              <div>
                <div className="flex items-center gap-3 mb-1">
                  <h3 className="text-3xl font-black tracking-tighter">{order.id}</h3>
                  <span className={`px-2 py-0.5 rounded-md text-[10px] font-bold uppercase tracking-widest ${order.status === 'pending' ? 'bg-amber-500 text-black' : 'bg-indigo-600 text-white'
                    }`}>
                    {order.status}
                  </span>
                </div>
                <p className="text-xs font-bold text-zinc-500 uppercase tracking-widest flex items-center gap-2">
                  <span>{order.type}</span>
                  {order.table && (
                    <>
                      <span className="w-1 h-1 rounded-full bg-zinc-300" />
                      <span className="text-indigo-500">{order.table}</span>
                    </>
                  )}
                </p>
              </div>
              <div className="text-right">
                <div className="text-2xl font-mono font-bold text-zinc-400">{order.time}</div>
                <div className="text-[10px] font-bold text-red-500 animate-pulse">8m ELAPSED</div>
              </div>
            </div>

            <div className="space-y-4 mb-8">
              {order.items.map((item, idx) => (
                <div key={idx} className="flex justify-between items-center group/item">
                  <div className="flex items-center gap-4">
                    <span className="w-8 h-8 rounded-lg bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center font-bold text-sm">
                      {item.qty}
                    </span>
                    <div>
                      <div className="font-semibold text-zinc-100">{item.name}</div>
                      {item.notes && <div className="text-xs text-red-400 font-medium italic">"{item.notes}"</div>}
                    </div>
                  </div>
                </div>
              ))}
            </div>

            <button
              onClick={() => markReady(order.id)}
              className={`w-full py-4 rounded-xl font-black text-lg shadow-xl transition-all flex items-center justify-center gap-3 ${order.status === 'pending'
                ? 'bg-zinc-100 dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 hover:bg-zinc-200 dark:hover:bg-zinc-700'
                : 'bg-green-600 text-white hover:bg-green-700 shadow-green-600/20'
                }`}
            >
              {order.status === 'pending' ? 'Start Preparing' : 'Ready for Pickup'}
            </button>
          </div>
        </div>
      ))}

      {orders.filter(o => o.status !== 'ready').length === 0 && (
        <div className="col-span-full diamond-card p-20 text-center rounded-3xl">
          <div className="text-7xl mb-6">👨‍🍳</div>
          <h3 className="text-2xl font-bold mb-2">Kitchen is Clear</h3>
          <p className="text-zinc-500">Wait for new orders to appear here.</p>
        </div>
      )}
    </div>
  );
}
