'use strict';

module.exports = {
    register({ strapi }) {
        strapi.customFields.register({
            name: 'json-form',
            plugin: 'json-form',
            type: 'json',
            inputSize: {
                default: 12,
                isResizable: false,
            },
        });
    },
};
