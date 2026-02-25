const STRAPI_URL = import.meta.env.VITE_STRAPI_URL || 'https://cms.' + (import.meta.env.VITE_DOMAIN || 'localhost');

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
                sessionStorage.setItem('admin_jwt', data.jwt);
                sessionStorage.setItem('admin_user', JSON.stringify(data.user));
                return true;
            }
            return false;
        } catch {
            console.error('[AuthService] Login failed — is Strapi reachable?');
            return false;
        }
    },

    isAuthenticated: (): boolean => {
        return !!sessionStorage.getItem('admin_jwt');
    },

    getToken: (): string | null => {
        return sessionStorage.getItem('admin_jwt');
    },

    logout: () => {
        sessionStorage.removeItem('admin_jwt');
        sessionStorage.removeItem('admin_user');
        window.location.reload();
    },
};
