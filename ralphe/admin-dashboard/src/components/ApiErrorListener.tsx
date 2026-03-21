import { useEffect } from 'react';
import { useToast } from './ToastProvider';

export function ApiErrorListener() {
    const { addToast } = useToast();

    useEffect(() => {
        const handleNetworkError = (e: Event) => {
            const customEvent = e as CustomEvent<{ message: string }>;
            addToast({
                type: 'error',
                title: 'API Déconnectée',
                message: customEvent.detail.message
            });
        };

        const handleSessionExpiring = (e: Event) => {
            const customEvent = e as CustomEvent<{ message: string }>;
            addToast({
                type: 'info',
                title: 'Session expirée bientôt',
                message: customEvent.detail.message
            });
        };

        window.addEventListener('strapi-network-error', handleNetworkError);
        window.addEventListener('strapi-session-expiring', handleSessionExpiring);

        return () => {
            window.removeEventListener('strapi-network-error', handleNetworkError);
            window.removeEventListener('strapi-session-expiring', handleSessionExpiring);
        };
    }, [addToast]);

    return null;
}
