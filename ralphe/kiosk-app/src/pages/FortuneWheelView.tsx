import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Ticket, Sparkles, Trophy, RotateCw, ExternalLink, ChevronLeft } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { cn } from "@/lib/utils";

const REWARDS = [
  { id: 1, name: 'Burger Offert', color: 'bg-brand-primary' },
  { id: 2, name: 'Neural Drift', color: 'bg-zinc-900' },
  { id: 3, name: 'Frites DNA', color: 'bg-indigo-500' },
  { id: 4, name: 'Neural Drift', color: 'bg-zinc-900' },
  { id: 5, name: 'Elixir 33cl', color: 'bg-success' },
  { id: 6, name: 'Neural Drift', color: 'bg-zinc-900' },
];

export default function FortuneWheelView() {
  const navigate = useNavigate();
  const [hasReviewed, setHasReviewed] = useState(false);
  const [isSpinning, setIsSpinning] = useState(false);
  const [rotation, setRotation] = useState(0);
  const [wonReward, setWonReward] = useState<string | null>(null);

  const handleReviewClick = () => {
    window.open('https://g.page/r/example/review', '_blank');
    setTimeout(() => {
      setHasReviewed(true);
    }, 2000);
  };

  const spinWheel = () => {
    if (isSpinning || !hasReviewed) return;
    setIsSpinning(true);
    const prizeIndex = Math.floor(Math.random() * REWARDS.length);
    const sliceAngle = 360 / REWARDS.length;
    const extraSpins = 360 * 8; // More spins for drama
    const prizeRotation = extraSpins + (prizeIndex * sliceAngle) + (sliceAngle / 2);
    const finalRotation = rotation - prizeRotation;
    setRotation(finalRotation);

    setTimeout(() => {
      setIsSpinning(false);
      setWonReward(REWARDS[prizeIndex].name);
    }, 5000);
  };

  return (
    <div className="min-h-screen bg-black text-white flex flex-col relative overflow-hidden selection:bg-brand-primary/30">

      {/* Dynamic Background */}
      <div className="fixed inset-0 z-0">
        <div className="absolute top-[-10%] left-[-10%] w-[50%] h-[50%] bg-brand-primary/10 rounded-full blur-[180px] animate-pulse" />
        <div className="absolute bottom-[-10%] right-[-10%] w-[50%] h-[50%] bg-indigo-500/10 rounded-full blur-[180px] animate-pulse delay-1000" />
        <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-20 mix-blend-overlay pointer-events-none" />
      </div>

      {/* Navigation Layer */}
      <div className="p-10 flex items-center justify-between z-10 relative">
        <button
          onClick={() => navigate('/')}
          className="w-16 h-16 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center hover:bg-white/10 transition-all active:scale-90"
        >
          <ChevronLeft size={28} className="text-zinc-400" />
        </button>
        <div className="flex items-center gap-3">
          <div className="w-2 h-2 rounded-full bg-brand-primary animate-ping" />
          <span className="text-[10px] font-black uppercase tracking-[0.5em] italic text-zinc-500">Ralphé Rewards Matrix</span>
        </div>
      </div>

      <div className="flex-1 flex flex-col items-center justify-center p-10 z-10 relative max-w-4xl mx-auto w-full">

        {/* Tactical Title */}
        <div className="text-center mb-16 space-y-4">
          <motion.div
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            className="w-20 h-20 mx-auto rounded-3xl bg-brand-primary/10 border border-brand-primary/20 flex items-center justify-center text-brand-primary mb-6"
          >
            <Trophy size={40} />
          </motion.div>
          <h2 className="text-7xl font-black uppercase italic tracking-tighter leading-none mb-4">
            Spin & <span className="text-brand-primary">Synchronize</span>
          </h2>
          <p className="text-zinc-500 text-sm font-black uppercase tracking-[0.4em] italic leading-relaxed">
            Contribute 5-Star Telemetry to initiate the extraction protocol and unlock premium physical assets.
          </p>
        </div>

        {/* The Chrono-Wheel */}
        <div className="relative w-[500px] h-[500px] mb-20 group">
          {/* Tactical Pointer */}
          <div className="absolute -top-6 left-1/2 -translate-x-1/2 z-30 filter drop-shadow-[0_0_20px_rgba(255,51,102,0.5)]">
            <div className="w-10 h-14 bg-brand-primary clip-path-pointer flex items-center justify-center">
              <div className="w-2 h-6 bg-white/40 rounded-full blur-[2px]" />
            </div>
          </div>

          {/* Wheel Frame */}
          <div className="w-full h-full rounded-full p-6 bg-white/[0.02] border-4 border-white/5 shadow-[0_0_100px_rgba(0,0,0,0.5)] backdrop-blur-2xl relative">
            <motion.div
              className="w-full h-full rounded-full border-[12px] border-black overflow-hidden relative shadow-inner"
              animate={{ rotate: rotation }}
              transition={{ duration: 5, ease: [0.15, 0, 0.15, 1] }}
            >
              {REWARDS.map((reward, index) => {
                const rotationAngle = index * (360 / REWARDS.length);
                return (
                  <div
                    key={index}
                    className={cn("absolute w-full h-[50%] left-0 top-0 origin-bottom border-r border-black/20", reward.color)}
                    style={{
                      transform: `rotate(${rotationAngle}deg)`,
                      clipPath: 'polygon(0 0, 100% 0, 50% 100%)'
                    }}
                  >
                    <div className="absolute top-16 left-1/2 -translate-x-1/2 -rotate-90 origin-center text-white font-black text-xs uppercase italic tracking-widest whitespace-nowrap drop-shadow-[0_2px_4px_rgba(0,0,0,0.5)]">
                      {reward.name}
                    </div>
                  </div>
                );
              })}
            </motion.div>

            {/* Center Hub */}
            <div className="absolute inset-0 m-auto w-24 h-24 rounded-full bg-black border-4 border-white/10 flex items-center justify-center shadow-2xl z-20">
              <div className="w-8 h-8 rounded-full bg-brand-primary shadow-[0_0_30px_rgba(255,51,102,0.8)]" />
            </div>
          </div>
        </div>

        {/* Interaction Layer */}
        <div className="w-full max-w-sm">
          {!hasReviewed ? (
            <button
              onClick={handleReviewClick}
              className="btn-quantum w-full bg-white text-black hover:bg-zinc-200"
            >
              <ExternalLink size={24} /> Feed Google Registry
            </button>
          ) : (
            <button
              onClick={spinWheel}
              disabled={isSpinning || !!wonReward}
              className={cn(
                "btn-quantum w-full relative overflow-hidden group/spin",
                isSpinning ? "opacity-50 cursor-not-allowed" : "hover:scale-105 active:scale-95"
              )}
            >
              <RotateCw size={24} className={cn(isSpinning && "animate-spin")} />
              {isSpinning ? 'Synchronizing...' : wonReward ? 'Sector Drained' : 'Initiate Spin Cycle'}
            </button>
          )}
        </div>

        {/* Result Overlay Matrix */}
        <AnimatePresence>
          {wonReward && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="fixed inset-0 z-[150] flex items-center justify-center p-12 bg-black/60 backdrop-blur-3xl"
            >
              <motion.div
                initial={{ scale: 0.9, y: 40, opacity: 0 }}
                animate={{ scale: 1, y: 0, opacity: 1 }}
                className="quantum-card p-12 w-full max-w-2xl text-center relative overflow-hidden border-brand-primary/30"
              >
                <div className="absolute top-0 left-0 w-full h-2 bg-brand-primary shadow-[0_0_20px_rgba(255,51,102,0.5)]" />

                <div className="w-24 h-24 mx-auto rounded-full bg-white/5 border border-white/10 flex items-center justify-center mb-10">
                  {wonReward.includes('Drift') ? (
                    <span className="text-6xl grayscale filter brightness-50">💀</span>
                  ) : (
                    <Sparkles size={48} className="text-brand-primary" />
                  )}
                </div>

                <h3 className="text-6xl font-black uppercase italic tracking-tighter mb-4 text-white">
                  {wonReward.includes('Drift') ? 'Neural Drift' : 'Asset Allocated'}
                </h3>

                <p className="text-zinc-500 text-sm font-black uppercase tracking-[0.4em] italic mb-12">
                  {wonReward.includes('Drift')
                    ? "Probability engine fluctuated. No asset detected in this sector."
                    : `Identity confirmed. Unlocked: ${wonReward}`}
                </p>

                {!wonReward.includes('Drift') && (
                  <div className="bg-brand-primary/10 p-8 rounded-[2.5rem] mb-12 border border-brand-primary/20 flex flex-col items-center gap-4 group">
                    <span className="text-[10px] font-black text-brand-primary uppercase tracking-[0.5em] italic">Access Key</span>
                    <div className="flex items-center gap-4">
                      <Ticket size={28} className="text-brand-primary" />
                      <span className="text-6xl font-black text-white italic tracking-widest group-hover:tracking-[0.3em] transition-all duration-700">RALPHE-PRO</span>
                    </div>
                  </div>
                )}

                <button
                  onClick={() => navigate('/')}
                  className="btn-quantum-outline w-full"
                >
                  Return to Control Center
                </button>
              </motion.div>
            </motion.div>
          )}
        </AnimatePresence>

      </div>

      <style>{`
        .clip-path-pointer {
            clip-path: polygon(0 0, 100% 0, 50% 100%);
        }
      `}</style>
    </div>
  );
}
