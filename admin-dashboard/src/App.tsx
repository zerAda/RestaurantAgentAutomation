import { BrowserRouter, Routes, Route } from "react-router-dom";
import DashboardLayout from "@/components/layout/DashboardLayout";
import DashboardHome from "@/pages/DashboardHome";
import OrdersKanban from "@/pages/OrdersKanban";
import GodMode from "@/pages/GodMode";
import KitchenDisplay from "@/pages/KitchenDisplay";
import { Providers } from "@/components/Providers";

function App() {
  return (
    <Providers>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<DashboardLayout />}>
            <Route index element={<DashboardHome />} />
            <Route path="orders" element={<OrdersKanban />} />
            <Route path="god-mode" element={<GodMode />} />
            <Route path="kitchen" element={<KitchenDisplay />} />
            <Route path="menu" element={<div className="p-10 text-gray-500">Module Menu (En cours)</div>} />
            <Route path="drivers" element={<div className="p-10 text-gray-500">Module Livreurs (En cours)</div>} />
            <Route path="settings" element={<div className="p-10 text-gray-500">Paramètres (En cours)</div>} />
          </Route>
        </Routes>
      </BrowserRouter>
    </Providers>
  );
}

export default App;
