import VerticalVideoFeed from "./components/VerticalVideoFeed";
import { CartProvider } from "./context/CartContext";

function App() {
  return (
    <CartProvider>
      <div className="w-full h-screen bg-black">
        <VerticalVideoFeed />
      </div>
    </CartProvider>
  );
}

export default App;
