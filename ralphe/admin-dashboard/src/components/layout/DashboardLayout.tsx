import { useState, useEffect } from "react";
import { Outlet, Link, useLocation } from "react-router-dom";
import {
    LayoutDashboard,
    ShoppingBag,
    Users,
    Settings,
    Menu,
    X,
    ChefHat,
    Search,
    Bell,
    Cpu,
    Zap,
    LifeBuoy
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
    const [scrolled, setScrolled] = useState(false);
    const location = useLocation();

    useEffect(() => {
        const handleScroll = () => setScrolled(window.scrollY > 20);
        window.addEventListener("scroll", handleScroll);
        return () => window.removeEventListener("scroll", handleScroll);
    }, []);

    return (
        <div className="flex h-screen bg-black text-white font-sans overflow-hidden selection:bg-brand-primary/30 selection:text-white">
            {/* Sidebar - Quantum Glass Panel */}
            <aside
                className={cn(
                    "relative h-[calc(100vh-2rem)] my-4 ml-4 rounded-quantum quantum-card w-72 flex-shrink-0 transition-all duration-500 ease-quantum z-30 flex flex-col",
                    !sidebarOpen && "w-0 ml-0 opacity-0 -translate-x-full overflow-hidden"
                )}
            >
                {/* Logo Section */}
                <div className="p-8 flex items-center justify-between">
                    <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-brand-primary to-brand-secondary flex items-center justify-center shadow-quantum-glow">
                            <Zap className="h-6 w-6 text-white fill-white" />
                        </div>
                        <div>
                            <h1 className="text-xl font-black tracking-tight leading-tight">
                                Ralphé <span className="opacity-40 font-medium">OS</span>
                            </h1>
                            <p className="text-[10px] font-bold text-brand-primary tracking-[0.2em] uppercase">Quantum v3.5</p>
                        </div>
                    </div>
                </div>

                {/* Navigation */}
                <nav className="flex-1 px-4 space-y-2 mt-4 overflow-y-auto scrollbar-hide">
                    <p className="px-4 text-[10px] font-bold text-zinc-500 uppercase tracking-widest mb-4">Command Center</p>
                    {NAV_ITEMS.map((item) => {
                        const isActive = location.pathname === item.href;
                        return (
                            <Link
                                key={item.href}
                                to={item.href}
                                className={cn(
                                    "group flex items-center gap-4 px-4 py-3 rounded-quantum-sm text-sm font-semibold transition-all duration-300 relative overflow-hidden",
                                    isActive
                                        ? "nav-item-active"
                                        : "text-zinc-400 hover:bg-white/5 hover:text-white"
                                )}
                            >
                                <item.icon className={cn("h-5 w-5 transition-transform group-hover:scale-110", isActive ? "text-white" : "text-zinc-500")} />
                                {item.label}
                                {isActive && <div className="absolute right-0 top-1/2 -translate-y-1/2 w-1.5 h-6 bg-white rounded-l-full shadow-[0_0_15px_white]" />}
                            </Link>
                        );
                    })}
                </nav>

                {/* System Status Footnote */}
                <div className="p-6 mt-auto">
                    <div className="bg-white/5 rounded-2xl p-4 border border-white/5 space-y-3">
                        <div className="flex items-center justify-between text-[10px] font-bold text-zinc-500 uppercase">
                            <span>System Health</span>
                            <span className="text-success flex items-center gap-1">
                                <span className="status-dot bg-success" /> Optimal
                            </span>
                        </div>
                        <div className="flex items-center gap-3">
                            <Cpu className="h-4 w-4 text-zinc-400" />
                            <div className="flex-1 h-1 bg-white/10 rounded-full overflow-hidden">
                                <div className="h-full bg-brand-primary w-1/3 rounded-full shadow-[0_0_8px_var(--color-brand-primary)]" />
                            </div>
                            <span className="text-[10px] font-mono text-zinc-400">32%</span>
                        </div>
                    </div>

                    <div className="flex items-center gap-4 mt-6 px-2">
                        <div className="h-10 w-10 rounded-full bg-zinc-800 border-2 border-brand-primary/20 p-0.5 shadow-quantum">
                            <img src="https://ui-avatars.com/api/?name=Admin&background=0D0D0D&color=fff" className="w-full h-full rounded-full object-cover" alt="Avatar" />
                        </div>
                        <div className="flex-1 min-w-0">
                            <p className="text-sm font-bold truncate">Master Admin</p>
                            <p className="text-[10px] text-zinc-500 font-medium">Session Active</p>
                        </div>
                        <button className="p-2 rounded-xl hover:bg-white/10 text-zinc-500 hover:text-white transition-colors">
                            <LifeBuoy className="h-4 w-4" />
                        </button>
                    </div>
                </div>
            </aside>

            {/* Main Content Viewport */}
            <div className="flex-1 flex flex-col min-w-0 relative">
                {/* Glossy Header */}
                <header
                    className={cn(
                        "h-20 flex items-center px-8 justify-between z-20 transition-all duration-300",
                        scrolled ? "bg-black/60 backdrop-blur-md border-b border-white/5 shadow-xl" : "bg-transparent"
                    )}
                >
                    <div className="flex items-center gap-6">
                        <button
                            onClick={() => setSidebarOpen(!sidebarOpen)}
                            className="p-2.5 rounded-2xl quantum-glass hover:bg-white/10 text-white transition-all active:scale-90"
                        >
                            {sidebarOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
                        </button>

                        <div className="relative group hidden md:block">
                            <Search className="absolute left-4 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-500 group-focus-within:text-brand-primary transition-colors" />
                            <input
                                type="text"
                                placeholder="Search Command (⌘K)"
                                className="pl-11 pr-4 py-2.5 w-64 rounded-2xl bg-white/5 border border-white/5 focus:border-brand-primary/40 focus:bg-white/10 focus:ring-0 transition-all outline-none text-sm font-medium"
                            />
                        </div>
                    </div>

                    <div className="flex items-center gap-4">
                        <div className="hidden lg:flex flex-col items-end px-4 border-r border-white/5">
                            <p className="text-[10px] font-bold text-zinc-500 uppercase tracking-tighter">Connected Node</p>
                            <p className="text-xs font-mono font-bold text-success select-none">node_srv_1258231</p>
                        </div>

                        <button className="relative p-2.5 rounded-2xl bg-white/5 hover:bg-white/10 border border-white/5 transition-all">
                            <Bell className="h-5 w-5 text-white" />
                            <span className="absolute top-2 right-2 w-2 h-2 bg-red-500 rounded-full border-2 border-black" />
                        </button>

                        <div className="px-4 py-1.5 rounded-full bg-brand-primary/10 border border-brand-primary/30 flex items-center gap-2">
                            <div className="w-1.5 h-1.5 rounded-full bg-brand-primary shadow-[0_0_10px_var(--color-brand-primary)]" />
                            <span className="text-[10px] font-black uppercase tracking-tighter text-brand-primary">Live</span>
                        </div>
                    </div>
                </header>

                <main className="flex-1 overflow-y-auto overflow-x-hidden p-8 scrollbar-hide scroll-smooth">
                    <Outlet />
                </main>
            </div>
        </div>
    );
}
