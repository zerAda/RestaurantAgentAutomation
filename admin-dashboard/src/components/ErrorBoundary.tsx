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
                    background: '#1a1a2e',
                    color: '#e0e0e0',
                    fontFamily: 'system-ui, sans-serif',
                    padding: '2rem',
                    textAlign: 'center',
                }}>
                    <div style={{ fontSize: '4rem', marginBottom: '1rem' }}>⚠️</div>
                    <h1 style={{ fontSize: '1.5rem', color: '#f59e0b', marginBottom: '0.5rem' }}>
                        Something went wrong
                    </h1>
                    <p style={{ color: '#9ca3af', marginBottom: '1.5rem', maxWidth: '400px' }}>
                        {this.state.error?.message || 'An unexpected error occurred'}
                    </p>
                    <button
                        onClick={() => window.location.reload()}
                        style={{
                            background: '#f59e0b',
                            color: '#1a1a2e',
                            border: 'none',
                            padding: '0.75rem 2rem',
                            borderRadius: '0.5rem',
                            fontSize: '1rem',
                            fontWeight: 600,
                            cursor: 'pointer',
                        }}
                    >
                        Recharger
                    </button>
                </div>
            );
        }

        return this.props.children;
    }
}

export default ErrorBoundary;
