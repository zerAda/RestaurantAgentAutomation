import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { Gift, Star, ChevronLeft, Ticket } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

const REWARDS = [
  { id: 1, name: 'Burger Offert', color: '#ef4444' }, // Red
  { id: 2, name: 'Oups, Perdu !', color: '#1f2937' }, // Gray
  { id: 3, name: 'Frites Gratuites', color: '#f59e0b' }, // Amber
  { id: 4, name: 'Oups, Perdu !', color: '#1f2937' },
  { id: 5, name: 'Boisson 33cl', color: '#3b82f6' }, // Blue
  { id: 6, name: 'Oups, Perdu !', color: '#1f2937' },
];

export default function FortuneWheelView() {
  const navigate = useNavigate();
  const [hasReviewed, setHasReviewed] = useState(false);
  const [isSpinning, setIsSpinning] = useState(false);
  const [rotation, setRotation] = useState(0);
  const [wonReward, setWonReward] = useState<string | null>(null);

  const handleReviewClick = () => {
    // Dans un cas réel, ça ouvre le lien Google My Business
    window.open('https://g.page/r/example/review', '_blank');
    // On simule que l'utilisateur a laissé un avis après être revenu
    setTimeout(() => {
      setHasReviewed(true);
    }, 2000);
  };

  const spinWheel = () => {
    if (isSpinning || !hasReviewed) return;

    setIsSpinning(true);
    // Logique RNG simulée (idéalement appelé via l'API n8n)
    const prizeIndex = Math.floor(Math.random() * REWARDS.length);

    // Calcul de la rotation : 5 tours complets + l'angle du prix
    const sliceAngle = 360 / REWARDS.length;
    const extraSpins = 360 * 5;
    const prizeRotation = extraSpins + (prizeIndex * sliceAngle) + (sliceAngle / 2);
    // Pour que le prix tombe en haut, on soustrait l'angle
    const finalRotation = rotation - prizeRotation - (Math.random() * sliceAngle * 0.5);

    setRotation(finalRotation);

    setTimeout(() => {
      setIsSpinning(false);
      setWonReward(REWARDS[prizeIndex].name);
    }, 4500); // Durée de l'animation
  };

  return (
    <div className="min-h-screen bg-neutral-950 text-white flex flex-col relative overflow-hidden font-sans">
      {/* Background Effects */}
      <div className="absolute top-[-20%] left-[-10%] w-[50%] h-[50%] bg-amber-500/20 blur-[120px] rounded-full pointer-events-none" />
      <div className="absolute bottom-[-20%] right-[-10%] w-[50%] h-[50%] bg-blue-500/20 blur-[120px] rounded-full pointer-events-none" />

      {/* Header */}
      <div className="p-6 flex items-center gap-4 z-10">
        <button
          onClick={() => navigate('/')}
          className="p-3 bg-white/10 hover:bg-white/20 rounded-full backdrop-blur-md transition-colors"
        >
          <ChevronLeft className="w-6 h-6" />
        </button>
        <h1 className="text-2xl font-bold tracking-tight">Ralphé Rewards</h1>
      </div>

      <div className="flex-1 flex flex-col items-center justify-center p-6 z-10 max-w-md mx-auto w-full">

        {/* Title Area */}
        <div className="text-center mb-10 space-y-4">
          <motion.div
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            className="inline-flex items-center justify-center p-4 bg-amber-500/20 text-amber-500 rounded-full mb-2"
          >
            <Star className="w-10 h-10 fill-current" />
          </motion.div>
          <h2 className="text-4xl font-black uppercase tracking-widest bg-gradient-to-r from-amber-200 to-amber-500 bg-clip-text text-transparent">
            Tournez & Gagnez
          </h2>
          <p className="text-neutral-400 text-lg">
            Laissez-nous un avis 5 étoiles sur Google et tentez de gagner votre prochain repas !
          </p>
        </div>

        {/* The Wheel */}
        <div className="relative w-80 h-80 mb-12">
          {/* Pointer */}
          <div className="absolute -top-4 left-1/2 -translate-x-1/2 z-20 text-white drop-shadow-2xl">
            <svg width="40" height="50" viewBox="0 0 40 50" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
              <path d="M20 50L0 20C0 20 5.5 0 20 0C34.5 0 40 20 40 20L20 50Z" fill="white" />
            </svg>
          </div>

          {/* Wheel Container */}
          <div className="w-full h-full rounded-full p-2 bg-gradient-to-b from-amber-300 to-amber-600 shadow-[0_0_50px_rgba(245,158,11,0.3)]">
            <motion.div
              className="w-full h-full rounded-full border-4 border-neutral-900 overflow-hidden relative"
              animate={{ rotate: rotation }}
              transition={{ duration: 4.5, type: 'spring', bounce: 0.1 }}
              style={{ transformOrigin: 'center center' }}
            >
              {REWARDS.map((reward, index) => {
                const rotationAngle = index * (360 / REWARDS.length);
                return (
                  <div
                    key={index}
                    className="absolute w-full h-[50%] left-0 top-0 origin-bottom"
                    style={{
                      transform: `rotate(${rotationAngle}deg)`,
                      backgroundColor: reward.color,
                      clipPath: 'polygon(0 0, 100% 0, 50% 100%)' // Triangle slice
                    }}
                  >
                    <div className="absolute top-8 left-1/2 -translate-x-1/2 -rotate-90 origin-center text-white font-bold text-sm whitespace-nowrap drop-shadow-md">
                      {reward.name}
                    </div>
                  </div>
                );
              })}
            </motion.div>
          </div>
        </div>

        {/* Call to Action */}
        {
          !hasReviewed ? (
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={handleReviewClick}
              className="w-full py-5 rounded-2xl bg-white text-black font-extrabold text-xl tracking-wide flex items-center justify-center gap-3 shadow-[0_0_30px_rgba(255,255,255,0.3)]"
            >
              <Star className="w-6 h-6 fill-current" />
              Laisser un avis Google
            </motion.button>
          ) : !wonReward ? (
            <motion.button
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              whileHover={{ scale: isSpinning ? 1 : 1.05 }}
              whileTap={{ scale: isSpinning ? 1 : 0.95 }}
              onClick={spinWheel}
              disabled={isSpinning}
              className={`w-full py-5 rounded-2xl font-extrabold text-xl tracking-wide flex items-center justify-center gap-3 transition-colors ${isSpinning ? 'bg-neutral-800 text-neutral-500 cursor-not-allowed' : 'bg-gradient-to-r from-amber-400 to-amber-600 text-black shadow-[0_0_30px_rgba(245,158,11,0.5)]'}`}
            >
              {isSpinning ? 'Tirage en cours...' : 'Tourner la roue !'}
            </motion.button>
          ) : null}

        {/* Result Overlay */}
        {wonReward && (
          <motion.div
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            className="fixed inset-0 z-50 flex items-center justify-center p-6 bg-black/80 backdrop-blur-sm"
          >
            <div className="bg-neutral-900 border border-neutral-800 p-8 rounded-3xl w-full max-w-sm text-center relative overflow-hidden">
              <div className="absolute top-0 left-0 w-full h-2 bg-gradient-to-r from-amber-400 to-amber-600" />

              <div className="w-20 h-20 mx-auto bg-neutral-800 rounded-full flex items-center justify-center mb-6">
                {wonReward.includes('Perdu') ? (
                  <span className="text-4xl">😢</span>
                ) : (
                  <Gift className="w-10 h-10 text-amber-500" />
                )}
              </div>

              <h3 className="text-3xl font-black mb-2 text-white">
                {wonReward.includes('Perdu') ? 'Dommage !' : 'Félicitations !'}
              </h3>
              <p className="text-neutral-400 mb-8">
                {wonReward.includes('Perdu')
                  ? "La chance n'était pas de votre côté cette fois. Mais merci pour votre avis !"
                  : `Vous avez gagné : ${wonReward}. \nMontrez cet écran en caisse.`}
              </p>

              {!wonReward.includes('Perdu') && (
                <div className="bg-neutral-950 p-4 rounded-xl mb-8 border border-neutral-800 flex items-center justify-center gap-3">
                  <Ticket className="text-amber-500" />
                  <span className="text-2xl font-mono text-amber-400 tracking-widest">RALPHE-882</span>
                </div>
              )}

              <button
                onClick={() => navigate('/')}
                className="w-full py-4 rounded-xl bg-white text-black font-bold text-lg"
              >
                Retourner au Menu
              </button>
            </div>
          </motion.div>
        )}

      </div>
    </div>
  );
}
