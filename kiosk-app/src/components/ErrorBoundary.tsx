import React, { Component, type ErrorInfo, type ReactNode } from 'react';

interface Props {
    children: ReactNode;
    fallback?: ReactNode;
}

interface State {
    hasError: boolean;
    error: Error | null;
}

class ErrorBoundary extends Component<Props, State> {
    constructor(props: Props) {
        super(props);
        this.state = { hasError: false, error: null };
    }

    static getDerivedStateFromError(error: Error): State {
        return { hasError: true, error };
    }

    componentDidCatch(error: Error, errorInfo: ErrorInfo) {
        console.error('[ErrorBoundary]', error, errorInfo);
    }

    render() {
        if (this.state.hasError) {
            if (this.props.fallback) return this.props.fallback;
            return (
                <div style={{
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    justifyContent: 'center',
                    height: '100vh',
                    background: '#0f0f0f',
                    color: '#e0e0e0',
                    fontFamily: 'system-ui, sans-serif',
                    padding: '2rem',
                    textAlign: 'center',
                }}>
                    <div style={{ fontSize: '5rem', marginBottom: '1rem' }}>🍔</div>
                    <h1 style={{ fontSize: '1.8rem', color: '#f59e0b', marginBottom: '0.5rem' }}>
                        Oups !
                    </h1>
                    <p style={{ color: '#9ca3af', marginBottom: '1.5rem' }}>
                        Un problème est survenu. Veuillez réessayer.
                    </p>
                    <button
                        onClick={() => window.location.reload()}
                        style={{
                            background: '#f59e0b',
                            color: '#0f0f0f',
                            border: 'none',
                            padding: '1rem 3rem',
                            borderRadius: '1rem',
                            fontSize: '1.2rem',
                            fontWeight: 700,
                            cursor: 'pointer',
                        }}
                    >
                        Réessayer
                    </button>
                </div>
            );
        }

        return this.props.children;
    }
}

export default ErrorBoundary;
