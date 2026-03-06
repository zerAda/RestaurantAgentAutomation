import { useState, useEffect, useCallback } from 'react';
import { strapi } from './services/strapiClient';
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
import { NotificationCenter } from './components/NotificationCenter';
import DashboardHome from './pages/DashboardHome';
import { AiObservatoryView } from './components/AiObservatoryView';
import { ControlPlaneView } from './pages/ControlPlaneView';
import { ToastProvider } from './components/ToastProvider';
import { PageTransition } from './components/PageTransition';
import { ErrorBoundary } from './components/ErrorBoundary';
import { ApiErrorListener } from './components/ApiErrorListener';
import { authService } from './services/authService';
import { getTranslation, setPageDirection, type Language } from './utils/i18n';
import {
  Menu,
  X,
  LayoutDashboard,
  Package,
  UtensilsCrossed,
  BarChart3,
  Palette,
  Bot,
  Users,
  Brain,
  Zap,
  Diamond,
  LogOut
} from 'lucide-react';
import { cn } from './lib/utils';

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(authService.isAuthenticated());
  const [activeTab, setActiveTab] = useState('dashboard');
  const [lang, setLang] = useState<Language>('fr');
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  // Basic RBAC Check
  const user = authService.getUser();
  const isFullAdmin = !user?.email?.toLowerCase().includes('cash') &&
    (!user?.role?.name || !user.role.name.toLowerCase().includes('cashier'));

  useEffect(() => {
    setPageDirection(lang);
  }, [lang]);

  if (!isAuthenticated) {
    return (
      <ToastProvider>
        <LoginView onLogin={() => setIsAuthenticated(true)} />
      </ToastProvider>
    );
  }

  const toggleLang = () => {
    const langs: Language[] = ['en', 'fr', 'ar'];
    const next = langs[(langs.indexOf(lang) + 1) % langs.length];
    setLang(next);
  };

  const t = (key: string) => getTranslation(key, lang);

  return (
    <ToastProvider>
      <ApiErrorListener />
      <div className={`min-h-screen bg-black text-zinc-100 font-sans selection:bg-brand-primary/30 relative overflow-hidden ${lang === 'ar' ? 'font-arabic' : ''}`}>

        {/* Cinematic Quantum Backdrop */}
        <div className="quantum-backdrop">
          <div className="quantum-glow-halo top-[-10%] left-[-10%] w-[50%] h-[50%] bg-brand-primary/10 animate-pulse-subtle" />
          <div className="quantum-glow-halo bottom-[-10%] right-[-10%] w-[60%] h-[60%] bg-indigo-500/10 animate-pulse-subtle delay-1000" />
          <div className="grain-overlay" />
        </div>

        <div className="relative z-10 min-h-screen flex flex-col md:flex-row">
          {/* Sidebar / Navigation */}
          {/* Mobile Overlay */}
          {isMobileMenuOpen && (
            <div
              className="fixed inset-0 bg-black/50 z-40 md:hidden backdrop-blur-sm"
              onClick={() => setIsMobileMenuOpen(false)}
            />
          )}

          {/* Sidebar - Quantum Glass Panel */}
          <nav
            className={cn(
              "fixed inset-y-4 rounded-quantum quantum-card w-72 flex-shrink-0 transition-all duration-500 z-50 flex flex-col scale-100",
              lang === 'ar' ? 'right-4' : 'left-4',
              !isMobileMenuOpen && (lang === 'ar' ? 'translate-x-[calc(100%+1rem)] md:translate-x-0' : '-translate-x-[calc(100%+1rem)] md:translate-x-0')
            )}
          >
            {/* Logo Section */}
            <div className="p-8 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-brand-primary to-brand-secondary flex items-center justify-center shadow-quantum-glow animate-float">
                  <span className="text-white font-black text-xl">R</span>
                </div>
                <div>
                  <h1 className="text-xl font-black tracking-tight leading-tight">
                    RestoBot <span className="opacity-40 font-medium italic">Diamond</span>
                  </h1>
                  <p className="text-[10px] font-bold text-brand-primary tracking-[0.2em] uppercase">Quantum v3.5</p>
                </div>
              </div>
              <button onClick={() => setIsMobileMenuOpen(false)} className="md:hidden p-2 rounded-lg hover:bg-white/10 text-zinc-400">
                <X size={18} />
              </button>
            </div>

            {/* Lang Switcher - Integral to Sidebar */}
            <div className="px-6 mb-4 flex items-center gap-2">
              <button
                onClick={toggleLang}
                className="flex-1 py-1.5 rounded-xl border border-white/5 bg-white/5 flex items-center justify-center gap-2 text-[10px] font-black uppercase hover:bg-white/10 transition-all"
              >
                🌍 {lang}
              </button>
              <AppSwitcher />
            </div>

            {/* Navigation */}
            <div className="flex-1 px-4 space-y-2 mt-4 overflow-y-auto scrollbar-hide pb-10">
              <p className="px-4 text-[10px] font-bold text-zinc-500 uppercase tracking-widest mb-4">Operations</p>
              <div className="space-y-1">
                <NavItem active={activeTab === 'dashboard'} onClick={() => setActiveTab('dashboard')} label="Dashboard" icon={LayoutDashboard} lang={lang} />
                <NavItem active={activeTab === 'stock'} onClick={() => setActiveTab('stock')} label={t('stock_inventory')} icon={Package} lang={lang} />
                <NavItem active={activeTab === 'kitchen'} onClick={() => setActiveTab('kitchen')} label={t('kitchen_display')} icon={UtensilsCrossed} lang={lang} />
              </div>

              <p className="px-4 text-[10px] font-bold text-zinc-500 uppercase tracking-widest mt-6 mb-4 italic">Strategy</p>
              <div className="space-y-1">
                {isFullAdmin && (
                  <>
                    <NavItem active={activeTab === 'analytics'} onClick={() => setActiveTab('analytics')} label="Intelligence" icon={BarChart3} lang={lang} />
                    <NavItem active={activeTab === 'marketing'} onClick={() => setActiveTab('marketing')} label="Creative Hub" icon={Palette} lang={lang} />
                    <NavItem active={activeTab === 'automation'} onClick={() => setActiveTab('automation')} label="n8n Engine" icon={Bot} lang={lang} />
                  </>
                )}
                <NavItem active={activeTab === 'customers'} onClick={() => setActiveTab('customers')} label="User Base" icon={Users} lang={lang} />
              </div>

              {isFullAdmin && (
                <>
                  <p className="px-4 text-[10px] font-bold text-zinc-500 uppercase tracking-widest mt-6 mb-4">Advanced</p>
                  <div className="space-y-1">
                    <NavItem active={activeTab === 'ai-observatory'} onClick={() => setActiveTab('ai-observatory')} label="AI Observ." icon={Brain} lang={lang} />
                    <NavItem active={activeTab === 'control-plane'} onClick={() => setActiveTab('control-plane')} label="Control Plane" icon={Zap} lang={lang} />
                    <NavItem active={activeTab === 'brand'} onClick={() => setActiveTab('brand')} label="DNA Studio" icon={Diamond} lang={lang} />
                  </div>
                </>
              )}
            </div>

            {/* System Status Footer */}
            <div className="p-6 mt-auto">
              <div className="bg-white/5 rounded-2xl p-4 border border-white/5 space-y-3">
                <div className="flex items-center justify-between text-[10px] font-bold text-zinc-500 uppercase">
                  <span>Cluster Sync</span>
                  <span className="text-success flex items-center gap-1">
                    <span className="status-dot bg-success" /> Active
                  </span>
                </div>
                <div className="flex items-center gap-3">
                  <div className="flex-1 h-1 bg-white/10 rounded-full overflow-hidden">
                    <div className="h-full bg-brand-primary w-2/3 rounded-full shadow-[0_0_8px_var(--color-brand-primary)]" />
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-4 mt-6 px-2">
                <div className="h-10 w-10 rounded-full bg-zinc-800 border-2 border-brand-primary/20 p-0.5 shadow-quantum">
                  <img src={`https://ui-avatars.com/api/?name=${user?.username || 'Admin'}&background=0D0D0D&color=fff`} className="w-full h-full rounded-full object-cover" alt="Avatar" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-xs font-bold truncate">{user?.username || 'Master Admin'}</p>
                  <p className="text-[10px] text-zinc-500 font-medium">Lvl 99 Ghost</p>
                </div>
                <button onClick={() => authService.logout()} className="p-2 rounded-xl hover:bg-white/10 text-zinc-500 hover:text-white transition-colors group">
                  <LogOut size={18} className="transition-transform group-hover:translate-x-0.5" />
                </button>
              </div>
            </div>
          </nav>

          {/* Main Content */}
          <main className={cn(
            "min-h-screen transition-all duration-500 p-6 md:p-10",
            lang === 'ar' ? 'md:mr-80' : 'md:ml-80'
          )}>
            {/* Mobile Header */}
            <div className="md:hidden flex items-center gap-4 mb-8 p-4 quantum-card">
              <button onClick={() => setIsMobileMenuOpen(true)} className="p-2.5 rounded-xl bg-white/5 border border-white/10 text-white">
                <Menu size={20} />
              </button>
              <div className="flex items-center gap-2">
                <span className="text-lg font-black tracking-tight text-white">RestoBot</span>
                <div className="w-2 h-2 rounded-full bg-brand-primary animate-pulse shadow-[0_0_10px_var(--color-brand-primary)]" />
              </div>
            </div>

            <header className="mb-12 flex flex-col sm:flex-row sm:justify-between items-start sm:items-end gap-6">
              <div>
                <div className="flex items-center gap-3 mb-2">
                  <div className="px-2 py-1 rounded-md bg-white/5 border border-white/10 text-[10px] font-bold text-zinc-500 uppercase tracking-widest">{activeTab}</div>
                  {activeTab === 'dashboard' && <span className="text-[10px] font-bold text-success uppercase tracking-widest flex items-center gap-1"><span className="status-dot bg-success" /> Live Sync</span>}
                </div>
                <h2 className="text-4xl md:text-5xl font-black tracking-tighter text-white">
                  {activeTab === 'dashboard' && "Vue d'ensemble"}
                  {activeTab === 'stock' && "Inventory"}
                  {activeTab === 'alerts' && "Quick Adjust"}
                  {activeTab === 'kitchen' && "Kitchen Display"}
                  {activeTab === 'support' && "Support Hub"}
                  {activeTab === 'marketing' && "Creative Center"}
                  {activeTab === 'automation' && "n8n Workflows"}
                  {activeTab === 'analytics' && "Ops Intelligence"}
                  {activeTab === 'ai-observatory' && 'AI Observatory'}
                  {activeTab === 'fleet' && "Delivery Fleet"}
                  {activeTab === 'customers' && "Customer Base"}
                  {activeTab === 'control-plane' && 'Control Plane'}
                  {activeTab === 'brand' && "Brand DNA"}
                </h2>
                <p className="text-zinc-500 font-medium max-w-xl mt-3">
                  RestoBot Quantum Engine v3.5. Real-time data aggregation across cluster nodes.
                </p>
              </div>

              <div className="flex items-center gap-4">
                <NotificationCenter />
                <div className="quantum-glass pl-5 pr-2 py-2 rounded-full text-sm font-bold flex items-center gap-4">
                  <span className="text-zinc-400 select-none tracking-tight">{new Date().toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })}</span>
                  <div className="px-4 py-1.5 rounded-full bg-white text-black font-black text-[10px] uppercase shadow-xl">
                    {new Date().toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                  </div>
                </div>
              </div>
            </header>

            <ErrorBoundary>
              <PageTransition activeKey={activeTab}>
                {activeTab === 'dashboard' && <DashboardHome />}
                {activeTab === 'stock' && <StockView />}
                {activeTab === 'alerts' && <QuickAdjust />}
                {activeTab === 'kitchen' && <KitchenView />}
                {activeTab === 'support' && <SupportView lang={lang} />}
                {activeTab === 'marketing' && <MarketingView lang={lang} />}
                {activeTab === 'automation' && <AutomationView lang={lang} />}
                {activeTab === 'analytics' && <AnalyticsView lang={lang} />}
                {activeTab === 'ai-observatory' && <AiObservatoryView />}
                {activeTab === 'control-plane' && <ControlPlaneView />}
                {activeTab === 'fleet' && <FleetPlaceholder />}
                {activeTab === 'customers' && <CustomerView lang={lang} />}
                {activeTab === 'brand' && <BrandView lang={lang} />}
              </PageTransition>
            </ErrorBoundary>
            <AIChatBubble />
          </main>
        </div>
      </div>
    </ToastProvider>
  );
}

