import GodModeMap from "@/components/GodModeMap";

export default function GodMode() {
    return (
        <div className="p-6 space-y-6">
            <div className="flex items-center justify-between">
                <h1 className="text-3xl font-bold tracking-tight text-white glow-sm">GOD MODE</h1>
                <div className="flex gap-2">
                    <span className="px-3 py-1 bg-red-500/20 text-red-400 rounded-full text-xs font-mono border border-red-500/50 animate-pulse">
                        LIVE PRODUCTION
                    </span>
                </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                <div className="lg:col-span-2">
                    <GodModeMap />
                </div>
                <div className="space-y-6">
                    <div className="p-4 rounded-lg bg-slate-900 border border-slate-800">
                        <h3 className="text-lg font-semibold text-slate-200 mb-4">Live Insights</h3>
                        <ul className="space-y-3">
                            <li className="flex justify-between text-sm">
                                <span className="text-slate-400">Rain Prob. (Next 1h)</span>
                                <span className="text-blue-400 font-bold">85%</span>
                            </li>
                            <li className="flex justify-between text-sm">
                                <span className="text-slate-400">Avg. Delivery Time</span>
                                <span className="text-green-400 font-bold">18 min</span>
                            </li>
                            <li className="flex justify-between text-sm">
                                <span className="text-slate-400">Pending Orders</span>
                                <span className="text-yellow-400 font-bold">12</span>
                            </li>
                        </ul>
                    </div>
                    <div className="p-4 rounded-lg bg-red-900/10 border border-red-500/20">
                        <h3 className="text-lg font-semibold text-red-400 mb-2">Panic Zone</h3>
                        <button className="w-full py-3 bg-red-600 hover:bg-red-700 text-white font-bold rounded shadow-lg shadow-red-900/50 transition-all active:scale-95">
                            KILL SWITCH (PAUSE ORDERS)
                        </button>
                    </div>
                </div>
            </div>
        </div>
    );
}
