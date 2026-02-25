import { useState, useEffect } from 'react';
import { StockView } from './components/StockView';
import { QuickAdjust } from './components/QuickAdjust';
import { KitchenView } from './components/KitchenView';
import { MarketingView } from './components/MarketingView';
import { AutomationView } from './components/AutomationView';
import { SupportView } from './components/SupportView';
import { CustomerView } from './components/CustomerView';
import { BrandView } from './components/BrandView';
import { LoginView } from './components/LoginView';
import { AppSwitcher } from './components/AppSwitcher';
import { AIChatBubble } from './components/AIChatBubble';
import { AnalyticsView } from './components/AnalyticsView';
import { authService } from './services/authService';
import { getTranslation, setPageDirection, type Language } from './utils/i18n';
import { Menu, X, Building2 } from 'lucide-react';

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(authService.isAuthenticated());
  const [activeTab, setActiveTab] = useState('stock');
  const [lang, setLang] = useState<Language>('fr');
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const [isMultiTenant] = useState(true); // Example flag
  const [currentTenant] = useState('RestoBot Diamond (HQ)');

  useEffect(() => {
    setPageDirection(lang);
  }, [lang]);

  if (!isAuthenticated) {
    return <LoginView onLogin={() => setIsAuthenticated(true)} />;
  }

  const toggleLang = () => {
    const langs: Language[] = ['en', 'fr', 'ar'];
    const next = langs[(langs.indexOf(lang) + 1) % langs.length];
    setLang(next);
  };

  const t = (key: string) => getTranslation(key, lang);

  return (
    <div className={`min-h-screen bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 font-sans selection:bg-indigo-500/30 ${lang === 'ar' ? 'font-arabic' : ''}`}>
      {/* Sidebar / Navigation */}
      {/* Mobile Overlay */}
      {isMobileMenuOpen && (
        <div
          className="fixed inset-0 bg-black/50 z-40 md:hidden backdrop-blur-sm"
          onClick={() => setIsMobileMenuOpen(false)}
        />
      )}

      <nav className={`fixed top-0 ${lang === 'ar' ? 'right-0' : 'left-0'} ${lang === 'ar' ? 'border-l' : 'border-r'} w-72 h-full bg-white/95 dark:bg-zinc-900/95 backdrop-blur-xl border-zinc-200 dark:border-zinc-800 p-6 flex flex-col z-50 transition-transform duration-300 ease-in-out ${isMobileMenuOpen ? 'translate-x-0' : lang === 'ar' ? 'translate-x-full md:translate-x-0' : '-translate-x-full md:translate-x-0'}`}>
        <div className="mb-8 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center shadow-lg shadow-indigo-500/20">
              <span className="text-white font-bold text-xl">R</span>
            </div>
            <h1 className="text-xl font-bold tracking-tight bg-gradient-to-r from-zinc-900 to-zinc-500 dark:from-white dark:to-zinc-500 bg-clip-text text-transparent">
              RestoBot <span className="text-indigo-500 italic">Diamond</span>
            </h1>
          </div>
          <button onClick={() => setIsMobileMenuOpen(false)} className="md:hidden w-8 h-8 rounded-lg bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center text-zinc-500">
            <X size={18} />
          </button>
        </div>

        {/* Multi-tenant Switcher */}
        {isMultiTenant && (
          <div className="mb-6 pb-6 border-b border-zinc-100 dark:border-zinc-800">
            <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest mb-2 block px-2">Current Location</label>
            <button className="w-full flex items-center justify-between bg-zinc-100 dark:bg-zinc-800/50 hover:bg-zinc-200 dark:hover:bg-zinc-800 px-3 py-2 rounded-xl transition-colors text-left text-sm">
              <div className="flex items-center gap-2 truncate">
                <Building2 size={14} className="text-indigo-500 shrink-0" />
                <span className="font-bold truncate">{currentTenant}</span>
              </div>
              <span className="text-xs text-zinc-400 ml-2">▼</span>
            </button>
          </div>
        )}

        <div className="mb-6 flex items-center gap-2">
          <div className="flex-1"><AppSwitcher /></div>
          <button
            onClick={toggleLang}
            className="w-10 h-10 rounded-xl border border-zinc-200 dark:border-zinc-800 flex items-center justify-center text-[10px] font-bold uppercase hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors"
          >
            {lang}
          </button>
        </div>

        <div className="flex-1 space-y-6 overflow-y-auto no-scrollbar pb-10">
          <div>
            <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em] mb-3 px-4">{t('management')}</p>
            <div className="space-y-1">
              <NavItem active={activeTab === 'stock'} onClick={() => setActiveTab('stock')} label={t('stock_inventory')} icon="📦" lang={lang} />
              <NavItem active={activeTab === 'kitchen'} onClick={() => setActiveTab('kitchen')} label={t('kitchen_display')} icon="👨‍🍳" lang={lang} />
              <NavItem active={activeTab === 'support'} onClick={() => setActiveTab('support')} label={t('support_hub')} icon="🧑‍💬" lang={lang} />
            </div>
          </div>

          <div>
            <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em] mb-3 px-4">{t('marketing')}</p>
            <div className="space-y-1">
              <NavItem active={activeTab === 'marketing'} onClick={() => setActiveTab('marketing')} label={t('creative_center')} icon="🎨" lang={lang} />
            </div>
          </div>

          <div>
            <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em] mb-3 px-4">{t('automation')}</p>
            <div className="space-y-1">
              <NavItem active={activeTab === 'automation'} onClick={() => setActiveTab('automation')} label={t('workflows')} icon="⚙️" lang={lang} />
              <NavItem active={activeTab === 'alerts'} onClick={() => setActiveTab('alerts')} label={t('quick_adjust')} icon="⚡" lang={lang} />
            </div>
          </div>

          <div>
            <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em] mb-3 px-4">{t('customers')}</p>
            <div className="space-y-1">
              <NavItem active={activeTab === 'customers'} onClick={() => setActiveTab('customers')} label={t('customers')} icon="👥" lang={lang} />
            </div>
          </div>

          <div>
            <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em] mb-3 px-4">{t('insights')}</p>
            <div className="space-y-1">
              <NavItem active={activeTab === 'analytics'} onClick={() => { setActiveTab('analytics'); setIsMobileMenuOpen(false); }} label={t('live_analytics')} icon="📊" lang={lang} />
              <NavItem active={activeTab === 'fleet'} onClick={() => { setActiveTab('fleet'); setIsMobileMenuOpen(false); }} label={t('fleet_status')} icon="🚚" lang={lang} />
            </div>
          </div>

          <div className="pt-4 border-t border-zinc-100 dark:border-zinc-800">
            <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em] mb-3 px-4">{t('settings')}</p>
            <NavItem active={activeTab === 'brand'} onClick={() => setActiveTab('brand')} label={t('brand_dna')} icon="💎" lang={lang} />
          </div>
        </div>

        <div className="pt-6 border-t border-zinc-100 dark:border-zinc-800 bg-white/50 dark:bg-zinc-900/50 -mx-6 px-6 -mb-6 pb-6">
          <div className="diamond-card p-4 rounded-xl text-xs">
            <p className="opacity-60 mb-1">{t('system_health')}</p>
            <div className="flex items-center gap-2 font-mono">
              <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />
              <span>{t('all_services_online')}</span>
            </div>
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className={`${lang === 'ar' ? 'md:mr-72' : 'md:ml-72'} p-6 md:p-10 min-h-screen transition-all`}>
        {/* Mobile Header */}
        <div className="md:hidden flex items-center gap-4 mb-8">
          <button onClick={() => setIsMobileMenuOpen(true)} className="p-2 rounded-xl bg-white dark:bg-zinc-900 shadow-sm border border-zinc-200 dark:border-zinc-800 text-zinc-800 dark:text-zinc-200">
            <Menu size={20} />
          </button>
          <div className="flex items-center gap-2">
            <span className="text-lg font-black tracking-tight bg-gradient-to-r from-zinc-900 to-zinc-500 dark:from-white dark:to-zinc-500 bg-clip-text text-transparent">RestoBot</span>
            <span className="text-indigo-500 italic font-bold">Diamond</span>
          </div>
        </div>

        <header className="mb-8 md:mb-12 flex flex-col sm:flex-row sm:justify-between items-start sm:items-end gap-4">
          <div>
            <h2 className="text-3xl md:text-4xl font-bold tracking-tight">
              {activeTab === 'stock' && t('stock_inventory')}
              {activeTab === 'alerts' && t('quick_adjust')}
              {activeTab === 'kitchen' && t('kitchen_display')}
              {activeTab === 'support' && t('support_hub')}
              {activeTab === 'marketing' && t('creative_center')}
              {activeTab === 'automation' && t('workflows')}
              {activeTab === 'analytics' && t('operational_intelligence')}
              {activeTab === 'fleet' && t('delivery_fleet')}
              {activeTab === 'customers' && t('customers')}
              {activeTab === 'brand' && t('brand_dna')}
            </h2>
            <p className="text-zinc-500 dark:text-zinc-400 mt-2 text-sm md:text-lg">
              Diamond Grade administration interface.
            </p>
          </div>
          <div className="diamond-glass px-4 py-2 rounded-full text-xs md:text-sm font-medium flex items-center gap-3">
            <span className="opacity-60 italic whitespace-nowrap">Feb 22, 2026</span>
            <div className="w-px h-4 bg-zinc-200 dark:bg-zinc-700" />
            <span className="text-indigo-500 font-bold whitespace-nowrap">LIVE</span>
            <button onClick={() => authService.logout()} className="md:hidden w-6 h-6 rounded bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center text-[10px] ml-2">🚪</button>
          </div>
        </header>

        <div className="animate-in fade-in slide-in-from-bottom-4 duration-700 ease-out">
          {activeTab === 'stock' && <StockView />}
          {activeTab === 'alerts' && <QuickAdjust />}
          {activeTab === 'kitchen' && <KitchenView />}
          {activeTab === 'support' && <SupportView lang={lang} />}
          {activeTab === 'marketing' && <MarketingView lang={lang} />}
          {activeTab === 'automation' && <AutomationView lang={lang} />}
          {activeTab === 'analytics' && <AnalyticsView lang={lang} />}
          {activeTab === 'fleet' && <FleetPlaceholder />}
          {activeTab === 'customers' && <CustomerView lang={lang} />}
          {activeTab === 'brand' && <BrandView lang={lang} />}
        </div>
        <AIChatBubble />
      </main>
    </div>
  );
}

