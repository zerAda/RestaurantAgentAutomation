import type { StrapiApp } from '@strapi/strapi/admin';
import './custom.css';

export default {
    config: {
        locales: ['ar', 'fr'],
        tutorials: false,
        notifications: { releases: false },
        theme: {
            light: {
                colors: {
                    primary100: '#fef3e2',
                    primary200: '#fde1b0',
                    primary500: '#f59e0b',
                    primary600: '#d97706',
                    primary700: '#b45309',
                    buttonPrimary500: '#f59e0b',
                    buttonPrimary600: '#d97706',
                },
            },
            dark: {
                colors: {
                    // SaaS pitch black background
                    neutral0: '#000000',
                    neutral100: '#111111',
                    neutral150: '#161616',
                    neutral200: '#262626', // Border accuracy
                    neutral500: '#666666',
                    neutral800: '#e5e5e5', // High Contrast Text
                    neutral900: '#ffffff',

                    // Quantum brand essence
                    primary100: '#1a1a1a',
                    primary200: '#33111a', // Subtle brand glow
                    primary500: '#FF3366', // Brand Primary
                    primary600: '#E62E5C',
                    primary700: '#CC2952',
                    buttonPrimary500: '#FF3366',
                    buttonPrimary600: '#E62E5C',
                },
            },
        },
    },
    bootstrap(app: StrapiApp) {
        // Custom menu overrides for Ralphé branding
        app.addMenuLink({
            to: '/plugins/content-manager/single-types/api::system-config.system-config',
            icon: () => '⚙️',
            intlLabel: {
                id: 'app.nav.system-config',
                defaultMessage: '⚙️ Panneau de Contrôle',
            },
            Component: async () => ({ default: () => null }),
            permissions: [],
        });
    },
};
