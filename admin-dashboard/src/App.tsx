import { useState, useEffect, useCallback, lazy, Suspense } from 'react';
import { strapi } from './services/strapiClient';
// PERF-07: Lazy-loaded view components (route-level code splitting)
// Only app-shell components remain eager: LoginView, AppSwitcher, AIChatBubble, NotificationCenter
const StockView = lazy(() => import('./components/StockView').then(m => ({ default: m.StockView })));
const QuickAdjust = lazy(() => import('./components/QuickAdjust').then(m => ({ default: m.QuickAdjust })));
const KitchenView = lazy(() => import('./components/KitchenView').then(m => ({ default: m.KitchenView })));
const MarketingView = lazy(() => import('./components/MarketingView').then(m => ({ default: m.MarketingView })));
const AutomationView = lazy(() => import('./components/AutomationView').then(m => ({ default: m.AutomationView })));
const SupportView = lazy(() => import('./components/SupportView').then(m => ({ default: m.SupportView })));
const CustomerView = lazy(() => import('./components/CustomerView').then(m => ({ default: m.CustomerView })));
const BrandView = lazy(() => import('./components/BrandView').then(m => ({ default: m.BrandView })));
const AnalyticsView = lazy(() => import('./components/AnalyticsView').then(m => ({ default: m.AnalyticsView })));
const DashboardHome = lazy(() => import('./pages/DashboardHome'));
const AiObservatoryView = lazy(() => import('./components/AiObservatoryView').then(m => ({ default: m.AiObservatoryView })));
const GrowthAgentView = lazy(() => import('./components/GrowthAgentView').then(m => ({ default: m.GrowthAgentView })));
const ControlPlaneView = lazy(() => import('./pages/ControlPlaneView').then(m => ({ default: m.ControlPlaneView })));
const AuditLogView = lazy(() => import('./pages/AuditLogView').then(m => ({ default: m.AuditLogView })));
// Eager imports (always needed at app shell level)
import { LoginView } from './components/LoginView';
import { AppSwitcher } from './components/AppSwitcher';
import { AIChatBubble } from './components/AIChatBubble';
import { NotificationCenter } from './components/NotificationCenter';
import { ToastProvider } from './components/ToastProvider';
import { PageTransition } from './components/PageTransition';
import { ErrorBoundary } from './components/ErrorBoundary';
import { ApiErrorListener } from './components/ApiErrorListener';
import { authService } from './services/authService';
import { useEntitlements } from './hooks/useEntitlements';
import { getTranslation, setPageDirection, type Language } from './utils/i18n';
import { Routes, Route, Navigate, useLocation, useNavigate } from 'react-router-dom';
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
  TrendingUp,
  Zap,
  Diamond,
  FileText,
  LogOut
} from 'lucide-react';
import { cn } from './lib/utils';

