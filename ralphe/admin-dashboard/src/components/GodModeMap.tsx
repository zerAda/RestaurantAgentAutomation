import { useEffect, useRef, useState } from "react";
import { Maximize2, Crosshair, Users, Activity, Map as MapIcon, ShieldCheck } from "lucide-react";

/* ── Types ── */
interface Driver {
    id: number;
    name: string;
    x: number;
    y: number;
    color: string;
    status: 'online' | 'busy' | 'offline';
}

export default function GodModeMap() {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const [stats] = useState({ online: 12, busy: 4, latency: '14ms' });

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;
        const ctx = canvas.getContext("2d");
        if (!ctx) return;

        let animationFrameId: number;
        let t = 0;

        const drivers: Driver[] = [
            { id: 1, name: 'DZ-01', x: 150, y: 120, color: '#10b981', status: 'online' },
            { id: 2, name: 'DZ-09', x: 280, y: 180, color: '#f59e0b', status: 'busy' },
            { id: 3, name: 'DZ-04', x: 400, y: 350, color: '#ef4444', status: 'offline' },
            { id: 4, name: 'DZ-12', x: 120, y: 400, color: '#10b981', status: 'online' },
            { id: 5, name: 'DZ-22', x: 500, y: 150, color: '#10b981', status: 'online' },
        ];

        const render = () => {
            t += 0.008;

            // Deep Space Clear
            ctx.fillStyle = "#030303";
            ctx.fillRect(0, 0, canvas.width, canvas.height);

            // Quantum Grid (3D perspective sim)
            ctx.strokeStyle = "rgba(255,255,255,0.03)";
            ctx.lineWidth = 1;
            ctx.beginPath();
            for (let i = 0; i < canvas.width; i += 40) {
                ctx.moveTo(i, 0);
                ctx.lineTo(i, canvas.height);
            }
            for (let i = 0; i < canvas.height; i += 40) {
                ctx.moveTo(0, i);
                ctx.lineTo(canvas.width, i);
            }
            ctx.stroke();

            // Tactical Overlay - Radial Mesh
            ctx.strokeStyle = "rgba(255,51,102,0.05)";
            ctx.beginPath();
            ctx.arc(canvas.width / 2, canvas.height / 2, 200 + Math.sin(t) * 20, 0, Math.PI * 2);
            ctx.stroke();

            // Drivers
            drivers.forEach(d => {
                const dx = Math.sin(t + d.id) * 15;
                const dy = Math.cos(t + d.id) * 15;
                const posX = d.x + dx;
                const posY = d.y + dy;

                // Glow Path
                const gradient = ctx.createRadialGradient(posX, posY, 0, posX, posY, 20);
                gradient.addColorStop(0, `${d.color}33`);
                gradient.addColorStop(1, 'transparent');
                ctx.fillStyle = gradient;
                ctx.beginPath();
                ctx.arc(posX, posY, 20, 0, Math.PI * 2);
                ctx.fill();

                // Core Node
                ctx.beginPath();
                ctx.arc(posX, posY, 5, 0, Math.PI * 2);
                ctx.fillStyle = d.color;
                ctx.fill();
                ctx.strokeStyle = "#fff";
                ctx.lineWidth = 2;
                ctx.stroke();

                // Pulse Ring
                ctx.beginPath();
                ctx.arc(posX, posY, 8 + Math.sin(t * 4) * 4, 0, Math.PI * 2);
                ctx.strokeStyle = d.color;
                ctx.lineWidth = 1;
                ctx.globalAlpha = 0.4;
                ctx.stroke();
                ctx.globalAlpha = 1;

                // Label Matrix
                ctx.fillStyle = "rgba(255,255,255,0.8)";
                ctx.font = "bold 9px monospace";
                ctx.fillText(d.name, posX + 15, posY - 10);
                ctx.fillStyle = "rgba(255,255,255,0.4)";
                ctx.fillText(`${Math.round(posX)}, ${Math.round(posY)}`, posX + 15, posY + 2);
            });

            animationFrameId = requestAnimationFrame(render);
        };

        render();
        return () => cancelAnimationFrame(animationFrameId);
    }, []);

    return (
        <div className="quantum-card h-[600px] relative overflow-hidden group">
            {/* Tactical Header Overlay */}
            <div className="absolute top-0 left-0 right-0 p-8 z-10 flex justify-between items-start pointer-events-none">
                <div className="flex items-center gap-4">
                    <div className="w-12 h-12 rounded-2xl bg-brand-primary/20 text-brand-primary flex items-center justify-center border border-brand-primary/20 shadow-lg backdrop-blur-xl">
                        <Crosshair size={24} className="animate-spin-slow" />
                    </div>
                    <div className="pointer-events-auto">
                        <h4 className="text-xl font-black text-white tracking-widest italic uppercase leading-none">God Mode Tactical</h4>
                        <div className="flex items-center gap-3 mt-2">
                            <div className="flex items-center gap-1.5 px-2 py-0.5 rounded bg-success/10 border border-success/20">
                                <span className="w-1.5 h-1.5 rounded-full bg-success animate-pulse" />
                                <span className="text-[8px] font-black text-success uppercase">Active Matrix</span>
                            </div>
                            <span className="text-[9px] font-bold text-zinc-500 uppercase tracking-widest italic">Algiers Sector: 4.2.0</span>
                        </div>
                    </div>
                </div>

                <div className="flex gap-2 pointer-events-auto">
                    <button className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-zinc-500 hover:text-white transition-all backdrop-blur-md">
                        <MapIcon size={18} />
                    </button>
                    <button className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-zinc-500 hover:text-white transition-all backdrop-blur-md">
                        <Maximize2 size={18} />
                    </button>
                </div>
            </div>

            {/* Live Data Widgets Overlay */}
            <div className="absolute bottom-8 left-8 right-8 z-10 flex justify-between items-end pointer-events-none">
                <div className="flex gap-4 pointer-events-auto">
                    {[
                        { label: 'Active Drivers', value: stats.online, icon: Users, color: 'text-success' },
                        { label: 'Surge Multiplier', value: '1.25x', icon: Activity, color: 'text-warning' },
                        { label: 'Avg Dispatch', value: '1.2m', icon: Crosshair, color: 'text-brand-primary' },
                        { label: 'Fleet Integrity', value: 'Optimal', icon: ShieldCheck, color: 'text-success' },
                    ].map((w, i) => (
                        <div key={i} className="px-6 py-4 rounded-2xl bg-black/60 border border-white/10 backdrop-blur-xl shadow-2xl flex flex-col items-start min-w-[140px]">
                            <div className="flex items-center gap-2 mb-2">
                                <w.icon size={12} className={w.color} />
                                <span className="text-[9px] font-black text-zinc-500 uppercase tracking-widest">{w.label}</span>
                            </div>
                            <span className="text-xl font-black text-white italic tracking-tighter">{w.value}</span>
                        </div>
                    ))}
                </div>

                <div className="pointer-events-auto flex flex-col items-end gap-2">
                    <div className="px-4 py-2 rounded-xl bg-brand-primary text-black font-black text-[10px] tracking-widest uppercase italic shadow-lg shadow-brand-primary/20">
                        Signal: Optimal
                    </div>
                    <span className="text-[9px] font-bold text-zinc-700 uppercase tracking-widest">Neural Link v4.2 stable</span>
                </div>
            </div>

            {/* Cinematic Canvas Background */}
            <canvas
                ref={canvasRef}
                width={1200}
                height={800}
                className="w-full h-full object-cover transition-transform duration-1000 group-hover:scale-110"
            />

            {/* Vignette Overlay */}
            <div className="absolute inset-0 pointer-events-none shadow-[inset_0_0_150px_rgba(0,0,0,0.8)]" />
        </div>
    );
}
