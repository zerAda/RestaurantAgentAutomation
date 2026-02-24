import { ShoppingBag, Users, DollarSign, Clock } from "lucide-react";
import { cn } from "@/lib/utils";

interface KPICardProps {
    title: string;
    value: string;
    change: number;
    icon: React.ElementType;
    className?: string;
}

const KPICard = ({ title, value, change, icon: Icon, className }: KPICardProps) => (
    <div className={cn("bg-white p-6 rounded-xl border border-gray-200 shadow-sm", className)}>
        <div className="flex items-center justify-between mb-4">
            <div className="p-2 bg-slate-50 rounded-lg">
                <Icon className="h-5 w-5 text-slate-600" />
            </div>
            <span className={cn("text-xs font-medium px-2 py-1 rounded-full", change > 0 ? "bg-green-50 text-green-700" : "bg-red-50 text-red-700")}>
                {change > 0 ? "+" : ""}{change}%
            </span>
        </div>
        <h3 className="text-2xl font-bold text-gray-900">{value}</h3>
        <p className="text-sm text-gray-500 mt-1">{title}</p>
    </div>
);

export default function DashboardHome() {
    return (
        <div className="space-y-6">
            <div className="flex items-center justify-between">
                <h2 className="text-2xl font-bold text-gray-900">Vue d'ensemble</h2>
                <div className="flex gap-2">
                    <button className="px-4 py-2 bg-slate-900 text-white text-sm font-medium rounded-lg hover:bg-slate-800 transition">
                        Actualiser
                    </button>
                </div>
            </div>

            {/* KPI Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                <KPICard title="Chiffre d'Affaires (Jour)" value="24,500 DA" change={12} icon={DollarSign} />
                <KPICard title="Commandes Actives" value="8" change={5} icon={ShoppingBag} />
                <KPICard title="Temps Moyen (Prep)" value="18 min" change={-2} icon={Clock} />
                <KPICard title="Clients Actifs" value="142" change={8} icon={Users} />
            </div>

            {/* Charts Section Placeholder */}
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 h-96">
                <div className="lg:col-span-2 bg-white rounded-xl border border-gray-200 p-6 shadow-sm flex items-center justify-center text-gray-400">
                    Chart: Revenus (Semaine)
                </div>
                <div className="bg-white rounded-xl border border-gray-200 p-6 shadow-sm flex items-center justify-center text-gray-400">
                    Chart: Top Produits
                </div>
            </div>
        </div>
    );
}
