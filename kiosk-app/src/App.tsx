import { useState, useEffect } from 'react';
import { MenuGrid } from './components/MenuGrid';
import { Cart } from './components/Cart';
import { menuService, CATEGORIES, Product } from './services/menuService';

function App() {
  const [activeCategory, setActiveCategory] = useState(CATEGORIES[0]);
  const [products, setProducts] = useState<Product[]>([]);
  const [cart, setCart] = useState<{ product: Product; qty: number }[]>([]);

  useEffect(() => {
    loadProducts();
  }, [activeCategory]);

  const loadProducts = async () => {
    const data = await menuService.getProducts(activeCategory);
    setProducts(data);
  };

  const addToCart = (product: Product) => {
    setCart(prev => {
      const existing = prev.find(item => item.product.id === product.id);
      if (existing) {
        return prev.map(item =>
          item.product.id === product.id ? { ...item, qty: item.qty + 1 } : item
        );
      }
      return [...prev, { product, qty: 1 }];
    });
  };

  const removeFromCart = (id: string) => {
    setCart(prev => prev.filter(item => item.product.id !== id));
  };

  return (
    <div className="flex h-screen bg-gray-100 font-sans overflow-hidden">
      {/* Main Menu Area */}
      <div className="flex-1 flex flex-col">
        {/* Categories Header */}
        <header className="bg-white p-4 shadow-sm z-10 overflow-x-auto">
          <div className="flex gap-4">
            {CATEGORIES.map(cat => (
              <button
                key={cat}
                onClick={() => setActiveCategory(cat)}
                className={`flex-shrink-0 px-8 py-4 rounded-xl text-lg font-bold transition-all ${activeCategory === cat
                    ? 'bg-orange-500 text-white shadow-lg scale-105'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                  }`}
              >
                {cat}
              </button>
            ))}
          </div>
        </header>

        {/* Product Grid */}
        <main className="flex-1 overflow-y-auto pb-20">
          <MenuGrid products={products} onAddToCart={addToCart} />
        </main>
      </div>

      {/* Cart Sidebar */}
      <div className="w-96 h-full">
        <Cart items={cart} onRemove={removeFromCart} onClear={() => setCart([])} />
      </div>
    </div>
  );
}

export default App;
