import { BrowserRouter, Routes, Route, useNavigate } from "react-router-dom";
import { useEffect } from "react";
import VerticalVideoFeed from "./components/VerticalVideoFeed";
import FortuneWheelView from "./pages/FortuneWheelView";
import CheckoutView from "./pages/CheckoutView";
import { CartProvider, useCart } from "./context/CartContext";
import { configService } from "./services/configService";

function IdleTimer() {
  const navigate = useNavigate();
  const { clearCart } = useCart();

  useEffect(() => {
    let timeoutId: NodeJS.Timeout;
    let timeoutSec = 120; // fallback

    configService.getConfig().then(config => {
      if (config) timeoutSec = config.kiosk_idle_timeout_sec;
      resetTimer();
    });

    const resetTimer = () => {
      clearTimeout(timeoutId);
      timeoutId = setTimeout(() => {
        clearCart();
        navigate('/');
      }, timeoutSec * 1000);
    };

    window.addEventListener('mousemove', resetTimer);
    window.addEventListener('keydown', resetTimer);
    window.addEventListener('touchstart', resetTimer);
    window.addEventListener('click', resetTimer);

    return () => {
      clearTimeout(timeoutId);
      window.removeEventListener('mousemove', resetTimer);
      window.removeEventListener('keydown', resetTimer);
      window.removeEventListener('touchstart', resetTimer);
      window.removeEventListener('click', resetTimer);
    };
  }, [navigate, clearCart]);

  return null;
}

function App() {
  return (
    <CartProvider>
      <BrowserRouter>
        <IdleTimer />
        <div className="w-full h-screen bg-black">
          <Routes>
            <Route path="/" element={<VerticalVideoFeed />} />
            <Route path="/checkout" element={<CheckoutView />} />
            <Route path="/wheel" element={<FortuneWheelView />} />
          </Routes>
        </div>
      </BrowserRouter>
    </CartProvider>
  );
}

export default App;
