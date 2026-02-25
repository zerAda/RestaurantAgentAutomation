export const trackEvent = async (eventType: string, metadata: Record<string, unknown> = {}) => {
    try {
        const session_id = localStorage.getItem('kiosk_session') || `kiosk_${Date.now()}`;
        if (!localStorage.getItem('kiosk_session')) {
            localStorage.setItem('kiosk_session', session_id);
        }

        await fetch(`${import.meta.env.VITE_N8N_URL || 'http://localhost:5678'}/webhook/track`, {
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