function NavItem({ active, onClick, label, icon, lang }: { active: boolean, onClick: () => void, label: string, icon: string, lang: Language }) {
  return (
    <button
      onClick={onClick}
      className={`w-full flex items-center gap-3 px-4 py-3 rounded-xl transition-all duration-300 ${active
        ? 'nav-item-active'
        : 'text-zinc-500 hover:text-zinc-900 dark:hover:text-white hover:bg-zinc-100 dark:hover:bg-zinc-800'
        }`}
    >
      <span className="text-xl leading-none">{icon}</span>
      <span className="text-sm font-medium">{label}</span>
      {active && <div className={`${lang === 'ar' ? 'mr-auto' : 'ml-auto'} w-1.5 h-1.5 rounded-full bg-white animate-pulse`} />}
    </button>
  );
}

// Removed AnalyticsPlaceholder and MetricCard (Now in components/AnalyticsView.tsx)

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function TopItem({ name, sales, growth }: { name: string, sales: number, growth: string }) {
  return (
    <div className="flex items-center gap-4">
      <div className="w-12 h-12 rounded-xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center font-bold">#{sales}</div>
      <div className="flex-1">
        <div className="font-bold">{name}</div>
        <div className="w-full bg-zinc-100 dark:bg-zinc-800 h-1 rounded-full mt-2">
          <div className="h-full bg-indigo-500 rounded-full" style={{ width: `${(sales / 500) * 100}%` }} />
        </div>
      </div>
      <div className={`text-xs font-bold ${growth.startsWith('+') ? 'text-green-500' : 'text-red-500'}`}>
        {growth}
      </div>
    </div>
  );
}

