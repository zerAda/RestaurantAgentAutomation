import { useState, useEffect } from "react";
import { Card, CardHeader, CardContent, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Clock, Flame, CheckCircle } from "lucide-react";

// Mock Data representing the "Symphony" logic
// Items are sorted by "Start Cooking At" time, not Order Time.
const MOCK_KITCHEN_QUEUE = [
    { id: "k1", orderId: "101", item: "Burger Ralphé", status: "PENDING", startAt: "12:05", eta: "12:15", station: "GRILL" },
    { id: "k2", orderId: "102", item: "Frites Maison", status: "PENDING", startAt: "12:10", eta: "12:15", station: "FRYER" }, // Starts later to be fresh
    { id: "k3", orderId: "103", item: "Pizza 4F", status: "COOKING", startAt: "12:00", eta: "12:12", station: "OVEN" },
];

export default function KitchenDisplay() {
    const [currentTime, setCurrentTime] = useState(new Date());

    useEffect(() => {
        const timer = setInterval(() => setCurrentTime(new Date()), 1000);
        return () => clearInterval(timer);
    }, []);

    const formatTime = (date: Date) => {
        return date.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
    };

    return (
        <div className="p-6 bg-slate-950 min-h-screen text-white">
            <div className="flex justify-between items-center mb-8">
                <h1 className="text-3xl font-bold flex items-center gap-3">
                    <Flame className="text-orange-500" />
                    KITCHEN SYMPHONY
                </h1>
                <div className="text-4xl font-mono font-bold text-slate-400">
                    {formatTime(currentTime)}
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                {/* STATION: GRILL */}
                <KitchenStation title="🔥 STATION GRILL" station="GRILL" items={MOCK_KITCHEN_QUEUE.filter(i => i.station === 'GRILL')} />

                {/* STATION: FRYER */}
                <KitchenStation title="🍟 STATION FRYER" station="FRYER" items={MOCK_KITCHEN_QUEUE.filter(i => i.station === 'FRYER')} />

                {/* STATION: OVEN */}
                <KitchenStation title="🍕 STATION OVEN" station="OVEN" items={MOCK_KITCHEN_QUEUE.filter(i => i.station === 'OVEN')} />
            </div>
        </div>
    );
}

interface KitchenItem {
    id: string;
    orderId: string;
    item: string;
    status: string;
    startAt: string;
    eta: string;
    station: string;
}

function KitchenStation({ title, station, items }: { title: string, station: string, items: KitchenItem[] }) {
    return (
        <div className="bg-slate-900 rounded-xl p-4 border border-slate-800" aria-label={`Station ${station}`}>
            <h2 className="text-xl font-bold mb-4 text-slate-300 border-b border-slate-800 pb-2">{title}</h2>
            <div className="space-y-4">
                {items.length === 0 && <p className="text-slate-600 italic">Aucune commande.</p>}
                {items.map(item => (
                    <Card key={item.id} className="bg-slate-800 border-none shadow-lg">
                        <CardHeader className="pb-2">
                            <div className="flex justify-between items-start">
                                <Badge variant="outline" className="text-slate-400 border-slate-600">#{item.orderId}</Badge>
                                <span className={`text-sm font-mono px-2 py-1 rounded ${item.status === 'COOKING' ? 'bg-orange-500/20 text-orange-400 animate-pulse' : 'bg-blue-500/20 text-blue-400'}`}>
                                    Start: {item.startAt}
                                </span>
                            </div>
                            <CardTitle className="text-white text-lg mt-1">{item.item}</CardTitle>
                        </CardHeader>
                        <CardContent>
                            <div className="flex justify-between items-center mt-2">
                                <div className="text-xs text-slate-500 flex items-center gap-1">
                                    <Clock className="w-3 h-3" /> Target: {item.eta}
                                </div>
                                <button className="p-2 bg-green-600 hover:bg-green-700 rounded-full transition-colors">
                                    <CheckCircle className="w-5 h-5 text-white" />
                                </button>
                            </div>
                        </CardContent>
                    </Card>
                ))}
            </div>
        </div>
    );
}
