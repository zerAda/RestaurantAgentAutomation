export const trackEvent = async (eventType: string, metadata: Record<string, unknown> = {}) => {
    try {
        const session_id = sessionStorage.getItem('kiosk_session') || `kiosk_${Date.now()}`;
        if (!sessionStorage.getItem('kiosk_session')) {
            sessionStorage.setItem('kiosk_session', session_id);
        }

        // SEC-P0: No fallback URL — exposes internal infra in public bundle. Tracking is a no-op when unset.
        if (!import.meta.env.VITE_N8N_URL) return;
        await fetch(`${import.meta.env.VITE_N8N_URL}/webhook/track`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                session_id,
                channel: 'kiosk',
                event_type: eventType,
                metadata
            })
        });
    } catch (err) {
        console.debug('[Tracking] Silent fail:', err);
    }
};