// Helper view to map paths to active keys for PageTransition
function ViewWrapper({ component: Component, activeKey }: { component: React.ReactNode, activeKey: string }) {
  return <PageTransition activeKey={activeKey}>{Component}</PageTransition>;
}

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(authService.isAuthenticated());
  const location = useLocation();
  const navigate = useNavigate();
  const activeTab = location.pathname.split('/')[1] || 'dashboard';

  const [lang, setLang] = useState<Language>('fr');
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const { hasModule } = useEntitlements();

  // Robust RBAC Check: Rely on actual role structure instead of generic string matching
  const user = authService.getUser();
  const isAdminRole = user?.role?.type === 'authenticated' || user?.role?.name?.toLowerCase() === 'admin' || user?.role?.name?.toLowerCase() === 'super_admin';
  const isFullAdmin = isAdminRole;

  useEffect(() => {
    setPageDirection(lang);
  }, [lang]);

  if (!isAuthenticated) {
    return (
      <ToastProvider>
        <LoginView onLogin={() => {
          setIsAuthenticated(true);
          // D-02 FIX: Restore the manager's location from before the 401 redirect.
          const redirectPath = sessionStorage.getItem('redirect_after_login');
          sessionStorage.removeItem('redirect_after_login');
          navigate(redirectPath || '/dashboard');
        }} />
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
                <NavItem active={activeTab === 'dashboard'} onClick={() => { navigate('/dashboard'); setIsMobileMenuOpen(false); }} label="Dashboard" icon={LayoutDashboard} lang={lang} />
                <NavItem active={activeTab === 'stock'} onClick={() => { navigate('/stock'); setIsMobileMenuOpen(false); }} label={t('stock_inventory')} icon={Package} lang={lang} />
                {hasModule('addon_kitchen_display') && (
                  <NavItem active={activeTab === 'kitchen'} onClick={() => { navigate('/kitchen'); setIsMobileMenuOpen(false); }} label={t('kitchen_display')} icon={UtensilsCrossed} lang={lang} />
                )}
              </div>

              <p className="px-4 text-[10px] font-bold text-zinc-500 uppercase tracking-widest mt-6 mb-4 italic">Strategy</p>
              <div className="space-y-1">
                {isFullAdmin && (
                  <>
                    {hasModule('addon_analytics') && (
                      <NavItem active={activeTab === 'analytics'} onClick={() => { navigate('/analytics'); setIsMobileMenuOpen(false); }} label="Intelligence" icon={BarChart3} lang={lang} />
                    )}
                    {hasModule('experimental_growth_agent') && (
                      <NavItem active={activeTab === 'growth'} onClick={() => { navigate('/growth'); setIsMobileMenuOpen(false); }} label="Growth AI" icon={TrendingUp} lang={lang} />
                    )}
                    <NavItem active={activeTab === 'marketing'} onClick={() => { navigate('/marketing'); setIsMobileMenuOpen(false); }} label="Creative Hub" icon={Palette} lang={lang} />
                    <NavItem active={activeTab === 'automation'} onClick={() => { navigate('/automation'); setIsMobileMenuOpen(false); }} label="n8n Engine" icon={Bot} lang={lang} />
                  </>
                )}
                <NavItem active={activeTab === 'customers'} onClick={() => { navigate('/customers'); setIsMobileMenuOpen(false); }} label="User Base" icon={Users} lang={lang} />
              </div>

              {isFullAdmin && (
                <>
                  <p className="px-4 text-[10px] font-bold text-zinc-500 uppercase tracking-widest mt-6 mb-4">Advanced</p>
                  <div className="space-y-1">
                    <NavItem active={activeTab === 'ai-observatory'} onClick={() => { navigate('/ai-observatory'); setIsMobileMenuOpen(false); }} label="AI Observ." icon={Brain} lang={lang} />
                    <NavItem active={activeTab === 'control-plane'} onClick={() => { navigate('/control-plane'); setIsMobileMenuOpen(false); }} label="Control Plane" icon={Zap} lang={lang} />
                    <NavItem active={activeTab === 'brand'} onClick={() => { navigate('/brand'); setIsMobileMenuOpen(false); }} label="DNA Studio" icon={Diamond} lang={lang} />
                    <NavItem active={activeTab === 'audit-log'} onClick={() => { navigate('/audit-log'); setIsMobileMenuOpen(false); }} label="Audit Trail" icon={FileText} lang={lang} />
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
                  {activeTab === 'growth' && 'Growth Intelligence'}
                  {activeTab === 'audit-log' && 'Audit Trail'}
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
              <Suspense fallback={
                <div className="flex items-center justify-center min-h-[60vh]">
                  <div className="space-y-4 w-full max-w-2xl px-8">
                    <div className="h-8 bg-white/5 rounded-xl animate-pulse w-1/3" />
                    <div className="h-4 bg-white/5 rounded-lg animate-pulse w-2/3" />
                    <div className="grid grid-cols-3 gap-4 mt-8">
                      <div className="h-32 bg-white/5 rounded-2xl animate-pulse" />
                      <div className="h-32 bg-white/5 rounded-2xl animate-pulse delay-100" />
                      <div className="h-32 bg-white/5 rounded-2xl animate-pulse delay-200" />
                    </div>
                    <div className="h-64 bg-white/5 rounded-2xl animate-pulse mt-4" />
                  </div>
                </div>
              }>
              <Routes>
                <Route path="/dashboard" element={<ViewWrapper activeKey="dashboard" component={<DashboardHome />} />} />
                <Route path="/stock" element={<ViewWrapper activeKey="stock" component={<StockView />} />} />
                <Route path="/alerts" element={<ViewWrapper activeKey="alerts" component={<QuickAdjust />} />} />
                <Route path="/kitchen" element={<ViewWrapper activeKey="kitchen" component={<KitchenView />} />} />
                <Route path="/support" element={<ViewWrapper activeKey="support" component={<SupportView lang={lang} />} />} />
                
                {isFullAdmin && (
                  <>
                    <Route path="/marketing" element={<ViewWrapper activeKey="marketing" component={<MarketingView lang={lang} />} />} />
                    <Route path="/automation" element={<ViewWrapper activeKey="automation" component={<AutomationView lang={lang} />} />} />
                    <Route path="/analytics" element={<ViewWrapper activeKey="analytics" component={<AnalyticsView lang={lang} />} />} />
                    <Route path="/growth" element={<ViewWrapper activeKey="growth" component={<GrowthAgentView />} />} />
                    <Route path="/ai-observatory" element={<ViewWrapper activeKey="ai-observatory" component={<AiObservatoryView />} />} />
                    <Route path="/control-plane" element={<ViewWrapper activeKey="control-plane" component={<ControlPlaneView />} />} />
                    <Route path="/brand" element={<ViewWrapper activeKey="brand" component={<BrandView lang={lang} />} />} />
                    <Route path="/audit-log" element={<ViewWrapper activeKey="audit-log" component={<AuditLogView />} />} />
                  </>
                )}
                
                <Route path="/fleet" element={<ViewWrapper activeKey="fleet" component={<FleetPlaceholder />} />} />
                <Route path="/customers" element={<ViewWrapper activeKey="customers" component={<CustomerView lang={lang} />} />} />
                
                <Route path="*" element={<Navigate to="/dashboard" replace />} />
              </Routes>
              </Suspense>
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
