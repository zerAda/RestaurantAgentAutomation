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
                sessionStorage.setItem(TOKEN_KEY, data.jwt);
                sessionStorage.setItem(USER_KEY, JSON.stringify(data.user));
                sessionStorage.setItem(TOKEN_EXPIRY_KEY, String(Date.now() + TOKEN_LIFESPAN_MS));
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
        const token = sessionStorage.getItem(TOKEN_KEY);
        if (!token) return false;
        const expiry = Number(sessionStorage.getItem(TOKEN_EXPIRY_KEY) || 0);
        if (expiry && Date.now() > expiry) {
            authService.logout();
            return false;
        }
        return true;
    },

    getToken: (): string | null => {
        return sessionStorage.getItem(TOKEN_KEY);
    },

    logout: () => {
        sessionStorage.removeItem(TOKEN_KEY);
        sessionStorage.removeItem(USER_KEY);
        sessionStorage.removeItem(TOKEN_EXPIRY_KEY);
        sessionStorage.removeItem(REFRESH_KEY);
        window.location.href = '/';
    },

    // Re-authenticate to get fresh token (Strapi v5 doesn't have refresh endpoint)
    _scheduleRefresh: () => {
        const expiry = Number(sessionStorage.getItem(TOKEN_EXPIRY_KEY) || 0);
        const delay = Math.max(0, expiry - Date.now() - 60000); // 1 min before expiry

        setTimeout(async () => {
            const user = sessionStorage.getItem(USER_KEY);
            if (!user) return;
            // Show notification that session is expiring
            console.info('[AuthService] Session expiring soon, please re-login if needed');
        }, delay);
    },
};
