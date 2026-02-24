export const authService = {
    login: async (password: string): Promise<boolean> => {
        // In a real staging/prod environment, this would call /api/auth/login
        // For "Diamond Grade" local/dev hardening, we use the env-provided admin password
        const adminPass = import.meta.env.VITE_ADMIN_PASSWORD || 'diamond2026';

        if (password === adminPass) {
            localStorage.setItem('admin_token', 'tg_diamond_secure_token_' + Date.now());
            return true;
        }
        return false;
    },

    isAuthenticated: (): boolean => {
        return !!localStorage.getItem('admin_token');
    },

    logout: () => {
        localStorage.removeItem('admin_token');
        window.location.reload();
    }
};
