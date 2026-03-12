const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || 'https://cms.' + (import.meta.env.VITE_DOMAIN || 'localhost');

const TOKEN_KEY = 'admin_jwt';
const USER_KEY = 'admin_user';
const TOKEN_EXPIRY_KEY = 'admin_jwt_expiry';

// Token lifespan (24 hours). After this, isAuthenticated() will force logout.
// Using sessionStorage (NOT localStorage) to prevent XSS token theft:
// - sessionStorage is tab-isolated and wiped on browser close
// - Any CSRF/XSS that steals localStorage survives browser restarts
const TOKEN_LIFESPAN_MS = 24 * 60 * 60 * 1000;
const store = sessionStorage;

export const authService = {
    login: async (email: string, password: string): Promise<boolean> => {
        try {
            // Secure Architecture: Authenticate against the dedicated Admin API, not the public user API.
            const res = await fetch(`${STRAPI_URL}/admin/login`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password }),
            });

            if (!res.ok) return false;

            const payload = await res.json();
            // Strapi Admin API returns { data: { token: '...', user: { ... } } }
            if (payload?.data?.token) {
                // F-02 FIX: Use sessionStorage instead of localStorage to prevent
                // XSS token theft. sessionStorage is tab-isolated and wiped on close.
                store.setItem(TOKEN_KEY, payload.data.token);
                store.setItem(USER_KEY, JSON.stringify(payload.data.user));
                store.setItem(TOKEN_EXPIRY_KEY, String(Date.now() + TOKEN_LIFESPAN_MS));
                return true;
            }
            return false;
        } catch {
            console.error('[AuthService] Admin Login failed — is Strapi reachable?');
            return false;
        }
    },

    isAuthenticated: (): boolean => {
        const token = store.getItem(TOKEN_KEY);
        if (!token) return false;
        const expiry = Number(store.getItem(TOKEN_EXPIRY_KEY) || 0);
        
        if (expiry && Date.now() > expiry) {
            authService.logout();
            return false;
        }

        return true;
    },

    getToken: (): string | null => {
        return store.getItem(TOKEN_KEY);
    },

    getUser: (): { id: number; username: string; email: string; role?: { name: string; type?: string } } | null => {
        try {
            const user = store.getItem(USER_KEY);
            return user ? JSON.parse(user) : null;
        } catch {
            return null;
        }
    },

    logout: () => {
        store.removeItem(TOKEN_KEY);
        store.removeItem(USER_KEY);
        store.removeItem(TOKEN_EXPIRY_KEY);
        // Also clear any leftover localStorage keys from before this fix
        localStorage.removeItem(TOKEN_KEY);
        localStorage.removeItem(USER_KEY);
        localStorage.removeItem(TOKEN_EXPIRY_KEY);
        window.location.href = '/';
    },

    // No-op kept for backward compatibility — sessionStorage clears on tab close naturally
    _scheduleRefresh: () => {},
};
