import { useState, useEffect, useCallback } from 'react';
import { Activity, Zap, ShieldCheck, Cpu, BrainCircuit } from 'lucide-react';
import { strapi } from '../services/strapiClient';
import { cn } from '../lib/utils';

interface CortexData {
  KITCHEN_LOAD?: number;
  SURGE_MULTIPLIER?: number;
  AGENT_STATUS?: Record<string, 'ONLINE' | 'OFFLINE' | 'BUSY'>;
}

export const CortexHub = () => {
  const [data, setData] = useState<CortexData | null>(null);
  const [, setLoading] = useState(true);

  const fetchCortex = useCallback(async () => {
    try {
      const res = await strapi.getCortexData(['KITCHEN_LOAD', 'SURGE_MULTIPLIER', 'AGENT_STATUS']);
      setData(res as CortexData);
    } catch (err) {
      console.error('[CortexHub] Fetch failed:', err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchCortex();
    const interval = setInterval(fetchCortex, 10000);
    return () => clearInterval(interval);
  }, [fetchCortex]);

  const load = data?.KITCHEN_LOAD || 0;
  const surge = data?.SURGE_MULTIPLIER || 1.0;
  const agents = data?.AGENT_STATUS || {
    'OMNISCIENT': 'ONLINE',
    'LOGISTICS': 'ONLINE',
    'GROWTH': 'ONLINE'
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-8">
      {/* Kitchen Load & Surge */}
      <div className="quantum-card p-6 flex flex-col justify-between min-h-[160px] relative overflow-hidden bg-gradient-to-br from-zinc-900/40 to-black/40">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <Activity size={14} className="text-brand-primary" />
            <span className="text-[10px] font-black text-zinc-500 uppercase tracking-widest">Kitchen Capacity</span>
          </div>
          <div className={cn(
            "px-2 py-0.5 rounded text-[8px] font-black uppercase tracking-tighter shadow-lg animate-pulse",
            load > 80 ? "bg-red-500/10 text-red-500 border border-red-500/20" : "bg-success/10 text-success border border-success/20"
          )}>
            {load > 80 ? 'CRITIQUE' : 'OPÉRATIONNEL'}
          </div>
        </div>
        
        <div className="flex items-end justify-between gap-4">
          <div className="flex-1">
            <div className="flex items-baseline gap-2 mb-2">
              <span className="text-4xl font-black text-white tracking-tighter">{load}%</span>
              <span className="text-[10px] font-bold text-zinc-600 uppercase">Utilisation</span>
            </div>
            <div className="h-1.5 w-full bg-white/5 rounded-full overflow-hidden">
              <div 
                className={cn(
                  "h-full transition-all duration-1000 rounded-full",
                  load > 80 ? "bg-red-500 shadow-[0_0_12px_rgba(239,68,68,0.4)]" : "bg-brand-primary shadow-[0_0_12px_rgba(99,102,241,0.4)]"
                )}
                style={{ width: `${load}%` }}
              />
            </div>
          </div>
          
          <div className="flex flex-col items-end">
            <span className="text-[9px] font-black text-zinc-500 uppercase tracking-widest mb-1">Surge</span>
            <div className="px-3 py-1 rounded-xl bg-white/5 border border-white/10 text-brand-primary font-black text-sm italic tracking-tighter shadow-quantum">
              x{surge.toFixed(1)}
            </div>
          </div>
        </div>
      </div>

      {/* Agent Pulse Matrix */}
      <div className="quantum-card p-6 lg:col-span-2 relative overflow-hidden bg-zinc-900/40">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-2">
            <BrainCircuit size={14} className="text-indigo-400" />
            <span className="text-[10px] font-black text-zinc-500 uppercase tracking-widest">Neural Agent Pulse</span>
          </div>
          <div className="flex items-center gap-3">
             <div className="flex items-center gap-1.5">
               <div className="w-1.5 h-1.5 rounded-full bg-success" />
               <span className="text-[8px] font-bold text-zinc-500 uppercase">Active</span>
             </div>
             <div className="flex items-center gap-1.5">
               <div className="w-1.5 h-1.5 rounded-full bg-amber-500" />
               <span className="text-[8px] font-bold text-zinc-500 uppercase">Thinking</span>
             </div>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-6">
          {Object.entries(agents).map(([name, status]) => (
            <div key={name} className="flex flex-col gap-3 group">
              <div className="flex items-center gap-3">
                <div className={cn(
                  "w-8 h-8 rounded-xl flex items-center justify-center border transition-all duration-500",
                  status === 'ONLINE' ? "bg-success/5 border-success/20 text-success shadow-[0_0_10px_rgba(16,185,129,0.1)] group-hover:shadow-[0_0_20px_rgba(16,185,129,0.2)]" :
                  status === 'BUSY' ? "bg-amber-500/5 border-amber-500/20 text-amber-500 shadow-[0_0_10px_rgba(245,158,11,0.1)]" :
                  "bg-zinc-800 border-zinc-700 text-zinc-500"
                )}>
                  {name === 'OMNISCIENT' ? <ShieldCheck size={16} /> : name === 'LOGISTICS' ? <Zap size={16} /> : <Cpu size={16} />}
                </div>
                <div className="min-w-0">
                  <div className="text-[10px] font-black text-white tracking-wide truncate">{name}</div>
                  <div className="text-[8px] font-bold text-zinc-500 uppercase tracking-widest flex items-center gap-1">
                    <span className={cn(
                      "w-1 h-1 rounded-full",
                      status === 'ONLINE' ? "bg-success" : status === 'BUSY' ? "bg-amber-500" : "bg-zinc-700"
                    )} />
                    {status === 'ONLINE' ? 'Optimal' : status === 'BUSY' ? 'Processing' : 'Idle'}
                  </div>
                </div>
              </div>
              <div className="h-0.5 w-full bg-white/5 rounded-full relative overflow-hidden">
                 {status === 'ONLINE' && <div className="absolute inset-0 bg-success/20 animate-pulse" />}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
