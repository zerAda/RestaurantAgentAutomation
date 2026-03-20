import React, { useState, useEffect } from 'react';
import { useCart, type CartItem } from '../context/CartContext';
import { strapi } from '../services/strapiClient';
import { motion, AnimatePresence } from 'framer-motion';
import { ShoppingBag, ChevronLeft, ChevronRight, Check, Loader2, MapPin, Package, Activity, PartyPopper, AlertTriangle } from 'lucide-react';
import { cn } from "@/lib/utils";

type ServiceMode = 'kiosk_sur_place' | 'kiosk_a_emporter';

const CheckoutView: React.FC = () => {
    const { items, clearCart, total } = useCart();
    const [step, setStep] = useState<'review' | 'mode' | 'confirm' | 'done'>('review');
    const [serviceMode, setServiceMode] = useState<ServiceMode>('kiosk_sur_place');
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [orderId, setOrderId] = useState<string>('');
    const [error, setError] = useState<string>('');

    useEffect(() => {
        import('../services/configService').then(({ configService }) => {
            configService.getConfig().then(config => {
                if (config?.kiosk_default_service_mode === 'kiosk_sur_place' || config?.kiosk_default_service_mode === 'kiosk_a_emporter') {
                    setServiceMode(config.kiosk_default_service_mode);
                }
            });
        });
    }, []);

    if (items.length === 0 && step !== 'done') {
        return (
            <div className="w-full h-screen bg-black text-white flex flex-col items-center justify-center p-12">
                <div className="w-32 h-32 rounded-full bg-white/5 border border-white/10 flex items-center justify-center mb-10">
                    <ShoppingBag size={64} className="text-zinc-700" />
                </div>
                <h2 className="text-5xl font-black text-white mb-12 uppercase italic tracking-tighter">Your matrix is empty</h2>
                <button
                    onClick={() => window.location.href = '/'}
                    className="btn-quantum px-16"
                >
                    Return to menu
                </button>
            </div>
        );
    }

    const handleSubmitOrder = async () => {
        setIsSubmitting(true);
        setError('');
        try {
            const orderItems = items.map((item: CartItem) => ({
                item_code: item.product.id,
                label: item.product.name,
                qty: item.quantity,
                unit_price_cents: item.product.price,
                line_total_cents: item.product.price * item.quantity,
            }));

            const payload = {
                channel: 'kiosk',
                service_mode: serviceMode,
                status: 'NEW',
                total_cents: total,
                order_items: orderItems,
                restaurant_id: import.meta.env.VITE_RESTAURANT_ID || 'default',
            };

            const res = await strapi.n8n<{ id: number }>('/kiosk-order', payload);

            const id = res?.id;
            setOrderId(id ? `#${String(id).padStart(4, '0')}` : `#${Math.floor(Math.random() * 9000 + 1000)}`);
            clearCart();
            setStep('done');
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Transmission failed. Signal drift detected.');
        } finally {
            setIsSubmitting(false);
        }
    };

    return (
        <div className="w-full min-h-screen bg-black text-white overflow-hidden relative">

            {/* Cinematic Background Elements */}
            <div className="fixed inset-0 pointer-events-none z-0">
                <div className="absolute top-[-20%] left-[-10%] w-[60%] h-[60%] bg-brand-primary/5 rounded-full blur-[160px]" />
                <div className="absolute bottom-[-10%] right-[-10%] w-[50%] h-[50%] bg-indigo-500/5 rounded-full blur-[160px]" />
            </div>

            <main className="relative z-10 w-full max-w-4xl mx-auto min-h-screen flex flex-col p-12">

                <AnimatePresence mode="wait">
                    {/* Step: Review */}
                    {step === 'review' && (
                        <motion.div
                            key="review"
                            initial={{ opacity: 0, x: 50 }}
                            animate={{ opacity: 1, x: 0 }}
                            exit={{ opacity: 0, x: -50 }}
                            className="flex-1 flex flex-col"
                        >
                            <header className="mb-12">
                                <h1 className="text-6xl font-black uppercase italic tracking-tighter leading-none mb-4">Validate Matrix</h1>
                                <p className="text-zinc-500 text-xs font-black uppercase tracking-[0.4em] italic">Buffer Execution: Step 01</p>
                            </header>

                            <div className="flex-1 space-y-4 mb-12">
                                {items.map((item, i) => (
                                    <div key={i} className="quantum-card p-8 flex justify-between items-center group hover:bg-white/[0.04]">
                                        <div className="flex items-center gap-6">
                                            <div className="w-16 h-16 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center text-zinc-600 font-black italic">
                                                x{item.quantity}
                                            </div>
                                            <div>
                                                <h3 className="text-2xl font-black uppercase italic tracking-tight">{item.product.name}</h3>
                                                <p className="text-[10px] font-black text-zinc-500 uppercase tracking-widest mt-1">Sector: {item.product.category || 'Standard'}</p>
                                            </div>
                                        </div>
                                        <div className="text-3xl font-black italic text-zinc-400 group-hover:text-white transition-colors">
                                            {(item.product.price * item.quantity).toLocaleString()} <span className="text-xs uppercase">DA</span>
                                        </div>
                                    </div>
                                ))}
                            </div>

                            <div className="quantum-card p-10 flex justify-between items-end mb-12 border-brand-primary/20 bg-brand-primary/[0.02]">
                                <div>
                                    <span className="text-[10px] font-black text-zinc-500 uppercase tracking-[0.4em] italic block mb-3">Aggregate Value</span>
                                    <div className="flex items-center gap-4">
                                        <Activity size={24} className="text-brand-primary" />
                                        <span className="text-7xl font-black italic tracking-tighter">{total.toLocaleString()}</span>
                                        <span className="text-xl font-black text-zinc-500 uppercase italic">Credits</span>
                                    </div>
                                </div>
                            </div>

                            <div className="flex gap-6">
                                <button onClick={() => window.location.href = '/'} className="btn-quantum-outline flex-1">
                                    <ChevronLeft size={24} /> Back to Hub
                                </button>
                                <button onClick={() => setStep('mode')} className="btn-quantum flex-[1.5]">
                                    Proceed to Protocol <ChevronRight size={24} />
                                </button>
                            </div>
                        </motion.div>
                    )}

                    {/* Step: Service Mode */}
                    {step === 'mode' && (
                        <motion.div
                            key="mode"
                            initial={{ opacity: 0, x: 50 }}
                            animate={{ opacity: 1, x: 0 }}
                            exit={{ opacity: 0, x: -50 }}
                            className="flex-1 flex flex-col justify-center"
                        >
                            <h1 className="text-6xl font-black uppercase italic tracking-tighter leading-none text-center mb-16">Select Protocol</h1>
                            <div className="grid grid-cols-2 gap-8 mb-16">
                                <button
                                    onClick={() => { setServiceMode('kiosk_sur_place'); setStep('confirm'); }}
                                    className={cn(
                                        "p-16 rounded-[3rem] border-2 transition-all flex flex-col items-center gap-8 group",
                                        serviceMode === 'kiosk_sur_place' ? "bg-white text-black border-transparent shadow-[0_0_60px_rgba(255,255,255,0.1)] scale-105" : "bg-white/5 border-white/5 text-zinc-600 hover:bg-white/10"
                                    )}
                                >
                                    <MapPin size={80} className={cn("transition-transform group-hover:scale-110", serviceMode === 'kiosk_sur_place' ? "text-black" : "text-zinc-800")} />
                                    <span className="text-3xl font-black uppercase italic tracking-tighter">Internal Protocol</span>
                                </button>
                                <button
                                    onClick={() => { setServiceMode('kiosk_a_emporter'); setStep('confirm'); }}
                                    className={cn(
                                        "p-16 rounded-[3rem] border-2 transition-all flex flex-col items-center gap-8 group",
                                        serviceMode === 'kiosk_a_emporter' ? "bg-white text-black border-transparent shadow-[0_0_60px_rgba(255,255,255,0.1)] scale-105" : "bg-white/5 border-white/5 text-zinc-600 hover:bg-white/10"
                                    )}
                                >
                                    <Package size={80} className={cn("transition-transform group-hover:scale-110", serviceMode === 'kiosk_a_emporter' ? "text-black" : "text-zinc-800")} />
                                    <span className="text-3xl font-black uppercase italic tracking-tighter">External Protocol</span>
                                </button>
                            </div>
                            <button onClick={() => setStep('review')} className="btn-quantum-outline max-w-sm mx-auto">
                                <ChevronLeft size={20} /> Review Items
                            </button>
                        </motion.div>
                    )}

                    {/* Step: Confirm */}
                    {step === 'confirm' && (
                        <motion.div
                            key="confirm"
                            initial={{ opacity: 0, scale: 0.95 }}
                            animate={{ opacity: 1, scale: 1 }}
                            exit={{ opacity: 0, scale: 1.05 }}
                            className="flex-1 flex flex-col justify-center"
                        >
                            <h1 className="text-6xl font-black uppercase italic tracking-tighter leading-none text-center mb-12">Final Verification</h1>

                            <div className="quantum-card p-12 space-y-10 mb-12 border-brand-primary/20">
                                <div className="flex justify-between items-center pb-8 border-b border-white/5">
                                    <div className="flex items-center gap-4 text-zinc-500">
                                        <Activity size={20} />
                                        <span className="text-xs font-black uppercase tracking-widest italic">Protocol Mode</span>
                                    </div>
                                    <span className="text-2xl font-black text-white italic uppercase tracking-tighter">
                                        {serviceMode === 'kiosk_sur_place' ? 'Internal (Stay)' : 'External (Extract)'}
                                    </span>
                                </div>
                                <div className="flex justify-between items-center pb-8 border-b border-white/5">
                                    <div className="flex items-center gap-4 text-zinc-500">
                                        <ShoppingBag size={20} />
                                        <span className="text-xs font-black uppercase tracking-widest italic">Matrix Units</span>
                                    </div>
                                    <span className="text-2xl font-black text-white italic uppercase tracking-tighter">{items.length} Modules</span>
                                </div>
                                <div className="flex justify-between items-end pt-4">
                                    <span className="text-xs font-black text-brand-primary uppercase tracking-[0.4em] italic">Authorized Credits</span>
                                    <span className="text-7xl font-black text-white italic tracking-tighter">{total.toLocaleString()} DA</span>
                                </div>
                            </div>

                            {error && (
                                <div className="p-6 rounded-3xl bg-error/10 border border-error/20 text-error font-black uppercase italic text-sm tracking-widest mb-10 text-center flex items-center gap-4 justify-center">
                                    <AlertTriangle size={20} /> {error}
                                </div>
                            )}

                            <div className="flex gap-6">
                                <button onClick={() => setStep('mode')} className="btn-quantum-outline flex-1">
                                    Reconfigure Mode
                                </button>
                                <button
                                    onClick={handleSubmitOrder}
                                    disabled={isSubmitting}
                                    className="btn-quantum flex-[2] bg-brand-primary text-black shadow-[0_0_50px_rgba(255,51,102,0.3)]"
                                >
                                    {isSubmitting ? <Loader2 size={32} className="animate-spin" /> : (
                                        <>Deploy Order Matrix <Check size={28} /></>
                                    )}
                                </button>
                            </div>
                        </motion.div>
                    )}

                    {/* Step: Done */}
                    {step === 'done' && (
                        <motion.div
                            key="done"
                            initial={{ opacity: 0, scale: 1.1 }}
                            animate={{ opacity: 1, scale: 1 }}
                            className="flex-1 flex flex-col items-center justify-center text-center"
                        >
                            <div className="w-48 h-48 rounded-[4rem] bg-brand-primary flex items-center justify-center mb-16 shadow-[0_0_100px_rgba(255,51,102,0.4)] relative">
                                <motion.div
                                    animate={{ rotate: 360 }}
                                    transition={{ duration: 20, repeat: Infinity, ease: "linear" }}
                                    className="absolute inset-[-20px] border-2 border-dashed border-brand-primary/30 rounded-full"
                                />
                                <PartyPopper size={80} className="text-black" />
                            </div>

                            <h1 className="text-8xl font-black uppercase italic tracking-tighter leading-none mb-6">Unit Deployed</h1>
                            <p className="px-12 py-4 rounded-2xl bg-brand-primary/10 border border-brand-primary/30 text-3xl font-black text-brand-primary uppercase italic tracking-[0.3em] mb-12">
                                Identifier: {orderId}
                            </p>

                            <div className="max-w-md space-y-4 text-zinc-500 font-black uppercase tracking-widest italic text-xs mb-16 leading-loose">
                                <p>Neural link established with kitchen hub.</p>
                                <p>Buffer extraction in progress. Maintain signal.</p>
                            </div>

                            <button
                                onClick={() => { window.location.href = '/'; }}
                                className="btn-quantum px-20"
                            >
                                Re-Initialize Interface
                            </button>
                        </motion.div>
                    )}
                </AnimatePresence>
            </main>
        </div>
    );
};

export default CheckoutView;
