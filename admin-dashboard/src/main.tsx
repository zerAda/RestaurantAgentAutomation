import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import './index.css';
import App from './App.tsx';
import ErrorBoundary from './components/ErrorBoundary.tsx';
import { Providers } from './components/Providers.tsx';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <BrowserRouter>
        <Providers>
          <App />
        </Providers>
      </BrowserRouter>
    </ErrorBoundary>
  </StrictMode>,
);