function FleetPlaceholder() {
  return (
    <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
        <DriverCard name="Hassan R." status="On Delivery" order="#1024" battery="82%" icon="🛵" />
        <DriverCard name="Amine K." status="Returning" order="None" battery="45%" icon="🚲" />
        <DriverCard name="Mehdi S." status="At Restaurant" order="None" battery="98%" icon="🛵" />
      </div>

      <div className="diamond-card p-10 rounded-3xl relative overflow-hidden h-[500px]">
        <div className="absolute inset-0 opacity-20 pointer-events-none">
          <div className="absolute top-1/4 left-1/4 w-4 h-4 bg-indigo-500 rounded-full animate-ping" />
          <div className="absolute top-1/2 left-2/3 w-4 h-4 bg-green-500 rounded-full animate-ping" />
          <div className="absolute top-3/4 left-1/3 w-4 h-4 bg-amber-500 rounded-full animate-ping" />
          <div className="w-full h-full border border-zinc-200/20 grid grid-cols-6 grid-rows-6">
            {Array.from({ length: 36 }).map((_, i) => (
              <div key={i} className="border-[0.5px] border-zinc-200/5" />
            ))}
          </div>
        </div>
        <div className="relative z-10">
          <h4 className="text-2xl font-black mb-2">Live Fleet Map</h4>
          <p className="text-zinc-500 text-sm mb-6">Real-time GPS tracking of active delivery partners.</p>
          <div className="flex gap-4">
            <div className="diamond-glass px-4 py-2 rounded-xl text-xs font-bold flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-green-500" /> 12 Active Drivers
            </div>
            <div className="diamond-glass px-4 py-2 rounded-xl text-xs font-bold flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-amber-500" /> 4 Congested Areas
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function DriverCard({ name, status, order, battery, icon }: { name: string, status: string, order: string, battery: string, icon: string }) {
  return (
    <div className="diamond-card p-6 rounded-2xl group hover:border-indigo-500/50">
      <div className="flex justify-between items-start mb-6">
        <div className="w-14 h-14 rounded-2xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center text-3xl">{icon}</div>
        <div className="text-right">
          <div className="text-[10px] font-black text-zinc-400 uppercase tracking-widest mb-1">Battery</div>
          <div className="font-mono text-sm font-bold text-green-500">{battery}</div>
        </div>
      </div>
      <h4 className="text-xl font-bold mb-1">{name}</h4>
      <div className={`text-xs font-bold mb-6 flex items-center gap-2 ${status === 'On Delivery' ? 'text-indigo-500' :
        status === 'Returning' ? 'text-amber-500' : 'text-green-500'
        }`}>
        <div className={`w-1.5 h-1.5 rounded-full ${status === 'On Delivery' ? 'bg-indigo-500' :
          status === 'Returning' ? 'bg-amber-500' : 'bg-green-500'
          }`} />
        {status}
      </div>
      <div className="pt-4 border-t border-zinc-100 dark:border-zinc-800 flex justify-between items-center">
        <span className="text-xs text-zinc-500">Active Order</span>
        <span className="font-mono font-bold text-sm">{order}</span>
      </div>
    </div>
  );
}

export default App;
