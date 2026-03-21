import { motion } from "framer-motion";
import { Languages, ArrowRight } from "lucide-react";
import { type Language, setPageDirection } from "../utils/i18n";
import { cn } from "@/lib/utils";

interface LanguageSelectorProps {
    currentLang: Language;
    onSelect: (lang: Language) => void;
    onClose: () => void;
}

const LAN_OPTIONS: { id: Language; label: string; sub: string; flag: string }[] = [
    { id: 'fr', label: 'Français', sub: 'Région Maghreb', flag: '🇫🇷' },
    { id: 'ar', label: 'العربية', sub: 'المنطقة الإقليمية', flag: '🇩🇿' },
    { id: 'en', label: 'English', sub: 'Global Matrix', flag: '🇬🇧' },
];

export default function LanguageSelector({ currentLang, onSelect, onClose }: LanguageSelectorProps) {

    const handleSelect = (lang: Language) => {
        setPageDirection(lang);
        onSelect(lang);
        setTimeout(onClose, 400); // Smooth transition escape
    };

    return (
        <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[200] bg-black/60 backdrop-blur-3xl flex items-center justify-center p-12"
        >
            <div className="absolute inset-0 z-0 opacity-20">
                <div className="absolute top-0 left-0 w-full h-full bg-[radial-gradient(circle_at_center,_var(--brand-primary)_0%,_transparent_70%)] blur-[120px]" />
            </div>

            <motion.div
                initial={{ scale: 0.9, y: 20, opacity: 0 }}
                animate={{ scale: 1, y: 0, opacity: 1 }}
                exit={{ scale: 1.1, opacity: 0 }}
                className="w-full max-w-4xl quantum-card p-16 relative z-10 text-center"
            >
                <div className="w-24 h-24 mx-auto rounded-3xl bg-brand-primary/10 border border-brand-primary/20 flex items-center justify-center text-brand-primary mb-12">
                    <Languages size={48} />
                </div>

                <h2 className="text-7xl font-black uppercase italic tracking-tighter leading-none mb-4 text-white">
                    Select <span className="text-brand-primary">Linguistic</span> Core
                </h2>
                <p className="text-zinc-500 text-xs font-black uppercase tracking-[0.5em] italic mb-16">
                    Establish neural communication parameters for this interaction cycle.
                </p>

                <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
                    {LAN_OPTIONS.map((opt) => {
                        const active = currentLang === opt.id;
                        return (
                            <button
                                key={opt.id}
                                onClick={() => handleSelect(opt.id)}
                                className={cn(
                                    "p-10 rounded-[3rem] border-2 transition-all flex flex-col items-center gap-4 group relative overflow-hidden",
                                    active
                                        ? "bg-white text-black border-transparent shadow-[0_0_60px_rgba(255,255,255,0.1)] scale-105"
                                        : "bg-white/5 border-white/5 text-zinc-500 hover:bg-white/10 hover:scale-102"
                                )}
                            >
                                <span className="text-5xl mb-2 group-hover:scale-125 transition-transform duration-500">{opt.flag}</span>
                                <div className="space-y-1">
                                    <span className="text-3xl font-black uppercase italic tracking-tighter block">{opt.label}</span>
                                    <span className={cn("text-[9px] font-black uppercase tracking-widest block opacity-60", active ? "text-zinc-500" : "text-zinc-600")}>
                                        {opt.sub}
                                    </span>
                                </div>
                                {active && (
                                    <motion.div
                                        layoutId="active-indicator"
                                        className="absolute bottom-6 right-6 w-8 h-8 rounded-full bg-black flex items-center justify-center"
                                    >
                                        <ArrowRight size={16} className="text-white" />
                                    </motion.div>
                                )}
                            </button>
                        );
                    })}
                </div>

                <div className="mt-20 pt-10 border-t border-white/5">
                    <p className="text-[9px] font-black text-zinc-600 uppercase tracking-[0.3em] italic">
                        Ralphé Kiosk OS — v. 4.0.0.1 Quantum DNA
                    </p>
                </div>
            </motion.div>
        </motion.div>
    );
}
