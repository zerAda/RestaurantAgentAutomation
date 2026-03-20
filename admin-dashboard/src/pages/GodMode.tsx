import { useState, useEffect, useCallback } from 'react';
import GodModeMap from "@/components/GodModeMap";
import { strapi } from '../services/strapiClient';

// Platform setting key that controls whether the bot accepts new orders.
// This entry must exist in the Strapi platform-settings collection.
const ORDERS_KEY = 'ORDERS_ACCEPTANCE_ENABLED';

interface PlatformSetting {
    id: number;
    attributes: { key: string; value: string };
}

export default function GodMode() {
    const [ordersPaused, setOrdersPaused] = useState(false);
    const [settingId, setSettingId] = useState<number | null>(null);
    const [killLoading, setKillLoading] = useState(false);
    const [statusMsg, setStatusMsg] = useState<string | null>(null);
    const [pendingCount, setPendingCount] = useState<number>(0);

    // Load metrics
    useEffect(() => {
        strapi.find<any>('orders', {
            filters: { status: { $in: ['pending', 'confirmed', 'preparing'] } },
            pagination: { limit: 0 }
        }).then(res => {
            if (res.meta?.pagination) {
                setPendingCount(res.meta.pagination.total);
            }
        }).catch(() => {});
    }, []);

    // Load current orders acceptance status on mount
    useEffect(() => {
        strapi
            .find<PlatformSetting>('platform-settings', {
                filters: { key: { $eq: ORDERS_KEY } },
                pagination: { limit: 1 },
            })
            .then((res) => {
                if (res.data && res.data.length > 0) {
                    const setting = res.data[0] as unknown as { id: number; key: string; value: string };
                    setSettingId(setting.id);
                    // Paused when value is explicitly 'false'
                    setOrdersPaused(setting.value === 'false');
                }
            })
            .catch(() => {
                // Non-blocking: Kill Switch will show an error on click if needed
            });
    }, []);

    const handleKillSwitch = useCallback(async () => {
        const nextPaused = !ordersPaused;
        const action = nextPaused ? 'SUSPENDRE' : 'REPRENDRE';

        if (!window.confirm(`⚠️ Confirmer : ${action} la réception de toutes les commandes ?`)) {
            return;
        }

        if (settingId === null) {
            window.alert(
                `Paramètre "${ORDERS_KEY}" introuvable en base.\n` +
                `Créez-le via le CMS admin (Strapi → Platform Settings) avant d'utiliser le Kill Switch.`
            );
            return;
        }

        setKillLoading(true);
        setStatusMsg(null);
        try {
            await strapi.put(`/api/platform-settings/${settingId}`, {
                value: nextPaused ? 'false' : 'true',
            });
            setOrdersPaused(nextPaused);
            setStatusMsg(
                nextPaused
                    ? '✅ Commandes suspendues. n8n ignorera les nouvelles commandes.'
                    : '✅ Commandes reprises. Le bot accepte à nouveau les commandes.'
            );
        } catch (err) {
            setStatusMsg('❌ Erreur Kill Switch : ' + (err instanceof Error ? err.message : String(err)));
        } finally {
            setKillLoading(false);
        }
    }, [ordersPaused, settingId]);

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
                                <span className="text-yellow-400 font-bold">{pendingCount}</span>
                            </li>
                        </ul>
                    </div>

                    <div className="p-4 rounded-lg bg-red-900/10 border border-red-500/20">
                        <h3 className="text-lg font-semibold text-red-400 mb-1">Panic Zone</h3>
                        <p className="text-xs text-slate-500 mb-3">
                            {ordersPaused
                                ? '🔴 Commandes actuellement SUSPENDUES'
                                : '🟢 Bot accepte les commandes'}
                        </p>
                        <button
                            onClick={handleKillSwitch}
                            disabled={killLoading}
                            className={`w-full py-3 font-bold rounded shadow-lg transition-all active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed ${
                                ordersPaused
                                    ? 'bg-emerald-600 hover:bg-emerald-700 text-white shadow-emerald-900/50'
                                    : 'bg-red-600 hover:bg-red-700 text-white shadow-red-900/50'
                            }`}
                        >
                            {killLoading
                                ? 'En cours...'
                                : ordersPaused
                                ? '▶ REPRENDRE LES COMMANDES'
                                : '⏹ KILL SWITCH (PAUSE ORDERS)'}
                        </button>
                        {statusMsg && (
                            <p className="mt-2 text-xs text-slate-300">{statusMsg}</p>
                        )}
                    </div>
                </div>
            </div>
        </div>
    );
}