interface NavItemProps {
  active: boolean;
  onClick: () => void;
  label: string;
  icon: React.ElementType;
  lang: string;
}

function NavItem({ active, onClick, label, icon: Icon, lang }: NavItemProps) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "w-full flex items-center gap-3 px-4 py-3 rounded-2xl transition-all duration-300 group relative overflow-hidden",
        active
          ? "bg-white/10 text-white shadow-quantum-glow"
          : "text-zinc-500 hover:text-zinc-300 hover:bg-white/5"
      )}
    >
      {active && (
        <div className={cn(
          "absolute inset-y-2 w-1 bg-brand-primary rounded-full shadow-[0_0_8px_var(--color-brand-primary)]",
          lang === 'ar' ? "right-0" : "left-0"
        )} />
      )}
      <Icon size={18} className={cn(
        "transition-transform duration-500",
        active ? "scale-110 text-brand-primary" : "group-hover:scale-110"
      )} />
      <span className="text-xs font-black uppercase tracking-widest">{label}</span>
    </button>
  );
}

// Removed AnalyticsPlaceholder and MetricCard (Now in components/AnalyticsView.tsx)


interface StrapiDriver {
  id: number;
  name: string;
  status: string;
  vehicle_type?: string;
  battery_pct?: number;
}

function FleetPlaceholder() {
  const [drivers, setDrivers] = useState<StrapiDriver[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchDrivers = useCallback(async () => {
    try {
      const res = await strapi.find<StrapiDriver>('drivers', {
        filters: { is_active: { $eq: true } },
        pagination: { limit: 20 },
      });
      setDrivers(res.data as unknown as StrapiDriver[]);
    } catch {
      setDrivers([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchDrivers();
    const t = setInterval(fetchDrivers, 30000);
    return () => clearInterval(t);
  }, [fetchDrivers]);

  const activeCount = drivers.filter(d => d.status === 'ONLINE').length;

  return (
    <div className="space-y-8 animate-in fade-in slide-in-from-bottom-8 duration-1000">
      {loading ? (
        <div className="text-center py-10 text-zinc-400">Loading fleet…</div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          {drivers.length === 0 ? (
            <div className="col-span-3 text-center py-10 text-zinc-400">No active drivers found.</div>
          ) : drivers.slice(0, 6).map(d => (
            <DriverCard
              key={d.id}
              name={d.name}
              status={d.status === 'ONLINE' ? 'Online' : d.status === 'ON_DELIVERY' ? 'On Delivery' : 'Offline'}
              order="—"
              battery={d.battery_pct !== undefined ? `${d.battery_pct}%` : '—'}
              icon={d.vehicle_type === 'bicycle' ? '🚲' : '🛵'}
            />
          ))}
        </div>
      )}

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
              <div className="w-2 h-2 rounded-full bg-green-500" /> {activeCount} Active Drivers
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
