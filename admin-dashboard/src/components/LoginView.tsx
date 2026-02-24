import { useState } from 'react';
import { authService } from '../services/authService';

export function LoginView({ onLogin }: { onLogin: () => void }) {
    const [password, setPassword] = useState('');
    const [error, setError] = useState(false);
    const [loading, setLoading] = useState(false);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setError(false);

        const success = await authService.login(password);
        if (success) {
            onLogin();
        } else {
            setError(true);
            setPassword('');
        }
        setLoading(false);
    };

    return (
        <div className="min-h-screen bg-zinc-950 flex items-center justify-center p-6 font-sans">
            <div className="absolute inset-0 overflow-hidden pointer-events-none">
                <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-indigo-500/10 rounded-full blur-[120px]" />
                <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-purple-600/10 rounded-full blur-[120px]" />
            </div>

            <div className="w-full max-w-md animate-in fade-in zoom-in duration-1000">
                <div className="diamond-card p-10 rounded-[2.5rem] border-white/5 bg-white/5 backdrop-blur-3xl shadow-2xl relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-8 opacity-5">
                        <span className="text-8xl">💎</span>
                    </div>

                    <div className="mb-10 text-center relative z-10">
                        <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center shadow-2xl shadow-indigo-500/40 mx-auto mb-6">
                            <span className="text-white font-black text-2xl">R</span>
                        </div>
                        <h1 className="text-2xl font-black tracking-tight text-white mb-2">RestoBot Diamond</h1>
                        <p className="text-zinc-500 text-sm">Secure Management Console</p>
                    </div>

                    <form onSubmit={handleSubmit} className="space-y-6 relative z-10">
                        <div className="space-y-2">
                            <label className="text-[10px] font-black text-zinc-400 uppercase tracking-[0.2em] ml-2">Access Key</label>
                            <input
                                type="password"
                                value={password}
                                onChange={(e) => setPassword(e.target.value)}
                                autoFocus
                                className={`w-full bg-white/5 border-2 ${error ? 'border-red-500/50 pr-12' : 'border-white/5 focus:border-indigo-500/50'} rounded-2xl px-6 py-4 text-white placeholder-white/10 outline-none transition-all duration-300 font-mono tracking-widest`}
                                placeholder="••••••••••••"
                            />
                            {error && <p className="text-red-500 text-[10px] font-bold mt-2 ml-2 uppercase animate-bounce">Invalid Key</p>}
                        </div>

                        <button
                            disabled={loading}
                            className="w-full py-4 rounded-2xl bg-indigo-500 hover:bg-indigo-400 text-white font-black text-sm tracking-widest shadow-xl shadow-indigo-500/20 hover:shadow-indigo-500/40 hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center justify-center gap-3"
                        >
                            {loading ? (
                                <div className="w-5 h-5 border-2 border-white/20 border-t-white rounded-full animate-spin" />
                            ) : (
                                'UNLOCK DASHBOARD'
                            )}
                        </button>
                    </form>

                    <p className="mt-8 text-center text-[10px] text-zinc-600 font-medium tracking-tight">
                        ESTABLISHED 2026 • ALGERIA OPERATIONS
                    </p>
                </div>
            </div>
        </div>
    );
}
