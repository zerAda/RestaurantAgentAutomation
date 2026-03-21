import { useState } from 'react';
import { authService } from '../services/authService';
import { Mail, Lock, ShieldCheck, Loader2, ArrowRight, Fingerprint } from 'lucide-react';
import { cn } from '../lib/utils';

export function LoginView({ onLogin }: { onLogin: () => void }) {
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!email.trim() || !password.trim()) {
            setError('Neural link requires full credentials');
            return;
        }
        setLoading(true);
        setError('');

        const success = await authService.login(email, password);
        if (success) {
            onLogin();
        } else {
            setError('Access Denied: Genetic match failed');
            setPassword('');
        }
        setLoading(false);
    };

    return (
        <div className="min-h-screen bg-black flex items-center justify-center p-6 font-sans relative overflow-hidden">
            {/* Unified Quantum Backdrop */}
            <div className="quantum-backdrop">
                <div className="quantum-glow-halo top-[-10%] left-[-10%] w-[50%] h-[50%] bg-brand-primary/10 animate-pulse-subtle" />
                <div className="quantum-glow-halo bottom-[-10%] right-[-10%] w-[60%] h-[60%] bg-indigo-500/10 animate-pulse-subtle delay-1000" />
                <div className="grain-overlay" />
            </div>

            <div className="w-full max-w-lg animate-in fade-in zoom-in duration-1000 slide-in-from-bottom-12">
                <div className="quantum-card p-12 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-10 opacity-[0.03] rotate-12">
                        <Fingerprint size={160} className="text-white" />
                    </div>

                    <div className="mb-12 text-center relative z-10">
                        <div className="w-20 h-20 rounded-3xl bg-brand-primary text-black flex items-center justify-center shadow-[0_0_50px_rgba(255,51,102,0.4)] mx-auto mb-8 group hover:scale-110 transition-transform duration-500">
                            <ShieldCheck size={36} strokeWidth={2.5} />
                        </div>
                        <h1 className="text-4xl font-black tracking-tighter text-white mb-2 italic uppercase">Ralphé DNS</h1>
                        <p className="text-[10px] font-black text-zinc-500 uppercase tracking-[0.4em] italic">Quantum Management Protocol v4.0</p>
                    </div>

                    <form onSubmit={handleSubmit} className="space-y-6 relative z-10">
                        <div className="space-y-3">
                            <label className="text-[10px] font-black text-zinc-600 uppercase tracking-[0.2em] ml-2 flex items-center gap-2 italic">
                                <Mail size={12} className="text-brand-primary" /> Core Identifier (Email)
                            </label>
                            <div className="relative group">
                                <input
                                    type="email"
                                    value={email}
                                    onChange={(e) => setEmail(e.target.value)}
                                    autoFocus
                                    autoComplete="email"
                                    className="w-full bg-black/40 border border-white/5 focus:border-brand-primary rounded-2xl px-6 py-4 text-white placeholder-zinc-700 outline-none transition-all duration-500 italic text-sm shadow-inner"
                                    placeholder="admin@ralphe.ai"
                                />
                            </div>
                        </div>
                        <div className="space-y-3">
                            <label className="text-[10px] font-black text-zinc-600 uppercase tracking-[0.2em] ml-2 flex items-center gap-2 italic">
                                <Lock size={12} className="text-brand-primary" /> Cipher Key (Password)
                            </label>
                            <div className="relative group">
                                <input
                                    type="password"
                                    value={password}
                                    onChange={(e) => setPassword(e.target.value)}
                                    autoComplete="current-password"
                                    className={cn(
                                        "w-full bg-black/40 border border-white/5 rounded-2xl px-6 py-4 text-white placeholder-zinc-800 outline-none transition-all duration-500 font-mono tracking-[0.5em] text-sm shadow-inner",
                                        error ? "border-error/50 focus:border-error" : "focus:border-brand-primary"
                                    )}
                                    placeholder="••••••••"
                                />
                                {error && (
                                    <p className="text-error text-[10px] font-black mt-3 ml-2 uppercase tracking-widest animate-in slide-in-from-top-2 duration-300 italic flex items-center gap-2">
                                        <ArrowRight size={10} /> {error}
                                    </p>
                                )}
                            </div>
                        </div>

                        <div className="pt-4">
                            <button
                                disabled={loading}
                                className="w-full py-5 rounded-2xl bg-white text-black font-black text-[11px] tracking-[0.3em] uppercase shadow-[0_20px_40px_rgba(0,0,0,0.4)] hover:shadow-[0_20px_50px_rgba(255,255,255,0.1)] hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center justify-center gap-4 group disabled:opacity-50"
                            >
                                {loading ? (
                                    <Loader2 className="animate-spin" size={20} />
                                ) : (
                                    <>
                                        INITIALIZE UPLINK
                                        <ArrowRight size={16} className="group-hover:translate-x-1 transition-transform" />
                                    </>
                                )}
                            </button>
                        </div>
                    </form>

                    <div className="mt-12 flex flex-col items-center gap-4">
                        <div className="flex items-center gap-3">
                            <div className="w-1.5 h-1.5 rounded-full bg-success animate-pulse" />
                            <span className="text-[9px] font-black text-zinc-500 uppercase tracking-widest">Nodes Operational</span>
                        </div>
                        <p className="text-[9px] text-zinc-700 font-black uppercase tracking-[0.4em] italic text-center">
                            Secure Quantum Tunnel Established • Algiers, DZ
                        </p>
                    </div>
                </div>
            </div>
        </div>
    );
}
