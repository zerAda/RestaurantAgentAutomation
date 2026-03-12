import { BrowserRouter, Routes, Route, useNavigate } from "react-router-dom";
import { useEffect } from "react";
import { ErrorBoundary } from "./components/ErrorBoundary";
import VerticalVideoFeed from "./components/VerticalVideoFeed";
import FortuneWheelView from "./pages/FortuneWheelView";
import CheckoutView from "./pages/CheckoutView";
import { CartProvider, useCart } from "./context/CartContext";
import { configService } from "./services/configService";

/**
 * IdleTimer Component
 * Resets the kiosk to the welcome screen after inactivity.
 */
function IdleTimer() {
  const navigate = useNavigate();
  const { clearCart } = useCart();

  useEffect(() => {
    let timeoutId: any;
    let timeoutSec = 120; // Default fallback
    let lastReset = 0;

    configService.getConfig().then(config => {
      if (config) timeoutSec = config.kiosk_idle_timeout_sec;
      resetTimer();
    }).catch(err => console.error("Could not fetch config for IdleTimer:", err));

    const resetTimer = () => {
      const now = Date.now();
      // Throttle executions to once per second to prevent high CPU usage from rapid mousemove/touch events
      if (now - lastReset < 1000) return;
      lastReset = now;

      clearTimeout(timeoutId);
      timeoutId = setTimeout(() => {
        clearCart();
        navigate('/');
      }, timeoutSec * 1000);
    };

    // Global reset events
    const events = ['mousemove', 'keydown', 'touchstart', 'click'];
    events.forEach(e => window.addEventListener(e, resetTimer, { passive: true }));

    return () => {
      clearTimeout(timeoutId);
      events.forEach(e => window.removeEventListener(e, resetTimer));
    };
  }, [navigate, clearCart]);

  return null;
}

function App() {
  return (
    <CartProvider>
      <BrowserRouter>
        <IdleTimer />
        <div className="relative min-h-screen bg-black overflow-hidden selection:bg-brand-primary/30">

          {/* Quantum Cinematic Backdrop */}
          <div className="fixed inset-0 pointer-events-none z-0">
            <div className="absolute top-[-10%] left-[-10%] w-[50%] h-[50%] bg-brand-primary/10 rounded-full blur-[160px] animate-pulse-subtle" />
            <div className="absolute bottom-[-10%] right-[-10%] w-[60%] h-[60%] bg-indigo-500/10 rounded-full blur-[160px] animate-pulse-subtle delay-1000" />
            <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.15] contrast-150 brightness-150 pointer-events-none" />
          </div>

          <div className="relative z-10 w-full h-full">
            <ErrorBoundary>
              <Routes>
                <Route path="/" element={<VerticalVideoFeed />} />
                <Route path="/checkout" element={<CheckoutView />} />
                <Route path="/wheel" element={<FortuneWheelView />} />
              </Routes>
            </ErrorBoundary>
          </div>

        </div>
      </BrowserRouter>
    </CartProvider>
  );
}

export default App;
