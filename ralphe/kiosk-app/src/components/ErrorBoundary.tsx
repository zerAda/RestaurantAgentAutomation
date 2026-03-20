import React, { Component, ErrorInfo, ReactNode } from 'react';

interface Props {
  children?: ReactNode;
}

interface State {
  hasError: boolean;
}

export class ErrorBoundary extends Component<Props, State> {
  public state: State = {
    hasError: false
  };

  public static getDerivedStateFromError(error: Error): State {
    console.error('[ErrorBoundary] Caught:', error.message);
    return { hasError: true };
  }

  public componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('Kiosk Error Boundary caught an error:', error, errorInfo);
    
    // Auto-heal: reload the kiosk after 10 seconds to recover from transient crashes
    setTimeout(() => {
        window.location.reload();
    }, 10000);
  }

  public render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen bg-black text-white flex flex-col items-center justify-center p-10 font-sans">
          <div className="w-20 h-20 mb-8 border-4 border-brand-primary border-t-transparent rounded-full animate-spin"></div>
          <h1 className="text-4xl font-black mb-4">Mise à jour du terminal...</h1>
          <p className="text-zinc-400 text-xl text-center max-w-lg">
            Le terminal redémarre pour appliquer une mise à jour système. Veuillez patienter quelques instants.
          </p>
        </div>
      );
    }

    return this.props.children;
  }
}
export default ErrorBoundary;
