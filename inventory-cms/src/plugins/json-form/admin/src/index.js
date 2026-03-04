import { prefixPluginTranslations } from '@strapi/helper-plugin';
import pluginId from './pluginId';

export default {
    register(app) {
        app.customFields.register({
            name: 'json-form',
            pluginId: 'json-form',
            type: 'json',
            intlLabel: {
                id: `${pluginId}.label`,
                defaultMessage: 'JSON Form',
            },
            intlDescription: {
                id: `${pluginId}.description`,
                defaultMessage: 'Edit JSON data with a structured form interface',
            },
            components: {
                Input: async () => import('./components/JsonFormInput'),
            },
            options: {
                base: [],
                advanced: [],
            },
        });
    },
    async registerTrads({ locales }) {
        const importedTrads = await Promise.all(
            locales.map((locale) => {
                return Promise.resolve({
                    data: {
                        [`${pluginId}.label`]: 'JSON Form',
                        [`${pluginId}.description`]: 'Structured JSON editor',
                    },
                    locale,
                });
            })
        );
        return Promise.resolve(importedTrads);
    },
};
