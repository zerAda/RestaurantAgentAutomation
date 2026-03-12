import { useState, useEffect } from 'react';
import { Activity, Database, HardDrive, Cpu, Settings, ExternalLink, Zap } from 'lucide-react';

interface SystemStatus {
    status: string;
    timestamp: string;
    services: {
        database: { status: string; provider: string };
        redis: { status: string; connections: number };
        n8n_hypervisor: { status: string; active_executions: number; queued_executions: number };
    };
    system: {
        os: string;
        uptime_seconds: number;
        load_average: number[];
        memory: { total_gb: string; used_gb: string; percent_used: string };
    };
}

export const ControlPlaneView = () => {
    const [data, setData] = useState<SystemStatus | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        const fetchStatus = async () => {
            try {
                const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || '';
                const response = await fetch(`${STRAPI_URL}/api/control-plane/status`);
                if (!response.ok) throw new Error('API unreachable');
                const json = await response.json();
                setData(json);
            } catch (err: any) {
                setError(err.message);
            } finally {
                setLoading(false);
            }
        };

        fetchStatus();
        const interval = setInterval(fetchStatus, 15000); // refresh every 15s
        return () => clearInterval(interval);
    }, []);

    if (loading && !data) return <div className="p-8 text-zinc-500 animate-pulse">Initializing Interface...</div>;
    if (error) return <div className="p-8 text-red-500 bg-red-50 dark:bg-red-950/20 rounded-xl my-4">Error loading telemetry: {error}</div>;
    if (!data) return null;

    return (
        <div className="p-8 max-w-7xl mx-auto space-y-8 animate-in fade-in duration-500">
            <div className="flex justify-between items-end">
                <div>
                    <h1 className="text-3xl font-bold tracking-tight text-transparent bg-clip-text bg-gradient-to-r from-zinc-900 to-zinc-500 dark:from-white dark:to-zinc-400">Ralphé Control Plane</h1>
                    <p className="text-zinc-500 mt-2">Operational telemetry & container orchestration health</p>
                </div>
                <div className="flex items-center gap-3">
                    <div className="relative flex h-3 w-3">
                        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                        <span className="relative inline-flex rounded-full h-3 w-3 bg-emerald-500"></span>
                    </div>
                    <span className="text-sm font-medium text-emerald-600 dark:text-emerald-400 uppercase tracking-widest">{data.status}</span>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                <StatusCard
                    title="PostgreSQL"
                    value={data.services.database.status}
                    subValue={data.services.database.provider}
                    icon={<Database size={20} />}
                    status={data.services.database.status === 'healthy' ? 'success' : 'danger'}
                />
                <StatusCard
                    title="Redis Outbox"
                    value={data.services.redis.status}
                    subValue={`${data.services.redis.connections} connections`}
                    icon={<Zap size={20} />}
                    status={data.services.redis.status === 'healthy' ? 'success' : 'warning'}
                />
                <StatusCard
                    title="n8n Hypervisor"
                    value={`${data.services.n8n_hypervisor.active_executions} Active`}
                    subValue={`${data.services.n8n_hypervisor.queued_executions} Queued`}
                    icon={<Activity size={20} />}
                    status="success"
                />
                <StatusCard
                    title="System Memory"
                    value={`${data.system.memory.percent_used}%`}
                    subValue={`${data.system.memory.used_gb} / ${data.system.memory.total_gb} GB`}
                    icon={<HardDrive size={20} />}
                    status={parseFloat(data.system.memory.percent_used) > 85 ? 'warning' : 'success'}
                />
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                <div className="lg:col-span-2 bg-white dark:bg-zinc-900/50 border border-zinc-200 dark:border-zinc-800 rounded-3xl p-6 shadow-sm">
                    <div className="flex justify-between items-center mb-6">
                        <h3 className="font-bold">Process Load Matrix</h3>
                        <Cpu size={18} className="text-zinc-400" />
                    </div>
                    <div className="space-y-4">
                        <div>
                            <div className="flex justify-between text-sm mb-1">
                                <span className="text-zinc-500">Node 1m Load Average</span>
                                <span className="font-mono">{data.system.load_average[0].toFixed(2)}</span>
                            </div>
                            <div className="h-2 bg-zinc-100 dark:bg-zinc-800 rounded-full overflow-hidden">
                                <div className="h-full bg-indigo-500 rounded-full transition-all duration-1000" style={{ width: `${Math.min(data.system.load_average[0] * 10, 100)}%` }} />
                            </div>
                        </div>
                        <div>
                            <div className="flex justify-between text-sm mb-1">
                                <span className="text-zinc-500">Node 5m Load Average</span>
                                <span className="font-mono">{data.system.load_average[1].toFixed(2)}</span>
                            </div>
                            <div className="h-2 bg-zinc-100 dark:bg-zinc-800 rounded-full overflow-hidden">
                                <div className="h-full bg-indigo-400 rounded-full transition-all duration-1000" style={{ width: `${Math.min(data.system.load_average[1] * 10, 100)}%` }} />
                            </div>
                        </div>
                    </div>
                </div>

                <div className="bg-zinc-900 text-white rounded-3xl p-6 flex flex-col justify-between overflow-hidden relative shadow-lg shadow-black/20">
                    <div className="relative z-10">
                        <h3 className="font-bold flex items-center gap-2 text-zinc-300">
                            <Settings size={18} /> Portainer
                        </h3>
                        <p className="text-sm mt-3 text-zinc-400 leading-relaxed">
                            Manage containers, volumes, and swarm network directly via graphical UI.
                        </p>
                    </div>
                    <a href="#" className="mt-8 flex items-center justify-between text-sm font-medium hover:text-indigo-400 transition-colors relative z-10">
                        Open Orchestrator
                        <ExternalLink size={16} />
                    </a>
                    <div className="absolute -bottom-10 -right-10 text-zinc-800/30">
                        <Settings size={120} />
                    </div>
                </div>
            </div>
        </div>
    );
};

const StatusCard = ({ title, value, subValue, icon, status }: any) => {
    const colors = {
        success: 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border-emerald-500/20',
        warning: 'bg-amber-500/10 text-amber-600 dark:text-amber-400 border-amber-500/20',
        danger: 'bg-red-500/10 text-red-600 dark:text-red-400 border-red-500/20',
    };

    return (
        <div className={`p-6 rounded-3xl border ${colors[status]} flex flex-col justify-between h-40 transition-all hover:shadow-lg`}>
            <div className="flex justify-between items-start">
                <span className="font-medium opacity-80">{title}</span>
                <div className="p-2 rounded-xl bg-white/50 dark:bg-black/20 backdrop-blur-sm">
                    {icon}
                </div>
            </div>
            <div>
                <div className="text-2xl font-bold uppercase tracking-tight">{value}</div>
                <div className="text-xs mt-1 opacity-70 font-mono tracking-wider">{subValue}</div>
            </div>
        </div>
    );
};
