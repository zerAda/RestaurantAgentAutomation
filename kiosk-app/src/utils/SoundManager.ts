// Simple Sound Manager for Kiosk
// Uses Web Audio API for synthesized sounds to avoid loading heavy assets for now

export const playSound = (type: 'swipe' | 'select' | 'ambient') => {
    const AudioContext = window.AudioContext || (window as unknown as { webkitAudioContext: typeof window.AudioContext }).webkitAudioContext;
    if (!AudioContext) return;

    const ctx = new AudioContext();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.connect(gain);
    gain.connect(ctx.destination);

    const now = ctx.currentTime;

    if (type === 'swipe') {
        // Whoosh sound
        osc.type = 'sine';
        osc.frequency.setValueAtTime(200, now);
        osc.frequency.exponentialRampToValueAtTime(600, now + 0.1);
        gain.gain.setValueAtTime(0.2, now);
        gain.gain.exponentialRampToValueAtTime(0.01, now + 0.1);
        osc.start(now);
        osc.stop(now + 0.1);
    } else if (type === 'select') {
        // Ding sound
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(800, now);
        gain.gain.setValueAtTime(0.1, now);
        gain.gain.exponentialRampToValueAtTime(0.01, now + 0.3);
        osc.start(now);
        osc.stop(now + 0.3);
    } else if (type === 'ambient') {
        // Low drone (simulated)
        osc.type = 'sine';
        osc.frequency.setValueAtTime(50, now);
        gain.gain.setValueAtTime(0.05, now);
        osc.start(now);
        // Ambient loops, so we don't stop it immediately here, 
        // but for this simple fn we just play a tone. 
        // In a real app we'd manage state.
        osc.stop(now + 2);
    }
};
