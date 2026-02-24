import { useState } from 'react';
import { StockView } from './components/StockView';
import { QuickAdjust } from './components/QuickAdjust';
import { KitchenView } from './components/KitchenView';

function App() {
  const [activeTab, setActiveTab] = useState('stock');

  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100 font-sans">
      {/* Sidebar / Navigation */}
      <nav className="fixed top-0 left-0 w-64 h-full bg-white dark:bg-zinc-800 border-r border-zinc-200 dark:border-zinc-700 p-4 hidden md:block">
        <div className="mb-8">
          <h1 className="text-2xl font-bold bg-gradient-to-r from-indigo-500 to-purple-600 bg-clip-text text-transparent">
            RestoBot Admin
          </h1>
        </div>
        <div className="space-y-2">
          <button
            onClick={() => setActiveTab('stock')}
            className={`w-full text-left px-4 py-2 rounded-lg transition-colors ${activeTab === 'stock' ? 'bg-indigo-50 text-indigo-600 dark:bg-indigo-900/20 dark:text-indigo-400 font-medium' : 'hover:bg-zinc-100 dark:hover:bg-zinc-700/50'}`}
          >
            📦 Stock Overview
          </button>
          <button
            onClick={() => setActiveTab('alerts')}
            className={`w-full text-left px-4 py-2 rounded-lg transition-colors ${activeTab === 'alerts' ? 'bg-indigo-50 text-indigo-600 dark:bg-indigo-900/20 dark:text-indigo-400 font-medium' : 'hover:bg-zinc-100 dark:hover:bg-zinc-700/50'}`}
          >
            ⚡ Quick Adjust
          </button>
        </div>
      </nav>

      {/* Main Content */}
      <main className="md:ml-64 p-8">
        <header className="mb-8">
          <h2 className="text-3xl font-bold">
            {activeTab === 'stock' && 'Stock Management'}
            {activeTab === 'alerts' && 'Quick Actions'}
            {activeTab === 'kitchen' && 'Kitchen Display System'}
          </h2>
          <p className="text-zinc-500 dark:text-zinc-400 mt-1">Real-time management interface.</p>
        </header>

        {activeTab === 'stock' && <StockView />}
        {activeTab === 'alerts' && <QuickAdjust />}
        {activeTab === 'kitchen' && <KitchenView />}
      </main>
    </div>
  );
}

export default App;
