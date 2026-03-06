const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || 'https://cms.' + (import.meta.env.VITE_DOMAIN || 'localhost');

const TOKEN_KEY = 'admin_jwt';
const REFRESH_KEY = 'admin_refresh_token';
const USER_KEY = 'admin_user';
const TOKEN_EXPIRY_KEY = 'admin_jwt_expiry';

// Token lifespan (24 hours - auto-logout propre après 24h)
const TOKEN_LIFESPAN_MS = 24 * 60 * 60 * 1000;

export const authService = {
    login: async (email: string, password: string): Promise<boolean> => {
        try {
            const res = await fetch(`${STRAPI_URL}/api/auth/local`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ identifier: email, password }),
            });

            if (!res.ok) return false;

            const data = await res.json();
            if (data?.jwt) {
                localStorage.setItem(TOKEN_KEY, data.jwt);
                localStorage.setItem(USER_KEY, JSON.stringify(data.user));
                localStorage.setItem(TOKEN_EXPIRY_KEY, String(Date.now() + TOKEN_LIFESPAN_MS));
                // Start auto-refresh timer
                authService._scheduleRefresh();
                return true;
            }
            return false;
        } catch {
            console.error('[AuthService] Login failed — is Strapi reachable?');
            return false;
        }
    },

    isAuthenticated: (): boolean => {
        const token = localStorage.getItem(TOKEN_KEY);
        if (!token) return false;
        const expiry = Number(localStorage.getItem(TOKEN_EXPIRY_KEY) || 0);
        if (expiry && Date.now() > expiry) {
            authService.logout();
            return false;
        }
        return true;
    },

    getToken: (): string | null => {
        return localStorage.getItem(TOKEN_KEY);
    },

    getUser: (): { id: number; username: string; email: string; role?: { name: string } } | null => {
        try {
            const user = localStorage.getItem(USER_KEY);
            return user ? JSON.parse(user) : null;
        } catch {
            return null;
        }
    },

    logout: () => {
        localStorage.removeItem(TOKEN_KEY);
        localStorage.removeItem(USER_KEY);
        localStorage.removeItem(TOKEN_EXPIRY_KEY);
        localStorage.removeItem(REFRESH_KEY);
        window.location.href = '/';
    },

    // Re-authenticate to get fresh token (Strapi v5 doesn't have refresh endpoint)
    _scheduleRefresh: () => {
        const expiry = Number(localStorage.getItem(TOKEN_EXPIRY_KEY) || 0);
        const delay = Math.max(0, expiry - Date.now() - 60000); // 1 min before expiry

        setTimeout(async () => {
            const user = localStorage.getItem(USER_KEY);
            if (!user) return;

            // Dispatch event to show a toast warning the user
            window.dispatchEvent(new CustomEvent('strapi-session-expiring', {
                detail: { message: 'Votre session va expirer dans 1 minute. Veuillez vous reconnecter.' }
            }));
        }, delay);
    },
};
