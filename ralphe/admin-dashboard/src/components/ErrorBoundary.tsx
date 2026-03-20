import { Component, type ErrorInfo, type ReactNode } from 'react';
import { AlertOctagon, RefreshCw } from 'lucide-react';

interface Props {
    children: ReactNode;
    fallback?: ReactNode;
}

interface State {
    hasError: boolean;
    error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
    public state: State = {
        hasError: false,
        error: null,
    };

    public static getDerivedStateFromError(error: Error): State {
        return { hasError: true, error };
    }

    public componentDidCatch(error: Error, errorInfo: ErrorInfo) {
        console.error('Uncaught error:', error, errorInfo);
    }

    private handleReset = () => {
        this.setState({ hasError: false, error: null });
        // In many cases, it's safer to just reload the page to clear bad state
        if (window.location.hash !== '') {
            window.location.hash = '';
        } else {
            window.location.reload();
        }
    };

    public render() {
        if (this.state.hasError) {
            if (this.props.fallback) {
                return <>{this.props.fallback}</>;
            }

            return (
                <div className="min-h-[400px] w-full flex flex-col items-center justify-center p-6 bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 rounded-3xl border border-red-500/20 shadow-2xl shadow-red-500/10 animate-in fade-in zoom-in-95 duration-500">
                    <div className="w-16 h-16 rounded-2xl bg-red-500/10 flex items-center justify-center mb-6">
                        <AlertOctagon className="w-8 h-8 text-red-500" />
                    </div>
                    <h2 className="text-2xl font-black mb-2 text-center">Oups ! Quelque chose a mal tourné.</h2>
                    <p className="text-zinc-500 dark:text-zinc-400 text-center max-w-md mb-8">
                        Une erreur inattendue s'est produite dans cette section de l'application. Nos équipes ont été alertées (localement).
                    </p>

                    <div className="bg-zinc-100 dark:bg-zinc-900 p-4 rounded-xl w-full max-w-lg overflow-auto mb-8 font-mono text-xs text-red-400 border border-red-500/10">
                        {this.state.error?.message || 'Erreur inconnue'}
                    </div>

                    <button
                        onClick={this.handleReset}
                        className="flex items-center gap-2 px-6 py-3 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl font-bold transition-all hover:scale-105 active:scale-95 shadow-lg shadow-indigo-600/20"
                    >
                        <RefreshCw className="w-4 h-4" />
                        Recharger l'application
                    </button>
                </div>
            );
        }

        return <>{this.props.children}</>;
    }
}

export default ErrorBoundary;

