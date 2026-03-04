import type { StrapiApp } from '@strapi/strapi/admin';

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
                    primary100: '#3b2f1f',
                    primary200: '#5c4a2a',
                    primary500: '#f59e0b',
                    primary600: '#fbbf24',
                    primary700: '#fcd34d',
                    buttonPrimary500: '#f59e0b',
                    buttonPrimary600: '#fbbf24',
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
            permissions: [],
        });
    },
};
