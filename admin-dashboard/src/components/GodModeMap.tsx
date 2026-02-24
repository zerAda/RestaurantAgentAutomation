import { useEffect, useRef } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

// Mocking a 3D Map view using HTML5 Canvas for now
// In real prod, would use Mapbox GL JS or Leaflet with WebGL

export default function GodModeMap() {
    const canvasRef = useRef<HTMLCanvasElement>(null);

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;
        const ctx = canvas.getContext("2d");
        if (!ctx) return;

        let animationFrameId: number;
        let t = 0;

        const drivers = [
            { id: 1, x: 100, y: 100, color: '#4ade80' }, // Green (Online)
            { id: 2, x: 200, y: 150, color: '#facc15' }, // Yellow (Busy)
            { id: 3, x: 300, y: 300, color: '#f87171' }, // Red (Offline)
        ];

        const render = () => {
            t += 0.01;

            // Clear
            ctx.fillStyle = "#0f172a"; // Slate 900
            ctx.fillRect(0, 0, canvas.width, canvas.height);

            // Draw Grid (3D effect simulation)
            ctx.strokeStyle = "#1e293b";
            ctx.beginPath();
            for (let i = 0; i < canvas.width; i += 50) {
                ctx.moveTo(i, 0);
                ctx.lineTo(i, canvas.height);
            }
            for (let i = 0; i < canvas.height; i += 50) {
                ctx.moveTo(0, i);
                ctx.lineTo(canvas.width, i);
            }
            ctx.stroke();

            // Draw Drivers (pulsing dots)
            drivers.forEach(d => {
                // Animate movement slightly
                const dx = Math.sin(t + d.id) * 20;
                const dy = Math.cos(t + d.id) * 20;

                ctx.beginPath();
                ctx.arc(d.x + dx, d.y + dy, 8, 0, Math.PI * 2);
                ctx.fillStyle = d.color;
                ctx.fill();

                // Pulse ring
                ctx.beginPath();
                ctx.arc(d.x + dx, d.y + dy, 12 + Math.sin(t * 5) * 4, 0, Math.PI * 2);
                ctx.strokeStyle = d.color;
                ctx.globalAlpha = 0.5;
                ctx.stroke();
                ctx.globalAlpha = 1;

                // Label
                ctx.fillStyle = "white";
                ctx.font = "12px sans-serif";
                ctx.fillText(`Driver ${d.id}`, d.x + dx + 15, d.y + dy + 4);
            });

            animationFrameId = requestAnimationFrame(render);
        };

        render();

        return () => {
            cancelAnimationFrame(animationFrameId);
        };
    }, []);

    return (
        <Card className="w-full h-[600px] border-none shadow-2xl bg-slate-950">
            <CardHeader className="absolute z-10 top-0 left-0">
                <CardTitle className="text-white flex items-center gap-2">
                    <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />
                    GOD MODE VIEW (ALGIERS)
                </CardTitle>
            </CardHeader>
            <CardContent className="p-0 h-full">
                <canvas
                    ref={canvasRef}
                    width={800}
                    height={600}
                    className="w-full h-full object-cover rounded-lg"
                />
            </CardContent>
        </Card>
    );
}
