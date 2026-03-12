import { useState, useEffect, useCallback } from 'react';
import {
  TrendingUp, Users, Zap, RefreshCw, Send, Brain,
  ShoppingBag, Activity, Target, BarChart2, Clock,
  ChevronRight, MessageCircle, Award, Sparkles
} from 'lucide-react';
import { strapi } from '../services/strapiClient';

// ---------- Types ----------
interface AIInsight {
  id: number;
  attributes: {
    insight: string;
    recommendations: string;
    metrics_json: Record<string, unknown> | null;
    period: string;
    source: string;
    generated_at: string;
    model?: string;
  };
}

interface Customer {
  id: number;
  attributes: {
    name: string;
    phone: string;
    total_spent: number;
    loyalty_points?: number;
    loyalty_tier?: string;
    updatedAt: string;
  };
}

// ---------- Tier Badge ----------
function TierBadge({ tier }: { tier?: string }) {
  const COLORS: Record<string, string> = {
    diamond: 'from-cyan-400 to-blue-500',
    gold: 'from-yellow-400 to-orange-400',
    silver: 'from-zinc-300 to-zinc-400',
    bronze: 'from-orange-700 to-amber-600',
  };
  const ICONS: Record<string, string> = {
    diamond: '💎', gold: '🥇', silver: '🥈', bronze: '🥉'
  };
  const t = (tier || 'bronze').toLowerCase();
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-black uppercase bg-gradient-to-r ${COLORS[t] || COLORS.bronze} text-white shadow-sm`}>
      {ICONS[t] || '🥉'} {t}
    </span>
  );
}

// ---------- KPI Card ----------
function KpiCard({ label, value, sub, accent }: { label: string; value: string | number; sub?: string; accent?: string }) {
  return (
    <div className="quantum-card p-5 rounded-2xl flex flex-col gap-1 relative overflow-hidden group hover:scale-[1.02] transition-transform">
      <div className={`absolute inset-0 opacity-5 group-hover:opacity-10 transition-opacity ${accent || 'bg-brand-primary'} blur-2xl`} />
      <span className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest">{label}</span>
      <span className="text-3xl font-black text-zinc-100 leading-none">{value}</span>
      {sub && <span className="text-[11px] text-zinc-500">{sub}</span>}
    </div>
  );
}

// ---------- Source Badge ----------
function SourceBadge({ source }: { source: string }) {
  const MAP: Record<string, { label: string; color: string }> = {
    W_RALPHE_OMNISCIENT: { label: 'Omniscient', color: 'text-red-400 bg-red-500/10 ring-1 ring-red-500/50' },
    W_GROWTH_AGENT: { label: 'Growth', color: 'text-emerald-400 bg-emerald-500/10' },
    W_REVENUE_INTELLIGENCE: { label: 'Revenue', color: 'text-yellow-400 bg-yellow-500/10' },
    W_ADMIN_AI_AGENT: { label: 'Admin AI', color: 'text-blue-400 bg-blue-500/10' },
    W_FUNNEL_ANALYZER: { label: 'Funnel', color: 'text-purple-400 bg-purple-500/10' },
    MANUAL: { label: 'Manual', color: 'text-zinc-400 bg-zinc-500/10' },
  };
  const s = MAP[source] || { label: source, color: 'text-zinc-400 bg-zinc-500/10' };
  return (
    <span className={`inline-block px-2 py-0.5 rounded-full text-[9px] font-black uppercase ${s.color}`}>{s.label}</span>
  );
}

// ---------- Main Component ----------
export function GrowthAgentView() {
  const [insights, setInsights] = useState<AIInsight[]>([]);
  const [churned, setChurned] = useState<Customer[]>([]);
  const [loading, setLoading] = useState(true);
  const [triggering, setTriggering] = useState<string | null>(null);
  const [lastKpis, setLastKpis] = useState<Record<string, number>>({});

  const fetchData = useCallback(async () => {
    setLoading(true);
    try {
      const [insightsRes, churnedRes] = await Promise.allSettled([
        strapi.get('/api/ai-learnings?sort=generated_at:desc&pagination[limit]=10'),
        strapi.get(
          `/api/customers?sort=updatedAt:asc&pagination[limit]=15&filters[total_spent][$gt]=0&filters[updatedAt][$lte]=${new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()}`
        ),
      ]);

      if (insightsRes.status === 'fulfilled') {
        const data = (insightsRes.value as { data: { data: AIInsight[] } }).data?.data || [];
        setInsights(data);

        // Extract latest KPIs
        const latest = data[0]?.attributes?.metrics_json as Record<string, number> | null;
        if (latest) setLastKpis(latest);
      }

      if (churnedRes.status === 'fulfilled') {
        setChurned((churnedRes.value as { data: { data: Customer[] } }).data?.data || []);
      }
    } catch (e) {
      console.error('GrowthAgentView fetch error:', e);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const triggerAgent = async (agent: string) => {
    setTriggering(agent);
    try {
      // Call n8n webhook to trigger growth agent manually
      const webhookBase = import.meta.env.VITE_N8N_BASE_URL || 'https://n8n.srv1258231.hstgr.cloud';
      await fetch(`${webhookBase}/webhook/${agent}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ trigger: 'manual', timestamp: new Date().toISOString() }),
      });
      // Refresh after 2s to show new insight
      setTimeout(fetchData, 2000);
    } catch (e) {
      console.error(`Failed to trigger ${agent}:`, e);
    } finally {
      setTriggering(null);
    }
  };

  return (
    <div className="p-6 md:p-8 max-w-7xl mx-auto space-y-8">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-black text-zinc-100 flex items-center gap-3">
            <span className="w-10 h-10 rounded-xl bg-gradient-to-br from-emerald-500 to-cyan-500 flex items-center justify-center shadow-lg">
              <TrendingUp size={20} className="text-white" />
            </span>
            Growth Intelligence
          </h1>
          <p className="text-zinc-500 text-sm mt-1">Agents IA autonomes — revenus, fidélité, acquisition</p>
        </div>
        <button
          onClick={fetchData}
          disabled={loading}
          className="flex items-center gap-2 px-4 py-2 rounded-xl bg-white/5 border border-white/10 text-zinc-400 hover:text-zinc-100 hover:bg-white/10 transition-all text-sm font-semibold"
        >
          <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
          Actualiser
        </button>
      </div>

      {/* KPI Strip */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <KpiCard label="Revenus 7j" value={`${lastKpis.totalRevenue?.toLocaleString('fr-FR') || '—'} DA`} sub="Cumul semaine" accent="bg-emerald-500" />
        <KpiCard label="Commandes 7j" value={lastKpis.orderCount || '—'} sub="Total semaine" accent="bg-blue-500" />
        <KpiCard label="Panier Moy." value={lastKpis.avgBasket ? `${lastKpis.avgBasket} DA` : '—'} sub="Par commande" accent="bg-indigo-500" />
        <KpiCard label="Clients Inactifs" value={churned.length} sub=">7j sans commande" accent="bg-orange-500" />
      </div>

      {/* Action Buttons */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[
          { id: 'growth-agent-trigger', label: 'Analyse Growth', icon: Brain, color: 'from-emerald-600 to-cyan-600' },
          { id: 'loyalty-event', label: 'Test Fidélité', icon: Award, color: 'from-yellow-600 to-orange-600' },
          { id: 'revenue-digest', label: 'Digest Revenus', icon: BarChart2, color: 'from-blue-600 to-indigo-600' },
          { id: 'winback-campaign', label: 'Campagne Win-Back', icon: MessageCircle, color: 'from-purple-600 to-pink-600' },
        ].map(({ id, label, icon: Icon, color }) => (
          <button
            key={id}
            onClick={() => triggerAgent(id)}
            disabled={triggering === id}
            className={`flex items-center gap-2 px-4 py-3 rounded-xl bg-gradient-to-r ${color} text-white font-bold text-sm shadow-lg hover:opacity-90 hover:scale-[1.02] transition-all disabled:opacity-50 disabled:cursor-not-allowed`}
          >
            {triggering === id
              ? <RefreshCw size={14} className="animate-spin" />
              : <Icon size={14} />
            }
            {label}
          </button>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* AI Insights Feed */}
        <div className="quantum-card rounded-2xl p-6 space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-base font-black text-zinc-100 flex items-center gap-2">
              <Sparkles size={16} className="text-yellow-400" />
              Insights IA
            </h2>
            <span className="text-[10px] text-zinc-500 font-semibold">{insights.length} insights</span>
          </div>

          {loading ? (
            <div className="space-y-3">
              {[1, 2, 3].map(i => (
                <div key={i} className="h-20 rounded-xl bg-white/5 animate-pulse" />
              ))}
            </div>
          ) : insights.length === 0 ? (
            <div className="text-center py-8">
              <Brain size={32} className="mx-auto text-zinc-700 mb-3" />
              <p className="text-zinc-500 text-sm">Aucun insight disponible</p>
              <p className="text-zinc-600 text-xs mt-1">Déclenche un agent via les boutons ci-dessus</p>
            </div>
          ) : (
            <div className="space-y-3 max-h-80 overflow-y-auto scrollbar-hide">
              {insights.map((ins) => {
                const attr = ins.attributes;
                const date = attr.generated_at
                  ? new Date(attr.generated_at).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
                  : '—';
                return (
                  <div key={ins.id} className="p-4 rounded-xl bg-white/5 border border-white/5 hover:border-emerald-500/20 transition-all group">
                    <div className="flex items-start justify-between gap-2 mb-2">
                      <SourceBadge source={attr.source} />
                      <div className="flex items-center gap-1 text-[10px] text-zinc-600">
                        <Clock size={10} />
                        {date}
                      </div>
                    </div>
                    <p className="text-sm text-zinc-300 leading-relaxed">
                      {attr.insight || 'Insight généré automatiquement'}
                    </p>
                    {attr.recommendations && (
                      <p className="text-xs text-zinc-500 mt-2 line-clamp-2">
                        {attr.recommendations.replace(/\n/g, ' • ')}
                      </p>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Win-Back Queue */}
        <div className="quantum-card rounded-2xl p-6 space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-base font-black text-zinc-100 flex items-center gap-2">
              <Target size={16} className="text-orange-400" />
              File Win-Back
            </h2>
            <span className="text-[10px] text-zinc-500 font-semibold">{churned.length} clients &gt;7j</span>
          </div>

          {loading ? (
            <div className="space-y-2">
              {[1, 2, 3, 4].map(i => (
                <div key={i} className="h-14 rounded-xl bg-white/5 animate-pulse" />
              ))}
            </div>
          ) : churned.length === 0 ? (
            <div className="text-center py-8">
              <Users size={32} className="mx-auto text-zinc-700 mb-3" />
              <p className="text-zinc-500 text-sm">Aucun client inactif 🎉</p>
            </div>
          ) : (
            <div className="space-y-2 max-h-80 overflow-y-auto scrollbar-hide">
              {churned.map((c) => {
                const attr = c.attributes;
                const daysInactive = Math.floor((Date.now() - new Date(attr.updatedAt).getTime()) / (1000 * 60 * 60 * 24));
                return (
                  <div key={c.id} className="flex items-center gap-3 p-3 rounded-xl bg-white/5 hover:bg-orange-500/5 border border-white/5 hover:border-orange-500/20 transition-all group">
                    <div className="w-9 h-9 rounded-full bg-gradient-to-br from-orange-500/30 to-red-500/30 flex items-center justify-center text-sm font-black text-orange-300 flex-shrink-0">
                      {(attr.name || 'C').charAt(0).toUpperCase()}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-bold text-zinc-200 truncate">{attr.name || 'Client'}</p>
                      <div className="flex items-center gap-2 mt-0.5">
                        <span className="text-[10px] text-zinc-500">{attr.phone}</span>
                        <TierBadge tier={attr.loyalty_tier} />
                      </div>
                    </div>
                    <div className="text-right flex-shrink-0">
                      <p className="text-xs font-black text-zinc-300">{(attr.total_spent || 0).toLocaleString('fr-FR')} DA</p>
                      <p className="text-[10px] text-orange-400">{daysInactive}j inactif</p>
                    </div>
                    <ChevronRight size={14} className="text-zinc-600 group-hover:text-orange-400 transition-colors" />
                  </div>
                );
              })}
            </div>
          )}

          {churned.length > 0 && (
            <button
              onClick={() => triggerAgent('growth-agent-trigger')}
              disabled={triggering === 'growth-agent-trigger'}
              className="w-full py-2.5 rounded-xl bg-orange-500/10 border border-orange-500/20 text-orange-400 text-sm font-bold hover:bg-orange-500/20 transition-all flex items-center justify-center gap-2"
            >
              <Send size={13} />
              Lancer campagne WhatsApp ({churned.length} contacts)
            </button>
          )}
        </div>
      </div>

      {/* Active Agent Status */}
      <div className="quantum-card rounded-2xl p-6">
        <h2 className="text-base font-black text-zinc-100 flex items-center gap-2 mb-4">
          <Activity size={16} className="text-blue-400" />
          Agents Actifs
        </h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          {[
            { name: 'W_ADMIN_AI_AGENT', label: 'Admin Intelligence', color: 'bg-blue-500', schedule: 'Webhook' },
            { name: 'W_GROWTH_AGENT', label: 'Growth & Win-Back', color: 'bg-emerald-500', schedule: 'Daily 06:00' },
            { name: 'W_REVENUE_INTELLIGENCE', label: 'Revenue Digest', color: 'bg-yellow-500', schedule: 'Daily 08:00' },
            { name: 'W_LOYALTY_ENGINE', label: 'Loyalty Engine', color: 'bg-purple-500', schedule: 'Webhook' },
          ].map(({ label, color, schedule }) => (
            <div key={label} className="p-4 rounded-xl bg-white/5 border border-white/5 flex flex-col gap-2">
              <div className="flex items-center gap-2">
                <div className={`w-2 h-2 rounded-full ${color} shadow-[0_0_6px_currentColor] animate-pulse`} />
                <span className="text-xs font-bold text-zinc-300 truncate">{label}</span>
              </div>
              <div className="flex items-center gap-1 text-[10px] text-zinc-600">
                <Zap size={9} />
                {schedule}
              </div>
              <div className="flex items-center gap-1">
                <span className="text-[9px] px-1.5 py-0.5 rounded bg-emerald-500/10 text-emerald-400 font-bold">ACTIF</span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Top Products from KPIs */}
      {lastKpis.topDishes && Array.isArray(lastKpis.topDishes) && (lastKpis.topDishes as unknown as Array<{label: string; qty: number; revenue: number}>).length > 0 && (
        <div className="quantum-card rounded-2xl p-6">
          <h2 className="text-base font-black text-zinc-100 flex items-center gap-2 mb-4">
            <ShoppingBag size={16} className="text-pink-400" />
            Top Produits (7 jours)
          </h2>
          <div className="space-y-2">
            {(lastKpis.topDishes as unknown as Array<{label: string; qty: number; revenue: number}>).slice(0, 5).map((dish, i) => {
              const maxRevenue = (lastKpis.topDishes as unknown as Array<{revenue: number}>)[0]?.revenue || 1;
              const pct = Math.round((dish.revenue / maxRevenue) * 100);
              return (
                <div key={i} className="flex items-center gap-3">
                  <span className="text-xs font-black text-zinc-600 w-4">#{i + 1}</span>
                  <span className="text-sm text-zinc-300 flex-1 truncate">{dish.label}</span>
                  <div className="flex-1 h-1.5 rounded-full bg-white/5 overflow-hidden max-w-24">
                    <div
                      className="h-full rounded-full bg-gradient-to-r from-pink-500 to-rose-500 transition-all duration-500"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                  <span className="text-xs font-black text-zinc-400 w-20 text-right">{(dish.revenue / 100).toFixed(0)} DA</span>
                  <span className="text-[10px] text-zinc-600 w-12 text-right">×{dish.qty}</span>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

export default GrowthAgentView;
