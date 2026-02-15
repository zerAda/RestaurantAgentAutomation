import { useState } from "react";
import { Outlet, Link, useLocation } from "react-router-dom";
import {
    LayoutDashboard,
    ShoppingBag,
    Users,
    Settings,
    Menu,
    X,
    ChefHat
} from "lucide-react";
import { cn } from "@/lib/utils";

const NAV_ITEMS = [
    { label: "Dashboard", href: "/", icon: LayoutDashboard },
    { label: "Commandes", href: "/orders", icon: ShoppingBag },
    { label: "Menu", href: "/menu", icon: ChefHat },
    { label: "Livreurs", href: "/drivers", icon: Users },
    { label: "Paramètres", href: "/settings", icon: Settings },
];

export default function DashboardLayout() {
    const [sidebarOpen, setSidebarOpen] = useState(true);
    const location = useLocation();

    return (
        <div className="flex h-screen bg-gray-100 text-gray-900 font-sans overflow-hidden">
            {/* Sidebar */}
            <aside
                className={cn(
                    "bg-white border-r border-gray-200 w-64 flex-shrink-0 transition-all duration-300 absolute inset-y-0 left-0 z-20 md:relative md:translate-x-0",
                    !sidebarOpen && "-translate-x-full md:w-0 md:opacity-0 md:overflow-hidden"
                )}
            >
                <div className="p-6 flex items-center justify-between">
                    <h1 className="text-2xl font-bold tracking-tight text-primary-600">
                        Resto<span className="text-gray-900">Bot</span>
                    </h1>
                    <button onClick={() => setSidebarOpen(false)} className="md:hidden">
                        <X className="h-6 w-6" />
                    </button>
                </div>

                <nav className="px-4 space-y-1">
                    {NAV_ITEMS.map((item) => {
                        const isActive = location.pathname === item.href;
                        return (
                            <Link
                                key={item.href}
                                to={item.href}
                                className={cn(
                                    "flex items-center gap-3 px-4 py-3 rounded-lg text-sm font-medium transition-colors",
                                    isActive
                                        ? "bg-slate-900 text-white shadow-md"
                                        : "text-gray-600 hover:bg-gray-100 hover:text-gray-900"
                                )}
                            >
                                <item.icon className="h-5 w-5" />
                                {item.label}
                            </Link>
                        );
                    })}
                </nav>

                <div className="absolute bottom-4 left-4 right-4 bg-slate-50 p-4 rounded-xl border border-gray-200">
                    <div className="flex items-center gap-3">
                        <div className="h-8 w-8 rounded-full bg-green-500 flex items-center justify-center text-white font-bold text-xs">
                            OP
                        </div>
                        <div>
                            <p className="text-xs font-semibold text-gray-900">Admin</p>
                            <p className="text-[10px] text-green-600 font-medium">● En ligne</p>
                        </div>
                    </div>
                </div>
            </aside>

            {/* Main Content */}
            <div className="flex-1 flex flex-col min-w-0">
                <header className="bg-white border-b border-gray-200 h-16 flex items-center px-6 justify-between flex-shrink-0">
                    <button
                        onClick={() => setSidebarOpen(!sidebarOpen)}
                        className="p-2 rounded-md hover:bg-gray-100"
                    >
                        <Menu className="h-5 w-5 text-gray-600" />
                    </button>

                    <div className="flex items-center gap-4">
                        <span className="text-sm text-gray-500 bg-gray-100 px-3 py-1 rounded-full border border-gray-200">
                            v3.2.4 (Diamond)
                        </span>
                    </div>
                </header>

                <main className="flex-1 overflow-auto p-6">
                    <Outlet />
                </main>
            </div>
        </div>
    );
}
